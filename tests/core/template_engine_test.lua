local function loadCore(name, dependencies)
    local chunk = assert(loadfile('src/FujiPhotoRenamer.lrplugin/core/' .. name .. '.lua'))
    setfenv(chunk, { type = type, pairs = pairs, ipairs = ipairs, tostring = tostring, tonumber = tonumber,
        assert = assert, math = math, table = table, string = string })
    return chunk(dependencies)
end
local parser = loadCore('TemplateParser')
local metadataResolver = loadCore('MetadataResolver')
local resolver = loadCore('TokenResolver', { normalizer = loadCore('ManufacturerNormalizer'), metadataResolver = metadataResolver })
local count = 0
local function equal(actual, expected)
    assert(actual == expected, string.format('Expected %s, got %s', tostring(expected), tostring(actual)))
end
local function test(name, callback) callback(); count = count + 1; print('PASS ' .. name) end
local function metadata()
    return { captureDateTime = '2026:10:09 12:34:56', cameraMaker = 'FUJIFILM', camera = 'X-H2S',
        lensMaker = 'FUJIFILM Corporation', lens = 'XF100-400mm', filmSim = 'PROVIA', iso = 800, focalLength = 100 }
end
local function options(overrides)
    local result = { extension = 'jpg', original = 'DSCF1234', sequence = 1 }
    for key, value in pairs(overrides or {}) do result[key] = value end
    return result
end
local function render(template, data, overrides)
    local parsed, err = parser.parse(template)
    assert(parsed, err and err.message)
    local result, renderError = resolver.resolve(parsed, data or metadata(), options(overrides))
    assert(result, renderError and (renderError.code .. ': ' .. renderError.message))
    return result
end

for token, expected in pairs { Date = '20261009', Time = '123456', DateTime = '20261009_123456',
    Original = 'DSCF1234', CameraMaker = 'FUJIFILM', Camera = 'X-H2S', LensMaker = 'FUJIFILM',
    Lens = 'XF100-400mm', FilmSim = 'PROVIA', ISO = '800', FocalLength = '100mm', Sequence = '0001' } do
    test('expands ' .. token, function() equal(render('{' .. token .. '}').filename, expected .. '.jpg') end)
end
test('uses the actual extension once at the explicit ending', function()
    equal(render('{Original}.{Extension}', nil, { extension = 'JPEG' }).filename, 'DSCF1234.jpeg')
end)
test('preserves escaped braces', function()
    equal(render('{{{Original}}}').filename, '{DSCF1234}.jpg')
    equal(render('{{Camera}}').filename, '{Camera}.jpg')
end)
for _, case in ipairs {
    { '', 'InvalidTemplate' }, { 'a/b', 'InvalidTemplate' }, { 'a\\b', 'InvalidTemplate' }, { 'a\0b', 'InvalidTemplate' },
    { '{Original', 'InvalidSyntax' }, { 'Original}', 'InvalidSyntax' }, { '{a{Original}', 'InvalidSyntax' },
    { '{Unknown}', 'UnknownToken' }, { '{date}', 'UnknownToken' }, { '{Date:YYYY}', 'UnknownToken' },
    { '{Extension}', 'InvalidExtension' }, { '{Original}{Extension}', 'InvalidExtension' },
    { '{Original}.{Extension}_tail', 'InvalidExtension' }, { '{Original}.{Extension}.{Extension}', 'InvalidExtension' },
} do
    test('rejects parser input ' .. case[1]:gsub('%c', '?'), function()
        local result, err = parser.parse(case[1]); equal(result, nil); equal(err.code, case[2])
    end)
end
test('omits only the semantic LensMaker when both manufacturers are equal', function()
    equal(render('{CameraMaker}_{Camera}_{LensMaker}').filename, 'FUJIFILM_X-H2S.jpg')
    local result = render('{CameraMaker}_{Camera}_{LensMaker}', nil, { omitDuplicateManufacturer = false })
    equal(result.filename, 'FUJIFILM_X-H2S_FUJIFILM.jpg')
    equal(#result.omittedTokens, 0)
end)
test('does not remove identical text from model or lens names', function()
    local data = metadata(); data.lens = 'FUJIFILM-XF__35mm'
    equal(render('{CameraMaker}_{LensMaker}_{Lens}', data).filename, 'FUJIFILM_FUJIFILM-XF__35mm.jpg')
end)
test('keeps different manufacturers', function()
    local data = metadata(); data.lensMaker = 'TAMRON'
    equal(render('{CameraMaker}_{Camera}_{LensMaker}', data).filename, 'FUJIFILM_X-H2S_TAMRON.jpg')
end)
test('compares unknown manufacturers through normalized keys', function()
    local data = metadata(); data.cameraMaker = ' Acme Labs '; data.lensMaker = 'ACME   LABS'
    equal(render('{CameraMaker}_{LensMaker}_{Original}', data).filename, 'Acme Labs_DSCF1234.jpg')
end)
test('does not suppress a standalone LensMaker token', function()
    equal(render('{LensMaker}').filename, 'FUJIFILM.jpg')
end)
test('works regardless of the order of manufacturer tokens', function()
    equal(render('{LensMaker}_{CameraMaker}_{Camera}').filename, 'FUJIFILM_X-H2S.jpg')
end)
for _, case in ipairs {
    { '{Camera}_{Lens}_{Original}', 'X-H2S_DSCF1234.jpg' },
    { '{Lens}_{Camera}', 'X-H2S.jpg' }, { '{Camera}_{Lens}', 'X-H2S.jpg' },
    { '{Camera}_{Lens}.{Extension}', 'X-H2S.jpg' },
    { '{Camera} - {Lens} _ {Original}', 'X-H2S DSCF1234.jpg' },
    { '__prefix__{Lens}__{Camera}__', '__prefix_X-H2S__.jpg' },
    { '{Camera}__keep__{Original}', 'X-H2S__keep__DSCF1234.jpg' },
    { '{Camera}{Lens}{Original}', 'X-H2SDSCF1234.jpg' },
} do
    test('cleans only separators adjacent to an empty token: ' .. case[1], function()
        local data = metadata(); data.lens = nil
        equal(render(case[1], data).filename, case[2])
    end)
end
test('cleans a whole run of missing tokens', function()
    local result = render('{CameraMaker}_{LensMaker}_{Lens}_{FilmSim}_{Original}', { cameraMaker = 'FUJIFILM' })
    equal(result.filename, 'FUJIFILM_DSCF1234.jpg'); equal(#result.missingTokens, 3)
end)
test('preserves source punctuation and parsed AST across calls', function()
    local parsed = assert(parser.parse('{CameraMaker}_{LensMaker}_{Original}.{Extension}'))
    local data = metadata(); local opts = options { original = 'IMG__1234_' }
    equal(assert(resolver.resolve(parsed, data, opts)).filename, 'FUJIFILM_IMG__1234_.jpg')
    opts.omitDuplicateManufacturer = false
    equal(assert(resolver.resolve(parsed, data, opts)).filename, 'FUJIFILM_FUJIFILM_IMG__1234_.jpg')
    equal(data.lensMaker, 'FUJIFILM Corporation'); equal(parsed.segments[2].value, '_')
end)
test('formats fractional focal length and longer sequences', function()
    local data = metadata(); data.focalLength = 23.5
    equal(render('{FocalLength}_{Sequence}', data, { sequence = 10000 }).filename, '23.5mm_10000.jpg')
end)
test('does not convert timestamp offsets or use fractional seconds', function()
    local data = metadata(); data.captureDateTime = '2026-10-09T12:34:56.999+09:00'
    equal(render('{DateTime}', data).filename, '20261009_123456.jpg')
end)
test('does not require dates when no date token is used', function()
    equal(render('{Original}', {}).filename, 'DSCF1234.jpg')
end)
for _, case in ipairs {
    { '{Date}', {}, {}, 'MissingDateTime' }, { '{Time}', { captureDateTime = '2026:02:29 12:00:00' }, {}, 'MissingDateTime' },
    { '{Lens}', {}, {}, 'EmptyFilename' }, { '{Lens}.{Extension}', {}, {}, 'EmptyFilename' },
    { '{ISO}', { iso = 0 }, {}, 'InvalidTokenValue' }, { '{FocalLength}', { focalLength = math.huge }, {}, 'InvalidTokenValue' },
    { '{Camera}', { camera = false }, {}, 'InvalidTokenValue' },
    { '{Sequence}', {}, { sequence = 0 }, 'InvalidSequence' }, { '{Sequence}', {}, { sequence = 1.5 }, 'InvalidSequence' },
    { '{Original}', {}, { original = '' }, 'MissingOriginal' },
    { '{Original}', {}, { extension = '.jpg' }, 'InvalidExtension' },
    { '{Original}', {}, { omitDuplicateManufacturer = 'ON' }, 'InvalidOption' },
} do
    test('reports render error ' .. case[4], function()
        local result, err = resolver.resolve(assert(parser.parse(case[1])), case[2], options(case[3]))
        equal(result, nil); equal(err.code, case[4])
    end)
end
test('treats whitespace text and missing numeric fields as empty', function()
    local result = render('{Camera}_{Lens}_{FilmSim}_{ISO}_{FocalLength}_{Original}', { camera = '  ', lens = '', filmSim = '\t' })
    equal(result.filename, 'DSCF1234.jpg'); equal(#result.missingTokens, 5)
end)
test('does not infer a missing manufacturer from the other one', function()
    local result = render('{CameraMaker}_{LensMaker}_{Original}', { lensMaker = 'TAMRON' })
    equal(result.filename, 'TAMRON_DSCF1234.jpg'); equal(result.missingTokens[1], 'CameraMaker')
    equal(#result.omittedTokens, 0)
end)
test('suppresses every LensMaker occurrence without removing literal manufacturer text', function()
    local result = render('FUJIFILM_{LensMaker}_{CameraMaker}_{LensMaker}_{Original}')
    equal(result.filename, 'FUJIFILM_FUJIFILM_DSCF1234.jpg'); equal(result.omittedTokens[1], 'LensMaker')
end)
test('rejects invalid capture dates and unrepresentable focal lengths', function()
    local result, err = resolver.resolve(assert(parser.parse('{DateTime}')), { captureDateTime = '2026:10:09' }, options())
    equal(result, nil); equal(err.code, 'MissingDateTime')
    result, err = resolver.resolve(assert(parser.parse('{FocalLength}')), { focalLength = 1e-12 }, options())
    equal(result, nil); equal(err.code, 'InvalidTokenValue')
end)
test('rounds focal length deterministically without modifying metadata', function()
    local data = metadata(); data.focalLength = 23.123456789012
    equal(render('{FocalLength}', data).filename, '23.123456789mm.jpg')
    equal(data.focalLength, 23.123456789012)
end)
print(string.format('%d Phase 6 pure-core tests passed.', count))
