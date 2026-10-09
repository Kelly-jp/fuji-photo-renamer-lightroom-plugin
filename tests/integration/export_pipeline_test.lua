local newHarness = assert(loadfile('tests/support/export_harness.lua'))()
local count = 0
local function equal(a, b) assert(a == b, tostring(a) .. ' ~= ' .. tostring(b)) end
local function test(name, callback) callback(); count = count + 1; print('PASS ' .. name) end
local metadata = { captureDateTime = '2026:10:09 12:34:56', cameraMaker = 'FUJIFILM', camera = 'X-H2S', lensMaker = 'Fujifilm Corporation', lens = 'XF18/55mm', filmSim = 'PROVIA' }
test('saves expanded metadata names and sanitizes them', function()
    local h = newHarness { metadata = metadata }
    h.settings.fprTemplate = '{DateTime}_{CameraMaker}_{Camera}_{LensMaker}_{Lens}_{Original}'
    h.run(); equal(#h.errors, 0)
    equal(h.copies[1][2], '/output/20261009_123456_FUJIFILM_X-H2S_XF18_55mm_DSCF1234.jpg')
end)
test('honors maker omission OFF in actual saves', function()
    local h = newHarness { metadata = metadata }; h.settings.fprTemplate = '{CameraMaker}_{LensMaker}'
    h.settings.fprOmitDuplicateManufacturer = false; h.run()
    equal(h.copies[1][2], '/output/FUJIFILM_FUJIFILM.jpg')
end)
test('uses actual JPEG extension instead of a template token', function()
    local h = newHarness { rendered = '/temporary/photo.JPEG' }; h.settings.fprTemplate = '{Original}'; h.run()
    equal(h.copies[1][2], '/output/DSCF1234.jpeg')
end)
for _, mode in ipairs { 'same_directory', 'parent_directory', 'same_then_parent' } do
    test('passes RAW mode to the reader: ' .. mode, function()
        local h = newHarness(); h.settings.fprRawSearchMode = mode; h.run()
        equal(h.lastRead.mode, mode); equal(h.lastRead.path, '/original/DSCF1234.RAF'); equal(h.lastRead.executable, '/test/exiftool')
    end)
end
test('does not number an output just because an earlier photo failed', function()
    local h = newHarness { repeatCount = 2, firstReadError = true }; h.settings.fprTemplate = '{Original}'
    h.run(); equal(#h.errors, 1); equal(#h.copies, 1); equal(h.copies[1][2], '/output/DSCF1234.jpg')
end)
test('freezes naming and RAW mode during the session', function()
    local h = newHarness { repeatCount = 2, onRead = function(state)
        state.settings.fprTemplate = 'changed'; state.settings.fprRawSearchMode = 'parent_directory'
    end }
    h.settings.fprTemplate = '{Original}'; h.run()
    equal(h.copies[2][2], '/output/DSCF1234_001.jpg'); equal(h.lastRead.mode, 'same_then_parent')
end)
for _, options in ipairs { { readError = true }, { metadata = {} }, { onRead = function(state) state.cancelRequested = true end } } do
    test('does not copy after read failure, missing required date, or cancellation', function()
        local h = newHarness(options); h.settings.fprTemplate = '{DateTime}_{Original}'; h.run()
        equal(#h.copies, 0); equal(#h.errors, 1)
    end)
end
test('rejects empty metadata expansion', function()
    local h = newHarness { metadata = {} }; h.settings.fprTemplate = '{Lens}'; h.run()
    equal(#h.copies, 0); equal(#h.errors, 1)
end)
test('shows reader warnings after a successful save', function()
    local h = newHarness { warnings = { 'Metadata warning' } }; h.run()
    equal(#h.copies, 1); assert(h.messages[1][2]:find('Metadata warning', 1, true)); equal(h.messages[1][3], 'warning')
end)
test('fails without deleting a partial copy', function()
    local h = newHarness { partialFailure = true }; h.run()
    equal(#h.errors, 1); equal(h.files['/output/test_DSCF1234.jpg'], 'file')
end)
for _, options in ipairs { { missingTool = true }, { remove = true }, { toolException = true } } do
    test('stops unsupported C2PA or missing ExifTool before rendering', function()
        local h = newHarness(options); if options.remove then h.settings.fprRemoveC2pa = true end
        h.run(); equal(h.waits, 0); equal(#h.copies, 0); equal(h.messages[1][3], 'critical')
    end)
end
local function pipeline(paths, values, failureKind)
    local resolver = assert(loadfile('src/FujiPhotoRenamer.lrplugin/core/MetadataResolver.lua'))()
    local calls = {}
    local reader = assert(loadfile('src/FujiPhotoRenamer.lrplugin/infrastructure/MetadataReader.lua')) {
        scanner = { resolve = function() return paths end }, resolver = resolver,
        reader = { readMetadata = function(path)
            calls[#calls + 1] = path
            if failureKind == path then return nil, { code = 'ReadError', message = 'Unreadable source' } end
            return { metadata = values[path], warnings = { path .. ' warning' } }
        end },
    }
    return reader, calls
end
test('merges XMP RAW JPG individually and retains source paths and warnings', function()
    local reader, calls = pipeline({ xmp = 'xmp', raw = 'raw', jpeg = 'jpeg' }, {
        xmp = { filmSim = 'CLASSIC_NEGATIVE' }, raw = { camera = 'X-H2S', lensMaker = 'FUJIFILM' }, jpeg = { captureDateTime = '2026:10:09 12:34:56' },
    })
    local result = assert(reader.read('/photo.jpg', 'same_then_parent', '/exiftool'))
    equal(result.metadata.filmSim, 'CLASSIC_NEGATIVE'); equal(result.metadata.camera, 'X-H2S')
    equal(result.fieldSources.captureDateTime.sourceKind, 'jpeg'); equal(#calls, 3); equal(#result.warnings, 3)
    equal(result.paths.raw, 'raw')
end)
test('does not fall through an XMP read error', function()
    local reader, calls = pipeline({ xmp = 'xmp', raw = 'raw' }, { raw = { camera = 'X-H2S' } }, 'xmp')
    local result, err = reader.read('/photo.jpg', 'same_then_parent', '/exiftool'); equal(result, nil); equal(err.code, 'ReadError'); equal(#calls, 1)
end)
test('cancels before reading a source', function()
    local reader, calls = pipeline({ raw = 'raw' }, { raw = {} })
    local result, err = reader.read('/photo.RAF', 'same_then_parent', '/exiftool', function() return true end)
    equal(result, nil); equal(err.code, 'Canceled'); equal(#calls, 0)
end)
test('asks the filesystem about case-equivalent existing names', function()
    local h = newHarness { caseInsensitive = true, extraFiles = { ['/output/TEST_DSCF1234.JPG'] = 'file' } }
    h.run(); equal(h.copies[1][2], '/output/test_DSCF1234_001.jpg')
end)
test('asks the filesystem about Unicode-equivalent existing names', function()
    local h = newHarness { original = '/original/café.JPG',
        extraFiles = { ['/output/test_cafe\204\129.jpg'] = 'file' },
        existsTransform = function(path) return (path:gsub('é', 'e\204\129')) end }
    -- Keep the synthetic original readable after the test-only filesystem transform.
    h.files['/original/cafe\204\129.JPG'] = 'file'
    h.run(); equal(h.copies[1][2], '/output/test_café_001.jpg')
end)
for _, name in ipairs { 'COM¹', 'LPT³' } do
    test('rejects superscript port names for subfolders: ' .. name, function()
        local h = newHarness { useSubfolder = true, subfolder = name }; h.run()
        equal(#h.errors, 1); equal(#h.copies, 0); equal(#h.createdDirectories, 0)
    end)
end
test('uses only collision suffixes across repeated independent exports', function()
    local h = newHarness(); h.settings.fprTemplate = '{Original}'
    h.run(); h.run(); h.run()
    equal(h.copies[1][2], '/output/DSCF1234.jpg')
    equal(h.copies[2][2], '/output/DSCF1234_001.jpg')
    equal(h.copies[3][2], '/output/DSCF1234_002.jpg')
end)
print(string.format('%d Phase 9 pipeline tests passed.', count))
