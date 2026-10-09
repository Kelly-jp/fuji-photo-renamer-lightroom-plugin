local dependencies = assert(..., 'ExportDialog requires UI and core dependencies')
local bind = assert(dependencies.bind)
local parser = assert(dependencies.parser)
local tokens = assert(dependencies.tokens)
local sanitizer = assert(dependencies.sanitizer)
local Dialog = {}
Dialog.exportPresetFields = {
    { key = 'fprTemplate', default = '{DateTime}_{Original}_{Sequence}' },
    { key = 'fprRawSearchMode', default = 'same_then_parent' },
    { key = 'fprOmitDuplicateManufacturer', default = true },
    { key = 'fprRemoveC2pa', default = false },
}
local modes = { same_directory = true, parent_directory = true, same_then_parent = true }
local observedKeys = { 'fprTemplate', 'fprRawSearchMode', 'fprOmitDuplicateManufacturer', 'fprRemoveC2pa' }
local sessions = setmetatable({}, { __mode = 'k' })
local sample = { captureDateTime = '2026:10:08 12:34:56', cameraMaker = 'FUJIFILM', camera = 'X-H2S',
    lensMaker = 'FUJIFILM Corporation', lens = 'XF100-400mm', filmSim = 'PROVIA' }

local function setting(properties, key)
    if properties[key] ~= nil then return properties[key] end
    for _, field in ipairs(Dialog.exportPresetFields) do if field.key == key then return field.default end end
end

function Dialog.preview(properties)
    local parsed, err = parser.parse(setting(properties, 'fprTemplate'))
    if not parsed then return nil, err.message end
    if not modes[setting(properties, 'fprRawSearchMode')] then return nil, 'RAW 探索方法を選択してください。' end
    if type(setting(properties, 'fprOmitDuplicateManufacturer')) ~= 'boolean'
        or type(setting(properties, 'fprRemoveC2pa')) ~= 'boolean' then return nil, 'チェックボックスの設定値が不正です。' end
    local candidate, tokenError = tokens.resolve(parsed, sample, {
        original = 'DSCF1234', extension = 'jpg', sequence = 1,
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
end

local function refresh(properties)
    migrateTemplate(properties)
    local filename, message, details = Dialog.preview(properties)
    properties.fprPreview = filename or 'プレビューを作成できません。'
    properties.fprPreviewStatus = message or ('サンプルで空欄：' .. (#details.missingTokens > 0 and table.concat(details.missingTokens, ', ') or 'なし')
        .. ' / 省略：' .. (#details.omittedTokens > 0 and table.concat(details.omittedTokens, ', ') or 'なし'))
    properties.LR_cantExportBecause = Dialog.cannotExportBecause(properties)
    local owner = sessions[properties]
    if owner then owner.reason = properties.LR_cantExportBecause end
    properties.fprExportStatus = properties.LR_cantExportBecause
        or 'この検証版の書き出し名は test_<元ファイル名>.jpg です。上の候補はまだ保存名に適用しません。'
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
    local owner = {}
    sessions[properties] = owner
    for _, key in ipairs(observedKeys) do
        properties:addObserver(key, owner, function(_, propertyTable) refresh(propertyTable) end)
    end
    refresh(properties)
end

function Dialog.sections(f, properties)
    local tokenRows = {}
    local names = { 'Date', 'Time', 'DateTime', 'Original', 'CameraMaker', 'Camera', 'LensMaker', 'Lens', 'FilmSim', 'Sequence' }
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
            f:static_text { title = 'ファイル名プレビュー（サンプル情報）', width_in_chars = 65 },
            f:edit_field { value = bind 'fprPreview', enabled = false, width_in_chars = 65, height_in_lines = 3 },
            f:static_text { title = '実写真の情報はまだ取得しません。撮影日時 2026-10-08 12:34:56、FUJIFILM / X-H2S / FUJIFILM / XF100-400mm、PROVIA、元名 DSCF1234、仮の連番 0001、JPEG。衝突・長さ制限は未確認です。', width_in_chars = 65, height_in_lines = -1 },
            f:static_text { title = bind 'fprPreviewStatus', width_in_chars = 65, height_in_lines = -1 },
            f:static_text { title = 'JPG に対応する RAW の探索方法（設定保存のみ）', width_in_chars = 65 },
            f:popup_menu { value = bind 'fprRawSearchMode', items = {
                { title = 'JPG と同じフォルダー', value = 'same_directory' },
                { title = 'JPG の 1 つ上のフォルダー', value = 'parent_directory' },
                { title = '同じフォルダー → 見つからなければ 1 つ上', value = 'same_then_parent' },
            } },
            f:checkbox { title = 'カメラメーカーとレンズメーカーが同じ場合は、レンズメーカーを省略する', value = bind 'fprOmitDuplicateManufacturer' },
            f:checkbox { title = '書き出し JPEG の C2PA / Content Credentials を削除する', value = bind 'fprRemoveC2pa' },
            f:static_text { title = '削除処理は未実装です。ON の間は書き出せません。実装後は新しい書き出し JPEG の来歴と他の JUMBF 情報を除去し、元 RAW / JPG / XMP は変更しません。', width_in_chars = 65, height_in_lines = -1 },
            f:static_text { title = bind 'fprExportStatus', width_in_chars = 65, height_in_lines = -1 },
            f:static_text { title = '同名時は上書きせずエラーにします。「このカタログに追加」とスタックへの追加は適用しません。', width_in_chars = 65, height_in_lines = -1 },
        },
    }
end

return Dialog
