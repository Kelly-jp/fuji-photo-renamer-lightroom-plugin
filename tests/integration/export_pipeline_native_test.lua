-- Actual ExifTool and file reads/writes through a test SDK adapter, not Lightroom rendering.
package.path = './?.lua;' .. package.path
local pipe = assert(io.popen('pwd')); local root = pipe:read('*l'); assert(pipe:close())
local sdk = require('tests.support.lightroom_native').install(root .. '/src/FujiPhotoRenamer.lrplugin')
local executable = assert(arg[1], 'Pass an explicit ExifTool path')
local work = os.tmpname(); assert(os.remove(work)); assert(sdk.LrFileUtils.createAllDirectories(work))
local function read(path) local f = assert(io.open(path, 'rb')); local data = f:read('*a'); f:close(); return data end
local function write(path, data) local f = assert(io.open(path, 'wb')); assert(f:write(data)); assert(f:close()) end
local jpeg = read(root .. '/fixtures/metadata/phase2-sample.jpg')
local xmp = read(root .. '/fixtures/metadata/phase2-lightroom-look.xmp')
write(work .. '/sample.jpg', jpeg); write(work .. '/sample.xmp', xmp)
assert(sdk.LrFileUtils.createAllDirectories(work .. '/output'))
local context = { fileUtils = sdk.LrFileUtils, pathUtils = sdk.LrPathUtils, tasks = sdk.LrTasks,
    pluginPath = root .. '/src/FujiPhotoRenamer.lrplugin', platform = 'macos' }
local function loadModule(name, deps) return assert(loadfile(context.pluginPath .. '/' .. name))(deps) end
local copied = {}
sdk.LrFileUtils.move = function(source, destination)
    if sdk.LrFileUtils.exists(destination) then return false, 'Destination exists' end
    -- Test-only transfer under a private temp directory; race behavior is covered by the SDK boundary double.
    assert(destination:sub(1, #work + 1) == work .. '/')
    write(destination, read(source)); assert(os.remove(source)); copied[#copied + 1] = destination; return true
end
local messages = {}
sdk.LrDialogs = { message = function(title, message) messages[#messages + 1] = { title, message } end }
sdk.LrView = { bind = function(key) return key end }
local selectedPhoto
sdk.LrApplication = { activeCatalog = function() return { getTargetPhoto = function() return selectedPhoto end } end }
sdk.LrTasks.startAsyncTask = function(callback) callback() end
_G.import = function(name) return assert(sdk[name], name) end
local provider = assert(loadfile(context.pluginPath .. '/ExportServiceProvider.lua'))()
local count = 0
local function test(name, callback) callback(); count = count + 1; print('PASS ' .. name) end
local function export(template, directPath)
    local settings = { fprExifToolPath = executable, fprTemplate = template,
        LR_export_destinationType = 'specificFolder', LR_export_destinationPathPrefix = work .. '/output' }
    local renderedPath = directPath or work .. '/render.jpg'
    assert(not sdk.LrFileUtils.exists(renderedPath), 'Refusing to overwrite an existing test file')
    write(renderedPath, jpeg)
    provider.updateExportSettings(settings)
    local failures, emitted = {}, false
    local progress = { isCanceled = function() return false end, cancel = function() error('Unexpected cancel') end }
    provider.processRenderedPhotos({}, {
        propertyTable = settings, configureProgress = function() return progress end,
        renditions = function() return function()
            if emitted then return end; emitted = true
            return 1, { photo = { getRawMetadata = function(_, key) assert(key == 'path'); return work .. '/sample.jpg' end },
                waitForRender = function() return true, renderedPath end,
                uploadFailed = function(_, message) failures[#failures + 1] = message end }
        end end,
    })
    assert(#failures == 0, table.concat(failures, '\n'))
end
test('loads the registered entry and previews selected metadata through actual ExifTool', function()
    local props = assert(loadfile('tests/support/observable_properties.lua'))() {
        fprTemplate = '{FilmSim}_{Original}', fprExifToolPath = executable,
    }
    provider.startDialog(props)
    selectedPhoto = { getRawMetadata = function(_, key) assert(key == 'path'); return work .. '/sample.jpg' end }
    local factory = {}
    for _, name in ipairs { 'static_text', 'edit_field', 'push_button', 'row', 'popup_menu', 'checkbox' } do
        factory[name] = function(_, specification) return specification end
    end
    local invoked = false
    for _, control in ipairs(provider.sectionsForTopOfDialog(factory, props)[1]) do
        if control.title == '選択中の写真でプレビューを更新' then control.action(); invoked = true end
    end
    assert(invoked and props.fprPreview == 'CLASSIC-Neg_sample.jpg')
    provider.endDialog(props); selectedPhoto = nil
end)
test('reads actual XMP JPEG and exports the merged edited FilmSim', function()
    export('{DateTime}_{CameraMaker}_{FilmSim}_{Original}')
    assert(copied[1] == work .. '/output/20261008_123456_FUJIFILM_CLASSIC-Neg_sample.jpg')
    assert(read(copied[1]) == jpeg)
end)
test('keeps an existing output and writes a numbered collision copy', function()
    local before = read(copied[1]); export('{DateTime}_{CameraMaker}_{FilmSim}_{Original}')
    assert(copied[2] == work .. '/output/20261008_123456_FUJIFILM_CLASSIC-Neg_sample_001.jpg')
    assert(read(copied[1]) == before and read(copied[2]) == jpeg)
end)
test('transfers a standard-name rendition from the output folder without leaving a second file', function()
    local ordinary = work .. '/output/ordinary.jpg'
    export('{FilmSim}_{Original}', ordinary)
    assert(not sdk.LrFileUtils.exists(ordinary))
    assert(read(work .. '/output/CLASSIC-Neg_sample.jpg') == jpeg)
end)
test('keeps an SDK rendition already at the final name as one output', function()
    local final = work .. '/output/sample.jpg'
    local before = #copied
    export('{Original}', final)
    assert(#copied == before and read(final) == jpeg)
    assert(not sdk.LrFileUtils.exists(work .. '/output/sample_001.jpg'))
    assert(os.remove(final))
end)
test('keeps original JPEG XMP byte-identical and transfers the SDK render', function()
    assert(read(work .. '/sample.jpg') == jpeg and read(work .. '/sample.xmp') == xmp and not sdk.LrFileUtils.exists(work .. '/render.jpg'))
end)
-- Only known files created by this test are removed.
for _, path in ipairs(copied) do assert(os.remove(path)) end
for _, name in ipairs { 'sample.jpg', 'sample.xmp' } do assert(os.remove(work .. '/' .. name)) end
assert(os.remove(work .. '/output')); assert(os.remove(work))
print(string.format('%d Phase 9 native pipeline tests passed; Lightroom and Windows verification remain separate.', count))
