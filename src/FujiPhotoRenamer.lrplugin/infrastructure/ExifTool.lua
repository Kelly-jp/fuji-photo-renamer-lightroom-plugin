local context = assert(..., 'ExifTool must be loaded through ExifToolLoader')
local LrFileUtils = assert(context.fileUtils)
local LrPathUtils = assert(context.pathUtils)
local LrTasks = assert(context.tasks)
local json = assert(context.json)

local ExifTool = {}
local maxOutputBytes = 1024 * 1024
local ownedFiles = { 'arguments.txt', 'stdout.json', 'stderr.txt', 'exit-code.txt', 'timed-out.txt' }
local requestedTags = {
    '-ExifToolVersion', '-DateTimeOriginal', '-Make', '-Model', '-LensMake', '-LensModel',
    '-FujiFilm:FilmMode', '-FujiFilm:Saturation', '-ISO', '-FocalLength', '-Error', '-Warning',
    '-XMP-crs:LookName', '-XMP-crs:CameraProfile', '-XMP-crs:CameraProfilesProfileName',
}
local fieldTags = {
    captureDateTime = { 'ExifIFD:DateTimeOriginal', 'XMP-exif:DateTimeOriginal' },
    cameraMaker = { 'IFD0:Make', 'XMP-tiff:Make' },
    camera = { 'IFD0:Model', 'XMP-tiff:Model' },
    lensMaker = { 'ExifIFD:LensMake', 'XMP-exifEX:LensMake' },
    lens = { 'ExifIFD:LensModel', 'XMP-exifEX:LensModel' },
    iso = { 'ExifIFD:ISO', 'XMP-exif:ISO' },
    focalLength = { 'ExifIFD:FocalLength', 'XMP-exif:FocalLength' },
}
local filmModes = {
    [0x000] = 'PROVIA', [0x120] = 'ASTIA', [0x200] = 'VELVIA', [0x400] = 'VELVIA',
    [0x500] = 'PRO_NEG_STD', [0x501] = 'PRO_NEG_HI', [0x600] = 'CLASSIC_CHROME',
    [0x700] = 'ETERNA', [0x800] = 'CLASSIC_NEGATIVE', [0x900] = 'ETERNA_BLEACH_BYPASS',
    [0xa00] = 'NOSTALGIC_NEG', [0xb00] = 'REALA_ACE',
}
local monochromeModes = {
    [0x300] = 'MONOCHROME', [0x301] = 'MONOCHROME_R', [0x302] = 'MONOCHROME_Y',
    [0x303] = 'MONOCHROME_G', [0x310] = 'SEPIA', [0x500] = 'ACROS',
    [0x501] = 'ACROS_R', [0x502] = 'ACROS_Y', [0x503] = 'ACROS_G',
}
local profileNames = {
    ['PROVIA'] = 'PROVIA', ['PROVIA/STANDARD'] = 'PROVIA',
    ['VELVIA'] = 'VELVIA', ['VELVIA/VIVID'] = 'VELVIA',
    ['ASTIA'] = 'ASTIA', ['ASTIA/SOFT'] = 'ASTIA',
    ['PRO NEG. STD'] = 'PRO_NEG_STD', ['PRO NEG STD'] = 'PRO_NEG_STD',
    ['PRO NEG. HI'] = 'PRO_NEG_HI', ['PRO NEG HI'] = 'PRO_NEG_HI',
    ['CLASSIC CHROME'] = 'CLASSIC_CHROME',
    ['CLASSIC NEG'] = 'CLASSIC_NEGATIVE', ['CLASSIC NEG.'] = 'CLASSIC_NEGATIVE',
    ['CLASSIC NEGATIVE'] = 'CLASSIC_NEGATIVE',
    ['ETERNA'] = 'ETERNA', ['ETERNA/CINEMA'] = 'ETERNA',
    ['ETERNA BLEACH BYPASS'] = 'ETERNA_BLEACH_BYPASS', ['BLEACH BYPASS'] = 'ETERNA_BLEACH_BYPASS',
    ['NOSTALGIC NEG'] = 'NOSTALGIC_NEG', ['NOSTALGIC NEG.'] = 'NOSTALGIC_NEG',
    ['REALA ACE'] = 'REALA_ACE', ['ACROS'] = 'ACROS', ['MONOCHROME'] = 'MONOCHROME', ['SEPIA'] = 'SEPIA',
}
for suffix, value in pairs { R = 'R', Y = 'Y', YE = 'Y', G = 'G' } do
    profileNames['ACROS+' .. suffix .. ' FILTER'] = 'ACROS_' .. value
    profileNames['ACROS+' .. suffix] = 'ACROS_' .. value
    profileNames['MONOCHROME+' .. suffix .. ' FILTER'] = 'MONOCHROME_' .. value
    profileNames['MONOCHROME+' .. suffix] = 'MONOCHROME_' .. value
end
local profileTags = { 'XMP-crs:LookName', 'XMP-crs:CameraProfile', 'XMP-crs:CameraProfilesProfileName' }

local function failure(code, message, extra)
    local result = extra or {}
    result.code = code
    result.message = message
    return nil, result
end

local function validatePath(path)
    return type(path) == 'string' and path ~= '' and not path:find('[%z\r\n]')
        and LrPathUtils.isAbsolute(path)
end

local function quote(path, platform)
    if not validatePath(path) then return nil, '絶対パスを指定してください。' end
    if platform == 'windows' then
        -- cmd.exe expands these even inside quotes; fail rather than guess an escaping rule.
        if path:find('["%%!^]') or path:find('[\\/]$') then
            return nil, 'Windows の実行用パスに引用符・%・!・^・末尾区切りは使用できません。'
        end
        return '"' .. path .. '"'
    elseif platform == 'macos' then
        return "'" .. path:gsub("'", "'\\''") .. "'"
    end
    return nil, '対応 OS を判定できません。'
end

function ExifTool.buildReadArguments(inputPath)
    if not validatePath(inputPath) then
        return failure('InvalidInputPath', '改行・NUL を含まない絶対パスを指定してください。')
    end
    local arguments = { '-j', '-G1', '-s', '-n' }
    for _, tag in ipairs(requestedTags) do arguments[#arguments + 1] = tag end
    arguments[#arguments + 1] = '--'
    arguments[#arguments + 1] = inputPath
    return table.concat(arguments, '\n') .. '\n'
end

function ExifTool.buildCommand(executablePath, pluginPath, workDirectory, timeoutSeconds, platform)
    if not validatePath(pluginPath) then return failure('UnsafeCommandPath', 'プラグインの絶対パスが必要です。') end
    if type(timeoutSeconds) ~= 'number' or timeoutSeconds ~= math.floor(timeoutSeconds)
        or timeoutSeconds < 1 or timeoutSeconds > 120 then
        return failure('InvalidTimeout', '実行時間上限は 1〜120 秒の整数にしてください。')
    end
    local runner = LrPathUtils.child(pluginPath, 'infrastructure/ExifToolRead.' ..
        (platform == 'windows' and 'ps1' or 'sh'))
    local quoted = {}
    for _, path in ipairs { runner, executablePath, workDirectory } do
        local value, message = quote(path, platform)
        if not value then return failure('UnsafeCommandPath', message) end
        quoted[#quoted + 1] = value
    end
    local prefix = platform == 'windows'
        and 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File '
        or '/bin/sh '
    return prefix .. table.concat(quoted, ' ') .. ' ' .. tostring(timeoutSeconds)
end

local function fieldValue(value, numeric)
    if value == json.null then return nil end
    if type(value) == 'table' and getmetatable(value) and getmetatable(value).__jsontype == 'array'
        and #value == 1 then value = value[1] end
    if numeric then
        if type(value) ~= 'number' and type(value) ~= 'string' then return nil end
        local number = tonumber(value)
        if number and number > 0 and number < math.huge then return number end
    elseif type(value) == 'string' and value:find('%S') then
        return value
    end
    return nil
end

local function resolveProfileFilmSim(tags)
    local hasProfile = false
    for _, tag in ipairs(profileTags) do
        local value = fieldValue(tags[tag], false)
        if value then
            hasProfile = true
            local name = value:match('^%s*(.-)%s*$'):upper()
            name = name:gsub('^"(.*)"$', '%1'):gsub('^CAMERA%s+', '')
            name = name:gsub('%s+', ' '):gsub('%s+V%d+%.?%d*$', '')
            -- Only explicit aliases are recognized; arbitrary profile names are not film simulations.
            if profileNames[name] then return profileNames[name], tag, true end
        end
    end
    return nil, nil, hasProfile
end

function ExifTool.decodeMetadata(text, inputPath)
    if not validatePath(inputPath) then return failure('InvalidInputPath', '取得元の絶対パスが必要です。') end
    if type(text) ~= 'string' or #text > maxOutputBytes then
        return failure('OutputLimit', 'ExifTool の JSON 出力が不正か上限を超えています。')
    end
    local ok, records, position, decodeError = pcall(json.decode, text, 1, json.null)
    if not ok or decodeError or type(records) ~= 'table'
        or not getmetatable(records) or getmetatable(records).__jsontype ~= 'array'
        or #records ~= 1 or type(records[1]) ~= 'table' or records[1] == json.null
        or not getmetatable(records[1]) or getmetatable(records[1]).__jsontype ~= 'object'
        or text:sub(position or 1):find('%S') then
        return failure('InvalidJson', '単一ファイルのメタデータ JSON を解析できません。')
    end
    local tags = records[1]
    if tags.SourceFile ~= inputPath then
        return failure('SourceMismatch', 'JSON の取得元が指定ファイルと一致しません。')
    end
    local metadataError = tags['ExifTool:Error'] or tags.Error
    if metadataError and metadataError ~= json.null then
        return failure('MetadataError', tostring(metadataError))
    end
    local result = { metadata = {}, fieldSources = {}, rawTags = tags, warnings = {}, missingFields = {} }
    local extension = LrPathUtils.extension(inputPath):lower()
    local sourceKind = extension == 'xmp' and 'xmp' or (extension == 'raf' or extension == 'dng') and 'raw' or 'jpeg'
    for field, candidates in pairs(fieldTags) do
        for _, tag in ipairs(candidates) do
            local value = fieldValue(tags[tag], field == 'iso' or field == 'focalLength')
            if field == 'iso' and value and value ~= math.floor(value) then value = nil end
            if value ~= nil then
                result.metadata[field] = value
                result.fieldSources[field] = { sourcePath = inputPath, sourceKind = sourceKind, tag = tag }
                break
            end
        end
        if result.metadata[field] == nil then result.missingFields[#result.missingFields + 1] = field end
    end
    local saturation = tags['FujiFilm:Saturation']
    local filmMode = tags['FujiFilm:FilmMode']
    local filmSim = type(saturation) == 'number' and monochromeModes[saturation] or nil
    local filmTag = 'FujiFilm:Saturation'
    if not filmSim then
        filmSim = type(filmMode) == 'number' and filmModes[filmMode] or nil
        filmTag = 'FujiFilm:FilmMode'
    end
    local profileSim, profileTag, hasProfile = resolveProfileFilmSim(tags)
    -- DNG/JPEG can retain capture MakerNotes after a different development profile is saved.
    local preferDevelopmentProfile = sourceKind == 'xmp' or extension == 'dng' or sourceKind == 'jpeg'
    if profileSim and (preferDevelopmentProfile or not filmSim) then
        filmSim, filmTag = profileSim, profileTag
    end
    result.metadata.filmSim = filmSim
    if filmSim then
        result.fieldSources.filmSim = { sourcePath = inputPath, sourceKind = sourceKind, tag = filmTag }
    else
        result.missingFields[#result.missingFields + 1] = 'filmSim'
        if filmMode ~= nil or saturation ~= nil then
            result.warnings[#result.warnings + 1] = 'FilmSim のコードが未対応のため値を推測しません。'
        end
        if hasProfile then
            result.warnings[#result.warnings + 1] = 'XMP のプロファイル名が対応するフィルム名に一致しません。'
        end
    end
    local warning = tags['ExifTool:Warning'] or tags.Warning
    if warning and warning ~= json.null then result.warnings[#result.warnings + 1] = tostring(warning) end
    table.sort(result.missingFields)
    result.toolVersion = tags['ExifTool:ExifToolVersion']
    return result
end

local function createWorkDirectory()
    local root = LrPathUtils.getStandardFilePath('temp')
    for attempt = 1, 10 do
        local name = 'fuji-exiftool-' .. tostring(os.time()) .. '-' .. tostring(math.random(1, 1000000000))
        local path = LrPathUtils.child(root, name)
        -- The SDK's created flag distinguishes our directory from an existing one.
        local ok, created = LrFileUtils.createAllDirectories(path)
        if ok and created == true then return path end
        if not ok then return nil, tostring(created) end
    end
    return nil, '専用作業フォルダーを確保できません。'
end

local function cleanup(workDirectory)
    local warnings = {}
    for _, name in ipairs(ownedFiles) do
        local path = LrPathUtils.child(workDirectory, name)
        if LrFileUtils.exists(path) then
            local ok, message = LrFileUtils.delete(path)
            if not ok then warnings[#warnings + 1] = tostring(message or '一時ファイルを削除できません。') end
        end
    end
    if LrFileUtils.isEmptyDirectory(workDirectory) then
        local ok, message = LrFileUtils.delete(workDirectory)
        if not ok then warnings[#warnings + 1] = tostring(message or '作業フォルダーを削除できません。') end
    else
        warnings[#warnings + 1] = '作業フォルダーが空でないため再帰削除しません。'
    end
    return warnings
end

function ExifTool.resolveExecutablePath(options)
    options = options or {}
    if type(options) ~= 'table' then return failure('InvalidOptions', '設定はテーブルで指定してください。') end
    local platform = context.platform
    if not platform then return failure('UnsupportedPlatform', 'Windows / macOS のみ対応します。') end
    local pluginPath = options.pluginPath or context.pluginPath
    local path = options.executablePath
        or LrPathUtils.child(pluginPath, platform == 'windows' and 'vendor/windows/exiftool.exe' or 'vendor/macos/exiftool')
    if not validatePath(path) or LrFileUtils.exists(path) ~= 'file' then
        return failure('ExecutableMissing', '同梱 ExifTool がありません。検証時は実行ファイルの絶対パスを指定してください。')
    end
    return path
end

local function runWork(executablePath, pluginPath, workDirectory, timeoutSeconds, arguments)
    local command, commandError = ExifTool.buildCommand(executablePath, pluginPath, workDirectory, timeoutSeconds, context.platform)
    if not command then return nil, commandError end
    local handle, openError = io.open(LrPathUtils.child(workDirectory, 'arguments.txt'), 'wb')
    if not handle then return failure('ArgumentFileError', tostring(openError)) end
    local written, writeError = handle:write(arguments)
    local closed, closeError = handle:close()
    if not written or not closed then return failure('ArgumentFileError', tostring(writeError or closeError)) end
    local shellCode = LrTasks.execute(command)
    local statusPath = LrPathUtils.child(workDirectory, 'exit-code.txt')
    if LrFileUtils.exists(statusPath) ~= 'file' then return failure('RunnerError', '終了コードを取得できません。', { shellCode = shellCode }) end
    local exitCode = tonumber(LrFileUtils.readFile(statusPath))
    if LrFileUtils.exists(LrPathUtils.child(workDirectory, 'process-running.txt')) then
        return failure('ProcessNotStopped', 'ExifTool の終了を確認できません。', { exitCode = exitCode, workDirectory = workDirectory })
    end
    if LrFileUtils.exists(LrPathUtils.child(workDirectory, 'timed-out.txt')) then
        if context.platform == 'windows' and exitCode ~= 124 then
            return failure('ProcessNotStopped', '時間上限後の終了を確認できません。', { exitCode = exitCode, workDirectory = workDirectory })
        end
        return failure('Timeout', 'ExifTool の実行時間が上限を超えました。', { exitCode = 124 })
    end
    local output, stderr = '', ''
    for _, name in ipairs { 'stdout.json', 'stderr.txt' } do
        local path = LrPathUtils.child(workDirectory, name)
        if LrFileUtils.exists(path) == 'file' then
            if (LrFileUtils.fileAttributes(path).fileSize or 0) > maxOutputBytes then return failure('OutputLimit', 'ExifTool 出力が上限を超えています。') end
            if name == 'stdout.json' then output = LrFileUtils.readFile(path) else stderr = LrFileUtils.readFile(path) end
        elseif name == 'stdout.json' then return failure('OutputMissing', 'ExifTool 出力がありません。') end
    end
    if exitCode ~= 0 or shellCode ~= 0 then
        return failure('ProcessFailed', 'ExifTool の処理に失敗しました。', { exitCode = exitCode, shellCode = shellCode, stderr = stderr, stdout = output })
    end
    return { stdout = output, stderr = stderr, exitCode = exitCode }
end

local function readMetadata(inputPath, options)
    options = options or {}
    if type(options) ~= 'table' then return failure('InvalidOptions', '設定はテーブルで指定してください。') end
    local arguments, argumentError = ExifTool.buildReadArguments(inputPath)
    if not arguments then return nil, argumentError end
    if LrFileUtils.exists(inputPath) ~= 'file' or not LrFileUtils.isReadable(inputPath) then
        return failure('InputUnreadable', '入力ファイルが存在しないか、読み取れません。')
    end
    local extension = LrPathUtils.extension(inputPath):lower()
    if extension ~= 'raf' and extension ~= 'dng' and extension ~= 'jpg'
        and extension ~= 'jpeg' and extension ~= 'xmp' then
        return failure('UnsupportedInput', 'RAF / DNG / JPG / JPEG / XMP のみ読み取れます。')
    end
    local platform = context.platform
    if not platform then return failure('UnsupportedPlatform', 'Windows / macOS のみ対応します。') end
    local pluginPath = options.pluginPath or context.pluginPath
    local executablePath, executableError = ExifTool.resolveExecutablePath(options)
    if not executablePath then return nil, executableError end
    local timeoutSeconds = options.timeoutSeconds or 30
    local workDirectory, workError = createWorkDirectory()
    if not workDirectory then return failure('WorkDirectoryError', workError) end
    local executionAttempted = false
    local executionFinished = false
    local ok, result, readError = LrTasks.pcall(function()
        executionAttempted = true
        local output, processError = runWork(executablePath, pluginPath, workDirectory, timeoutSeconds, arguments)
        executionFinished = true
        if not output then
            if processError.code == 'ProcessFailed' and processError.stdout then
                local _, outputError = ExifTool.decodeMetadata(processError.stdout, inputPath)
                if outputError and outputError.code == 'MetadataError' then
                    processError.stderr = processError.stderr .. (processError.stderr == '' and '' or '\n') .. outputError.message
                end
            end
            return nil, processError
        end
        local decoded, jsonError = ExifTool.decodeMetadata(output.stdout, inputPath)
        if not decoded then return nil, jsonError end
        decoded.exitCode = output.exitCode
        if output.stderr:find('%S') then decoded.warnings[#decoded.warnings + 1] = output.stderr end
        return decoded
    end)
    local cleanupOk, cleanupWarnings
    if not ok and executionAttempted and not executionFinished
        or readError and (readError.code == 'ProcessNotStopped' or readError.code == 'RunnerError'
        or platform == 'windows' and readError.exitCode == 125) then
        cleanupOk, cleanupWarnings = true, { 'プロセスの状態が未確定のため作業フォルダーを残します：' .. workDirectory }
    else
        cleanupOk, cleanupWarnings = LrTasks.pcall(cleanup, workDirectory)
    end
    if not cleanupOk then cleanupWarnings = { '一時ファイルの清掃に失敗しました：' .. tostring(cleanupWarnings) } end
    if not ok then
        result, readError = failure('SdkError', 'SDK / I/O 処理に失敗しました：' .. tostring(result),
            { workDirectory = not executionFinished and executionAttempted and workDirectory or nil })
    end
    if result then
        for _, warning in ipairs(cleanupWarnings) do result.warnings[#result.warnings + 1] = warning end
    elseif readError then
        readError.cleanupWarnings = cleanupWarnings
    end
    return result, readError
end

function ExifTool.readMetadata(inputPath, options)
    local ok, result, readError = LrTasks.pcall(readMetadata, inputPath, options)
    if not ok then return failure('SdkError', 'SDK / I/O 処理に失敗しました：' .. tostring(result)) end
    return result, readError
end

local pending = setmetatable({}, { __mode = 'k' })
function ExifTool.prepareC2pa(cap, options)
    options = options or {}
    if type(options) ~= 'table' then return failure('InvalidOptions', '設定はテーブルで指定してください。') end
    if pending[cap] then return failure('ArtifactRejected', '処理中の artifact は再利用できません。') end
    if not context.artifacts then return failure('ArtifactRejected', '書き出し artifact の所有確認が必要です。') end
    local source, sourceError = context.artifacts.source(cap)
    if not source then return nil, sourceError end
    local executable, executableError = ExifTool.resolveExecutablePath(options)
    if not executable then return nil, executableError end
    local work, workError = createWorkDirectory()
    if not work then return failure('WorkDirectoryError', workError) end
    pending[cap] = { work = work, retain = false }
    local ok, result, err = LrTasks.pcall(function()
        local target, targetError = context.artifacts.bindWork(cap, work)
        if not target then return nil, targetError end
        local args = table.concat({ '-o', target, '-jumbf:all=', '--', source }, '\n') .. '\n'
        -- -o creates a new file; never combine it with overwrite_original (which could delete the input).
        pending[cap].retain = true
        local output, processError = runWork(executable, context.pluginPath, work, options.timeoutSeconds or 30, args)
        if processError and (processError.code == 'ProcessNotStopped' or processError.code == 'RunnerError'
            or context.platform == 'windows' and processError.exitCode == 125) then return nil, processError end
        pending[cap].retain = false
        if not output then return nil, processError end
        if output.stderr:find('%S') then return failure('C2paWarning', '削除処理の警告を確認してください。', { stderr = output.stderr }) end
        local verified, verificationError = context.artifacts.verify(cap)
        if not verified then return nil, verificationError end
        local readArgs = table.concat({ '-j', '-G1', '-s', '-JUMBF:all', '-Error', '-Warning', '--', target }, '\n') .. '\n'
        pending[cap].retain = true
        local reread, rereadError = runWork(executable, context.pluginPath, work, options.timeoutSeconds or 30, readArgs)
        if rereadError and (rereadError.code == 'ProcessNotStopped' or rereadError.code == 'RunnerError'
            or context.platform == 'windows' and rereadError.exitCode == 125) then return nil, rereadError end
        pending[cap].retain = false
        if not reread then return nil, rereadError end
        if reread.stderr:find('%S') then return failure('C2paWarning', '削除後の読取に警告があります。', { stderr = reread.stderr }) end
        local records, position, jsonError = json.decode(reread.stdout)
        if jsonError or not position or reread.stdout:sub(position):find('%S')
            or type(records) ~= 'table' or #records ~= 1 or type(records[1]) ~= 'table'
            or type(records[1].SourceFile) ~= 'string'
            or LrPathUtils.standardizePath(records[1].SourceFile) ~= LrPathUtils.standardizePath(target) then
            return failure('C2paVerificationFailed', '削除後の JSON を確認できません。')
        end
        for key in pairs(records[1]) do
            if key ~= 'SourceFile' then return failure('C2paVerificationFailed', 'JUMBF が残るか、削除後の読取に診断があります。') end
        end
        return { artifact = cap, warnings = {} }
    end)
    if not ok then return failure('SdkError', tostring(result), { workDirectory = work }) end
    return result, err
end
function ExifTool.releaseC2pa(cap)
    local record = pending[cap]
    if not record then return {} end
    if record.retain then return { '実行状態が未確定のため作業フォルダーを保持します：' .. record.work } end
    local target = LrPathUtils.child(record.work, 'cleaned.jpg')
    local warnings = {}
    if LrFileUtils.exists(target) and not context.artifacts.canClean(cap, target) then
        return { '作業コピーの参照先を確認できないため清掃せず保持します：' .. record.work }
    end
    if LrFileUtils.exists(target) then
        local deleted, message = LrFileUtils.delete(target)
        if not deleted then warnings[#warnings + 1] = tostring(message) end
    end
    for _, warning in ipairs(cleanup(record.work)) do warnings[#warnings + 1] = warning end
    pending[cap] = nil; context.artifacts.forget(cap)
    return warnings
end

return ExifTool
