local chunk = assert(loadfile('src/FujiPhotoRenamer.lrplugin/core/JpegIntegrity.lua'))
setfenv(chunk, { type = type, pairs = pairs, ipairs = ipairs, string = string, table = table })
local integrity = chunk()
local fixture = assert(loadfile('tests/support/jumbf_fixture.lua'))()
local handle = assert(io.open('fixtures/metadata/phase2-sample.jpg', 'rb')); local jpeg = handle:read('*a'); handle:close()
local count = 0
local function test(name, callback) callback(); count = count + 1; print('PASS ' .. name) end
local function equal(a, b) assert(a == b, tostring(a) .. ' ~= ' .. tostring(b)) end
test('checks a plain JPEG without changing its bytes', function()
    local result = assert(integrity.inspect(jpeg)); equal(result.withoutJumbf, jpeg); equal(result.jumbfSegments, 0)
    equal(assert(integrity.verifyRemoval(jpeg, jpeg)).removedSegments, 0)
end)
for _, fragmented in ipairs { false, true } do
    test('identifies complete JUMBF packets: fragmented=' .. tostring(fragmented), function()
        local input = fixture.add(jpeg, fragmented); local result = assert(integrity.inspect(input))
        equal(result.withoutJumbf, jpeg); equal(result.jumbfSegments, fragmented and 2 or 1)
        equal(assert(integrity.verifyRemoval(input, jpeg)).removedSegments, result.jumbfSegments)
    end)
end
test('rejects retained JUMBF', function()
    local result, err = integrity.verifyRemoval(fixture.add(jpeg), fixture.add(jpeg)); equal(result, nil); equal(err.code, 'JumbfRemaining')
end)
test('rejects changed image data or non-JUMBF metadata', function()
    local modified = jpeg:sub(1, -4) .. string.char((jpeg:byte(-3) + 1) % 256) .. jpeg:sub(-2)
    local result, err = integrity.verifyRemoval(fixture.add(jpeg), modified); equal(result, nil); assert(err)
end)
test('preserves unrelated APP11 segments', function()
    local app = '\255\235\0\10not-jumb'; local input = jpeg:sub(1, 2) .. app .. jpeg:sub(3)
    equal(assert(integrity.inspect(input)).withoutJumbf, input)
end)
for _, metadata in ipairs {
    { 'EXIF', 225, 'Exif\0\0fixture' },
    { 'XMP', 225, 'http://ns.adobe.com/xap/1.0/\0<x:xmpmeta>fixture</x:xmpmeta>' },
    { 'ICC', 226, 'ICC_PROFILE\0\1\1fixture' },
} do
    test('retains ' .. metadata[1] .. ' bytes and rejects any change during removal', function()
        local length = #metadata[3] + 2
        local segment = string.char(255, metadata[2], math.floor(length / 256), length % 256) .. metadata[3]
        local original = jpeg:sub(1, 2) .. segment .. jpeg:sub(3)
        equal(assert(integrity.verifyRemoval(fixture.add(original), original)).removedSegments, 1)
        local changed = original:sub(1, 6) .. 'X' .. original:sub(8)
        local result, err = integrity.verifyRemoval(fixture.add(original), changed)
        equal(result, nil); equal(err.code, 'JpegChanged')
    end)
end
for _, input in ipairs { '', 'not JPEG', '\255\216\255', '\255\216\255\235\0\255x', jpeg:sub(1, -3) } do
    test('rejects malformed JPEG', function() local result, err = integrity.inspect(input); equal(result, nil); equal(err.code, 'InvalidJpeg') end)
end
test('rejects malformed JUMBF lengths', function()
    local data = fixture.add(jpeg); data = data:sub(1, 14) .. '\0\0\0\1' .. data:sub(19)
    local result, err = integrity.inspect(data); equal(result, nil); assert(err)
end)
test('rejects a missing first fragmented APP11 packet', function()
    local input = fixture.add(jpeg, true)
    local length = input:byte(5) * 256 + input:byte(6)
    local truncated = input:sub(1, 2) .. input:sub(length + 5)
    local result, err = integrity.inspect(truncated); equal(result, nil); equal(err.code, 'InvalidJpeg')
end)
print(string.format('%d JPEG-integrity tests passed.', count))
