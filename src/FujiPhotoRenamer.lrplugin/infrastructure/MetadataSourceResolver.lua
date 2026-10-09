local context = assert(..., 'MetadataSourceResolver requires the SDK context')
local fileUtils = assert(context.fileUtils)
local pathUtils = assert(context.pathUtils)
local tasks = assert(context.tasks)

local Resolver = {}
local rawExtensions = { raf = true, dng = true }
local jpegExtensions = { jpg = true, jpeg = true }
local xmpExtensions = { xmp = true }
local modes = { same_directory = true, parent_directory = true, same_then_parent = true }

local function fail(code, message, candidates)
    error({ code = code, message = message, candidates = candidates })
end

local function canonical(path)
    local resolved = pathUtils.standardizePath(fileUtils.resolveAllAliases(path))
    if type(resolved) ~= 'string' or resolved == '' then
        fail('SourceReadError', '入力候補のパスを解決できません：' .. path)
    end
    return resolved
end

local function parentDirectory(directory)
    local parent = pathUtils.parent(directory)
    if parent and parent ~= '' and parent ~= directory and pathUtils.isAbsolute(parent) then return parent end
    return nil
end

local function uniqueCandidate(candidates, description)
    local unique, identities = {}, {}
    for _, path in ipairs(candidates) do
        local identity = canonical(path)
        if not identities[identity] then
            identities[identity] = true
            unique[#unique + 1] = path
        end
    end
    if #unique > 1 then
        table.sort(unique)
        fail('AmbiguousSource', description .. 'が複数あります。自動では選択しません。', unique)
    end
    return unique[1]
end

local function resolve(originalPath, rawMode)
    if rawMode == nil then rawMode = 'same_then_parent' end
    if type(rawMode) ~= 'string' or not modes[rawMode] then
        fail('InvalidMode', 'RAW 探索方法が不正です。')
    end
    if type(originalPath) ~= 'string' or originalPath:find('[%z\r\n]')
        or not pathUtils.isAbsolute(originalPath) then
        fail('InvalidInputPath', '元画像の絶対パスを指定してください。')
    end
    local extension = pathUtils.extension(originalPath):lower()
    if not rawExtensions[extension] and not jpegExtensions[extension] then
        fail('UnsupportedInput', '元画像は JPG / JPEG / RAF / DNG を指定してください。')
    end
    if fileUtils.exists(originalPath) ~= 'file' or not fileUtils.isReadable(originalPath) then
        fail('SourceReadError', '元画像が存在しないか、読み取れません。')
    end
    local directory = pathUtils.parent(originalPath)
    if type(directory) ~= 'string' or not pathUtils.isAbsolute(directory) then
        fail('SourceReadError', '元画像の親フォルダーを解決できません。')
    end
    local stem = pathUtils.removeExtension(pathUtils.leafName(originalPath))
    local cache = {}

    local function findCandidates(folder, extensions)
        if not folder then return {} end
        if fileUtils.exists(folder) ~= 'directory' then
            fail('SourceReadError', '探索先フォルダーが存在しません：' .. folder)
        end
        if not cache[folder] then
            local entries = {}
            -- SDK iterators keep a directory handle open until exhausted; do not break early.
            for path in fileUtils.directoryEntries(folder) do entries[#entries + 1] = path end
            table.sort(entries)
            cache[folder] = entries
        end
        local candidates, variants = {}, {}
        for _, path in ipairs(cache[folder]) do
            local candidateExtension = pathUtils.extension(path):lower()
            if extensions[candidateExtension] then
                local candidateStem = pathUtils.removeExtension(pathUtils.leafName(path))
                if candidateStem == stem or candidateStem:lower() == stem:lower() then
                    local kind = fileUtils.exists(path)
                    if not kind then fail('SourceReadError', '列挙した入力候補が見つかりません：' .. path) end
                    if kind == 'file' then
                        if not fileUtils.isReadable(path) then
                            fail('SourceReadError', '入力候補を読み取れません：' .. path)
                        end
                        if candidateStem == stem then
                            candidates[#candidates + 1] = path
                        else
                            variants[#variants + 1] = path
                        end
                    end
                end
            end
        end
        if #variants > 0 then
            fail('AmbiguousStem', '元画像と stem の大小文字だけが異なる候補があります。', variants)
        end
        return candidates
    end

    local result = {}
    if jpegExtensions[extension] then
        result.jpeg = originalPath
        if rawMode ~= 'parent_directory' then
            result.raw = uniqueCandidate(findCandidates(directory, rawExtensions), '同階層の RAW')
        end
        if not result.raw and rawMode ~= 'same_directory' then
            result.raw = uniqueCandidate(findCandidates(parentDirectory(directory), rawExtensions), '親階層の RAW')
        end
    else
        result.raw = originalPath
        result.jpeg = uniqueCandidate(findCandidates(directory, jpegExtensions), '対応する JPEG')
    end

    local xmpCandidates = {}
    local xmpFolders = { directory }
    if result.raw then
        local rawDirectory = pathUtils.parent(result.raw)
        xmpFolders = rawDirectory == directory and { directory } or { rawDirectory, directory }
    end
    for _, folder in ipairs(xmpFolders) do
        for _, path in ipairs(findCandidates(folder, xmpExtensions)) do
            xmpCandidates[#xmpCandidates + 1] = path
        end
    end
    result.xmp = uniqueCandidate(xmpCandidates, '対応する XMP')
    return result
end

function Resolver.resolve(originalPath, rawMode)
    local ok, result = tasks.pcall(resolve, originalPath, rawMode)
    if ok then return result end
    if type(result) == 'table' and result.code then return nil, result end
    return nil, { code = 'SourceReadError', message = 'ファイル探索に失敗しました：' .. tostring(result) }
end

return Resolver
