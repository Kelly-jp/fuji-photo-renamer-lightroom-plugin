local context = assert(..., 'ExportPostProcessing requires SDK dependencies')
local files, paths, shell = assert(context.fileUtils), assert(context.pathUtils), assert(context.shell)
local Processing = {}
function Processing.validate(action, application)
    if application ~= nil and type(application) ~= 'string' then return nil, 'アプリケーションのパスは文字列で指定してください。' end
    if action == nil or action == 'none' or action == 'reveal' then return true end
    if action ~= 'open_application' then return nil, '書き出し後の処理を選択してください。' end
    if type(application) ~= 'string' or application:find('[%z\r\n]') or not paths.isAbsolute(application) then
        return nil, '書き出し後に開くアプリケーションの絶対パスを指定してください。'
    end
    local kind = files.exists(application)
    if kind ~= 'file' and not (kind == 'directory' and paths.extension(application):lower() == 'app') then
        return nil, '指定したアプリケーションが見つかりません。'
    end
    return true
end

function Processing.run(action, application, savedPaths)
    local valid, message = Processing.validate(action, application)
    if not valid then error(message) end
    if not action or action == 'none' or #savedPaths == 0 then return end
    local unique, seen = {}, {}
    for _, filename in ipairs(savedPaths) do
        if type(filename) ~= 'string' or filename:find('[%z\r\n]') or not paths.isAbsolute(filename)
            or files.exists(filename) ~= 'file' then error('後処理に渡す最終JPEGが見つかりません。') end
        if not seen[filename] then unique[#unique + 1] = filename; seen[filename] = true end
    end
    if action == 'open_application' then
        shell.openFilesInApp(unique, application)
    else
        local folders = {}
        for _, filename in ipairs(unique) do
            local parent = paths.parent(filename)
            if not folders[parent] then shell.revealInShell(filename); folders[parent] = true end
        end
    end
end
return Processing
