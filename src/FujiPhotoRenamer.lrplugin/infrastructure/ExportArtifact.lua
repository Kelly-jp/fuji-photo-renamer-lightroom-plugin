local context = assert(..., 'ExportArtifact requires SDK and JPEG dependencies')
local files, paths, integrity = assert(context.fileUtils), assert(context.pathUtils), assert(context.integrity)
local Store, records = {}, setmetatable({}, { __mode = 'k' })
local maxBytes = 64 * 1024 * 1024
local function failure(message) return nil, { code = 'ArtifactRejected', message = message } end
local function canonical(path) return paths.standardizePath(files.resolveAllAliases(path)) end
local function readJpeg(path)
    if files.exists(path) ~= 'file' then return failure('生成 JPEG がありません。') end
    local size = files.fileAttributes(path).fileSize
    if not size or size > maxBytes then return failure('JPEG が検証可能な上限 64 MiB を超えています。') end
    local handle, message = io.open(path, 'rb')
    if not handle then return failure(tostring(message)) end
    local data = handle:read(maxBytes + 1); handle:close()
    if not data or #data > maxBytes then return failure('JPEG の読み取りサイズが不正です。') end
    return data
end
function Store.capture(rendition, renderedPath, originalPath, sourcePaths)
    if rendition:type() ~= 'LrExportRendition' or type(rendition.destinationPath) ~= 'string'
        or canonical(rendition.destinationPath) ~= canonical(renderedPath)
        or canonical(rendition.photo:getRawMetadata('path')) ~= canonical(originalPath) then
        return failure('SDK のレンダリング由来を確認できません。')
    end
    local extension = paths.extension(renderedPath):lower()
    if extension ~= 'jpg' and extension ~= 'jpeg' then return failure('JPEG 以外は処理しません。') end
    local protected = { originalPath }
    for _, path in pairs(sourcePaths) do protected[#protected + 1] = path end
    local actual = canonical(renderedPath)
    for _, path in ipairs(protected) do
        if canonical(path):lower() == actual:lower() then return failure('入力画像と生成 JPEG が同じです。') end
    end
    local data, readError = readJpeg(renderedPath)
    if not data then return nil, readError end
    local jpeg, jpegError = integrity.inspect(data)
    if not jpeg then return nil, jpegError end
    local cap = {}
    records[cap] = { path = renderedPath, canonical = actual, before = data, protected = protected, photo = rendition.photo }
    return cap
end
function Store.source(cap)
    local record = records[cap]
    if not record then return failure('所有する書き出し artifact が必要です。') end
    local currentOriginal = record.photo:getRawMetadata('path')
    if type(currentOriginal) ~= 'string' or canonical(currentOriginal):lower() == record.canonical:lower() then
        return failure('カタログ元画像への参照を拒否します。')
    end
    if canonical(record.path) ~= record.canonical then return failure('生成 JPEG の参照先が変わりました。') end
    for _, path in ipairs(record.protected) do
        if canonical(path):lower() == record.canonical:lower() then return failure('入力画像への参照を拒否します。') end
    end
    local data, err = readJpeg(record.path)
    if not data then return nil, err end
    if data ~= record.before then return failure('処理中に生成 JPEG が変更されました。') end
    return record.path
end
function Store.bindWork(cap, directory)
    if not records[cap] then return failure('所有する artifact がありません。') end
    local output = paths.child(directory, 'cleaned.jpg')
    if files.exists(output) then return failure('作業コピーが既に存在します。') end
    if output:find('%', 1, true) then return failure('作業パスの % は ExifTool 出力書式と区別できないため拒否します。') end
    records[cap].output = output
    records[cap].outputCanonical = paths.child(canonical(directory), 'cleaned.jpg')
    return output
end
function Store.verify(cap)
    local record = records[cap]
    if not record or not record.output then return failure('未登録の作業コピーです。') end
    local source, sourceError = Store.source(cap)
    if not source then return nil, sourceError end
    if canonical(record.photo:getRawMetadata('path')):lower() == record.outputCanonical:lower() then return failure('作業コピーがカタログ元画像と同じです。') end
    if canonical(record.output) ~= record.outputCanonical then return failure('作業コピーの参照先が変わりました。') end
    for _, protected in ipairs(record.protected) do
        if canonical(protected):lower() == record.outputCanonical:lower() then return failure('作業コピーが入力画像と同じです。') end
    end
    local data, readError = readJpeg(record.output)
    if not data then return nil, readError end
    if canonical(record.output) == record.canonical then return failure('作業コピーが入力と同じです。') end
    local verified, verifyError = integrity.verifyRemoval(record.before, data)
    if not verified then return nil, verifyError end
    record.verified = true
    return record.output, verified
end
function Store.commitPath(cap)
    local record = records[cap]
    if not record or not record.verified then return failure('未検証の artifact は保存できません。') end
    local path, err = Store.verify(cap)
    if not path then return nil, err end
    -- Remove only this freshly generated rendition, after all byte-preservation checks passed.
    local removed, message = files.delete(record.path)
    if not removed then return failure('SDK 生成 JPEG の転送準備に失敗しました：' .. tostring(message)) end
    return record.output
end
function Store.canClean(cap, path)
    local record = records[cap]
    if not record or record.output ~= path or canonical(path) ~= record.outputCanonical then return false end
    if canonical(record.photo:getRawMetadata('path')):lower() == record.outputCanonical:lower() then return false end
    for _, protected in ipairs(record.protected) do
        if canonical(protected):lower() == record.outputCanonical:lower() then return false end
    end
    return true
end
function Store.forget(cap) records[cap] = nil end
return Store
