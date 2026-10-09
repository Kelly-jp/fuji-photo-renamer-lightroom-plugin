local context = assert(..., 'ExifToolLoader requires the plugin context')
local LrPathUtils = assert(context.pathUtils)

-- Use explicit file paths; neither SDK name lookup nor setfenv is required.
local function loadChunk(relativePath)
    local path = LrPathUtils.child(context.pluginPath, relativePath)
    local chunk, message = loadfile(path)
    if not chunk then error('読み込みに失敗しました：' .. path .. '\n' .. tostring(message)) end
    return chunk
end

local json = loadChunk('dkjson.lua')()
return loadChunk('infrastructure/ExifTool.lua') {
    fileUtils = context.fileUtils,
    pathUtils = LrPathUtils,
    tasks = context.tasks,
    json = json,
    pluginPath = context.pluginPath,
    platform = context.platform,
}
