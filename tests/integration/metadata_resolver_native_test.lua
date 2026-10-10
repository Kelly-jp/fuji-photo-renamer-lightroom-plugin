-- Native ExifTool reads through the SDK test adapter; export is not involved.
package.path = './?.lua;' .. package.path
local pipe = assert(io.popen('pwd')); local root = pipe:read('*l'); assert(pipe:close())
local sdk = require('tests.support.lightroom_native').install(root .. '/src/FujiPhotoRenamer.lrplugin')
local context = { fileUtils = sdk.LrFileUtils, pathUtils = sdk.LrPathUtils, tasks = sdk.LrTasks,
    pluginPath = root .. '/src/FujiPhotoRenamer.lrplugin', platform = 'macos' }
local reader = assert(loadfile(context.pluginPath .. '/ExifToolLoader.lua'))(context)
local resolver = assert(loadfile(context.pluginPath .. '/core/MetadataResolver.lua'))()
local count = 0
local function readFile(path)
    local handle = assert(io.open(path, 'rb')); local text = handle:read('*a'); handle:close(); return text
end
local function test(name, callback) callback(); count = count + 1; print('PASS ' .. name) end
local function envelope(result) return { metadata = result.metadata, fieldSources = result.fieldSources } end
local executable = assert(arg[1], 'Pass an explicit ExifTool executable path')
local profilePath = root .. '/fixtures/metadata/phase2-lightroom-look.xmp'
local jpegPath = root .. '/fixtures/metadata/phase2-sample.jpg'
local profileBefore, jpegBefore = readFile(profilePath), readFile(jpegPath)
local xmp = assert(reader.readMetadata(profilePath, { executablePath = executable }))
local jpeg = assert(reader.readMetadata(jpegPath, { executablePath = executable }))
local raw = assert(reader.decodeMetadata(readFile('fixtures/metadata/phase2-fujifilm.json'), '/fixtures/sample.RAF'))
local json = require 'dkjson.lua'

test('merges a changed embedded DNG profile before JPEG capture metadata', function()
    local data = assert(json.decode(readFile('fixtures/metadata/phase2-fujifilm.json')))
    data[1].SourceFile = '/fixtures/sample.DNG'
    data[1]['XMP-crs:CameraProfile'] = 'Camera CLASSIC Neg'
    local dng = assert(reader.decodeMetadata(json.encode(data), '/fixtures/sample.DNG'))
    local result = assert(resolver.resolve { raw = envelope(dng), jpeg = envelope(raw) })
    assert(result.metadata.filmSim == 'CLASSIC_NEGATIVE')
    assert(result.fieldSources.filmSim.sourceKind == 'raw')
    assert(result.fieldSources.filmSim.tag == 'XMP-crs:CameraProfile')
end)

test('combines actual XMP/JPEG reads with normalized synthetic RAW metadata by field', function()
    local result = assert(resolver.resolve { xmp = envelope(xmp), raw = envelope(raw), jpeg = envelope(jpeg) })
    assert(result.metadata.filmSim == 'CLASSIC_NEGATIVE' and result.fieldSources.filmSim.sourceKind == 'xmp')
    assert(result.metadata.camera == 'X-H2S' and result.fieldSources.camera.sourceKind == 'raw')
    assert(result.fieldSources.captureDateTime.sourceKind == 'raw')
    assert(result.fieldSources.filmSim.tag == 'XMP-crs:LookName')
end)
test('fills fields directly from JPEG when XMP lacks them and RAW is absent', function()
    local result = assert(resolver.resolve { xmp = envelope(xmp), jpeg = envelope(jpeg) })
    assert(result.metadata.iso == 160 and result.fieldSources.iso.sourceKind == 'jpeg')
    assert(result.metadata.filmSim == 'CLASSIC_NEGATIVE')
end)
test('keeps native inputs byte-identical', function()
    assert(readFile(profilePath) == profileBefore and readFile(jpegPath) == jpegBefore)
end)
for _, choice in ipairs { 'ok', 'cancel' } do
    test('dispatches merged metadata or cancellation without new SDK script names: ' .. choice, function()
        local previousImport, previousRequire = import, require
        local confirms, panels, messages = 0, 0, {}
        local namespaces = {
            LrFileUtils = sdk.LrFileUtils, LrPathUtils = sdk.LrPathUtils,
            LrTasks = { pcall = pcall, execute = sdk.LrTasks.execute, startAsyncTask = function(callback) callback() end },
            LrDialogs = {
                confirm = function() confirms = confirms + 1; return confirms == 1 and 'other' or choice end,
                runOpenPanel = function()
                    panels = panels + 1
                    return { panels == 1 and executable or jpegPath }
                end,
                message = function(title, info) messages[#messages + 1] = { title, info } end,
            },
        }
        _G.import = function(name) return assert(namespaces[name]) end
        _G.require = function(name) error('No script by the name ' .. name) end
        local ok, message = pcall(dofile, context.pluginPath .. '/Phase2Diagnostic.lua')
        _G.import, _G.require = previousImport, previousRequire
        assert(ok, message)
        if choice == 'ok' then
            assert(panels == 2 and #messages == 1 and messages[1][1] == 'Phase 4：項目単位の統合結果')
            assert(messages[1][2]:find('（xmp）', 1, true))
            assert(messages[1][2]:find('CameraMaker 比較キー：FUJIFILM', 1, true))
            assert(messages[1][2]:find('LensMaker 比較キー：FUJIFILM', 1, true))
            assert(messages[1][2]:find('同一メーカー：はい', 1, true))
            assert(messages[1][2]:find('ファイル名候補（Phase 6）', 1, true))
            assert(messages[1][2]:find('省略 ON：20261008_123456_FUJIFILM_X-H2S_Synthetic-Test-Lens_phase2-sample.jpg', 1, true))
            assert(messages[1][2]:find('省略 OFF：20261008_123456_FUJIFILM_X-H2S_FUJIFILM_Synthetic-Test-Lens_phase2-sample.jpg', 1, true))
            assert(messages[1][2]:find('Phase 7 整形後：20261008_123456_FUJIFILM_X-H2S_Synthetic-Test-Lens_phase2-sample.jpg', 1, true))
            assert(messages[1][2]:find('同名ありを仮定した例：20261008_123456_FUJIFILM_X-H2S_Synthetic-Test-Lens_phase2-sample_001.jpg', 1, true))
            assert(messages[1][2]:find('上の候補も使用済みと仮定した例：20261008_123456_FUJIFILM_X-H2S_Synthetic-Test-Lens_phase2-sample_002.jpg', 1, true))
            assert(messages[1][2]:find('衝突例は仮想データ', 1, true))
            assert(readFile(profilePath) == profileBefore and readFile(jpegPath) == jpegBefore)
        else
            assert(panels == 0 and #messages == 0)
        end
    end)
end

if arg[2] then
    test('merges the user-authorized real related sources', function()
        local scanner = assert(loadfile(context.pluginPath .. '/infrastructure/MetadataSourceResolver.lua'))(context)
        local paths, scanError = scanner.resolve(arg[2], 'same_then_parent')
        assert(paths, scanError and scanError.message)
        local sources = {}
        for _, kind in ipairs { 'xmp', 'raw', 'jpeg' } do
            if paths[kind] then
                local result, readError = reader.readMetadata(paths[kind], { executablePath = executable })
                assert(result, readError and readError.message)
                sources[kind] = envelope(result)
            end
        end
        local result = assert(resolver.resolve(sources))
        assert(result.metadata.camera == 'X-H2S' and result.metadata.filmSim == 'PROVIA')
        assert(result.fieldSources.filmSim.sourceKind == 'xmp')
    end)
end
print(string.format('%d Phase 4 native tests passed; Lightroom integration remains separate.', count))
