-- Infrastructure boundary: real pure resolver, controlled read-only source responses.
local count = 0
local function equal(a, b) assert(a == b, tostring(a) .. ' ~= ' .. tostring(b)) end
local function test(name, callback) callback(); count = count + 1; print('PASS ' .. name) end
local function harness(paths, values, options)
    options = options or {}
    local calls, scanned = {}, {}
    local resolver = assert(loadfile('src/FujiPhotoRenamer.lrplugin/core/MetadataResolver.lua'))()
    local reader = assert(loadfile('src/FujiPhotoRenamer.lrplugin/infrastructure/MetadataReader.lua')) {
        scanner = { resolve = function(original, mode)
            scanned.original, scanned.mode = original, mode
            if options.scanError then return nil, options.scanError end
            return paths
        end },
        reader = { readMetadata = function(path, settings)
            calls[#calls + 1] = path
            equal(settings.executablePath, '/tools/exiftool')
            if options.failedPath == path then return nil, options.readError end
            return { metadata = values[path], warnings = { 'read warning' },
                fieldSources = { camera = { sourcePath = path, tag = 'fixture-tag' } } }
        end }, resolver = resolver,
    }
    return { read = function(cancel, rendered)
        return reader.read('/photos/source.jpg', 'same_then_parent', '/tools/exiftool', cancel, rendered)
    end, calls = calls, scanned = scanned }
end
for _, kind in ipairs { 'xmp', 'raw', 'jpeg' } do
    test('reads and resolves only ' .. kind, function()
        local h = harness({ [kind] = kind }, { [kind] = { camera = 'X-H2S' } })
        local result = assert(h.read())
        equal(#h.calls, 1); equal(h.calls[1], kind)
        equal(result.metadata.camera, 'X-H2S'); equal(result.paths[kind], kind)
        equal(result.fieldSources.camera.sourceKind, kind); equal(result.fieldSources.camera.sourcePath, kind)
        equal(result.warnings[1], kind .. '：read warning')
        equal(h.scanned.original, '/photos/source.jpg'); equal(h.scanned.mode, 'same_then_parent')
    end)
end
test('merges fields and preserves priority and original responses', function()
    local paths = { xmp = 'xmp', raw = 'raw', jpeg = 'jpeg' }
    local values = { xmp = { camera = 'X-H2S', lens = '  ' },
        raw = { camera = 'Other', lens = 'XF35mm', filmSim = '' }, jpeg = { filmSim = 'PROVIA' } }
    local h = harness(paths, values); local result = assert(h.read())
    equal(table.concat(h.calls, ','), 'xmp,raw,jpeg'); equal(result.metadata.camera, 'X-H2S')
    equal(result.metadata.lens, 'XF35mm'); equal(result.fieldSources.lens.sourceKind, 'raw')
    equal(result.metadata.filmSim, 'PROVIA'); equal(result.fieldSources.filmSim.sourceKind, 'jpeg')
    equal(values.xmp.lens, '  '); equal(values.raw.camera, 'Other'); equal(#result.warnings, 3)
    result.paths.raw = 'changed'; equal(paths.raw, 'raw')
end)
test('empty discovery yields missing fields without a read', function()
    local h = harness({}, {}); local result = assert(h.read())
    equal(#h.calls, 0); equal(next(result.metadata), nil); equal(#result.missingFields, 8)
end)
test('preserves a scan error without executing ExifTool', function()
    local err = { code = 'AmbiguousSource', message = 'Two RAW candidates' }
    local h = harness({}, {}, { scanError = err }); local result, actual = h.read()
    equal(result, nil); equal(actual, err); equal(#h.calls, 0)
end)
for _, kind in ipairs { 'xmp', 'raw', 'jpeg' } do
    test('fails a ' .. kind .. ' read rather than silently falling back', function()
        local err = { code = 'ProcessFailed', message = 'Unreadable input' }
        local h = harness({ xmp = 'xmp', raw = 'raw', jpeg = 'jpeg' },
            { xmp = {}, raw = {}, jpeg = {} }, { failedPath = kind, readError = err })
        local result, actual = h.read(); equal(result, nil); equal(actual, err)
        equal(h.calls[#h.calls], kind)
    end)
end
for _, stopAt in ipairs { 1, 2, 3 } do
    test('stops cancellation before source ' .. stopAt, function()
        local h = harness({ xmp = 'xmp', raw = 'raw', jpeg = 'jpeg' }, { xmp = {}, raw = {}, jpeg = {} })
        local checks = 0
        local result, err = h.read(function() checks = checks + 1; return checks == stopAt end)
        equal(result, nil); equal(err.code, 'Canceled'); equal(#h.calls, stopAt - 1)
    end)
end
test('excludes an SDK rendering without changing discovered paths', function()
    local paths = { raw = 'raw', jpeg = 'rendered' }
    local h = harness(paths, { raw = { camera = 'X-H2S' }, rendered = { camera = 'Wrong' } })
    local result = assert(h.read(nil, function(path) return path == 'rendered' end))
    equal(result.paths.jpeg, nil); equal(result.metadata.camera, 'X-H2S')
    equal(#h.calls, 1); equal(paths.jpeg, 'rendered')
end)
test('does not hide an invalid metadata response as empty metadata', function()
    local h = harness({ raw = 'raw' }, { raw = false })
    local result, err = h.read(); equal(result, nil); equal(err.code, 'InvalidMetadata')
end)
print(string.format('%d metadata-reader boundary tests passed.', count))
