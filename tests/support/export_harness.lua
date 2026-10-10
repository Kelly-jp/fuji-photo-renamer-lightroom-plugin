local pluginDirectory = 'src/FujiPhotoRenamer.lrplugin/'
local function assertEqual(actual, expected)
    assert(actual == expected, string.format('Expected %s, got %s', tostring(expected), tostring(actual)))
end
local function newHarness(options)
    options = options or {}
    local original = options.original or '/original/DSCF1234.RAF'
    local rendered = options.rendered or '/temporary/DSCF1234.jpg'
    local files = { ['/output'] = 'directory', [original] = 'file', [rendered] = 'file' }
    local originalDirectory = original:match('^(.*)/[^/]+$')
    if originalDirectory then files[originalDirectory] = 'directory' end
    for _, name in ipairs { 'desktop', 'documents', 'home', 'pictures' } do
        files['/standard/' .. name] = 'directory'
    end
    for path, kind in pairs(options.extraFiles or {}) do files[path] = kind end
    for _, path in ipairs(options.originalPaths or {}) do
        files[path] = 'file'
        files[path:match('^(.*)/[^/]+$')] = 'directory'
    end
    if options.missingOriginal then files[original] = nil end
    if options.missingRender then files[rendered] = nil end
    if options.missingDirectory then files['/output'] = nil end
    if options.collision then files['/output/test_DSCF1234.jpg'] = options.collision end
    local state = { copies = {}, errors = {}, messages = {}, waits = 0, files = files, createdDirectories = {} }
    local progress = {
        isCanceled = function() return options.canceled or state.cancelAfterRender or state.cancelRequested end,
        cancel = function() state.cancelRequested = true end,
    }
    local namespaces = {
        LrFileUtils = {
            exists = function(path)
                if options.existsTransform then path = options.existsTransform(path) end
                if options.caseInsensitive then
                    for name, kind in pairs(files) do if name:lower() == path:lower() then return kind end end
                end
                return files[path] or false
            end,
            isReadable = function(path) return files[path] == 'file' and not options.unreadable end,
            resolveAllAliases = function(path)
                if options.alias and path == rendered then return original end
                return path
            end,
            createAllDirectories = function(path)
                state.createdDirectories[#state.createdDirectories + 1] = path
                if options.createFailure then return false, 'Permission denied' end
                if files[path] and files[path] ~= 'directory' then return false, 'File exists' end
                files[path] = 'directory'
                if options.cancelDuringCreate then state.cancelRequested = true end
                return true
            end,
            move = function(source, destination)
                state.copies[#state.copies + 1] = { source, destination }
                -- Emulate the documented no-overwrite contract, including a late collision.
                if options.race then files[destination] = 'file' end
                if files[destination] then return false, 'Destination exists' end
                if options.copyException then error('Copy exception') end
                if options.partialFailure then files[destination] = 'file'; return false, 'Partial failure' end
                if options.copyFailure then return false, 'Permission denied' end
                files[destination] = 'file'
                files[source] = nil
                return true
            end,
        },
        LrPathUtils = {
            isAbsolute = function(path) return path:sub(1, 1) == '/' or path:match('^%a:[/\\]') ~= nil end,
            leafName = function(path) return path:match('[^/\\]+$') end,
            removeExtension = function(path) return (path:gsub('%.[^.]*$', '')) end,
            extension = function(path) return path:match('%.([^.]*)$') or '' end,
            parent = function(path) return path:match('^(.*)/[^/]+$') end,
            getStandardFilePath = function(name) return '/standard/' .. name end,
            child = function(parent, name) return parent .. '/' .. name end,
            standardizePath = function(path) return path end,
        },
        LrTasks = { pcall = pcall, startAsyncTask = function(callback) callback() end },
        LrDialogs = {
            message = function(title, message, severity)
                state.messages[#state.messages + 1] = { title, message, severity }
            end,
            runOpenPanel = function()
                state.panelCount = (state.panelCount or 0) + 1
                if options.panelException then error('Panel error') end
                return options.selectedPaths
            end,
        },
        LrView = { bind = function(key) return key end },
    }
    local function loadModule(name, deps) return assert(loadfile(pluginDirectory .. name))(deps) end
    local metadataResolver = loadModule('core/MetadataResolver.lua')
    local parser = loadModule('core/TemplateParser.lua')
    local sanitizer = loadModule('core/FilenameSanitizer.lua')
    local tokens = loadModule('core/TokenResolver.lua', { normalizer = loadModule('core/ManufacturerNormalizer.lua'), metadataResolver = metadataResolver })
    local ui = loadModule('ui/ExportDialog.lua', { bind = namespaces.LrView.bind, parser = parser, tokens = tokens, sanitizer = sanitizer })
    state.provider = loadModule('lightroom/ExportServiceProvider.lua', {
        dialogs = namespaces.LrDialogs, fileUtils = namespaces.LrFileUtils, pathUtils = namespaces.LrPathUtils,
        tasks = namespaces.LrTasks, ui = ui, parser = parser, tokens = tokens, sanitizer = sanitizer,
        reader = { resolveExecutablePath = function()
            if options.toolException then error('Path check exception') end
            if options.missingTool then return nil, { code = 'ExecutableMissing', message = 'Missing tool' } end
            return '/test/exiftool'
        end },
        metadataReader = { read = function(path, mode, executable, cancel)
            state.reads = (state.reads or 0) + 1
            state.lastRead = { path = path, mode = mode, executable = executable }
            if options.onRead then options.onRead(state, cancel) end
            if options.readError or options.firstReadError and state.reads == 1 then
                return nil, { code = 'ReadError', message = 'Read failed' }
            end
            return { metadata = options.metadata or { captureDateTime = '2026:10:08 12:34:56', cameraMaker = 'FUJIFILM' }, paths = { raw = path }, warnings = options.warnings or {} }
        end },
        fileSystem = loadModule('infrastructure/FileSystem.lua', { fileUtils = namespaces.LrFileUtils,
            pathUtils = namespaces.LrPathUtils, collisions = loadModule('core/CollisionResolver.lua', { sanitizer = sanitizer }) }),
    })
    local rendition = {
        wasSkipped = options.skipped,
        photo = {
            getRawMetadata = function(_, key)
                assertEqual(key, 'path')
                if options.metadataException then error('Metadata exception') end
                if options.noPath then return nil end
                return state.currentOriginal or original
            end,
        },
        waitForRender = function()
            state.waits = state.waits + 1
            if not options.missingRender then files[rendered] = 'file' end
            if options.removeBaseDuringRender then files['/output'] = nil end
            if options.renderException then error('Render exception') end
            if options.cancelDuringRender then state.cancelAfterRender = true end
            if options.renderFailure then return false, 'Render failed' end
            return true, rendered
        end,
        uploadFailed = function(_, message) state.errors[#state.errors + 1] = message end,
    }
    state.settings = {
        LR_export_destinationType = options.destinationType or 'specificFolder',
        LR_export_destinationPathPrefix = options.directory or '/output',
        LR_export_useSubfolder = options.useSubfolder,
        LR_export_destinationPathSuffix = options.subfolder,
    }
    state.settings.fprTemplate = 'test_{Original}'
    state.provider.updateExportSettings(state.settings)
    if options.unsafeSettings then state.settings.LR_export_destinationType = 'sourceFolder' end
    local context = {
        propertyTable = state.settings,
        configureProgress = function() state.progressConfigured = true; return progress end,
        renditions = function(_, args)
            assert(state.progressConfigured)
            assertEqual(args.stopIfCanceled, true)
            local i = 0
            return function()
                i = i + 1
                if i <= (options.originalPaths and #options.originalPaths or options.repeatCount or 1) then
                    state.currentOriginal = options.originalPaths and options.originalPaths[i]
                    return i, rendition
                end
            end
        end,
    }
    state.run = function() state.provider.processRenderedPhotos({}, context) end
    return state
end

return newHarness
