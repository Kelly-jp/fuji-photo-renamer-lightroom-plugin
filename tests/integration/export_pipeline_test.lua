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
for _, options in ipairs { { missingTool = true }, { toolException = true } } do
    test('stops missing or invalid ExifTool before rendering', function()
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
test('uses formatted lens and film display names in actual saves', function()
    local h = newHarness { metadata = { lens = 'XF200mm  F2 R LM  OIS WR', filmSim = 'PRO_NEG_HI' } }
    h.settings.fprTemplate = '{Lens}_{FilmSim}_{Original}'
    h.run(); equal(h.copies[1][2], '/output/XF200mm-F2-R-LM-OIS-WR_PRO-Neg-Hi_DSCF1234.jpg')
end)
test('transfers a rendition rendered into the final folder without leaving the original name', function()
    local h = newHarness { rendered = '/output/DSCF1234.jpg' }; h.run()
    equal(#h.errors, 0); equal(h.files['/output/test_DSCF1234.jpg'], 'file')
    equal(h.files['/output/DSCF1234.jpg'], nil); equal(h.files['/original/DSCF1234.RAF'], 'file')
end)
test('accepts the owned SDK output when it already has the final name', function()
    local h = newHarness { rendered = '/output/DSCF1234.jpg' }; h.settings.fprTemplate = '{Original}'
    h.run(); equal(#h.errors, 0); equal(#h.copies, 0)
    equal(h.files['/output/DSCF1234.jpg'], 'file'); equal(h.files['/output/DSCF1234_001.jpg'], nil)
end)
test('preserves existing output while transferring a rendition from the final folder', function()
    local h = newHarness { rendered = '/output/DSCF1234.jpg', extraFiles = { ['/output/test_DSCF1234.jpg'] = 'file' } }
    h.run(); equal(#h.errors, 0); equal(h.files['/output/test_DSCF1234.jpg'], 'file')
    equal(h.files['/output/test_DSCF1234_001.jpg'], 'file'); equal(h.files['/output/DSCF1234.jpg'], nil)
end)
test('preserves final destination across repeated update callbacks without opening a dialog', function()
    local h = newHarness { useSubfolder = true, subfolder = 'exports' }
    h.provider.updateExportSettings(h.settings); h.provider.updateExportSettings(h.settings)
    equal(h.settings.phase1Destination.kind, 'specificFolder'); equal(h.settings.phase1Destination.path, '/output')
    equal(h.settings.phase1Destination.useSubfolder, true); equal(h.settings.phase1Destination.subfolder, 'exports')
    h.run(); equal(h.copies[1][2], '/output/exports/test_DSCF1234.jpg')
end)
test('rejects cached temporary settings without an original destination', function()
    local h = newHarness(); h.settings.phase1Destination = nil
    local ok, message = pcall(h.provider.updateExportSettings, h.settings)
    equal(ok, false); assert(message:find('保存先を復元', 1, true)); equal(#h.copies, 0)
end)
test('does not read a fresh SDK JPEG discovered next to its RAW as source metadata', function()
    local paths = { raw = 'raw', jpeg = 'rendered' }
    local reader, calls = pipeline(paths, { raw = { camera = 'X-H2S' }, rendered = { camera = 'Wrong source' } })
    local result = assert(reader.read('/photo.RAF', 'same_then_parent', '/exiftool', nil,
        function(path) return path == 'rendered' end))
    equal(#calls, 1); equal(result.paths.jpeg, nil); equal(result.metadata.camera, 'X-H2S')
    equal(paths.jpeg, 'rendered')
end)
test('invokes C2PA preparation only when ON', function()
    local h = newHarness(); h.settings.fprRemoveC2pa = true; h.run()
    equal(h.c2paCalls, 1); equal(h.releases, 1); equal(#h.errors, 0)
    equal(h.copies[1][1], '/temporary/c2pa-clean.jpg')
    local off = newHarness(); off.run(); equal(off.c2paCalls, nil)
end)
for _, options in ipairs { { c2paError = true }, { cancelC2pa = true }, { commitError = true } } do
    test('never publishes a failed, canceled, or changed C2PA artifact', function()
        local h = newHarness(options); h.settings.fprRemoveC2pa = true; h.run()
        equal(#h.copies, 0); equal(#h.errors, 1); equal(h.releases, 1)
        equal(h.files['/original/DSCF1234.RAF'], 'file')
    end)
end
for _, options in ipairs { { copyFailure = true }, { partialFailure = true }, { copyException = true } } do
    test('reports a final transfer failure after C2PA removal and releases its work copy', function()
        local h = newHarness(options); h.settings.fprRemoveC2pa = true; h.run()
        equal(#h.errors, 1); equal(h.releases, 1); equal(h.c2paCalls, 1)
        equal(h.files['/original/DSCF1234.RAF'], 'file'); equal(h.files['/temporary/c2pa-clean.jpg'], nil)
        if options.partialFailure then equal(h.files['/output/test_DSCF1234.jpg'], 'file') end
    end)
end
print(string.format('%d Phase 9 pipeline tests passed.', count))
