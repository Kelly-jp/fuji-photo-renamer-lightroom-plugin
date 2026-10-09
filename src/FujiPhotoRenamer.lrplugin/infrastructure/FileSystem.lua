local context = assert(..., 'FileSystem requires SDK and core dependencies')
local LrFileUtils, LrPathUtils = assert(context.fileUtils), assert(context.pathUtils)
local collisions = assert(context.collisions)
local FileSystem = {}

local function resolveOutputDirectory(destination, originalPath)
    local directory
    if destination.kind == 'sourceFolder' then
        directory = LrPathUtils.parent(originalPath)
    elseif destination.kind == 'specificFolder' then
        directory = destination.path
    elseif destination.kind == 'desktop' or destination.kind == 'documents'
        or destination.kind == 'home' or destination.kind == 'pictures' then
        directory = LrPathUtils.getStandardFilePath(destination.kind)
    else
        return nil, '対応していない保存先設定です：' .. tostring(destination.kind)
    end
    if type(directory) ~= 'string' or not LrPathUtils.isAbsolute(directory)
        or LrFileUtils.exists(directory) ~= 'directory' then
        return nil, '保存先フォルダーが存在しないか、絶対パスではありません。'
    end
    if destination.useSubfolder then
        local name = destination.subfolder
        if type(name) ~= 'string' or name == '' or name == '.' or name == '..'
            or name:find('[%c<>:"/\\|?*]') or name:find('[ .]$') then
            return nil, 'サブフォルダーにはパス区切りや禁止文字を含まないフォルダー名を指定してください。'
        end
        local deviceName = (name:match('^[^.]+') or name):gsub(' +$', ''):upper()
        if deviceName == 'CON' or deviceName == 'PRN' or deviceName == 'AUX' or deviceName == 'NUL'
            or deviceName:match('^COM[1-9]$') or deviceName:match('^LPT[1-9]$')
            or deviceName == 'COM¹' or deviceName == 'COM²' or deviceName == 'COM³'
            or deviceName == 'LPT¹' or deviceName == 'LPT²' or deviceName == 'LPT³' then
            return nil, 'サブフォルダーに予約名は使用できません。'
        end
        directory = LrPathUtils.child(directory, name)
        local existing = LrFileUtils.exists(directory)
        if existing and existing ~= 'directory' then
            return nil, 'サブフォルダーと同名のファイルが存在します。'
        end
    end
    return directory
end

function FileSystem.save(renderedPath, filename, destination, originalPath, sourcePaths, progress, session)
    local directory, directoryError = resolveOutputDirectory(destination, originalPath)
    if not directory then return nil, directoryError end
    local renderPath = LrPathUtils.standardizePath(LrFileUtils.resolveAllAliases(renderedPath))
    local protected = { originalPath }
    for _, path in pairs(sourcePaths) do protected[#protected + 1] = path end
    for _, path in ipairs(protected) do
        local canonical = LrPathUtils.standardizePath(LrFileUtils.resolveAllAliases(path))
        if canonical:lower() == renderPath:lower() then return nil, 'レンダリング結果が入力画像と同じパスのため保存しません。' end
    end
    if progress:isCanceled() then return nil, '書き出しがキャンセルされました。' end
    if LrFileUtils.exists(directory) ~= 'directory' then
        if not destination.useSubfolder or LrFileUtils.exists(LrPathUtils.parent(directory)) ~= 'directory' then
            return nil, '保存先または親フォルダーが失われました。'
        end
        local created, message = LrFileUtils.createAllDirectories(directory)
        if not created or LrFileUtils.exists(directory) ~= 'directory' then return nil, 'サブフォルダーを作成できません：' .. tostring(message) end
    end
    session[directory] = session[directory] or {}
    local occupied, reserved = {}, session[directory]
    for _ = 1, 10000 do
        if progress:isCanceled() then return nil, '書き出しがキャンセルされました。' end
        local candidate, candidateError = collisions.resolve(filename, {
            existingNames = occupied, reservedNames = reserved, nameKey = function(name) return name end,
        })
        if not candidate then return nil, candidateError.code .. '：' .. candidateError.message end
        local path = LrPathUtils.child(directory, candidate.filename)
        -- Ask the destination filesystem about every candidate; do not approximate Unicode equivalence in Lua.
        if LrFileUtils.exists(path) then occupied[#occupied + 1] = candidate.filename
        else
            local copied, message = LrFileUtils.copy(renderedPath, path)
            -- A failed copy might have left a partial file. Do not delete or reinterpret it as a collision.
            if not copied then return nil, 'JPEG を保存できません：' .. path .. '\n' .. tostring(message or '原因不明') end
            reserved[#reserved + 1] = candidate.filename
            return path
        end
    end
    return nil, '衝突回避の候補数上限に達しました。'
end
return FileSystem
