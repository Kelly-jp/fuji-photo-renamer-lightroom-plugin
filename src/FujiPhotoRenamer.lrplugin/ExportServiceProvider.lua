local LrDialogs = import 'LrDialogs'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'
local LrApplication = import 'LrApplication'

local function loadModule(relativePath, dependencies)
    local path = LrPathUtils.child(_PLUGIN.path, relativePath)
    local chunk, message = loadfile(path)
    if not chunk then error('読み込みに失敗しました：' .. path .. '\n' .. tostring(message)) end
    return chunk(dependencies)
end
local metadataResolver = loadModule('core/MetadataResolver.lua')
local normalizer = loadModule('core/ManufacturerNormalizer.lua')
local parser = loadModule('core/TemplateParser.lua')
local sanitizer = loadModule('core/FilenameSanitizer.lua')
local tokens = loadModule('core/TokenResolver.lua', { normalizer = normalizer, metadataResolver = metadataResolver })
local context = { fileUtils = LrFileUtils, pathUtils = LrPathUtils, tasks = LrTasks, pluginPath = _PLUGIN.path,
    platform = WIN_ENV and 'windows' or MAC_ENV and 'macos' or nil }
local reader = loadModule('ExifToolLoader.lua', context)
local metadataReader = loadModule('infrastructure/MetadataReader.lua', {
    scanner = loadModule('infrastructure/MetadataSourceResolver.lua', context), reader = reader, resolver = metadataResolver,
})
local exportDialog = loadModule('ui/ExportDialog.lua', {
    bind = LrView.bind, parser = parser, tokens = tokens, sanitizer = sanitizer,
    tasks = LrTasks, dialogs = LrDialogs,
    readPreview = function(mode, path)
        local photo = LrApplication.activeCatalog():getTargetPhoto()
        if not photo then return nil, 'カタログで写真を選択してください。' end
        local original = photo:getRawMetadata('path')
        local result, err = metadataReader.read(original, mode, path ~= '' and path or nil)
        if not result then return nil, err.code .. '：' .. err.message end
        return { metadata = result.metadata, original = LrPathUtils.removeExtension(LrPathUtils.leafName(original)),
            warnings = table.concat(result.warnings, '\n') }
    end,
})

context.collisions = loadModule('core/CollisionResolver.lua', { sanitizer = sanitizer })
return loadModule('lightroom/ExportServiceProvider.lua', {
    dialogs = LrDialogs, fileUtils = LrFileUtils, pathUtils = LrPathUtils, tasks = LrTasks,
    parser = parser, tokens = tokens, sanitizer = sanitizer, ui = exportDialog,
    reader = reader, metadataReader = metadataReader,
    fileSystem = loadModule('infrastructure/FileSystem.lua', context),
})
