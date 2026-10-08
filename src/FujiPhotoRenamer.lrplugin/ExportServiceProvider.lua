local LrDialogs = import 'LrDialogs'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

local provider = {
    showSections = { 'exportLocation', 'fileSettings', 'imageSettings', 'outputSharpening', 'metadata' },
    allowFileFormats = { 'JPEG' },
    canExportVideo = false,
    canExportToTemporaryLocation = false,
}

function provider.startDialog(propertyTable)
    local previous = propertyTable.phase1Destination
    if propertyTable.LR_export_destinationType == 'tempFolder' and type(previous) == 'table' then
        propertyTable.LR_export_destinationType = previous.kind
        propertyTable.LR_export_destinationPathPrefix = previous.path
        propertyTable.LR_export_useSubfolder = previous.useSubfolder
        propertyTable.LR_export_destinationPathSuffix = previous.subfolder
    end
    -- Migrate the earlier Phase 1 folder setting without retaining a second destination UI.
    if not propertyTable.LR_export_destinationType or propertyTable.LR_export_destinationType == 'tempFolder' then
        propertyTable.LR_export_destinationType = 'specificFolder'
        propertyTable.LR_export_destinationPathPrefix = propertyTable.phase1OutputDirectory or ''
    end
end

function provider.sectionsForTopOfDialog(f, propertyTable)
    return {
        {
            title = 'Phase 1：ファイル名と保存動作',
            f:static_text {
                title = '下の「書き出し場所」で保存先とサブフォルダーを指定してください。',
                width_in_chars = 60,
                height_in_lines = -1,
            },
            f:static_text {
                title = 'test_<元ファイル名>.jpg を保存します。同名ファイルは「既存のファイル」の設定にかかわらず上書きしません。',
                width_in_chars = 60,
                height_in_lines = -1,
            },
            f:static_text {
                title = 'この検証版では「このカタログに追加」とスタックへの追加は適用しません。',
                width_in_chars = 60,
                height_in_lines = -1,
            },
        },
    }
end

function provider.updateExportSettings(exportSettings)
    -- Keep the user's final destination before redirecting only the SDK's render output.
    exportSettings.phase1Destination = {
        kind = exportSettings.LR_export_destinationType,
        path = exportSettings.LR_export_destinationPathPrefix,
        useSubfolder = exportSettings.LR_export_useSubfolder,
        subfolder = exportSettings.LR_export_destinationPathSuffix,
    }
    exportSettings.LR_format = 'JPEG'
    exportSettings.LR_export_destinationType = 'tempFolder'
    exportSettings.LR_export_useSubfolder = false
    exportSettings.LR_reimportExportedPhoto = false
    exportSettings.LR_renamingTokensOn = false
    exportSettings.LR_collisionHandling = 'rename'
end

local function resolveOutputDirectory(destination, originalPath)
    local directory
    if destination.kind == 'sourceFolder' then
        directory = LrPathUtils.parent(originalPath)
    elseif destination.kind == 'specificFolder' then
        directory = destination.path
    elseif destination.kind == 'desktop' or destination.kind == 'documents'
        or destination.kind == 'home' or destination.kind == 'pictures' then
        directory = LrPathUtils.getStandardFilePath(destination.kind)
    else
        return nil, '対応していない保存先設定です：' .. tostring(destination.kind)
    end
    if type(directory) ~= 'string' or not LrPathUtils.isAbsolute(directory)
        or LrFileUtils.exists(directory) ~= 'directory' then
        return nil, '保存先フォルダーが存在しないか、絶対パスではありません。'
    end
    if destination.useSubfolder then
        local name = destination.subfolder
        if type(name) ~= 'string' or name == '' or name == '.' or name == '..'
            or name:find('[%c<>:"/\\|?*]') or name:find('[ .]$') then
            return nil, 'サブフォルダーにはパス区切りや禁止文字を含まないフォルダー名を指定してください。'
        end
        local deviceName = (name:match('^[^.]+') or name):gsub(' +$', ''):upper()
        if deviceName == 'CON' or deviceName == 'PRN' or deviceName == 'AUX' or deviceName == 'NUL'
            or deviceName:match('^COM[1-9]$') or deviceName:match('^LPT[1-9]$') then
            return nil, 'サブフォルダーに予約名は使用できません。'
        end
        directory = LrPathUtils.child(directory, name)
        local existing = LrFileUtils.exists(directory)
        if existing and existing ~= 'directory' then
            return nil, 'サブフォルダーと同名のファイルが存在します。'
        end
    end
    return directory
end

local function saveRendition(rendition, destination, progressScope)
    local originalPath = rendition.photo:getRawMetadata('path')
    if type(originalPath) ~= 'string' or not LrPathUtils.isAbsolute(originalPath)
        or LrFileUtils.exists(originalPath) ~= 'file' or not LrFileUtils.isReadable(originalPath) then
        return false, '元画像のパスを取得できないか、元画像が読み取れません。'
    end

    local directory, directoryError = resolveOutputDirectory(destination, originalPath)
    if not directory then
        return false, directoryError
    end

    local stem = LrPathUtils.removeExtension(LrPathUtils.leafName(originalPath))
    -- Phase 1 rejects problematic names; the full sanitizer belongs to Phase 7.
    if stem == '' or stem == '.' or stem == '..' or stem:find('[%c<>:"/\\|?*]')
        or stem:find('[ .]$') then
        return false, '元ファイル名を検証用の名前として安全に使用できません。'
    end
    local destinationPath = LrPathUtils.child(directory, 'test_' .. stem .. '.jpg')
    if LrFileUtils.exists(destinationPath) then
        return false, '保存先に同名のファイルまたはフォルダがあります：' .. destinationPath
    end

    local rendered, pathOrMessage = rendition:waitForRender()
    if progressScope:isCanceled() then
        return false, '書き出しがキャンセルされました。'
    end
    if not rendered then
        return false, 'レンダリングに失敗しました：' .. tostring(pathOrMessage)
    end
    if type(pathOrMessage) ~= 'string' or not LrPathUtils.isAbsolute(pathOrMessage)
        or LrFileUtils.exists(pathOrMessage) ~= 'file' then
        return false, 'レンダリング済みファイルが見つかりません。'
    end

    local extension = LrPathUtils.extension(pathOrMessage):lower()
    if extension ~= 'jpg' and extension ~= 'jpeg' then
        return false, 'JPEG 以外のレンダリング結果は保存しません。'
    end
    local sourcePath = LrPathUtils.standardizePath(LrFileUtils.resolveAllAliases(originalPath))
    local renderPath = LrPathUtils.standardizePath(LrFileUtils.resolveAllAliases(pathOrMessage))
    if sourcePath:lower() == renderPath:lower() then
        return false, 'レンダリング結果が元画像と同じパスのため保存しません。'
    end

    -- Only create an explicitly requested subfolder after the render succeeds.
    if LrFileUtils.exists(directory) ~= 'directory' then
        if not destination.useSubfolder
            or LrFileUtils.exists(LrPathUtils.parent(directory)) ~= 'directory' then
            return false, '保存先または親フォルダーがレンダリング中に失われました。'
        end
        local created, createMessage = LrFileUtils.createAllDirectories(directory)
        if not created or LrFileUtils.exists(directory) ~= 'directory' then
            return false, 'サブフォルダーを作成できません：' .. tostring(createMessage or directory)
        end
    end

    if progressScope:isCanceled() then
        return false, '書き出しがキャンセルされました。'
    end

    -- copy() refuses an existing destination per the SDK; exists() alone is not the guard.
    local copied, copyMessage = LrFileUtils.copy(pathOrMessage, destinationPath)
    if not copied then
        return false, 'JPEG を保存できません：' .. tostring(copyMessage or destinationPath)
    end
    return true
end

function provider.processRenderedPhotos(functionContext, exportContext)
    local settings = exportContext.propertyTable
    local destination = settings.phase1Destination or {}
    local progressScope = exportContext:configureProgress {
        title = 'Fuji Photo Renamer — Phase 1：JPEG を保存中',
    }
    if destination.kind == 'chooseLater' then
        local ok, paths = LrTasks.pcall(function()
            return LrDialogs.runOpenPanel {
                title = 'JPEG の保存先フォルダーを選択',
                canChooseFiles = false,
                canChooseDirectories = true,
                canCreateDirectories = true,
                allowsMultipleSelection = false,
            }
        end)
        if not ok then
            LrDialogs.message('保存先を選択できません', tostring(paths), 'critical')
            progressScope:cancel()
            return
        end
        if not paths or not paths[1] then
            progressScope:cancel()
            return
        end
        destination.kind = 'specificFolder'
        destination.path = paths[1]
    end
    local savedCount = 0
    local failedCount = 0

    for _, rendition in exportContext:renditions { stopIfCanceled = true } do
        if progressScope:isCanceled() then
            break
        end
        if not rendition.wasSkipped then
            local ok, saved, message = LrTasks.pcall(function()
                if settings.LR_format ~= 'JPEG' or settings.LR_export_destinationType ~= 'tempFolder' then
                    return false, 'JPEG の一時レンダリング設定が適用されていません。'
                end
                return saveRendition(rendition, destination, progressScope)
            end)
            if not ok then
                message = 'SDK 処理中にエラーが発生しました：' .. tostring(saved)
                saved = false
            end
            if saved then
                savedCount = savedCount + 1
            else
                failedCount = failedCount + 1
                rendition:uploadFailed(message)
            end
        end
    end

    local status = progressScope:isCanceled() and 'キャンセル' or '処理終了'
    local standardLocationNames = {
        desktop = 'デスクトップ', documents = 'ドキュメント', home = 'ホーム', pictures = 'ピクチャ',
    }
    local location = destination.kind == 'sourceFolder' and '各写真の元フォルダー'
        or standardLocationNames[destination.kind] or destination.path or destination.kind or '未選択'
    if destination.useSubfolder then
        location = location .. ' / ' .. tostring(destination.subfolder or '')
    end
    LrDialogs.message('Phase 1：' .. status,
        string.format('保存済み：%d 枚\n失敗：%d 枚\n保存先：%s',
            savedCount, failedCount, location),
        failedCount > 0 and 'warning' or 'info')
    -- No deletion or mutation of originals/renders: Lightroom owns temporary cleanup.
end

return provider
