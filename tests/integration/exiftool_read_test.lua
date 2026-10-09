-- Run at the repository root with Lua 5.1 (POSIX build on macOS).
package.path = 'src/FujiPhotoRenamer.lrplugin/?.lua;./?.lua;' .. package.path
local pipe = assert(io.popen('pwd'))
local root = pipe:read('*l'); assert(pipe:close())
local sdk = require('tests.support.lightroom_native').install(root .. '/src/FujiPhotoRenamer.lrplugin')
local ExifTool = assert(loadfile(root .. '/src/FujiPhotoRenamer.lrplugin/ExifToolLoader.lua')) {
    fileUtils = sdk.LrFileUtils, pathUtils = sdk.LrPathUtils, tasks = sdk.LrTasks,
    pluginPath = root .. '/src/FujiPhotoRenamer.lrplugin', platform = 'macos',
}
local json = require 'dkjson.lua'
local testCount = 0
local inputPath = '/fixtures/sample.RAF'

local function equal(actual, expected)
    assert(actual == expected, string.format('Expected %s, got %s', tostring(expected), tostring(actual)))
end
local function test(name, callback)
    callback(); testCount = testCount + 1; print('PASS ' .. name)
end
local function readFile(path)
    local handle = assert(io.open(path, 'rb')); local text = handle:read('*a'); assert(handle:close()); return text
end
local function writeFile(path, text)
    local handle = assert(io.open(path, 'wb')); assert(handle:write(text)); assert(handle:close())
end
local function fixture()
    local data = assert(json.decode(readFile('fixtures/metadata/phase2-fujifilm.json')))
    return data
end
local function quote(value) return "'" .. value:gsub("'", "'\\''") .. "'" end

test('registers a loadable diagnostic command in both File and Library menus', function()
    local info = dofile('src/FujiPhotoRenamer.lrplugin/Info.lua')
    assert(info.LrExportServiceProvider)
    for _, items in ipairs { info.LrExportMenuItems, info.LrLibraryMenuItems } do
        equal(#items, 1)
        equal(items[1].file, 'Phase2Diagnostic.lua')
        assert(loadfile(root .. '/src/FujiPhotoRenamer.lrplugin/' .. items[1].file))
        equal(items[1].enabledWhen, nil)
    end
    equal(info.LrExportMenuItems[1].file, info.LrLibraryMenuItems[1].file)
end)

test('rejects subdirectory and dotted module paths as Lightroom does', function()
    for _, name in ipairs { 'infrastructure/ExifTool.lua', 'third_party/dkjson.lua', 'infrastructure.ExifTool' } do
        local ok, message = pcall(require, name)
        equal(ok, false)
        assert(tostring(message):find('require: invalid characters in script name', 1, true))
    end
end)

test('does not assume SDK require appends the .lua extension', function()
    local ok, message = pcall(require, 'ExifToolLoader')
    equal(ok, false)
    assert(tostring(message):find('Could not load toolkit script: ExifToolLoader', 1, true))
    equal(require('dkjson.lua').version, 'dkjson 2.11')
end)

test('starts the diagnostic even when SDK require cannot find newly added files', function()
    local previousRequire = require
    local calls = {}
    local diagnosticImports = {
        LrFileUtils = sdk.LrFileUtils, LrPathUtils = sdk.LrPathUtils,
        LrTasks = { pcall = pcall, startAsyncTask = function(callback) callback() end },
        LrDialogs = {
            runOpenPanel = function() calls.panel = true; return nil end,
            message = function(title, message) error(title .. ': ' .. tostring(message)) end,
        },
    }
    local previousImport = import
    _G.require = function(name) error('Could not load toolkit script: ' .. name) end
    _G.import = function(name) return assert(diagnosticImports[name]) end
    local ok, message = pcall(dofile, root .. '/src/FujiPhotoRenamer.lrplugin/Phase2Diagnostic.lua')
    _G.require, _G.import = previousRequire, previousImport
    assert(ok, message)
    assert(calls.panel, 'Diagnostic did not reach the executable selection panel')
end)

test('decodes the observed RAF tag groups into eight internal fields', function()
    local result = assert(ExifTool.decodeMetadata(json.encode(fixture()), inputPath))
    equal(result.metadata.cameraMaker, 'FUJIFILM'); equal(result.metadata.camera, 'X-H2S')
    equal(result.metadata.lensMaker, 'FUJIFILM'); equal(result.metadata.filmSim, 'PROVIA')
    equal(result.metadata.iso, 160); equal(result.metadata.focalLength, 280)
    equal(#result.missingFields, 0)
    equal(result.metadata.Make, nil); equal(result.metadata['FujiFilm:FilmMode'], nil)
    equal(result.fieldSources.filmSim.sourceKind, 'raw')
end)

test('does not infer a missing lens manufacturer from the camera', function()
    local data = fixture(); data[1]['ExifIFD:LensMake'] = nil
    local result = assert(ExifTool.decodeMetadata(json.encode(data), inputPath))
    equal(result.metadata.lensMaker, nil); equal(result.metadata.cameraMaker, 'FUJIFILM')
end)

for _, value in ipairs { json.null, '', '   ', false, { unknown = true } } do
    test('marks an invalid or empty manufacturer as missing: ' .. type(value), function()
        local data = fixture(); data[1]['ExifIFD:LensMake'] = value
        local result = assert(ExifTool.decodeMetadata(json.encode(data), inputPath))
        equal(result.metadata.lensMaker, nil)
    end)
end

for _, number in ipairs { 0, -1, 160.5 } do
    test('rejects an invalid ISO ' .. tostring(number), function()
        local data = fixture(); data[1]['ExifIFD:ISO'] = number
        local result = assert(ExifTool.decodeMetadata(json.encode(data), inputPath))
        equal(result.metadata.iso, nil)
    end)
end

test('preserves Japanese lens strings and Unicode escapes', function()
    local data = fixture(); data[1]['ExifIFD:LensModel'] = '検証レンズ'
    local result = assert(ExifTool.decodeMetadata(json.encode(data), inputPath))
    equal(result.metadata.lens, '検証レンズ')
    local escaped = '[{"SourceFile":"/fixtures/sample.RAF","ExifIFD:LensModel":"\\u691c\\u8a3c"}]'
    equal(assert(ExifTool.decodeMetadata(escaped, inputPath)).metadata.lens, '検証')
end)

test('decodes XMP namespaces and a one-element ISO array', function()
    local path = '/fixtures/sample.xmp'
    local data = { { SourceFile = path, ['XMP-tiff:Make'] = 'FUJIFILM', ['XMP-tiff:Model'] = 'X-H2S',
        ['XMP-exifEX:LensMake'] = 'TAMRON', ['XMP-exifEX:LensModel'] = 'Synthetic Lens',
        ['XMP-exif:ISO'] = { 800 }, ['XMP-exif:FocalLength'] = 23.5,
        ['XMP-exif:DateTimeOriginal'] = '2026:10:08 12:34:56+09:00' } }
    local result = assert(ExifTool.decodeMetadata(json.encode(data), path))
    equal(result.metadata.iso, 800); equal(result.metadata.lensMaker, 'TAMRON')
    equal(result.metadata.filmSim, nil); equal(result.fieldSources.camera.sourceKind, 'xmp')
end)

for code, name in pairs { [0x300] = 'MONOCHROME', [0x301] = 'MONOCHROME_R', [0x500] = 'ACROS', [0x503] = 'ACROS_G' } do
    test('resolves monochrome Saturation before FilmMode: ' .. name, function()
        local data = fixture(); data[1]['FujiFilm:Saturation'] = code
        local result = assert(ExifTool.decodeMetadata(json.encode(data), inputPath))
        equal(result.metadata.filmSim, name); equal(result.fieldSources.filmSim.tag, 'FujiFilm:Saturation')
    end)
end

test('leaves unknown film codes missing with a diagnostic', function()
    local data = fixture(); data[1]['FujiFilm:FilmMode'] = 65535
    local result = assert(ExifTool.decodeMetadata(json.encode(data), inputPath))
    equal(result.metadata.filmSim, nil); assert(#result.warnings > 0)
end)

for _, case in ipairs {
    { 'Camera PROVIA/Standard', 'PROVIA' }, { 'Camera Velvia/Vivid', 'VELVIA' },
    { 'Camera ASTIA/Soft', 'ASTIA' }, { 'Camera CLASSIC Neg', 'CLASSIC_NEGATIVE' },
    { 'Camera REALA ACE v2', 'REALA_ACE' }, { 'Camera ACROS+R Filter', 'ACROS_R' },
    { 'Camera ACROS+Ye Filter', 'ACROS_Y' }, { 'Camera MONOCHROME+G Filter', 'MONOCHROME_G' },
    { '  camera   PROVIA/Standard  ', 'PROVIA' },
} do
    test('resolves a known XMP CameraProfile: ' .. case[1], function()
        local path = '/fixtures/sample.xmp'
        local data = { { SourceFile = path, ['XMP-crs:CameraProfile'] = case[1] } }
        local result = assert(ExifTool.decodeMetadata(json.encode(data), path))
        equal(result.metadata.filmSim, case[2])
        equal(result.fieldSources.filmSim.tag, 'XMP-crs:CameraProfile')
        equal(result.rawTags['XMP-crs:CameraProfile'], case[1])
    end)
end

for _, name in ipairs { 'Adobe Color', 'Adobe Standard', 'My PROVIA preset', 'Camera Custom Film' } do
    test('does not guess a film simulation from an unrelated profile: ' .. name, function()
        local path = '/fixtures/sample.xmp'
        local data = { { SourceFile = path, ['XMP-crs:CameraProfile'] = name } }
        local result = assert(ExifTool.decodeMetadata(json.encode(data), path))
        equal(result.metadata.filmSim, nil); assert(#result.warnings > 0)
    end)
end

test('prefers the edited XMP LookName over CameraProfile and capture FilmMode', function()
    local data = fixture(); local path = '/fixtures/sample.xmp'; data[1].SourceFile = path
    data[1]['XMP-crs:LookName'] = 'Camera CLASSIC Neg'
    data[1]['XMP-crs:CameraProfile'] = 'Camera PROVIA/Standard'
    local result = assert(ExifTool.decodeMetadata(json.encode(data), path))
    equal(result.metadata.filmSim, 'CLASSIC_NEGATIVE')
    equal(result.fieldSources.filmSim.tag, 'XMP-crs:LookName')
end)

test('falls back from an unrecognized LookName to a recognized CameraProfile', function()
    local path = '/fixtures/sample.xmp'
    local data = { { SourceFile = path, ['XMP-crs:LookName'] = 'Custom Look',
        ['XMP-crs:CameraProfile'] = 'Camera PROVIA/Standard', ['XMP-crd:LookName'] = 'Camera REALA ACE' } }
    equal(assert(ExifTool.decodeMetadata(json.encode(data), path)).metadata.filmSim, 'PROVIA')
end)

test('keeps RAW capture simulation before embedded development profile', function()
    local data = fixture(); data[1]['XMP-crs:CameraProfile'] = 'Camera CLASSIC Neg'
    equal(assert(ExifTool.decodeMetadata(json.encode(data), inputPath)).metadata.filmSim, 'PROVIA')
end)

test('resolves one CameraProfilesProfileName but does not choose between several', function()
    local path = '/fixtures/sample.xmp'
    local data = { { SourceFile = path, ['XMP-crs:CameraProfilesProfileName'] = { 'Camera PROVIA/Standard' } } }
    equal(assert(ExifTool.decodeMetadata(json.encode(data), path)).metadata.filmSim, 'PROVIA')
    data[1]['XMP-crs:CameraProfilesProfileName'] = { 'Camera PROVIA/Standard', 'Camera CLASSIC Neg' }
    equal(assert(ExifTool.decodeMetadata(json.encode(data), path)).metadata.filmSim, nil)
end)

test('preserves ExifTool warnings', function()
    local data = fixture(); data[1]['ExifTool:Warning'] = 'Synthetic warning'
    equal(assert(ExifTool.decodeMetadata(json.encode(data), inputPath)).warnings[1], 'Synthetic warning')
end)

test('rejects an Error even in otherwise usable metadata', function()
    local data = fixture(); data[1]['ExifTool:Error'] = 'Synthetic error'
    local result, err = ExifTool.decodeMetadata(json.encode(data), inputPath)
    equal(result, nil); equal(err.code, 'MetadataError')
end)

for _, text in ipairs { '', '[', 'null', '42', '{}', '[]', '[null]', '[{},{}]', '[[]]', json.encode(fixture()) .. ' garbage' } do
    test('rejects malformed JSON or an unexpected record shape: ' .. text:sub(1, 15), function()
        local result, err = ExifTool.decodeMetadata(text, inputPath)
        equal(result, nil); equal(err.code, 'InvalidJson')
    end)
end

test('rejects a mismatched SourceFile', function()
    local result, err = ExifTool.decodeMetadata(json.encode(fixture()), '/fixtures/other.RAF')
    equal(result, nil); equal(err.code, 'SourceMismatch')
end)
test('rejects oversized JSON', function()
    local result, err = ExifTool.decodeMetadata(string.rep(' ', 1024 * 1024 + 1), inputPath)
    equal(result, nil); equal(err.code, 'OutputLimit')
end)

test('passes special photo names as data in a UTF-8 argument file', function()
    local path = "/fixtures/写真 ' $(touch harmless) % ! & ;.RAF"
    local arguments = assert(ExifTool.buildReadArguments(path))
    assert(arguments:find('\n--\n' .. path .. '\n', 1, true))
    assert(arguments:find('-FujiFilm:FilmMode', 1, true))
    assert(not arguments:find('-overwrite_original', 1, true))
end)
for _, path in ipairs { 'relative.RAF', '/fixtures/a\nb.RAF', '/fixtures/a\rb.RAF', '/fixtures/a\0b.RAF' } do
    test('rejects unsafe argument-file input paths', function()
        local result, err = ExifTool.buildReadArguments(path)
        equal(result, nil); equal(err.code, 'InvalidInputPath')
    end)
end

test('quotes macOS tool and work paths, including apostrophes', function()
    local command = assert(ExifTool.buildCommand("/Tools/Exif Tool's/exiftool", '/Plugins/My Plugin', '/tmp/owned work', 30, 'macos'))
    assert(command:find("Tool'\\''s", 1, true)); assert(command:find("'/tmp/owned work'", 1, true))
end)
test('quotes Windows paths without injecting the photo path into cmd.exe', function()
    local command = assert(ExifTool.buildCommand('C:\\Exif Tool\\exiftool.exe', 'C:\\Plugins\\My Plugin', 'C:\\Temp\\owned', 30, 'windows'))
    assert(command:find('"C:\\Exif Tool\\exiftool.exe"', 1, true))
    assert(command:find('ExifToolRead.ps1', 1, true))
end)
for _, path in ipairs { 'C:\\Tool%name\\exiftool.exe', 'C:\\Tool!name\\exiftool.exe', 'C:\\Tool^name\\exiftool.exe', 'C:\\Tool"name\\exiftool.exe' } do
    test('rejects cmd.exe expansion characters in execution paths', function()
        local result, err = ExifTool.buildCommand(path, 'C:\\Plugin', 'C:\\Temp', 30, 'windows')
        equal(result, nil); equal(err.code, 'UnsafeCommandPath')
    end)
end
for _, timeout in ipairs { 0, -1, 1.5, 121, '30' } do
    test('rejects invalid timeout ' .. tostring(timeout), function()
        local result, err = ExifTool.buildCommand('/tool', '/plugin', '/tmp/work', timeout, 'macos')
        equal(result, nil); equal(err.code, 'InvalidTimeout')
    end)
end

-- Native tests intentionally use small synthetic inputs and disposable test executables.
local directoryPipe = assert(io.popen('/usr/bin/mktemp -d /tmp/fuji-phase2-test-XXXXXX'))
local testDirectory = directoryPipe:read('*l'); assert(directoryPipe:close())
local createdFiles = {}
local function fakeExecutable(name, script)
    local path = testDirectory .. '/' .. name
    writeFile(path, '#!/bin/sh\n' .. script .. '\n'); createdFiles[#createdFiles + 1] = path
    assert(os.execute('/bin/chmod 700 ' .. quote(path)) == 0)
    return path
end
local samplePath = root .. '/fixtures/metadata/phase2-sample.xmp'
local function fakeOptions(path) return { executablePath = path, timeoutSeconds = 1 } end

test('returns a structured missing-executable error instead of falling back to PATH', function()
    local result, err = ExifTool.readMetadata(samplePath, { pluginPath = testDirectory .. '/missing-plugin' })
    equal(result, nil); equal(err.code, 'ExecutableMissing')
end)

for _, case in ipairs {
    { 'nonzero exit', 'printf failed >&2; exit 7', 'ProcessFailed', 7 },
    { 'broken JSON', "printf '['; exit 0", 'InvalidJson' },
    { 'timeout', 'exec /bin/sleep 5', 'Timeout', 124 },
} do
    test('handles a real process ' .. case[1], function()
        local executable = fakeExecutable('fake-' .. case[1]:gsub(' ', '-'), case[2])
        local result, err = ExifTool.readMetadata(samplePath, fakeOptions(executable))
        equal(result, nil); equal(err.code, case[3])
        if case[4] then equal(err.exitCode, case[4]) end
        equal(#err.cleanupWarnings, 0)
    end)
end

test('handles a real stdout Error with exit code zero', function()
    local data = { { SourceFile = samplePath, ['ExifTool:Error'] = 'Synthetic error' } }
    local executable = fakeExecutable('stdout-error', "printf '%s' " .. quote(json.encode(data)))
    local result, err = ExifTool.readMetadata(samplePath, fakeOptions(executable))
    equal(result, nil); equal(err.code, 'MetadataError')
end)

test('surfaces the JSON Error accompanying a nonzero exit', function()
    local data = { { SourceFile = samplePath, ['ExifTool:Error'] = 'Synthetic input failure' } }
    local executable = fakeExecutable('json-exit-error', "printf '%s' " .. quote(json.encode(data)) .. '; exit 2')
    local result, err = ExifTool.readMetadata(samplePath, fakeOptions(executable))
    equal(result, nil); equal(err.code, 'ProcessFailed'); equal(err.exitCode, 2)
    assert(err.stderr:find('Synthetic input failure', 1, true))
end)

test('surfaces stderr with otherwise valid JSON', function()
    local data = { { SourceFile = samplePath, ['XMP-tiff:Make'] = 'FUJIFILM' } }
    local executable = fakeExecutable('stderr-warning', "printf '%s' " .. quote(json.encode(data)) .. '; printf warning >&2')
    local result = assert(ExifTool.readMetadata(samplePath, fakeOptions(executable)))
    equal(result.metadata.cameraMaker, 'FUJIFILM'); equal(result.warnings[1], 'warning')
end)

test('preserves an SDK failure as a structured error', function()
    local previous = sdk.LrTasks.execute
    sdk.LrTasks.execute = function() error('Synthetic SDK failure') end
    local executable = fakeExecutable('unused-tool', 'exit 0')
    local result, err = ExifTool.readMetadata(samplePath, fakeOptions(executable))
    sdk.LrTasks.execute = previous
    equal(result, nil); equal(err.code, 'SdkError'); equal(#err.cleanupWarnings, 1)
    -- The test knows no child was started; the production caller cannot assume that.
    assert(sdk.LrFileUtils.delete(err.workDirectory .. '/arguments.txt'))
    assert(sdk.LrFileUtils.delete(err.workDirectory))
end)

if arg[1] then
    for _, case in ipairs {
        { 'phase2-lightroom-profile.xmp', 'PROVIA', 'XMP-crs:CameraProfile' },
        { 'phase2-lightroom-look.xmp', 'CLASSIC_NEGATIVE', 'XMP-crs:LookName' },
    } do
        test('reads the Lightroom profile tag from a real XMP fixture: ' .. case[1], function()
            local path = root .. '/fixtures/metadata/' .. case[1]
            local before = readFile(path)
            local result = assert(ExifTool.readMetadata(path, { executablePath = arg[1] }))
            equal(result.metadata.filmSim, case[2]); equal(result.fieldSources.filmSim.tag, case[3])
            equal(readFile(path), before)
        end)
    end
    test('reads a synthetic JPEG and leaves its exact bytes unchanged', function()
        local path = root .. '/fixtures/metadata/phase2-sample.jpg'
        local before = readFile(path)
        local result = assert(ExifTool.readMetadata(path, { executablePath = arg[1] }))
        equal(result.metadata.camera, 'X-H2S'); equal(result.metadata.lensMaker, 'FUJIFILM')
        equal(result.metadata.lens, 'Synthetic Test Lens'); equal(result.metadata.iso, 160)
        equal(result.metadata.focalLength, 280); equal(result.metadata.filmSim, nil)
        equal(result.fieldSources.camera.sourceKind, 'jpeg')
        equal(readFile(path), before)
    end)
    test('reads the synthetic XMP through the actual ExifTool', function()
        local before = readFile(samplePath)
        local result = assert(ExifTool.readMetadata(samplePath, { executablePath = arg[1] }))
        equal(result.metadata.camera, 'X-H2S'); equal(result.metadata.lensMaker, 'FUJIFILM')
        equal(result.metadata.iso, 160); equal(result.metadata.focalLength, 280)
        equal(result.metadata.filmSim, nil); equal(result.exitCode, 0)
        equal(readFile(samplePath), before); equal(#result.warnings, 0)
    end)
    test('reads a special photo filename without executing its contents', function()
        local path = testDirectory .. "/photo ' $(touch injected) % ! & ;.xmp"
        writeFile(path, readFile(samplePath)); createdFiles[#createdFiles + 1] = path
        local result = assert(ExifTool.readMetadata(path, { executablePath = arg[1] }))
        equal(result.metadata.camera, 'X-H2S')
        equal(sdk.LrFileUtils.exists(root .. '/injected'), false)
    end)
    if arg[2] then
        test('reads the user-authorized RAF without assuming all RAF models behave alike', function()
            local result, err = ExifTool.readMetadata(arg[2], { executablePath = arg[1] })
            assert(result, err and err.message)
            equal(result.metadata.cameraMaker, 'FUJIFILM'); equal(result.metadata.camera, 'X-H2S')
            equal(result.metadata.lensMaker, 'FUJIFILM'); equal(result.metadata.filmSim, 'PROVIA')
            assert(result.metadata.lens); equal(result.exitCode, 0); equal(#result.warnings, 0)
        end)
    end
    if arg[3] then
        test('reads the reported XMP CameraProfile as PROVIA without modifying the file', function()
            local before = readFile(arg[3])
            local result, err = ExifTool.readMetadata(arg[3], { executablePath = arg[1] })
            assert(result, err and err.message)
            equal(result.metadata.filmSim, 'PROVIA')
            equal(result.fieldSources.filmSim.tag, 'XMP-crs:CameraProfile')
            equal(readFile(arg[3]), before)
        end)
    end
else
    print('SKIP actual ExifTool checks: pass an explicit executable path to enable them.')
end

for _, path in ipairs(createdFiles) do assert(os.remove(path)) end
assert(os.remove(testDirectory))
print(string.format('%d Phase 2 tests passed; Lightroom and Windows manual integration remain required.', testCount))
