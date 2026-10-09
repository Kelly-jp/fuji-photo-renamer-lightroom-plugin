local context = assert(..., 'Diagnostic requires the plugin context')
local dialogs = assert(context.dialogs)
local pathUtils = assert(context.pathUtils)

return function()
    local function loadModule(relativePath, moduleContext)
        local path = pathUtils.child(context.pluginPath, relativePath)
        local chunk, message = loadfile(path)
        if not chunk then error('読み込みに失敗しました：' .. path .. '\n' .. tostring(message)) end
        return chunk(moduleContext)
    end
    local scanner = loadModule('infrastructure/MetadataSourceResolver.lua', context)
    local reader = loadModule('ExifToolLoader.lua', context)
    local resolver = loadModule('core/MetadataResolver.lua')
    local normalizer = loadModule('core/ManufacturerNormalizer.lua')
    local executables = dialogs.runOpenPanel {
        title = 'Phase 4：検証用 ExifTool 実行ファイルを選択',
        canChooseFiles = true, canChooseDirectories = false, allowsMultipleSelection = false,
    }
    if not executables or not executables[1] then return end
    local photos = dialogs.runOpenPanel {
        title = 'Phase 4：元 JPG / JPEG / RAF / DNG を選択',
        canChooseFiles = true, canChooseDirectories = false, allowsMultipleSelection = false,
    }
    if not photos or not photos[1] then return end
    local paths, scanError = scanner.resolve(photos[1], 'same_then_parent')
    if not paths then
        dialogs.message('Phase 4：探索に失敗しました', scanError.code .. '：' .. scanError.message, 'critical')
        return
    end
    local sources, warnings = {}, {}
    for _, kind in ipairs { 'xmp', 'raw', 'jpeg' } do
        if paths[kind] then
            local result, readError = reader.readMetadata(paths[kind], { executablePath = executables[1] })
            if not result then
                local detail = readError.code .. '：' .. readError.message
                if readError.stderr then detail = detail .. '\n' .. readError.stderr end
                dialogs.message('Phase 4：' .. kind .. ' の読取に失敗しました', detail, 'critical')
                return
            end
            sources[kind] = { metadata = result.metadata, fieldSources = result.fieldSources }
            for _, warning in ipairs(result.warnings) do warnings[#warnings + 1] = kind .. '：' .. warning end
        end
    end
    local result, mergeError = resolver.resolve(sources)
    if not result then dialogs.message('Phase 4：統合に失敗しました', mergeError.message, 'critical'); return end
    local lines = { '項目ごとに XMP → RAW → JPG の順で有効な値を採用します。' }
    for _, field in ipairs { 'captureDateTime', 'cameraMaker', 'camera', 'lensMaker', 'lens', 'filmSim', 'iso', 'focalLength' } do
        local origin = result.fieldSources[field]
        lines[#lines + 1] = field .. '：' .. tostring(result.metadata[field] or '未取得')
            .. (origin and '（' .. origin.sourceKind .. '）' or '')
        if field == 'filmSim' and origin then
            lines[#lines + 1] = 'FilmSim 採用元：' .. tostring(origin.sourcePath or 'パス不明')
                .. ' / ' .. tostring(origin.tag or 'タグ不明')
        end
    end
    for _, rejected in ipairs(result.rejectedValues) do
        lines[#lines + 1] = '不採用：' .. rejected.sourceKind .. '.' .. rejected.field .. ' / ' .. rejected.reason
    end
    local same, compareError = normalizer.sameManufacturer(result.metadata.cameraMaker, result.metadata.lensMaker)
    lines[#lines + 1] = '\nメーカー比較（Phase 5）：元のメタデータは変更しません。'
    if compareError then
        warnings[#warnings + 1] = compareError.message
    else
        local camera = normalizer.normalize(result.metadata.cameraMaker)
        local lens = normalizer.normalize(result.metadata.lensMaker)
        lines[#lines + 1] = 'CameraMaker 比較キー：' .. (camera and camera.key or '未取得')
        lines[#lines + 1] = 'LensMaker 比較キー：' .. (lens and lens.key or '未取得')
        lines[#lines + 1] = '同一メーカー：' .. (same and 'はい' or '同一とは判定しません')
    end
    local parser = loadModule('core/TemplateParser.lua')
    local tokenResolver = loadModule('core/TokenResolver.lua', { normalizer = normalizer, metadataResolver = resolver })
    local sanitizer = loadModule('core/FilenameSanitizer.lua')
    local collisions = loadModule('core/CollisionResolver.lua', { sanitizer = sanitizer })
    local template = '{DateTime}_{CameraMaker}_{Camera}_{LensMaker}_{Lens}_{Original}_{Sequence}.{Extension}'
    local parsed = assert(parser.parse(template))
    lines[#lines + 1] = '\nファイル名候補（Phase 6）：保存・リネームは行いません。'
    lines[#lines + 1] = 'テンプレート：' .. template
    lines[#lines + 1] = '出力は JPEG を想定、Sequence は仮値 0001。Phase 6 候補は未整形です。'
    for _, omit in ipairs { true, false } do
        local preview, previewError = tokenResolver.resolve(parsed, result.metadata, {
            original = pathUtils.removeExtension(pathUtils.leafName(photos[1])),
            extension = 'jpg', sequence = 1, omitDuplicateManufacturer = omit,
        })
        local label = '同一メーカーのレンズメーカー省略 ' .. (omit and 'ON' or 'OFF') .. '：'
        if preview then
            lines[#lines + 1] = label .. preview.filename
            lines[#lines + 1] = '空欄：' .. (#preview.missingTokens > 0 and table.concat(preview.missingTokens, ', ') or 'なし')
            lines[#lines + 1] = '省略：' .. (#preview.omittedTokens > 0 and table.concat(preview.omittedTokens, ', ') or 'なし')
            local safe, safetyError = sanitizer.sanitize(preview.filename)
            if safe then
                lines[#lines + 1] = 'Phase 7 整形後：' .. safe.filename .. (safe.changed and '（整形あり）' or '（変更なし）')
                -- This fixture demonstrates numbering without inspecting or reserving a real destination.
                local first = assert(collisions.resolve(safe.filename, { existingNames = { safe.filename }, nameKey = function(name) return name end }))
                local second = assert(collisions.resolve(safe.filename, {
                    existingNames = { safe.filename }, reservedNames = { first.filename }, nameKey = function(name) return name end,
                }))
                lines[#lines + 1] = '同名ありを仮定した例：' .. first.filename
                lines[#lines + 1] = '上の候補も使用済みと仮定した例：' .. second.filename
            else
                lines[#lines + 1] = 'Phase 7 整形エラー：' .. safetyError.code .. ' / ' .. safetyError.message
            end
        else
            lines[#lines + 1] = label .. previewError.code .. ' / ' .. previewError.message
        end
    end
    lines[#lines + 1] = 'Phase 7 の衝突例は仮想データです。実フォルダーの衝突・長さ制限は未確認で、保存は行いません。'
    for _, warning in ipairs(warnings) do lines[#lines + 1] = '警告：' .. warning end
    dialogs.message('Phase 4：項目単位の統合結果', table.concat(lines, '\n'), #warnings > 0 and 'warning' or 'info')
end
