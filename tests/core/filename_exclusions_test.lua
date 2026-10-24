local chunk = assert(loadfile('src/FujiPhotoRenamer.lrplugin/core/FilenameExclusions.lua'))
setfenv(chunk, { type = type, ipairs = ipairs, table = table })
local exclusions = chunk()
local count = 0
local function test(name, callback) callback(); count = count + 1; print('PASS ' .. name) end
local function equal(a, b) assert(a == b, tostring(a) .. ' ~= ' .. tostring(b)) end
for _, entry in ipairs {
    { 'DSCF9649-DxO_DeepPRIME XD2s_XD', '-DxO_DeepPRIME XD2s_XD', 'DSCF9649' },
    { 'DSCF9649-DxO_DeepPRIME-XD2s_XD', '-DxO_DeepPRIME XD2s_XD', 'DSCF9649' },
    { 'DSCF-DxO-edit', '-DxO\n-edit', 'DSCF' },
    { 'foofoo_testfoo', 'foo', '_test' },
    { 'sample[a].+%', '[a]\n.+%', 'sample' },
    { 'DSCF_DxO', 'dxo', 'DSCF_DxO' },
    { '日本語_削除_写真', '_削除', '日本語_写真' },
    { 'a name_suffix', 'a name', '_suffix' },
    { 'ajpgb.jpg', '.jpg', 'ajpgb' },
    { 'acdb', 'ab\ncd', '' },
    { 'keep_a_b', '\n  a_  \r\nb\r\n', 'keep_' },
    { 'photo', '', 'photo' },
    { 'photo', 'absent', 'photo' },
} do
    test('removes literal exclusions: ' .. entry[1], function()
        equal(assert(exclusions.apply(entry[1], entry[2])), entry[3])
    end)
end
test('reapplies patterns formed by deletions', function()
    equal(assert(exclusions.apply('z_acdb', 'ab\ncd')), 'z_')
end)
for _, value in ipairs { false, 1, {}, '\0', '\1', string.rep('x', 16385), string.rep('a\n', 129) } do
    test('rejects invalid exclusion settings', function()
        local filename, err = exclusions.apply('photo.jpg', value); equal(filename, nil); equal(err.code, 'InvalidExclusions')
    end)
end
test('allows an empty cleaned stem for templates without Original', function()
    equal(assert(exclusions.apply('photo', 'photo')), '')
end)
test('does not accept missing or excessive filename data', function()
    equal(assert(exclusions.apply('photo', '')), 'photo'); assert(not exclusions.apply(string.rep('a', 65537), ''))
end)
print(string.format('%d filename-exclusion tests passed.', count))
