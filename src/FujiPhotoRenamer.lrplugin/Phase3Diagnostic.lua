local context = assert(..., 'Diagnostic requires the plugin context')
local LrDialogs = assert(context.dialogs)
local LrTasks = assert(context.tasks)
local LrFileUtils = assert(context.fileUtils)
local LrPathUtils = assert(context.pathUtils)

return function()
    local path = LrPathUtils.child(context.pluginPath, 'infrastructure/MetadataSourceResolver.lua')
    local chunk, loadError = loadfile(path)
    if not chunk then error('探索モジュールを読み込めません：' .. tostring(loadError)) end
    local resolver = chunk { fileUtils = LrFileUtils, pathUtils = LrPathUtils, tasks = LrTasks }
    local photos = LrDialogs.runOpenPanel {
        title = 'Phase 3：探索の起点にする元 JPG / JPEG / RAF / DNG を選択',
        canChooseFiles = true, canChooseDirectories = false, allowsMultipleSelection = false,
    }
    if not photos or not photos[1] then return end
    local lines = { 'ファイル名と配置だけを調べます。ExifTool は実行しません。' }
    local extension = LrPathUtils.extension(photos[1]):lower()
    if extension == 'raf' or extension == 'dng' then
        lines[#lines + 1] = 'RAW を起点にした場合は選択 RAW を使い、JPG と XMP は同じ階層で探します。'
    end
    local failed = false
    for _, mode in ipairs {
        { 'same_directory', '同じフォルダー' },
        { 'parent_directory', '1 つ上のフォルダー' },
        { 'same_then_parent', '同じフォルダー → 1 つ上のフォルダー' },
    } do
        lines[#lines + 1] = '\nRAW 探索：' .. mode[2]
        local sources, scanError = resolver.resolve(photos[1], mode[1])
        if sources then
            for _, name in ipairs { 'xmp', 'raw', 'jpeg' } do
                lines[#lines + 1] = name .. '：' .. tostring(sources[name] or '見つかりません')
            end
        else
            failed = true
            lines[#lines + 1] = scanError.code .. '：' .. scanError.message
            for _, candidate in ipairs(scanError.candidates or {}) do lines[#lines + 1] = candidate end
        end
    end
    LrDialogs.message('Phase 3：探索結果', table.concat(lines, '\n'), failed and 'warning' or 'info')
end
