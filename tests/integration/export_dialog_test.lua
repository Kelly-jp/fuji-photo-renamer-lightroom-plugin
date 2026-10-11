local pluginPath = 'src/FujiPhotoRenamer.lrplugin'
local count = 0
local function equal(actual, expected) assert(actual == expected, tostring(actual) .. ' ~= ' .. tostring(expected)) end
local function test(name, callback) callback(); count = count + 1; print('PASS ' .. name) end
local properties = assert(loadfile('tests/support/observable_properties.lua'))()
local factory = {}
for _, kind in ipairs { 'static_text', 'edit_field', 'popup_menu', 'checkbox', 'push_button', 'row' } do
    factory[kind] = function(_, specification) specification.kind = kind; return specification end
end
local namespaces = {
    LrDialogs = {}, LrFileUtils = {}, LrTasks = {}, LrApplication = {},
    LrPathUtils = { child = function(parent, leaf) return parent .. '/' .. leaf end },
    LrView = { bind = function(key) return { bindingKey = key } end },
}
local loader = assert(loadfile(pluginPath .. '/ExportServiceProvider.lua'))
setfenv(loader, setmetatable({ _PLUGIN = { path = pluginPath },
    import = function(name) return assert(namespaces[name], name) end,
    require = function(name) error('No script by the name ' .. name) end,
}, { __index = _G }))
local provider = loader()
local function start(initial) local props, observed = properties(initial); provider.startDialog(props); return props, observed end
local function findControl(props, key)
    for _, control in ipairs(provider.sectionsForTopOfDialog(factory, props)[1]) do
        local binding = control.value or control.title
        if type(binding) == 'table' and binding.bindingKey == key then return control end
    end
    error('Missing control ' .. key)
end

test('uses Lightroom standard export location and five persistent settings', function()
    equal(provider.showSections[1], 'exportLocation'); equal(#provider.exportPresetFields, 5)
    local expected = { fprTemplate = 'string', fprRawSearchMode = 'string', fprOmitDuplicateManufacturer = 'boolean', fprRemoveC2pa = 'boolean', fprExifToolPath = 'string' }
    for _, field in ipairs(provider.exportPresetFields) do equal(type(field.default), expected[field.key]); expected[field.key] = nil end
    equal(next(expected), nil)
end)
test('shows a sample when no photo or ExifTool is available', function()
    local props = start()
    equal(props.fprPreview, '20261008_123456_DSCF1234.jpg')
    equal(props.fprOmitDuplicateManufacturer, true); equal(props.fprRemoveC2pa, false)
    equal(props.fprRawSearchMode, 'same_then_parent'); equal(props.LR_cantExportBecause, nil)
end)
test('preserves restored settings including false instead of resetting defaults', function()
    local props = start { fprTemplate = '{Original}', fprRawSearchMode = 'parent_directory', fprOmitDuplicateManufacturer = false }
    equal(props.fprTemplate, '{Original}'); equal(props.fprRawSearchMode, 'parent_directory'); equal(props.fprOmitDuplicateManufacturer, false)
end)
test('updates preview on template edits without losing typed text', function()
    local props = start(); props.fprTemplate = '{Date}_{Time}_{Original}'
    equal(props.fprPreview, '20261008_123456_DSCF1234.jpg'); equal(props.fprTemplate, '{Date}_{Time}_{Original}')
end)
test('updates manufacturer omission live in both directions', function()
    local props = start { fprTemplate = '{CameraMaker}_{Camera}_{LensMaker}' }
    equal(props.fprPreview, 'FUJIFILM_X-H2S.jpg')
    props.fprOmitDuplicateManufacturer = false; equal(props.fprPreview, 'FUJIFILM_X-H2S_FUJIFILM.jpg')
    props.fprOmitDuplicateManufacturer = true; equal(props.fprPreview, 'FUJIFILM_X-H2S.jpg')
    assert(props.fprPreviewStatus:find('LensMaker', 1, true))
end)
test('reuses sanitizer in the UI preview', function()
    local props = start { fprTemplate = 'name?:{Original}' }
    equal(props.fprPreview, 'name__DSCF1234.jpg')
end)
for _, template in ipairs { '{Unknown}', '{Date', '', 'a/b', 'CON', '.hidden' } do
    test('reports invalid template without throwing: ' .. template, function()
        local props = start { fprTemplate = template }
        assert(type(props.LR_cantExportBecause) == 'string'); equal(props.fprTemplate, template)
        equal(props.fprPreview, 'プレビューを作成できません。')
        props.fprTemplate = '{Original}'; equal(props.LR_cantExportBecause, nil); equal(props.fprPreview, 'DSCF1234.jpg')
    end)
end
for _, mode in ipairs { 'same_directory', 'parent_directory', 'same_then_parent' } do
    test('stores RAW search mode: ' .. mode, function()
        local props = start(); props.fprRawSearchMode = mode
        equal(props.fprRawSearchMode, mode); equal(props.LR_cantExportBecause, nil)
    end)
end
for _, values in ipairs { { fprRawSearchMode = 'recursive' }, { fprOmitDuplicateManufacturer = 'ON' }, { fprRemoveC2pa = 1 } } do
    test('blocks corrupt preset values', function() local props = start(values); assert(type(props.LR_cantExportBecause) == 'string') end)
end
test('stores C2PA ON and allows verified export processing', function()
    local props = start(); props.fprRemoveC2pa = true
    equal(props.LR_cantExportBecause, nil); equal(props.fprRemoveC2pa, true)
    props.fprRemoveC2pa = false; equal(props.LR_cantExportBecause, nil)
end)
test('restoring an ON preset never silently turns C2PA off', function()
    local props = start { fprRemoveC2pa = true }; equal(props.fprRemoveC2pa, true); equal(props.LR_cantExportBecause, nil)
end)
test('declares immediate edits, read-only preview and all RAW choices', function()
    local props = start(); local edit = findControl(props, 'fprTemplate'); equal(edit.immediate, true)
    equal(findControl(props, 'fprPreview').enabled, false)
    local items = findControl(props, 'fprRawSearchMode').items; equal(#items, 3)
    equal(items[1].value, 'same_directory'); equal(items[2].value, 'parent_directory'); equal(items[3].value, 'same_then_parent')
    equal(findControl(props, 'fprOmitDuplicateManufacturer').kind, 'checkbox')
    equal(findControl(props, 'fprRemoveC2pa').kind, 'checkbox')
end)
test('makes sample and actual export behavior explicit', function()
    local props = start(); local section = provider.sectionsForTopOfDialog(factory, props)[1]
    equal(section.bind_to_object, props)
    local labels = {}
    for _, view in ipairs(section) do if type(view.title) == 'string' then labels[#labels + 1] = view.title end end
    assert(props.fprPreviewSource:find('サンプル情報', 1, true))
    assert(props.fprExportStatus:find('このテンプレートで保存', 1, true))
end)
test('removes observers on close and avoids duplicates on reopening', function()
    local props, observed = start(); equal(observed(), 5)
    provider.startDialog(props); equal(observed(), 5)
    provider.endDialog(props, 'cancel'); equal(observed(), 0)
    local preview = props.fprPreview; props.fprTemplate = '{FilmSim}'; equal(props.fprPreview, preview)
    provider.startDialog(props); equal(observed(), 5); equal(props.fprPreview, 'PROVIA.jpg')
    provider.endDialog(props, 'changedServiceProvider'); equal(observed(), 0)
    provider.endDialog(props, 'ok'); equal(observed(), 0)
end)
test('declares only scalar settings for Lightroom preset storage', function()
    local original = start { fprTemplate = '{Camera}', fprRawSearchMode = 'parent_directory', fprOmitDuplicateManufacturer = false }
    local preset = {}
    for _, field in ipairs(provider.exportPresetFields) do preset[field.key] = original[field.key] end
    equal(preset.fprPreview, nil); equal(preset.fprPreviewStatus, nil); equal(preset.LR_cantExportBecause, nil)
    local restored = start(preset); equal(restored.fprPreview, 'X-H2S.jpg'); equal(restored.fprOmitDuplicateManufacturer, false)
end)
test('preserves enabled C2PA in export settings', function()
    local settings = { fprRemoveC2pa = true, LR_export_destinationType = 'sourceFolder' }
    provider.updateExportSettings(settings)
    equal(settings.fprRemoveC2pa, true); equal(settings.LR_export_destinationType, 'tempFolder')
end)
test('blocks invalid templates for programmatic export too', function()
    local ok = pcall(provider.updateExportSettings, { fprTemplate = '{Unknown}' }); equal(ok, false)
end)
test('preserves custom settings while directing actual export to temporary JPEG', function()
    local settings = { fprTemplate = '{Camera}', fprRawSearchMode = 'parent_directory', fprOmitDuplicateManufacturer = false,
        fprRemoveC2pa = false, LR_export_destinationType = 'sourceFolder', LR_export_useSubfolder = true, LR_export_destinationPathSuffix = 'exports' }
    provider.updateExportSettings(settings)
    equal(settings.fprTemplate, '{Camera}'); equal(settings.fprOmitDuplicateManufacturer, false)
    equal(settings.phase1Destination.kind, 'sourceFolder'); equal(settings.phase1Destination.subfolder, 'exports')
    equal(settings.LR_export_destinationType, 'tempFolder'); equal(settings.LR_format, 'JPEG')
end)
test('clears only this provider export blocker when switching services', function()
    local props = start { fprTemplate = '{Unknown}' }
    assert(props.LR_cantExportBecause)
    provider.endDialog(props, 'changedServiceProvider'); equal(props.LR_cantExportBecause, nil)
    provider.startDialog(props); props.LR_cantExportBecause = 'Another provider reason'
    provider.endDialog(props, 'changedServiceProvider'); equal(props.LR_cantExportBecause, 'Another provider reason')
end)
test('token buttons append each supported token and immediately update the preview', function()
    local props = start { fprTemplate = 'prefix_' }
    local section = provider.sectionsForTopOfDialog(factory, props)[1]
    local titles = {}
    for _, view in ipairs(section) do
        if view.kind == 'row' then
            for _, button in ipairs(view) do
                props.fprTemplate = 'prefix_'
                button.action()
                equal(props.fprTemplate, 'prefix_' .. button.title)
                assert(props.fprPreview:find('prefix_', 1, true)); equal(props.LR_cantExportBecause, nil)
                titles[button.title] = true
            end
        end
    end
    local n = 0; for _ in pairs(titles) do n = n + 1 end
    equal(n, 9); equal(titles['{Extension}'], nil); equal(titles['{ISO}'], nil); equal(titles['{FocalLength}'], nil); equal(titles['{Sequence}'], nil)
end)
test('migrates the old extension suffix on opening and applying presets', function()
    local props = start { fprTemplate = '{Original}.{Extension}' }
    equal(props.fprTemplate, '{Original}'); equal(props.fprPreview, 'DSCF1234.jpg')
    props.fprTemplate = '{Camera}.{Extension}'
    equal(props.fprTemplate, '{Camera}'); equal(props.fprPreview, 'X-H2S.jpg')
end)
test('rejects removed tokens except for the legacy terminal suffix', function()
    local props = start { fprTemplate = '{Extension}_{Original}' }; assert(props.LR_cantExportBecause)
    props.fprTemplate = '{Extention}'; assert(props.LR_cantExportBecause)
    props.fprTemplate = '{{Extension}}_{Original}'
    equal(props.fprTemplate, '{{Extension}}_{Original}'); equal(props.fprPreview, '{Extension}_DSCF1234.jpg')
end)
for _, template in ipairs { '{ISO}', '{FocalLength}' } do
    test('reports removed numeric tokens in existing templates: ' .. template, function()
        local props = start { fprTemplate = template }
        equal(props.fprTemplate, template); assert(props.LR_cantExportBecause)
        props.fprTemplate = '{Original}'; equal(props.LR_cantExportBecause, nil)
    end)
end
test('migrates the legacy terminal sequence and extension suffix', function()
    local props = start { fprTemplate = '{DateTime}_{Original}_{Sequence}.{Extension}' }
    equal(props.fprTemplate, '{DateTime}_{Original}'); equal(props.fprPreview, '20261008_123456_DSCF1234.jpg')
    props.fprTemplate = '{Original}_{Sequence}'; equal(props.fprTemplate, '{Original}')
    props.fprTemplate = '{{Sequence}}_{Original}'; equal(props.fprPreview, '{Sequence}_DSCF1234.jpg')
    props.fprTemplate = '{Sequence}_{Original}'; assert(props.LR_cantExportBecause)
end)
print(string.format('%d Phase 8 SDK-boundary tests passed; Lightroom manual verification remains required.', count))
