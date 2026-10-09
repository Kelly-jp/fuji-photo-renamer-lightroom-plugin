local context = assert(..., 'ExportServiceProvider requires plugin dependencies')
local LrDialogs, LrFileUtils = assert(context.dialogs), assert(context.fileUtils)
local LrPathUtils, LrTasks = assert(context.pathUtils), assert(context.tasks)
local exportDialog = assert(context.ui)

local provider = {
    exportPresetFields = exportDialog.exportPresetFields,
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
    exportDialog.startDialog(propertyTable)
end

function provider.endDialog(propertyTable)
    exportDialog.endDialog(propertyTable)
end

function provider.sectionsForTopOfDialog(f, propertyTable)
    return exportDialog.sections(f, propertyTable)
end

function provider.updateExportSettings(exportSettings)
    local reason = exportDialog.cannotExportBecause(exportSettings)
    if reason then error(reason) end
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

local function saveRendition(rendition, destination, progressScope, settings, session)
    local rendered, renderedPath = rendition:waitForRender()
    if progressScope:isCanceled() then return false, '書き出しがキャンセルされました。' end
    if not rendered then return false, 'レンダリングに失敗しました：' .. tostring(renderedPath) end
    if type(renderedPath) ~= 'string' or not LrPathUtils.isAbsolute(renderedPath)
        or LrFileUtils.exists(renderedPath) ~= 'file' then return false, 'レンダリング済みファイルが見つかりません。' end
    local extension = LrPathUtils.extension(renderedPath):lower()
    if extension ~= 'jpg' and extension ~= 'jpeg' then return false, 'JPEG 以外は保存しません。' end
    local originalPath = rendition.photo:getRawMetadata('path')
    if type(originalPath) ~= 'string' or not LrPathUtils.isAbsolute(originalPath)
        or LrFileUtils.exists(originalPath) ~= 'file' or not LrFileUtils.isReadable(originalPath) then
        return false, '元画像のパスを取得できないか、元画像が読み取れません。'
    end
    local metadata, readError = context.metadataReader.read(originalPath, settings.fprRawSearchMode,
        settings.executablePath, function() return progressScope:isCanceled() end)
    if not metadata then return false, readError.code .. '：' .. readError.message end
    if progressScope:isCanceled() then return false, '書き出しがキャンセルされました。' end
    local parsed, parseError = context.parser.parse(settings.fprTemplate)
    if not parsed then return false, parseError.message end
    local candidate, tokenError = context.tokens.resolve(parsed, metadata.metadata, {
        original = LrPathUtils.removeExtension(LrPathUtils.leafName(originalPath)), extension = extension,
        omitDuplicateManufacturer = settings.fprOmitDuplicateManufacturer,
    })
    if not candidate then return false, tokenError.message end
    local safe, safetyError = context.sanitizer.sanitize(candidate.filename)
    if not safe then return false, safetyError.message end
    local path, saveError = context.fileSystem.save(renderedPath, safe.filename, destination, originalPath,
        metadata.paths, progressScope, session)
    if not path then return false, saveError end
    return true, table.concat(metadata.warnings, '\n')
end

function provider.processRenderedPhotos(functionContext, exportContext)
    local input = exportContext.propertyTable
    local settings = {}
    for _, field in ipairs(exportDialog.exportPresetFields) do
        settings[field.key] = input[field.key]
        if settings[field.key] == nil then settings[field.key] = field.default end
    end
    settings.LR_format, settings.LR_export_destinationType = input.LR_format, input.LR_export_destinationType
    local destination = {}
    for key, value in pairs(input.phase1Destination or {}) do destination[key] = value end
    local progressScope = exportContext:configureProgress {
        title = 'Fuji Photo Renamer：JPEG を保存中',
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
    local reason = exportDialog.cannotExportBecause(settings)
    local toolOk, executable, toolError = LrTasks.pcall(function()
        return context.reader.resolveExecutablePath {
            executablePath = settings.fprExifToolPath ~= '' and settings.fprExifToolPath or nil,
        }
    end)
    if not toolOk then reason = 'ExifTool のパス確認に失敗しました：' .. tostring(executable) end
    if reason or not executable then
        LrDialogs.message('書き出しを開始できません', reason or toolError.message, 'critical')
        progressScope:cancel()
        return
    end
    settings.executablePath = executable
    local savedCount, failedCount = 0, 0
    local session, warnings = {}, {}

    for _, rendition in exportContext:renditions { stopIfCanceled = true } do
        if progressScope:isCanceled() then
            break
        end
        if not rendition.wasSkipped then
            local ok, saved, message = LrTasks.pcall(function()
                if settings.LR_format ~= 'JPEG' or settings.LR_export_destinationType ~= 'tempFolder' then
                    return false, 'JPEG の一時レンダリング設定が適用されていません。'
                end
                return saveRendition(rendition, destination, progressScope, settings, session)
            end)
            if not ok then
                message = 'SDK 処理中にエラーが発生しました：' .. tostring(saved)
                saved = false
            end
            if saved then
                savedCount = savedCount + 1
                if message and message ~= '' then warnings[#warnings + 1] = message end
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
    LrDialogs.message('Fuji Photo Renamer：' .. status,
        string.format('保存済み：%d 枚\n失敗：%d 枚\n保存先：%s',
            savedCount, failedCount, location) .. (#warnings > 0 and '\n警告：\n' .. table.concat(warnings, '\n') or ''),
        (failedCount > 0 or #warnings > 0) and 'warning' or 'info')
    -- No deletion or mutation of originals/renders: Lightroom owns temporary cleanup.
end

return provider
