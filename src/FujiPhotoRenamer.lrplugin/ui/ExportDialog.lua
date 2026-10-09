local dependencies = assert(..., 'ExportDialog requires UI and core dependencies')
local bind = assert(dependencies.bind)
local parser = assert(dependencies.parser)
local tokens = assert(dependencies.tokens)
local sanitizer = assert(dependencies.sanitizer)
local Dialog = {}
Dialog.exportPresetFields = {
    { key = 'fprTemplate', default = '{DateTime}_{Original}' },
    { key = 'fprRawSearchMode', default = 'same_then_parent' },
    { key = 'fprOmitDuplicateManufacturer', default = true },
    { key = 'fprRemoveC2pa', default = false },
    { key = 'fprExifToolPath', default = '' },
}
local modes = { same_directory = true, parent_directory = true, same_then_parent = true }
local observedKeys = { 'fprTemplate', 'fprRawSearchMode', 'fprOmitDuplicateManufacturer', 'fprRemoveC2pa', 'fprExifToolPath' }
local sessions = setmetatable({}, { __mode = 'k' })
local sample = { captureDateTime = '2026:10:08 12:34:56', cameraMaker = 'FUJIFILM', camera = 'X-H2S',
    lensMaker = 'FUJIFILM Corporation', lens = 'XF100-400mm', filmSim = 'PROVIA' }

local function setting(properties, key)
    if properties[key] ~= nil then return properties[key] end
    for _, field in ipairs(Dialog.exportPresetFields) do if field.key == key then return field.default end end
end

function Dialog.preview(properties, photo)
    local parsed, err = parser.parse(setting(properties, 'fprTemplate'))
    if not parsed then return nil, err.message end
    if not modes[setting(properties, 'fprRawSearchMode')] then return nil, 'RAW 探索方法を選択してください。' end
    if type(setting(properties, 'fprOmitDuplicateManufacturer')) ~= 'boolean'
        or type(setting(properties, 'fprRemoveC2pa')) ~= 'boolean' then return nil, 'チェックボックスの設定値が不正です。' end
    if type(setting(properties, 'fprExifToolPath')) ~= 'string' then return nil, 'ExifTool のパスは文字列で指定してください。' end
    local candidate, tokenError = tokens.resolve(parsed, photo and photo.metadata or sample, {
        original = photo and photo.original or 'DSCF1234', extension = 'jpg',
        omitDuplicateManufacturer = setting(properties, 'fprOmitDuplicateManufacturer'),
    })
    if not candidate then return nil, tokenError.message end
    local safe, safetyError = sanitizer.sanitize(candidate.filename)
    if not safe then return nil, safetyError.message end
    return safe.filename, nil, candidate
end

function Dialog.cannotExportBecause(properties)
    local filename, message = Dialog.preview(properties)
    if not filename then return message end
    if setting(properties, 'fprRemoveC2pa') then
        return 'C2PA / Content Credentials の削除処理は未実装です。OFF にすると検証用 JPEG を書き出せます。'
    end
end

local function migrateTemplate(properties)
    local template, suffix = properties.fprTemplate, '.{Extension}'
    if type(template) == 'string' and template:sub(-#suffix) == suffix then
        properties.fprTemplate = template:sub(1, #template - #suffix)
    end
    template = properties.fprTemplate
    if type(template) == 'string' then
        local stem = template:match('^(.-)[_%- ]?{Sequence}$')
        if stem then properties.fprTemplate = stem end
    end
end

local function refresh(properties)
    migrateTemplate(properties)
    local owner = sessions[properties]
    local filename, message, details = Dialog.preview(properties, owner and owner.photo)
    properties.fprPreview = filename or 'プレビューを作成できません。'
    properties.fprPreviewSource = owner and owner.source or 'ファイル名プレビュー（サンプル情報）'
    properties.fprPreviewStatus = (owner and owner.photo and owner.photo.warnings and owner.photo.warnings ~= '' and owner.photo.warnings .. '\n' or '') .. (owner and owner.readError and owner.readError .. '\n' or '') .. (message or ('空欄：' .. (#details.missingTokens > 0 and table.concat(details.missingTokens, ', ') or 'なし')
        .. ' / 省略：' .. (#details.omittedTokens > 0 and table.concat(details.omittedTokens, ', ') or 'なし')))
    properties.LR_cantExportBecause = Dialog.cannotExportBecause(properties)
    if owner then owner.reason = properties.LR_cantExportBecause end
    properties.fprExportStatus = properties.LR_cantExportBecause
        or '書き出し時に各写真の XMP → RAW → JPG を読み直し、このテンプレートで保存します。同名時だけ番号を付け、最終名は保存時に確定します。'
end

function Dialog.endDialog(properties)
    local owner = sessions[properties]
    if owner then
        for _, key in ipairs(observedKeys) do properties:removeObserver(key, owner) end
        if owner.reason and properties.LR_cantExportBecause == owner.reason then properties.LR_cantExportBecause = nil end
        sessions[properties] = nil
    end
end

function Dialog.startDialog(properties)
    Dialog.endDialog(properties)
    for _, field in ipairs(Dialog.exportPresetFields) do
        if properties[field.key] == nil then properties[field.key] = field.default end
    end
    migrateTemplate(properties)
    local owner = { generation = 0, source = 'ファイル名プレビュー（サンプル情報）' }
    sessions[properties] = owner
    for _, key in ipairs(observedKeys) do
        properties:addObserver(key, owner, function(_, propertyTable, changedKey)
            if changedKey == 'fprRawSearchMode' or changedKey == 'fprExifToolPath' then
                owner.generation = owner.generation + 1
                owner.photo, owner.readError = nil, nil
                owner.source = 'ファイル名プレビュー（サンプル情報）：取得設定を変更しました。'
            end
            refresh(propertyTable)
        end)
    end
    refresh(properties)
end

function Dialog.requestPreview(properties)
    local owner = sessions[properties]
    if not owner or not dependencies.readPreview then return end
    owner.generation = owner.generation + 1
    local generation, mode, path = owner.generation, properties.fprRawSearchMode, properties.fprExifToolPath
    owner.source = '選択中の写真を取得中…（下の候補は取得前の情報です）'
    refresh(properties)
    dependencies.tasks.startAsyncTask(function()
        local ok, photo, message = dependencies.tasks.pcall(function() return dependencies.readPreview(mode, path) end)
        if sessions[properties] ~= owner or owner.generation ~= generation then return end
        if not ok then message, photo = tostring(photo), nil end
        owner.photo = photo
        owner.readError = not photo and (message or '写真情報を取得できません。') or nil
        owner.source = photo and ('ファイル名プレビュー：' .. photo.original .. '（衝突時の番号は保存時に確定）')
            or '写真情報の取得失敗（サンプル情報を表示）'
        refresh(properties)
    end)
end

function Dialog.sections(f, properties)
    local tokenRows = {}
    local names = { 'Date', 'Time', 'DateTime', 'Original', 'CameraMaker', 'Camera', 'LensMaker', 'Lens', 'FilmSim' }
    for offset = 1, #names, 4 do
        local buttons = {}
        for i = offset, math.min(offset + 3, #names) do
            local token = '{' .. names[i] .. '}'
            buttons[#buttons + 1] = f:push_button {
                title = token,
                action = function()
                    local template = properties.fprTemplate
                    if type(template) ~= 'string' then template = '' end
                    properties.fprTemplate = template .. token
                end,
            }
        end
        tokenRows[#tokenRows + 1] = f:row(buttons)
    end
    return {
        {
            title = 'Fuji Photo Renamer：ファイル名の設定',
            bind_to_object = properties,
            f:static_text { title = '保存先・元の写真と同じフォルダー・サブフォルダーは下の「書き出し場所」で指定します。', width_in_chars = 65, height_in_lines = -1 },
            f:static_text { title = 'ファイル名テンプレート', width_in_chars = 65 },
            f:edit_field { value = bind 'fprTemplate', immediate = true, width_in_chars = 65 },
            f:static_text { title = 'トークンをクリックするとテンプレート末尾へ追加します。区切りの _ や - は入力欄で編集してください。拡張子は出力形式から自動で付きます。', width_in_chars = 65, height_in_lines = -1 },
            tokenRows[1], tokenRows[2], tokenRows[3],
            f:static_text { title = bind 'fprPreviewSource', width_in_chars = 65 },
            f:edit_field { value = bind 'fprPreview', enabled = false, width_in_chars = 65, height_in_lines = 3 },
            f:static_text { title = '初期サンプル：撮影日時 2026-10-08 12:34:56、FUJIFILM / X-H2S / FUJIFILM / XF100-400mm、PROVIA、元名 DSCF1234、JPEG。「選択中の写真」で更新後は実ファイルの情報を使います。最終対象・衝突名・長さは保存時に確認します。', width_in_chars = 65, height_in_lines = -1 },
            f:push_button { title = '選択中の写真でプレビューを更新', action = function() Dialog.requestPreview(properties) end },
            f:static_text { title = bind 'fprPreviewStatus', width_in_chars = 65, height_in_lines = -1 },
            f:static_text { title = 'JPG に対応する RAW の探索方法', width_in_chars = 65 },
            f:popup_menu { value = bind 'fprRawSearchMode', items = {
                { title = 'JPG と同じフォルダー', value = 'same_directory' },
                { title = 'JPG の 1 つ上のフォルダー', value = 'parent_directory' },
                { title = '同じフォルダー → 見つからなければ 1 つ上', value = 'same_then_parent' },
            } },
            f:static_text { title = '検証用 ExifTool の絶対パス（空欄なら同梱ツール）', width_in_chars = 65 },
            f:edit_field { value = bind 'fprExifToolPath', immediate = true, width_in_chars = 65 },
            f:push_button { title = 'ExifTool 実行ファイルを選択…', action = function()
                local paths = dependencies.dialogs.runOpenPanel { title = 'ExifTool 実行ファイルを選択', canChooseFiles = true, canChooseDirectories = false, allowsMultipleSelection = false }
                if paths and paths[1] then properties.fprExifToolPath = paths[1] end
            end },
            f:checkbox { title = 'カメラメーカーとレンズメーカーが同じ場合は、レンズメーカーを省略する', value = bind 'fprOmitDuplicateManufacturer' },
            f:checkbox { title = '書き出し JPEG の C2PA / Content Credentials を削除する', value = bind 'fprRemoveC2pa', 'fprExifToolPath' },
            f:static_text { title = '削除処理は未実装です。ON の間は書き出せません。実装後は新しい書き出し JPEG の来歴と他の JUMBF 情報を除去し、元 RAW / JPG / XMP は変更しません。', width_in_chars = 65, height_in_lines = -1 },
            f:static_text { title = bind 'fprExportStatus', width_in_chars = 65, height_in_lines = -1 },
            f:static_text { title = '同名時は _001、_002 を付加し、既存ファイルを上書きしません。「このカタログに追加」とスタックへの追加は適用しません。', width_in_chars = 65, height_in_lines = -1 },
        },
    }
end

return Dialog
