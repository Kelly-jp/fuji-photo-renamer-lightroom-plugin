-- Boundary checks only. These doubles do not validate Lightroom's SDK implementation.
local pluginDirectory = 'src/FujiPhotoRenamer.lrplugin/'
local testCount = 0

local function assertEqual(actual, expected)
    assert(actual == expected, string.format('Expected %s, got %s', tostring(expected), tostring(actual)))
end

local newHarness = assert(loadfile('tests/support/export_harness.lua'))()

local function test(name, callback)
    callback()
    testCount = testCount + 1
    print('PASS ' .. name)
end

test('plugin registration points to a loadable provider', function()
    local info = dofile(pluginDirectory .. 'Info.lua')
    assertEqual(info.LrExportServiceProvider.file, 'ExportServiceProvider.lua')
    assertEqual(info.LrSdkMinimumVersion, 11.0)
    assert(loadfile(pluginDirectory .. info.LrExportServiceProvider.file))
end)

test('settings force temporary JPEG rendering and prevent catalog reimport', function()
    local h = newHarness()
    assertEqual(h.settings.LR_format, 'JPEG')
    assertEqual(h.settings.LR_export_destinationType, 'tempFolder')
    assertEqual(h.settings.LR_reimportExportedPhoto, false)
    assertEqual(h.settings.LR_renamingTokensOn, false)
    assertEqual(h.provider.canExportVideo, false)
    local hasExportLocation = false
    for _, section in ipairs(h.provider.showSections) do
        if section == 'exportLocation' then hasExportLocation = true end
    end
    assert(hasExportLocation)
    assertEqual(h.settings.phase1Destination.kind, 'specificFolder')
    assertEqual(h.settings.phase1Destination.path, '/output')
end)

test('copies only the completed render to the selected folder with the original stem', function()
    local h = newHarness()
    h.run()
    assertEqual(h.waits, 1)
    assertEqual(#h.errors, 0)
    assertEqual(#h.copies, 1)
    assertEqual(h.copies[1][1], '/temporary/DSCF1234.jpg')
    assertEqual(h.copies[1][2], '/output/test_DSCF1234.jpg')
    assertEqual(h.files['/original/DSCF1234.RAF'], 'file')
end)

test('preserves Unicode, spaces, and dots in the source stem', function()
    local h = newHarness { original = '/original/写真 sample.v2.JPG' }
    h.run()
    assertEqual(h.copies[1][2], '/output/test_写真 sample.v2.jpg')
end)

for _, case in ipairs {
    { 'missing folder', { missingDirectory = true } },
    { 'relative folder', { directory = 'relative' } },
    { 'missing original', { missingOriginal = true } },
    { 'unreadable original', { unreadable = true } },
    { 'missing catalog path', { noPath = true } },
    { 'relative catalog path', { original = 'DSCF1234.JPG' } },
    { 'metadata exception', { metadataException = true } },
    { 'render failure', { renderFailure = true } },
    { 'render exception', { renderException = true } },
    { 'missing render', { missingRender = true } },
    { 'non JPEG render', { rendered = '/temporary/photo.tif' } },
    { 'original returned as render', { original = '/original/DSCF1234.jpg', rendered = '/original/DSCF1234.jpg' } },
    { 'alias resolving to original', { alias = true } },
    { 'unsafe export settings', { unsafeSettings = true } },
    { 'canceled while rendering', { cancelDuringRender = true } },
} do
    test('rejects ' .. case[1] .. ' without copying', function()
        local h = newHarness(case[2])
        h.run()
        assertEqual(#h.copies, 0)
        assertEqual(#h.errors, 1)
        assert(type(h.errors[1]) == 'string' and h.errors[1] ~= '')
    end)
end

for _, case in ipairs {
    { 'late destination collision', { race = true } },
    { 'copy failure', { copyFailure = true } },
    { 'copy exception', { copyException = true } },
} do
    test('reports ' .. case[1] .. ' as failure', function()
        local h = newHarness(case[2])
        h.run()
        assertEqual(#h.copies, 1)
        assertEqual(#h.errors, 1)
        assert(h.messages[1][2]:find('保存済み：0', 1, true))
        assertEqual(h.files['/original/DSCF1234.RAF'], 'file')
    end)
end

test('second rendition with the same stem uses a collision suffix', function()
    local h = newHarness { repeatCount = 2 }
    h.run()
    assertEqual(#h.copies, 2)
    assertEqual(#h.errors, 0)
    assertEqual(h.copies[2][2], '/output/test_DSCF1234_001.jpg')
    assert(h.messages[1][2]:find('保存済み：2', 1, true))
end)

for _, case in ipairs { { 'canceled', { canceled = true } }, { 'skipped', { skipped = true } } } do
    test('does not process a ' .. case[1] .. ' rendition', function()
        local h = newHarness(case[2])
        h.run()
        assertEqual(h.waits, 0)
        assertEqual(#h.copies, 0)
        assertEqual(#h.errors, 0)
    end)
end

test('migrates the previous destination into Lightroom settings', function()
    local h = newHarness()
    local settings = { phase1OutputDirectory = '/chosen', LR_export_destinationType = 'tempFolder' }
    settings.addObserver = function() end; settings.removeObserver = function() end
    h.provider.startDialog(settings)
    assertEqual(settings.LR_export_destinationType, 'specificFolder')
    assertEqual(settings.LR_export_destinationPathPrefix, '/chosen')
    local sourceSettings = { LR_export_destinationType = 'sourceFolder', LR_export_useSubfolder = true }
    sourceSettings.addObserver = function() end; sourceSettings.removeObserver = function() end
    h.provider.startDialog(sourceSettings)
    assertEqual(sourceSettings.LR_export_destinationType, 'sourceFolder')
    assertEqual(sourceSettings.LR_export_useSubfolder, true)
end)

test('saves next to the original', function()
    local h = newHarness { destinationType = 'sourceFolder' }
    h.run()
    assertEqual(h.copies[1][2], '/original/test_DSCF1234.jpg')
    assertEqual(h.files['/original/DSCF1234.RAF'], 'file')
end)

test('restores the selected location if the dialog receives the temporary session settings', function()
    local h = newHarness { destinationType = 'sourceFolder', useSubfolder = true, subfolder = 'exports' }
    h.settings.addObserver = function() end; h.settings.removeObserver = function() end
    h.provider.startDialog(h.settings)
    assertEqual(h.settings.LR_export_destinationType, 'sourceFolder')
    assertEqual(h.settings.LR_export_useSubfolder, true)
    assertEqual(h.settings.LR_export_destinationPathSuffix, 'exports')
end)

test('resolves each original directory in a mixed-folder export', function()
    local h = newHarness { destinationType = 'sourceFolder', useSubfolder = true, subfolder = 'exports',
        originalPaths = { '/first/DSCF1234.RAF', '/second/DSCF1234.RAF' } }
    h.run()
    assertEqual(#h.errors, 0)
    assertEqual(#h.copies, 2)
    assertEqual(h.copies[1][2], '/first/exports/test_DSCF1234.jpg')
    assertEqual(h.copies[2][2], '/second/exports/test_DSCF1234.jpg')
end)

for _, kind in ipairs { 'specificFolder', 'sourceFolder' } do
    test('creates the requested subfolder for ' .. kind, function()
        local h = newHarness { destinationType = kind, useSubfolder = true, subfolder = '書き出し JPEG' }
        h.run()
        local parent = kind == 'sourceFolder' and '/original' or '/output'
        assertEqual(h.copies[1][2], parent .. '/書き出し JPEG/test_DSCF1234.jpg')
        assertEqual(h.createdDirectories[1], parent .. '/書き出し JPEG')
        assertEqual(#h.errors, 0)
    end)
end

for _, kind in ipairs { 'desktop', 'documents', 'home', 'pictures' } do
    test('supports standard destination ' .. kind, function()
        local h = newHarness { destinationType = kind }
        h.run()
        assertEqual(h.copies[1][2], '/standard/' .. kind .. '/test_DSCF1234.jpg')
    end)
end

for _, name in ipairs { '', '..', '.', '../escape', '/absolute', 'nested/folder', 'nested\\folder', 'bad:name', 'name.', 'name ', 'CON', 'NUL.txt', 'CON .txt', 'COM1', 'LPT9' } do
    test('rejects unsafe subfolder: ' .. name, function()
        local h = newHarness { useSubfolder = true, subfolder = name }
        h.run()
        assertEqual(#h.copies, 0)
        assertEqual(#h.createdDirectories, 0)
        assertEqual(#h.errors, 1)
    end)
end

test('supports an existing subfolder without recreating it', function()
    local h = newHarness { useSubfolder = true, subfolder = '.exports', extraFiles = { ['/output/.exports'] = 'directory' } }
    h.run()
    assertEqual(#h.errors, 0)
    assertEqual(#h.createdDirectories, 0)
    assertEqual(h.copies[1][2], '/output/.exports/test_DSCF1234.jpg')
end)

test('ignores an unused subfolder name', function()
    local h = newHarness { useSubfolder = false, subfolder = '../ignored' }
    h.run()
    assertEqual(#h.errors, 0)
    assertEqual(h.copies[1][2], '/output/test_DSCF1234.jpg')
end)

for _, useSubfolder in ipairs { false, true } do
    test('does not recreate a missing base folder after rendering: subfolder=' .. tostring(useSubfolder), function()
        local h = newHarness { removeBaseDuringRender = true, useSubfolder = useSubfolder, subfolder = 'exports' }
        h.run()
        assertEqual(#h.copies, 0)
        assertEqual(#h.createdDirectories, 0)
        assertEqual(#h.errors, 1)
    end)
end

for _, case in ipairs {
    { 'file occupies the subfolder', { extraFiles = { ['/output/exports'] = 'file' } } },
    { 'subfolder creation fails', { createFailure = true } },
    { 'cancel during subfolder creation', { cancelDuringCreate = true } },
    { 'render fails before subfolder creation', { renderFailure = true } },
} do
    test('handles ' .. case[1], function()
        case[2].useSubfolder = true
        case[2].subfolder = 'exports'
        local h = newHarness(case[2])
        h.run()
        assertEqual(#h.copies, 0)
        assertEqual(#h.errors, 1)
    end)
end

test('prompts once for chooseLater and applies the subfolder', function()
    local h = newHarness { destinationType = 'chooseLater', selectedPaths = { '/output' }, useSubfolder = true, subfolder = 'exports' }
    h.run()
    assertEqual(h.panelCount, 1)
    assertEqual(h.copies[1][2], '/output/exports/test_DSCF1234.jpg')
end)

for _, case in ipairs { { 'folder selection canceled', {} }, { 'folder selection exception', { panelException = true } } } do
    test('handles ' .. case[1] .. ' without rendering or copying', function()
        case[2].destinationType = 'chooseLater'
        local h = newHarness(case[2])
        h.run()
        assert(h.cancelRequested)
        assertEqual(h.waits, 0)
        assertEqual(#h.copies, 0)
    end)
end

test('rejects unsupported destinations', function()
    local h = newHarness { destinationType = 'tempFolder' }
    h.run()
    assertEqual(#h.errors, 1)
    assertEqual(#h.copies, 0)
end)

for _, kind in ipairs { 'file', 'directory' } do
    test('renames around an existing ' .. kind, function()
        local h = newHarness { collision = kind }; h.run()
        assertEqual(#h.errors, 0); assertEqual(h.copies[1][2], '/output/test_DSCF1234_001.jpg')
        assertEqual(h.files['/output/test_DSCF1234.jpg'], kind)
    end)
end
test('sanitizes prohibited characters from the source stem', function()
    local h = newHarness { original = '/original/invalid:name.JPG' }; h.run()
    assertEqual(h.copies[1][2], '/output/test_invalid_name.jpg')
end)
test('renames around an existing subfolder output', function()
    local h = newHarness { useSubfolder = true, subfolder = 'exports', extraFiles = {
        ['/output/exports'] = 'directory', ['/output/exports/test_DSCF1234.jpg'] = 'file' } }
    h.run(); assertEqual(h.copies[1][2], '/output/exports/test_DSCF1234_001.jpg')
end)
print(string.format('%d boundary tests passed; Lightroom manual integration remains required.', testCount))
