local chunk = assert(loadfile('src/FujiPhotoRenamer.lrplugin/core/ManufacturerNormalizer.lua'))
setfenv(chunk, { type = type, string = string })
local normalizer = chunk()
local count = 0
local function equal(actual, expected)
    assert(actual == expected, string.format('Expected %s, got %s', tostring(expected), tostring(actual)))
end
local function test(name, callback) callback(); count = count + 1; print('PASS ' .. name) end

for _, value in ipairs { 'FUJIFILM', 'Fujifilm', 'fujifilm', 'FUJIFILM Corporation',
    ' FUJIFILM CORPORATION ', 'Fuji Film', 'FUJI   FILM', '\tFuji\nFilm\r' } do
    test('normalizes the known Fujifilm alias ' .. value:gsub('%s+', ' '), function()
        local result = assert(normalizer.normalize(value))
        equal(result.key, 'FUJIFILM'); equal(result.displayName, 'FUJIFILM'); equal(result.known, true)
        equal(normalizer.sameManufacturer(value, 'FUJIFILM'), true)
    end)
end
for _, value in ipairs { 'TAMRON', 'Tamron', ' tamron ', 'SIGMA', 'Sigma', ' sigma ' } do
    test('normalizes the known brand ' .. value, function()
        local result = assert(normalizer.normalize(value))
        equal(result.key, value:match('^%s*(.-)%s*$'):upper()); equal(result.known, true)
    end)
end
test('keeps unknown names comparable without guessing an alias', function()
    local result = assert(normalizer.normalize('  Acme   Labs  '))
    equal(result.key, 'ACME LABS'); equal(result.displayName, 'Acme Labs'); equal(result.known, false)
    equal(normalizer.sameManufacturer('Acme Labs', ' ACME\tLABS '), true)
end)
test('does not merge different manufacturers', function()
    equal(normalizer.sameManufacturer('FUJIFILM', 'TAMRON'), false)
    equal(normalizer.sameManufacturer('TAMRON', 'SIGMA'), false)
    equal(normalizer.sameManufacturer('Acme', 'Other'), false)
end)
test('does not remove arbitrary company suffixes or punctuation', function()
    equal(normalizer.sameManufacturer('Acme Corporation', 'Acme'), false)
    equal(normalizer.sameManufacturer('FUJIFILM CAMERA', 'FUJIFILM'), false)
    equal(normalizer.sameManufacturer('SIGMA Corporation of America', 'SIGMA'), false)
    equal(normalizer.sameManufacturer('AC-ME', 'ACME'), false)
end)
for _, case in ipairs { { 'Tamron Co., Ltd.', 'TAMRON' }, { ' Sigma Corporation ', 'SIGMA' } } do
    test('recognizes the explicit official company name ' .. case[1], function()
        local result = assert(normalizer.normalize(case[1]))
        equal(result.key, case[2]); equal(result.displayName, case[2]); equal(result.known, true)
        equal(normalizer.sameManufacturer(case[1], case[2]), true)
    end)
end
for _, value in ipairs { '', ' ', '\t\r\n' } do
    test('does not equate missing names represented by whitespace', function()
        equal(normalizer.normalize(value), nil)
        equal(normalizer.sameManufacturer(value, value), false)
        equal(normalizer.sameManufacturer('FUJIFILM', value), false)
    end)
end
test('does not equate absent names', function()
    equal(normalizer.normalize(nil), nil)
    equal(normalizer.sameManufacturer(nil, nil), false)
    equal(normalizer.sameManufacturer(nil, 'FUJIFILM'), false)
end)
for _, value in ipairs { false, 0, {}, { 'FUJIFILM' } } do
    test('reports a non-string input ' .. type(value), function()
        local result, err = normalizer.normalize(value)
        equal(result, nil); equal(err.code, 'InvalidManufacturer')
        local same, compareError = normalizer.sameManufacturer('FUJIFILM', value)
        equal(same, nil); equal(compareError.code, 'InvalidManufacturer')
    end)
end
for _, value in ipairs { 'FUJI\0FILM', 'FUJI\1FILM', 'FUJI\127FILM' } do
    test('reports an invalid control character', function()
        local result, err = normalizer.normalize(value)
        equal(result, nil); equal(err.code, 'InvalidManufacturer')
    end)
end
test('does not infer Unicode case or normalization equivalence', function()
    equal(normalizer.sameManufacturer('カメラ工房', ' カメラ工房 '), true)
    equal(normalizer.sameManufacturer('Équipement', 'équipement'), false)
    equal(normalizer.sameManufacturer('Café', 'Café'), false)
end)
test('leaves the original metadata and independent output records unchanged', function()
    local metadata = { cameraMaker = ' Fujifilm Corporation ', lensMaker = 'FUJI FILM' }
    local result = assert(normalizer.normalize(metadata.cameraMaker))
    equal(normalizer.sameManufacturer(metadata.cameraMaker, metadata.lensMaker), true)
    result.key = 'changed'
    equal(metadata.cameraMaker, ' Fujifilm Corporation '); equal(metadata.lensMaker, 'FUJI FILM')
    equal(assert(normalizer.normalize(metadata.cameraMaker)).key, 'FUJIFILM')
end)
print(string.format('%d Phase 5 pure-core tests passed.', count))
