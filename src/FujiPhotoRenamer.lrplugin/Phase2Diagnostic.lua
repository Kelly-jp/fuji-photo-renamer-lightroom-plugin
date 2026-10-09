local LrDialogs = import 'LrDialogs'
local LrTasks = import 'LrTasks'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'

-- Reuse a script already recognized by Lightroom instead of registering new entry names.
LrTasks.startAsyncTask(function()
    local ok, message = LrTasks.pcall(function()
        local choice = LrDialogs.confirm('検証する内容を選択してください',
            '入力ファイルの探索は ExifTool を使わず、ファイル名と配置だけを確認します。',
            'XMP / RAW / JPG の探索', 'キャンセル', 'ExifTool でメタデータ取得')
        if choice == 'cancel' then return end
        if choice ~= 'ok' and choice ~= 'other' then error('検証内容の選択結果が不正です。') end
        local filename = choice == 'ok' and 'Phase3Diagnostic.lua' or 'Phase2MetadataDiagnostic.lua'
        local path = LrPathUtils.child(_PLUGIN.path, filename)
        local chunk, loadError = loadfile(path)
        if not chunk then error('検証処理を読み込めません：' .. path .. '\n' .. tostring(loadError)) end
        local run = chunk {
            dialogs = LrDialogs, fileUtils = LrFileUtils, pathUtils = LrPathUtils, tasks = LrTasks,
            pluginPath = _PLUGIN.path,
            platform = WIN_ENV and 'windows' or MAC_ENV and 'macos' or nil,
        }
        run()
    end)
    if not ok then LrDialogs.message('検証処理に失敗しました', tostring(message), 'critical') end
end)
