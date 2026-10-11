package.path = './?.lua;' .. package.path
local pipe = assert(io.popen('pwd')); local root = pipe:read('*l'); assert(pipe:close())
local sdk = require('tests.support.lightroom_native').install(root .. '/src/FujiPhotoRenamer.lrplugin')
local fixture = assert(loadfile(root .. '/tests/support/jumbf_fixture.lua'))()
local executable = assert(arg[1], 'Pass explicit ExifTool path')
local work = os.tmpname(); assert(os.remove(work)); assert(sdk.LrFileUtils.createAllDirectories(work))
local function read(path) local f = assert(io.open(path, 'rb')); local s = f:read('*a'); f:close(); return s end
local function write(path, data) local f = assert(io.open(path, 'wb')); assert(f:write(data)); assert(f:close()) end
local jpeg = read(root .. '/fixtures/metadata/phase2-sample.jpg')
write(work .. '/original.jpg', jpeg)
local context = { fileUtils = sdk.LrFileUtils, pathUtils = sdk.LrPathUtils, tasks = sdk.LrTasks,
    pluginPath = root .. '/src/FujiPhotoRenamer.lrplugin', platform = 'macos' }
local function loadModule(path, deps) return assert(loadfile(context.pluginPath .. '/' .. path))(deps) end
context.artifacts = loadModule('infrastructure/ExportArtifact.lua', { fileUtils = sdk.LrFileUtils, pathUtils = sdk.LrPathUtils, integrity = loadModule('core/JpegIntegrity.lua') })
local reader = loadModule('ExifToolLoader.lua', context)
local delete = sdk.LrFileUtils.delete
sdk.LrFileUtils.delete = function(path)
    if path == work .. '/render.jpg' then return os.remove(path) end
    return delete(path)
end
local function capture(data, original)
    original = original or work .. '/original.jpg'
    write(work .. '/render.jpg', data)
    local rendition = { type = function() return 'LrExportRendition' end, destinationPath = work .. '/render.jpg',
        photo = { getRawMetadata = function(_, key) assert(key == 'path'); return original end } }
    return assert(context.artifacts.capture(rendition, rendition.destinationPath, original, { jpeg = original }))
end
local count = 0
local function test(name, callback) callback(); count = count + 1; print('PASS ' .. name) end
local function prepare(cap, tool)
    local result, err = reader.prepareC2pa(cap, { executablePath = tool or executable })
    assert(result, err and (err.code .. ': ' .. err.message .. (err.stderr or '')))
    return assert(context.artifacts.verify(cap))
end
for _, fragmented in ipairs { false, true } do
    test('removes synthetic JUMBF and preserves all other bytes: fragmented=' .. tostring(fragmented), function()
        local input = fixture.add(jpeg, fragmented); local cap = capture(input)
        local path = prepare(cap); assert(read(path) == jpeg); assert(read(work .. '/render.jpg') == input)
        assert(read(work .. '/original.jpg') == jpeg)
        assert(#reader.releaseC2pa(cap) == 0)
    end)
end
test('creates a byte-identical private copy when JUMBF is absent', function()
    local cap = capture(jpeg); local path = prepare(cap); assert(read(path) == jpeg)
    assert(#reader.releaseC2pa(cap) == 0)
end)
test('rejects a fabricated capability before executing a write', function()
    local result, err = reader.prepareC2pa({}, { executablePath = executable }); assert(not result and err.code == 'ArtifactRejected')
end)
test('rejects an original JPEG presented as its own rendering', function()
    local original = work .. '/original.jpg'
    local result, err = context.artifacts.capture({ type = function() return 'LrExportRendition' end,
        destinationPath = original, photo = { getRawMetadata = function() return original end } }, original, original, {})
    assert(not result and err.code == 'ArtifactRejected'); assert(read(original) == jpeg)
end)
test('rejects malformed JPEG before a mutation command', function()
    write(work .. '/render.jpg', 'broken')
    local result, err = context.artifacts.capture({ type = function() return 'LrExportRendition' end,
        destinationPath = work .. '/render.jpg', photo = { getRawMetadata = function() return work .. '/original.jpg' end } },
        work .. '/render.jpg', work .. '/original.jpg', {})
    assert(not result and err.code == 'InvalidJpeg')
end)
test('will not consume a rendering that changed while processing', function()
    local cap = capture(fixture.add(jpeg)); prepare(cap)
    write(work .. '/render.jpg', jpeg)
    local path, err = context.artifacts.commitPath(cap); assert(not path and err.code == 'ArtifactRejected')
    assert(read(work .. '/render.jpg') == jpeg); assert(#reader.releaseC2pa(cap) == 0)
end)
test('does not publish the output when ExifTool emits a warning', function()
    local tool = work .. '/warning-tool'
    write(tool, '#!/bin/sh\nprintf "warning\\n" >&2\nexit 0\n')
    assert(os.execute('/bin/chmod +x ' .. tool) == 0)
    local cap = capture(fixture.add(jpeg)); local result, err = reader.prepareC2pa(cap, { executablePath = tool })
    assert(not result and err.code == 'C2paWarning'); assert(#reader.releaseC2pa(cap) == 0); assert(os.remove(tool))
end)
test('rejects false success with retained JUMBF using the independent parser', function()
    local cap = capture(fixture.add(jpeg)); local output = assert(context.artifacts.bindWork(cap, work))
    write(output, fixture.add(jpeg)); local path, err = context.artifacts.verify(cap)
    assert(not path and err.code == 'JumbfRemaining'); assert(os.remove(output)); context.artifacts.forget(cap)
end)
for _, case in ipairs {
    { 'nonzero exit', 'exit 7', 'ProcessFailed', 30 },
    { 'timeout', 'exec /bin/sleep 5', 'Timeout', 1 },
    { 'false success without output', 'exit 0', 'ArtifactRejected', 30 },
} do
    test('rejects ' .. case[1] .. ' without touching the rendition', function()
        local tool = work .. '/failure-tool'; write(tool, '#!/bin/sh\n' .. case[2] .. '\n')
        assert(os.execute('/bin/chmod +x ' .. tool) == 0)
        local before = fixture.add(jpeg); local cap = capture(before)
        local result, err = reader.prepareC2pa(cap, { executablePath = tool, timeoutSeconds = case[4] })
        assert(not result and err.code == case[3], err and err.code)
        assert(read(work .. '/render.jpg') == before)
        assert(#reader.releaseC2pa(cap) == 0)
        assert(os.remove(tool))
    end)
end
test('does not accept an artifact after the catalog path changes to the rendition', function()
    write(work .. '/render.jpg', jpeg)
    local original = work .. '/original.jpg'
    local rendition = { type = function() return 'LrExportRendition' end, destinationPath = work .. '/render.jpg',
        photo = { getRawMetadata = function() return original end } }
    local cap = assert(context.artifacts.capture(rendition, rendition.destinationPath, original, {}))
    original = work .. '/render.jpg'
    local source, err = context.artifacts.source(cap)
    assert(not source and err.code == 'ArtifactRejected'); assert(read(original) == jpeg)
    context.artifacts.forget(cap)
end)
if arg[2] then
    test('removes JUMBF from the user-authorized JPEG copy without changing the input', function()
        local before = read(arg[2]); local cap = capture(before, arg[2])
        local output = prepare(cap)
        local verified = assert(loadModule('core/JpegIntegrity.lua').verifyRemoval(before, read(output)))
        assert(verified.removedSegments > 0); assert(read(arg[2]) == before)
        assert(read(work .. '/render.jpg') == before)
        if arg[3] then
            local function quote(path) return "'" .. path:gsub("'", "'\\''") .. "'" end
            assert(os.execute(quote(arg[3]) .. ' ' .. quote(root .. '/tests/support/verify_jpeg_pixels.py')
                .. ' ' .. quote(arg[2]) .. ' ' .. quote(output)) == 0)
            print('Real JPEG: independent Pillow decode and pixel equality passed.')
        end
        assert(#reader.releaseC2pa(cap) == 0)
        print('Real JPEG: JUMBF removed; all non-JUMBF bytes and authorized input unchanged.')
    end)
end
assert(os.remove(work .. '/render.jpg')); assert(os.remove(work .. '/original.jpg')); assert(os.remove(work))
print(string.format('%d native C2PA tests passed; Lightroom and Windows remain separate.', count))
