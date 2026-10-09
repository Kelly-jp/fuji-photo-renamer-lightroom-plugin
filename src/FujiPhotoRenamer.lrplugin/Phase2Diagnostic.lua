local LrDialogs = import 'LrDialogs'
local LrTasks = import 'LrTasks'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'

LrTasks.startAsyncTask(function()
    local ok, message = LrTasks.pcall(function()
        -- Keep module loading independent of SDK script-name registration.
        local loaderPath = LrPathUtils.child(_PLUGIN.path, 'ExifToolLoader.lua')
        local loader, loadError = loadfile(loaderPath)
        if not loader then error('検証モジュールを読み込めません：' .. tostring(loadError)) end
        local ExifTool = loader {
            fileUtils = LrFileUtils, pathUtils = LrPathUtils, tasks = LrTasks,
            pluginPath = _PLUGIN.path,
            platform = WIN_ENV and 'windows' or MAC_ENV and 'macos' or nil,
        }
        -- This explicit development-only selection is not an automatic PATH fallback.
        local executables = LrDialogs.runOpenPanel {
            title = 'Phase 2：検証に使用する ExifTool 実行ファイルを選択',
            canChooseFiles = true, canChooseDirectories = false, allowsMultipleSelection = false,
        }
        if not executables or not executables[1] then return end
        local photos = LrDialogs.runOpenPanel {
            title = 'Phase 2：読み取り専用で検証する RAF / DNG / JPG / XMP を選択',
            canChooseFiles = true, canChooseDirectories = false, allowsMultipleSelection = false,
        }
        if not photos or not photos[1] then return end
        local result, readError = ExifTool.readMetadata(photos[1], { executablePath = executables[1] })
        if not result then
            local detail = readError.message
            if readError.exitCode then detail = detail .. '\n終了コード：' .. tostring(readError.exitCode) end
            if readError.stderr and readError.stderr ~= '' then detail = detail .. '\n' .. readError.stderr end
            for _, warning in ipairs(readError.cleanupWarnings or {}) do detail = detail .. '\n' .. warning end
            LrDialogs.message('メタデータ取得に失敗しました：' .. readError.code, detail, 'critical')
            return
        end
        local names = {
            { 'captureDateTime', '撮影日時' }, { 'cameraMaker', 'CameraMaker' }, { 'camera', 'Camera' },
            { 'lensMaker', 'LensMaker' }, { 'lens', 'Lens' }, { 'filmSim', 'FilmSim' },
            { 'iso', 'ISO' }, { 'focalLength', '焦点距離（mm）' },
        }
        local lines = { 'ExifTool ' .. tostring(result.toolVersion or '不明') .. ' / 終了コード 0' }
        for _, item in ipairs(names) do
            lines[#lines + 1] = item[2] .. '：' .. tostring(result.metadata[item[1]] or '未取得')
        end
        for _, warning in ipairs(result.warnings) do lines[#lines + 1] = '警告：' .. warning end
        LrDialogs.message('Phase 2：読み取り専用の取得結果', table.concat(lines, '\n'),
            #result.warnings > 0 and 'warning' or 'info')
    end)
    if not ok then LrDialogs.message('Phase 2：検証処理に失敗しました', tostring(message), 'critical') end
end)
