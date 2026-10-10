local dependencies = assert(..., 'TokenResolver requires core dependencies')
local normalizer = assert(dependencies.normalizer)
local metadataResolver = assert(dependencies.metadataResolver)
local Resolver = {}
local textTokens = { Camera = 'camera', Lens = 'lens', FilmSim = 'filmSim' }
-- Display names follow fphoto-renamer; canonical metadata IDs remain untouched.
local filmSimNames = {
    PROVIA = 'PROVIA', VELVIA = 'Velvia', ASTIA = 'ASTIA',
    PRO_NEG_STD = 'PRO Neg Std', PRO_NEG_HI = 'PRO Neg Hi',
    CLASSIC_CHROME = 'CLASSIC CHROME', CLASSIC_NEGATIVE = 'CLASSIC Neg',
    ETERNA = 'ETERNA', ETERNA_BLEACH_BYPASS = 'ETERNA BLEACH BYPASS',
    NOSTALGIC_NEG = 'NOSTALGIC Neg', REALA_ACE = 'REALA ACE',
    MONOCHROME = 'MONOCHROME', MONOCHROME_R = 'MONOCHROME+ R FILTER',
    MONOCHROME_Y = 'MONOCHROME+ Ye FILTER', MONOCHROME_G = 'MONOCHROME+ G FILTER',
    ACROS = 'ACROS', ACROS_R = 'ACROS+ R FILTER', ACROS_Y = 'ACROS+ Ye FILTER',
    ACROS_G = 'ACROS+ G FILTER', SEPIA = 'SEPIA',
}
local function formatTokenValue(value)
    local words = value:gsub('[ \t\r\n\v\f]+', ' '):match('^ *(.-) *$')
    return (words:gsub(' ', '-'))
end
local function failure(code, message, token)
    return nil, { code = code, message = message, token = token }
end
local function hasText(value) return type(value) == 'string' and value:find('%S') ~= nil end
local function separatorOnly(piece)
    return piece.kind == 'literal' and piece.value:match('^[_%- ]*$') ~= nil
end

local function cleanEmptySeparators(pieces)
    for i, piece in ipairs(pieces) do
        if piece.empty and not piece.processed then
            local first, last = i, i
            while first > 1 and (pieces[first - 1].empty or separatorOnly(pieces[first - 1])) do first = first - 1 end
            while last < #pieces and (pieces[last + 1].empty or separatorOnly(pieces[last + 1])) do last = last + 1 end
            local left, right = pieces[first - 1], pieces[last + 1]
            local leftRun = left and left.kind == 'literal' and left.value:match('([_%- ]+)$') or ''
            local rightRun = right and right.kind == 'literal' and right.value:match('^([_%- ]+)') or ''
            if leftRun ~= '' then left.value = left.value:sub(1, #left.value - #leftRun) end
            if rightRun ~= '' then right.value = right.value:sub(#rightRun + 1) end
            local separators = leftRun
            for j = first, last do
                if pieces[j].kind == 'literal' then separators = separators .. pieces[j].value end
                pieces[j].value = ''; pieces[j].processed = true
            end
            separators = separators .. rightRun
            if left and right and left.value ~= '' and right.value ~= '' then
                pieces[first].value = separators:sub(1, 1)
            end
        end
    end
end

function Resolver.resolve(parsed, metadata, options)
    if type(parsed) ~= 'table' or type(parsed.segments) ~= 'table' or type(parsed.tokens) ~= 'table' then
        return failure('InvalidTemplate', 'TemplateParser の解析結果が必要です。')
    end
    if type(metadata) ~= 'table' or type(options) ~= 'table' then return failure('InvalidInput', 'metadata と出力情報が必要です。') end
    local extension = options.extension
    if type(extension) ~= 'string' or not extension:match('^[A-Za-z0-9]+$') then
        return failure('InvalidExtension', '実際の出力拡張子をドットなしで指定してください。')
    end
    local omit = options.omitDuplicateManufacturer
    if omit == nil then omit = true end
    if type(omit) ~= 'boolean' then return failure('InvalidOption', 'メーカー省略設定は boolean で指定してください。') end
    local values, omitted, missing = {}, {}, {}
    for token, field in pairs(textTokens) do
        if parsed.tokens[token] then
            local value = metadata[field]
            if value ~= nil and type(value) ~= 'string' then return failure('InvalidTokenValue', '文字列の項目が必要です。', token) end
            if token == 'FilmSim' and value then value = filmSimNames[value] or value end
            values[token] = hasText(value) and value or ''
        end
    end
    local makers = {}
    for _, token in ipairs { 'CameraMaker', 'LensMaker' } do
        if parsed.tokens[token] then
            local result, err = normalizer.normalize(metadata[token == 'CameraMaker' and 'cameraMaker' or 'lensMaker'])
            if err then return failure('InvalidTokenValue', err.message, token) end
            makers[token] = result
            values[token] = result and result.displayName or ''
        end
    end
    if omit and makers.CameraMaker and makers.LensMaker and makers.CameraMaker.key == makers.LensMaker.key then
        values.LensMaker = ''; omitted[#omitted + 1] = 'LensMaker'
    end
    if parsed.tokens.Date or parsed.tokens.Time or parsed.tokens.DateTime then
        local value = metadata.captureDateTime
        if not metadataResolver.isValidCaptureDateTime(value) then
            return failure('MissingDateTime', '使用した日時トークンの有効な撮影日時がありません。')
        end
        local text = value:match('^%s*(.-)%s*$')
        local year, month, day, hour, minute, second = text:match('^(%d%d%d%d):(%d%d):(%d%d) (%d%d):(%d%d):(%d%d)')
        if not year then year, month, day, hour, minute, second = text:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)[T ](%d%d):(%d%d):(%d%d)') end
        values.Date = year .. month .. day; values.Time = hour .. minute .. second
        values.DateTime = values.Date .. '_' .. values.Time
    end
    if parsed.tokens.Original then
        if not hasText(options.original) then return failure('MissingOriginal', '元画像の stem が必要です。', 'Original') end
        values.Original = options.original
    end
    local pieces = {}
    for i = 1, #parsed.segments do
        local segment = parsed.segments[i]
        if segment.kind == 'literal' then
            local literal = segment.value
            pieces[#pieces + 1] = { kind = 'literal', value = literal }
        else
            local value = values[segment.name]
            if value == nil then return failure('InvalidTemplate', '未解決のトークンがあります。', segment.name) end
            value = formatTokenValue(value)
            local empty = value == ''
            if empty and segment.name ~= 'LensMaker' then missing[segment.name] = true end
            if empty and segment.name == 'LensMaker' and not makers.LensMaker then missing.LensMaker = true end
            pieces[#pieces + 1] = { kind = 'token', value = value, empty = empty }
        end
    end
    cleanEmptySeparators(pieces)
    local parts = {}
    for _, piece in ipairs(pieces) do parts[#parts + 1] = piece.value end
    local stem = table.concat(parts)
    if stem == '' or not stem:find('%S') then return failure('EmptyFilename', '展開後の stem が空です。') end
    local missingTokens = {}
    for token in pairs(missing) do missingTokens[#missingTokens + 1] = token end
    table.sort(missingTokens)
    return { filename = stem .. '.' .. extension:lower(), missingTokens = missingTokens, omittedTokens = omitted }
end

return Resolver
