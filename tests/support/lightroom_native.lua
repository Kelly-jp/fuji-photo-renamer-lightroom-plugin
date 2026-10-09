-- macOS test adapter only; this is not proof of Lightroom SDK behavior.
local Adapter = {}
local function quote(value) return "'" .. value:gsub("'", "'\\''") .. "'" end
local function exists(path)
    if os.execute('/bin/test -d ' .. quote(path)) == 0 then return 'directory' end
    if os.execute('/bin/test -f ' .. quote(path)) == 0 then return 'file' end
    return false
end

function Adapter.install(pluginPath)
    local pluginModules = {}
    _G.require = function(name)
        assert(type(name) == 'string' and (name:match('^[%a_][%w_]*$')
            or name:match('^[%a_][%w_]*%.lua$')), 'require: invalid characters in script name')
        local filename = name
        if pluginModules[filename] == nil then
            local chunk = loadfile(pluginPath .. '/' .. filename)
            assert(chunk, 'Could not load toolkit script: ' .. name)
            pluginModules[filename] = chunk() or true
        end
        return pluginModules[filename]
    end
    local namespaces = {
        LrPathUtils = {
            isAbsolute = function(path) return path:sub(1, 1) == '/' or path:match('^%a:[/\\]') ~= nil end,
            child = function(parent, child) return parent .. '/' .. child end,
            extension = function(path) return path:match('%.([^./]*)$') or '' end,
            parent = function(path)
                if path == '/' then return nil end
                local parent = path:match('^(.*)/[^/]+$')
                return parent == '' and '/' or parent
            end,
            leafName = function(path) return path:match('[^/]+$') end,
            removeExtension = function(path) return (path:gsub('%.[^.]*$', '')) end,
            standardizePath = function(path) return path end,
            getStandardFilePath = function(key) assert(key == 'temp'); return '/tmp' end,
        },
        LrFileUtils = {
            exists = exists,
            resolveAllAliases = function(path) return path end,
            directoryEntries = function(path)
                local pipe = assert(io.popen('/usr/bin/find ' .. quote(path) .. ' -mindepth 1 -maxdepth 1 -print0'))
                local text = pipe:read('*a'); assert(pipe:close())
                local entries = {}
                for entry in text:gmatch('[^%z]+') do entries[#entries + 1] = entry end
                local i = 0
                return function() i = i + 1; return entries[i] end
            end,
            isReadable = function(path)
                local handle = io.open(path, 'rb')
                if not handle then return false end
                handle:close(); return true
            end,
            createAllDirectories = function(path)
                if exists(path) == 'directory' then return true, false end
                local code = os.execute('/bin/mkdir -p ' .. quote(path))
                return code == 0, code == 0 and true or 'mkdir failed'
            end,
            readFile = function(path)
                local handle = assert(io.open(path, 'rb')); local text = handle:read('*a'); handle:close(); return text
            end,
            fileAttributes = function(path)
                local handle = assert(io.open(path, 'rb')); local size = handle:seek('end'); handle:close()
                return { fileSize = size }
            end,
            delete = function(path)
                assert(path:match('^/tmp/fuji%-exiftool%-'), 'Refusing to delete outside owned test work paths')
                return os.remove(path)
            end,
            isEmptyDirectory = function(path)
                local pipe = assert(io.popen('/bin/ls -A ' .. quote(path)))
                local entries = pipe:read('*a'); assert(pipe:close()); return entries == ''
            end,
        },
        LrTasks = { pcall = pcall, execute = os.execute },
    }
    _G.import = function(name) return assert(namespaces[name], 'Unexpected SDK namespace: ' .. name) end
    _G._PLUGIN = { path = pluginPath }
    _G.MAC_ENV = true
    _G.WIN_ENV = false
    return namespaces
end

return Adapter
