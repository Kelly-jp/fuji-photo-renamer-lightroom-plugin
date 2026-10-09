local properties = assert(loadfile('tests/support/observable_properties.lua'))()
local count = 0
local function equal(a, b) assert(a == b, tostring(a) .. ' ~= ' .. tostring(b)) end
local function test(name, callback) callback(); count = count + 1; print('PASS ' .. name) end
local function loadCore(name, deps) return assert(loadfile('src/FujiPhotoRenamer.lrplugin/core/' .. name .. '.lua'))(deps) end
local function harness(readPreview)
    local tasks, queue = { pcall = pcall }, {}
    tasks.startAsyncTask = function(callback) queue[#queue + 1] = callback end
    local resolver = loadCore('MetadataResolver')
    local ui = assert(loadfile('src/FujiPhotoRenamer.lrplugin/ui/ExportDialog.lua')) {
        bind = function(key) return key end, parser = loadCore('TemplateParser'), sanitizer = loadCore('FilenameSanitizer'),
        tokens = loadCore('TokenResolver', { normalizer = loadCore('ManufacturerNormalizer'), metadataResolver = resolver }),
        tasks = tasks, readPreview = readPreview,
    }
    local props = properties { fprTemplate = '{Camera}_{Original}' }
    ui.startDialog(props)
    return ui, props, queue
end
local function photo(name) return { original = name or 'real', metadata = { camera = 'X-T5' } } end
test('updates the preview with real metadata after an asynchronous read', function()
    local ui, props, queue = harness(function(mode, path) equal(mode, 'same_then_parent'); equal(path, ''); return photo() end)
    ui.requestPreview(props); equal(props.fprPreview, 'X-H2S_DSCF1234.jpg'); queue[1]()
    equal(props.fprPreview, 'X-T5_real.jpg'); assert(props.fprPreviewSource:find('real', 1, true))
    props.fprTemplate = '{Original}'; equal(props.fprPreview, 'real.jpg')
end)
test('keeps sample and error explanation when no selected photo is available', function()
    local ui, props, queue = harness(function() return nil, 'No photo selected' end)
    ui.requestPreview(props); queue[1]()
    equal(props.fprPreview, 'X-H2S_DSCF1234.jpg'); assert(props.fprPreviewStatus:find('No photo selected', 1, true))
    assert(props.fprPreviewSource:find('取得失敗', 1, true)); equal(props.LR_cantExportBecause, nil)
end)
test('does not reinterpret an ExifTool exception as a successful photo preview', function()
    local ui, props, queue = harness(function() error('Tool failed') end)
    ui.requestPreview(props); queue[1](); assert(props.fprPreviewStatus:find('Tool failed', 1, true))
end)
test('shows missing required real dates without replacing them with sample dates', function()
    local ui, props, queue = harness(function() return photo() end)
    props.fprTemplate = '{DateTime}'; ui.requestPreview(props); queue[1]()
    equal(props.fprPreview, 'プレビューを作成できません。'); assert(props.fprPreviewStatus:find('撮影日時', 1, true))
end)
for _, field in ipairs { 'fprRawSearchMode', 'fprExifToolPath' } do
    test('drops stale data after acquisition settings change: ' .. field, function()
        local ui, props, queue = harness(function() return photo('stale') end)
        ui.requestPreview(props); props[field] = field == 'fprExifToolPath' and '/new/exiftool' or 'parent_directory'
        queue[1](); equal(props.fprPreview, 'X-H2S_DSCF1234.jpg'); assert(props.fprPreviewSource:find('取得設定を変更', 1, true))
    end)
end
test('drops results after closing and reopening the dialog', function()
    local ui, props, queue = harness(function() return photo('stale') end)
    ui.requestPreview(props); ui.endDialog(props); ui.startDialog(props); queue[1]()
    equal(props.fprPreview, 'X-H2S_DSCF1234.jpg')
end)
test('allows current template edits while metadata is being acquired', function()
    local ui, props, queue = harness(function() return photo() end)
    ui.requestPreview(props); props.fprTemplate = '{Original}'; queue[1](); equal(props.fprPreview, 'real.jpg')
end)
test('drops an older request that completes after the newer request', function()
    local n = 0
    local ui, props, queue = harness(function() n = n + 1; return photo('read' .. n) end)
    ui.requestPreview(props); ui.requestPreview(props); queue[2](); equal(props.fprPreview, 'X-T5_read1.jpg')
    queue[1](); equal(props.fprPreview, 'X-T5_read1.jpg')
end)
test('retains developer ExifTool path as a scalar preset setting', function()
    local ui, props = harness(function() return photo() end)
    props.fprExifToolPath = '/tools/exiftool'; equal(props.fprExifToolPath, '/tools/exiftool')
    equal(ui.exportPresetFields[5].key, 'fprExifToolPath'); equal(ui.exportPresetFields[5].default, '')
end)
test('shows metadata warnings with a real preview', function()
    local ui, props, queue = harness(function() local result = photo(); result.warnings = 'ExifTool warning'; return result end)
    ui.requestPreview(props); queue[1](); assert(props.fprPreviewStatus:find('ExifTool warning', 1, true))
end)
print(string.format('%d Phase 9 asynchronous-preview tests passed.', count))
