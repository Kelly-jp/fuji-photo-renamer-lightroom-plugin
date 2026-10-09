-- Real macOS filesystem through a test adapter; no ExifTool is involved.
package.path = './?.lua;' .. package.path
local function quote(value) return "'" .. value:gsub("'", "'\\''") .. "'" end
local pipe = assert(io.popen('pwd')); local root = pipe:read('*l'); assert(pipe:close())
local sdk = require('tests.support.lightroom_native').install(root .. '/src/FujiPhotoRenamer.lrplugin')
local resolver = assert(loadfile('src/FujiPhotoRenamer.lrplugin/infrastructure/MetadataSourceResolver.lua')) {
    fileUtils = sdk.LrFileUtils, pathUtils = sdk.LrPathUtils, tasks = sdk.LrTasks,
}
local directoryPipe = assert(io.popen('/usr/bin/mktemp -d /tmp/fuji-phase3-test-XXXXXX'))
local directory = directoryPipe:read('*l'); assert(directoryPipe:close())
local jpegDirectory = directory .. '/書き出し JPG'
assert(os.execute('/bin/mkdir ' .. quote(jpegDirectory)) == 0)
local created = {}
local function write(path)
    local handle = assert(io.open(path, 'wb')); assert(handle:write('synthetic fixture')); assert(handle:close())
    created[#created + 1] = path
end
local function bytes(path)
    local handle = assert(io.open(path, 'rb')); local text = handle:read('*a'); handle:close(); return text
end
local jpg = jpegDirectory .. '/写真.v2.JPG'
local raw = directory .. '/写真.v2.rAf'
local xmp = directory .. '/写真.v2.XMP'
write(jpg); write(raw); write(xmp)
local before = { [jpg] = bytes(jpg), [raw] = bytes(raw), [xmp] = bytes(xmp) }
local count = 0
local function test(name, callback)
    callback(); count = count + 1; print('PASS ' .. name)
end

test('native same_directory does not use a parent RAW', function()
    local result = assert(resolver.resolve(jpg, 'same_directory'))
    assert(result.raw == nil and result.xmp == nil and result.jpeg == jpg)
end)
for _, mode in ipairs { 'parent_directory', 'same_then_parent' } do
    test('native ' .. mode .. ' finds mixed-case RAW and XMP beside it', function()
        local result, err = resolver.resolve(jpg, mode)
        assert(result, err and err.message)
        assert(result.raw == raw and result.xmp == xmp and result.jpeg == jpg)
    end)
end
test('native same_then_parent prefers a same-directory DNG', function()
    local dng = jpegDirectory .. '/写真.v2.dNg'; write(dng)
    local result = assert(resolver.resolve(jpg, 'same_then_parent'))
    assert(result.raw == dng and result.xmp == nil)
end)
test('native ambiguity does not silently choose RAF versus DNG', function()
    write(jpegDirectory .. '/写真.v2.RAF')
    local result, err = resolver.resolve(jpg, 'same_then_parent')
    assert(result == nil and err.code == 'AmbiguousSource')
end)
test('native scanning leaves source bytes unchanged', function()
    for path, content in pairs(before) do assert(bytes(path) == content) end
end)
test('uses the existing script entry in both menus instead of a new SDK script name', function()
    local info = dofile('src/FujiPhotoRenamer.lrplugin/Info.lua')
    for _, items in ipairs { info.LrExportMenuItems, info.LrLibraryMenuItems } do
        local found = false
        for _, item in ipairs(items) do
            assert(item.file ~= 'Phase3Diagnostic.lua')
            if item.file == 'Phase2Diagnostic.lua' then
                found = true
                assert(loadfile(root .. '/src/FujiPhotoRenamer.lrplugin/' .. item.file))
            end
        end
        assert(found)
    end
end)

for _, choice in ipairs { 'ok', 'cancel' } do
    test('dispatches exploration or cancel without SDK lookup of new scripts: ' .. choice, function()
        local previousImport, previousRequire = import, require
        local panels, messages = 0, {}
        local namespaces = {
            LrFileUtils = sdk.LrFileUtils, LrPathUtils = sdk.LrPathUtils,
            LrTasks = { pcall = pcall, startAsyncTask = function(callback) callback() end,
                execute = function() error('Exploration must not execute ExifTool') end },
            LrDialogs = {
                confirm = function() return choice end,
                runOpenPanel = function() panels = panels + 1; return { jpg } end,
                message = function(title, info) messages[#messages + 1] = { title, info } end,
            },
        }
        _G.import = function(name) return assert(namespaces[name]) end
        _G.require = function(name) error('No script by the name ' .. name) end
        local ok, message = pcall(dofile, root .. '/src/FujiPhotoRenamer.lrplugin/Phase2Diagnostic.lua')
        _G.import, _G.require = previousImport, previousRequire
        assert(ok, message)
        if choice == 'ok' then
            assert(panels == 1 and #messages == 1 and messages[1][1] == 'Phase 3：探索結果')
        else
            assert(panels == 0 and #messages == 0)
        end
    end)
end

for _, path in ipairs(created) do assert(os.remove(path)) end
assert(os.remove(jpegDirectory)); assert(os.remove(directory))
print(string.format('%d Phase 3 native tests passed; Lightroom integration remains required.', count))
