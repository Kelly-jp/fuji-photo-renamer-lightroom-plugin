-- Load core without SDK, ExifTool, filesystem, process, or clock capabilities.
local chunk = assert(loadfile('src/FujiPhotoRenamer.lrplugin/core/MetadataResolver.lua'))
setfenv(chunk, { type = type, pairs = pairs, ipairs = ipairs, tostring = tostring,
    tonumber = tonumber, math = math, table = table })
local resolver = chunk()
local count = 0
local function equal(actual, expected)
    assert(actual == expected, string.format('Expected %s, got %s', tostring(expected), tostring(actual)))
end
local function source(metadata, fieldSources) return { metadata = metadata, fieldSources = fieldSources } end
local function test(name, callback) callback(); count = count + 1; print('PASS ' .. name) end

for _, kind in ipairs { 'xmp', 'raw', 'jpeg' } do
    test('resolves ' .. kind .. ' only', function()
        local result = assert(resolver.resolve { [kind] = source { camera = 'X-H2S', iso = 160 } })
        equal(result.metadata.camera, 'X-H2S'); equal(result.metadata.iso, 160)
        equal(result.fieldSources.camera.sourceKind, kind)
    end)
end
test('merges fields from all sources instead of picking a whole file', function()
    local result = assert(resolver.resolve {
        xmp = source { rating = 5, filmSim = 'CLASSIC_NEGATIVE' },
        raw = source { camera = 'X-H2S', lensMaker = 'FUJIFILM', filmSim = 'PROVIA' },
        jpeg = source { camera = 'other', iso = 800 },
    })
    equal(result.metadata.rating, 5); equal(result.metadata.camera, 'X-H2S')
    equal(result.metadata.lensMaker, 'FUJIFILM'); equal(result.metadata.iso, 800)
    equal(result.metadata.filmSim, 'CLASSIC_NEGATIVE')
    equal(result.fieldSources.iso.sourceKind, 'jpeg')
end)
test('preserves extra scalar fields such as the Rating example', function()
    local result = assert(resolver.resolve { xmp = source { Rating = 5 }, raw = source { Camera = 'X-H2S' } })
    equal(result.metadata.Rating, 5); equal(result.metadata.Camera, 'X-H2S')
end)
for _, value in ipairs { '', '   ', '\t\n', {}, { 'bad' } } do
    test('falls back from missing or unsupported XMP values: ' .. type(value), function()
        local result = assert(resolver.resolve { xmp = source { camera = value }, raw = source { camera = 'X-H2S' } })
        equal(result.metadata.camera, 'X-H2S'); equal(result.fieldSources.camera.sourceKind, 'raw')
        equal(#result.rejectedValues, 1)
    end)
end
test('falls back through XMP and RAW to JPEG', function()
    local result = assert(resolver.resolve { xmp = source { lens = '' }, raw = source { lens = ' ' }, jpeg = source { lens = 'XF35mm' } })
    equal(result.metadata.lens, 'XF35mm'); equal(result.fieldSources.lens.sourceKind, 'jpeg')
    equal(#result.rejectedValues, 2)
end)
test('preserves zero and false when they are valid scalar values', function()
    local result = assert(resolver.resolve { xmp = source { rating = 0, count = 0, enabled = false }, raw = source { rating = 5, count = 10, enabled = true } })
    equal(result.metadata.rating, 0); equal(result.metadata.count, 0); equal(result.metadata.enabled, false)
    equal(result.fieldSources.enabled.sourceKind, 'xmp')
end)
test('rejects a boolean camera name but does not lose it through truthiness', function()
    local result = assert(resolver.resolve { xmp = source { camera = false }, raw = source { camera = 'X-H2S' } })
    equal(result.metadata.camera, 'X-H2S'); equal(result.rejectedValues[1].reason, 'InvalidText')
end)
for _, case in ipairs {
    { 'iso', 0 }, { 'iso', -1 }, { 'iso', 1.5 }, { 'iso', '160' },
    { 'focalLength', 0 }, { 'focalLength', -1 }, { 'focalLength', false },
    { 'rating', -1 }, { 'rating', 6 }, { 'rating', 2.5 },
    { 'count', math.huge }, { 'count', -math.huge }, { 'count', 0 / 0 },
} do
    test('rejects invalid numeric field ' .. case[1] .. '=' .. tostring(case[2]), function()
        local fallback = case[1] == 'focalLength' and 23.5 or 3
        local result = assert(resolver.resolve { xmp = source { [case[1]] = case[2] }, raw = source { [case[1]] = fallback } })
        equal(result.metadata[case[1]], fallback); equal(result.fieldSources[case[1]].sourceKind, 'raw')
    end)
end
for _, date in ipairs {
    '2026:10:09 12:34:56', '2026-10-09T12:34:56Z', '2026-10-09 12:34:56+09:00',
    '2026:10:09 12:34:56.123-05:30', '2000:02:29 00:00:00', '2024-02-29T23:59:59.9',
} do
    test('preserves valid capture timestamp ' .. date, function()
        local result = assert(resolver.resolve { xmp = source { captureDateTime = date } })
        equal(result.metadata.captureDateTime, date); equal(result.fieldSources.captureDateTime.sourceKind, 'xmp')
    end)
end
for _, date in ipairs {
    '2026:02:29 12:00:00', '1900:02:29 12:00:00', '2026:04:31 12:00:00',
    '0000:10:09 12:00:00', '2026:00:09 12:00:00', '2026:13:09 12:00:00',
    '2026:10:00 12:00:00', '2026:10:09 24:00:00', '2026:10:09 12:60:00',
    '2026:10:09 12:00:60', '2026:10:09', '12:34:56', '2026-10-09T12:34:56.',
    '2026-10-09T12:34:56+24:00', '2026-10-09T12:34:56+09:60', '2026-10-09T12:34:56junk',
} do
    test('falls back from invalid capture timestamp ' .. date, function()
        local rawDate = '2026:10:08 01:02:03'
        local result = assert(resolver.resolve { xmp = source { captureDateTime = date }, raw = source { captureDateTime = rawDate } })
        equal(result.metadata.captureDateTime, rawDate); equal(result.fieldSources.captureDateTime.sourceKind, 'raw')
    end)
end
test('never combines partial dates or substitutes the current time', function()
    local result = assert(resolver.resolve { xmp = source { captureDateTime = '2026:10:09' }, raw = source { captureDateTime = '12:34:56' } })
    equal(result.metadata.captureDateTime, nil)
end)
test('copies provenance without changing the input or maker strings', function()
    local origin = { sourcePath = '/fixtures/sample.xmp', tag = 'custom-tag', sourceKind = 'raw' }
    local input = { xmp = source({ cameraMaker = ' Fujifilm Corporation ' }, { cameraMaker = origin }) }
    local result = assert(resolver.resolve(input))
    equal(result.metadata.cameraMaker, ' Fujifilm Corporation ')
    equal(result.fieldSources.cameraMaker.sourceKind, 'xmp')
    equal(origin.sourceKind, 'raw'); assert(result.fieldSources.cameraMaker ~= origin)
    result.fieldSources.cameraMaker.tag = 'changed'
    equal(origin.tag, 'custom-tag')
end)
test('rejects a read failure even if lower priority data is complete', function()
    local result, err = resolver.resolve { xmp = { readError = { code = 'ProcessFailed' } }, raw = source { camera = 'X-H2S' } }
    equal(result, nil); equal(err.code, 'ReadError'); equal(err.sourceKind, 'xmp')
end)
test('empty inputs produce a deterministic missing list', function()
    local result = assert(resolver.resolve {})
    equal(next(result.metadata), nil); equal(#result.missingFields, 8); equal(#result.rejectedValues, 0)
    for i = 2, #result.missingFields do assert(result.missingFields[i - 1] < result.missingFields[i]) end
end)
for _, case in ipairs {
    { false, 'InvalidInput' }, { { jpg = source {} }, 'InvalidSourceKind' },
    { { raw = false }, 'InvalidSource' }, { { xmp = {} }, 'InvalidMetadata' },
    { { xmp = source { [1] = 'bad' } }, 'InvalidField' },
    { { xmp = source({ camera = 'X-H2S' }, false) }, 'InvalidProvenance' },
    { { xmp = source({ camera = 'X-H2S' }, { camera = { tag = {} } }) }, 'InvalidProvenance' },
} do
    test('returns structural error ' .. case[2], function()
        local result, err = resolver.resolve(case[1]); equal(result, nil); equal(err.code, case[2])
    end)
end

print(string.format('%d Phase 4 pure-core tests passed.', count))
