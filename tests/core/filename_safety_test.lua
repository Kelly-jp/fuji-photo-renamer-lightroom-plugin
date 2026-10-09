local function loadCore(name, dependencies)
    local chunk = assert(loadfile('src/FujiPhotoRenamer.lrplugin/core/' .. name .. '.lua'))
    setfenv(chunk, { type = type, pairs = pairs, ipairs = ipairs, assert = assert, pcall = pcall,
        math = math, table = table, string = string, tonumber = tonumber, tostring = tostring })
    return chunk(dependencies)
end
local sanitizer = loadCore('FilenameSanitizer')
local resolver = loadCore('CollisionResolver', { sanitizer = sanitizer })
local count = 0
local function test(name, callback) callback(); count = count + 1; print('PASS ' .. name) end
local function equal(actual, expected) assert(actual == expected, tostring(actual) .. ' ~= ' .. tostring(expected)) end
local function key(name) return (name:gsub('[A-Z]', function(c) return string.char(c:byte() + 32) end)) end
local function resolve(filename, overrides)
    local options = { nameKey = key }
    for k, v in pairs(overrides or {}) do options[k] = v end
    return resolver.resolve(filename, options)
end
for _, case in ipairs {
    { 'DSCF1234.jpg', 'DSCF1234.jpg' }, { '写真_日本語_é_😀.JPG', '写真_日本語_é_😀.jpg' },
    { 'a<>:"/\\|?*b.jpg', 'a_________b.jpg' }, { 'a\0\1\31\127b.jpg', 'ab.jpg' },
    { 'a\194\128\194\159b.jpg', 'ab.jpg' },
    { 'photo . .jpg', 'photo.jpg' }, { 'photo.jpg . ', 'photo.jpg' },
    { 'a..b__ c-d.jpg', 'a..b__ c-d.jpg' }, { ' /photo.jpg', ' _photo.jpg' },
} do
    test('sanitizes filename: ' .. case[2], function()
        local result = assert(sanitizer.sanitize(case[1])); equal(result.filename, case[2])
        equal(result.changed, case[1] ~= case[2])
        local again = assert(sanitizer.sanitize(result.filename)); equal(again.filename, case[2]); equal(again.changed, false)
    end)
end
for _, name in ipairs { 'CON', 'prn', 'AUX', 'nul', 'COM1', 'COM9', 'LPT1', 'LPT9', 'COM¹', 'COM²', 'LPT³', 'CON .txt' } do
    test('rejects Windows reserved stem: ' .. name, function()
        local result, err = sanitizer.sanitize(name .. '.jpg'); equal(result, nil); equal(err.code, 'ReservedFilename')
    end)
end
for _, name in ipairs { 'COM0', 'COM10', 'LPT0', 'CONsole', 'prefix.CON', 'COM⁴' } do
    test('does not overmatch a reserved name: ' .. name, function() equal(assert(sanitizer.sanitize(name .. '.jpg')).filename, name .. '.jpg') end)
end
for _, case in ipairs {
    { '', 'EmptyFilename' }, { '   ', 'EmptyFilename' }, { '.', 'EmptyFilename' }, { '..', 'EmptyFilename' },
    { '.jpg', 'EmptyFilename' }, { ' .jpg', 'EmptyFilename' }, { '\0.jpg', 'EmptyFilename' },
    { '.hidden.jpg', 'InvalidFilename' }, { '../escape.jpg', 'InvalidFilename' },
    { 'photo', 'InvalidExtension' }, { 'photo.j/p', 'InvalidExtension' },
    { '\192\128.jpg', 'InvalidEncoding' }, { '\237\160\128.jpg', 'InvalidEncoding' },
    { '\244\144\128\128.jpg', 'InvalidEncoding' }, { '\240\159.jpg', 'InvalidEncoding' },
} do
    test('rejects unsafe filename: ' .. case[2], function()
        local result, err = sanitizer.sanitize(case[1]); equal(result, nil); equal(err.code, case[2])
    end)
end
test('rejects non-string names', function() local result, err = sanitizer.sanitize(false); equal(result, nil); equal(err.code, 'InvalidFilename') end)
test('uses byte limits without cutting Unicode or changing caller limits', function()
    local limits = { maxBytes = 7 }
    equal(assert(sanitizer.sanitize('写.jpg', limits)).filename, '写.jpg')
    local result, err = sanitizer.sanitize('写真.jpg', limits); equal(result, nil); equal(err.code, 'FilenameTooLong')
    equal(limits.maxBytes, 7)
end)
for _, limit in ipairs { 0, -1, 1.5, math.huge, 0/0, '255', false } do
    test('rejects invalid byte limit', function() local result, err = sanitizer.sanitize('a.jpg', { maxBytes = limit }); equal(result, nil); equal(err.code, 'InvalidLimits') end)
end
test('leaves an unoccupied name unchanged', function() local result = assert(resolve('photo.jpg')); equal(result.filename, 'photo.jpg'); equal(result.collisionNumber, 0) end)
test('finds the first free number across disk names and session reservations', function()
    local existing, reserved = { 'PHOTO.JPG', 'photo_001.jpg' }, { 'photo_002.jpg', 'unrelated.jpg' }
    local result = assert(resolve('photo.jpg', { existingNames = existing, reservedNames = reserved }))
    equal(result.filename, 'photo_003.jpg'); equal(result.collisionNumber, 3)
    equal(existing[1], 'PHOTO.JPG'); equal(#reserved, 2)
end)
test('fills numbering gaps and preserves source sequence and multiple dots', function()
    local result = assert(resolve('photo.raw_0001.jpg', { existingNames = { 'photo.raw_0001.jpg', 'photo.raw_0001_002.jpg' } }))
    equal(result.filename, 'photo.raw_0001_001.jpg')
end)
test('does not strip an existing numeric suffix', function()
    equal(assert(resolve('photo_001.jpg', { existingNames = { 'photo_001.jpg' } })).filename, 'photo_001_001.jpg')
end)
test('supports larger suffixes without wrapping at 999', function()
    local names = { 'photo.jpg' }
    for i = 1, 999 do names[#names + 1] = string.format('photo_%03d.jpg', i) end
    equal(assert(resolve('photo.jpg', { existingNames = names })).filename, 'photo_1000.jpg')
end)
test('uses an explicit case-sensitive name key when required', function()
    equal(assert(resolve('photo.jpg', { existingNames = { 'PHOTO.JPG' }, nameKey = function(name) return name end })).collisionNumber, 0)
end)
test('honors Unicode equivalence supplied by the platform boundary', function()
    local composed, decomposed = 'café.jpg', 'cafe\204\129.jpg'
    local function verifiedFixtureKey(name) return key(name:gsub('e\204\129', 'é')) end
    equal(assert(resolve(composed, { existingNames = { decomposed }, nameKey = verifiedFixtureKey })).filename, 'café_001.jpg')
end)
test('does not mutate caller reservations between calls', function()
    local reserved = {}
    local first = assert(resolve('photo.jpg', { reservedNames = reserved }))
    reserved[#reserved + 1] = first.filename
    equal(assert(resolve('photo.jpg', { reservedNames = reserved })).filename, 'photo_001.jpg')
    equal(#reserved, 1)
end)
test('fails rather than truncating when a collision suffix exceeds the limit', function()
    local result, err = resolve('photo.jpg', { existingNames = { 'photo.jpg' }, limits = { maxBytes = 9 } })
    equal(result, nil); equal(err.code, 'FilenameTooLong')
end)
test('counts the original candidate in the bounded search', function()
    local result, err = resolve('photo.jpg', { existingNames = { 'photo.jpg', 'photo_001.jpg' }, maxAttempts = 2 })
    equal(result, nil); equal(err.code, 'CollisionLimitReached')
end)
test('rejects an unsanitized input name', function()
    local result, err = resolve('photo?.jpg'); equal(result, nil); equal(err.code, 'InvalidFilename')
end)
for _, options in ipairs { {}, { nameKey = 'ascii' }, { nameKey = key, existingNames = false },
    { nameKey = key, reservedNames = { [2] = 'photo.jpg' } }, { nameKey = key, existingNames = { 'dir/photo.jpg' } },
    { nameKey = key, maxAttempts = false }, { nameKey = key, maxAttempts = 0 }, { nameKey = key, maxAttempts = 1000001 },
    { nameKey = key, maxAttempts = 1.1 }, { nameKey = key, existingNames = { foo = 'photo.jpg' } },
} do
    test('rejects invalid collision options', function()
        local result, err = resolver.resolve('photo.jpg', options); equal(result, nil); equal(err.code, 'InvalidOptions')
    end)
end
for _, callback in ipairs { function() error('key failed') end, function() return nil end, function() return '' end } do
    test('surfaces comparison key failure', function()
        local result, err = resolve('photo.jpg', { nameKey = callback }); equal(result, nil); equal(err.code, 'InvalidNameKey')
    end)
end
test('composes template expansion, sanitization, and collision resolution without SDK or I/O', function()
    local parser = loadCore('TemplateParser')
    local tokens = loadCore('TokenResolver', { normalizer = loadCore('ManufacturerNormalizer'), metadataResolver = loadCore('MetadataResolver') })
    local expanded = assert(tokens.resolve(assert(parser.parse('{CameraMaker}_{Camera}_{LensMaker}_{Lens}_{Original}_{Sequence}')),
        { cameraMaker = 'FUJIFILM', camera = 'X-H2S', lensMaker = 'Fujifilm Corporation', lens = 'XF18/55mm: Test' },
        { original = 'DSCF1234', extension = 'jpg', sequence = 1 }))
    local safe = assert(sanitizer.sanitize(expanded.filename))
    equal(safe.filename, 'FUJIFILM_X-H2S_XF18_55mm_ Test_DSCF1234_0001.jpg')
    equal(assert(resolve(safe.filename, { existingNames = { safe.filename } })).filename,
        'FUJIFILM_X-H2S_XF18_55mm_ Test_DSCF1234_0001_001.jpg')
end)
print(string.format('%d Phase 7 pure-core tests passed.', count))
