local Sanitizer = {}
local reserved = { CON = true, PRN = true, AUX = true, NUL = true }
for i = 1, 9 do reserved['COM' .. i] = true; reserved['LPT' .. i] = true end
for _, digit in ipairs { '¹', '²', '³' } do reserved['COM' .. digit] = true; reserved['LPT' .. digit] = true end
local function failure(code, message)
    return nil, { code = code, message = message }
end
local function asciiUpper(value)
    return (value:gsub('[a-z]', function(character) return string.char(string.byte(character) - 32) end))
end
local function validUtf8(value)
    local i = 1
    while i <= #value do
        local first = value:byte(i)
        local size, low, high = 1, 128, 191
        if first >= 194 and first <= 223 then size = 2
        elseif first >= 224 and first <= 239 then
            size = 3
            if first == 224 then low = 160 elseif first == 237 then high = 159 end
        elseif first >= 240 and first <= 244 then
            size = 4
            if first == 240 then low = 144 elseif first == 244 then high = 143 end
        elseif first >= 128 then return false end
        for offset = 1, size - 1 do
            local byte = value:byte(i + offset)
            if not byte or byte < (offset == 1 and low or 128) or byte > (offset == 1 and high or 191) then return false end
        end
        i = i + size
    end
    return true
end

function Sanitizer.sanitize(filename, limits)
    if type(filename) ~= 'string' then return failure('InvalidFilename', 'ファイル名は文字列で指定してください。') end
    if not validUtf8(filename) then return failure('InvalidEncoding', 'ファイル名は有効な UTF-8 が必要です。') end
    if limits ~= nil and type(limits) ~= 'table' then return failure('InvalidLimits', '長さ制約はテーブルで指定してください。') end
    local maxBytes = limits and limits.maxBytes
    if maxBytes ~= nil and (type(maxBytes) ~= 'number' or maxBytes ~= maxBytes or maxBytes == math.huge
        or maxBytes < 1 or maxBytes ~= math.floor(maxBytes)) then
        return failure('InvalidLimits', 'maxBytes は正の有限整数が必要です。')
    end
    -- Remove controls before trimming; keep actual Unicode letters and punctuation intact.
    local clean = filename:gsub('[%z\1-\31\127]', ''):gsub('\194[\128-\159]', ''):gsub('[<>:"/\\|?*]', '_'):gsub('[ .]+$', '')
    if clean == '' or not clean:find('%S') then return failure('EmptyFilename', '整形後のファイル名が空です。') end
    local stem, extension = clean:match('^(.*)%.([A-Za-z0-9]+)$')
    if not stem then return failure('InvalidExtension', '末尾に実際の出力拡張子が必要です。') end
    stem = stem:gsub('[ .]+$', '')
    if stem == '' or not stem:find('%S') then return failure('EmptyFilename', '整形後の stem が空です。') end
    -- Finder hides dot-prefixed output; reject it rather than making exports hard to find.
    if stem:sub(1, 1) == '.' then return failure('InvalidFilename', '先頭がドットのファイル名は使用できません。') end
    local base = asciiUpper(stem:match('^[^.]*'):gsub('[ ]+$', ''))
    if reserved[base] then return failure('ReservedFilename', 'Windows の予約名は使用できません。') end
    clean = stem .. '.' .. extension:lower()
    if maxBytes and #clean > maxBytes then return failure('FilenameTooLong', '指定されたファイル名のバイト長制限を超えています。') end
    return { filename = clean, changed = clean ~= filename }
end

return Sanitizer
