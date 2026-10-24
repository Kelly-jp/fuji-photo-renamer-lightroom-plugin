local Exclusions = {}
local function failure(message) return nil, { code = 'InvalidExclusions', message = message } end

local function removeLiteral(text, pattern)
    local pieces, position = {}, 1
    while true do
        local first, last = text:find(pattern, position, true)
        if not first then pieces[#pieces + 1] = text:sub(position); break end
        pieces[#pieces + 1] = text:sub(position, first - 1); position = last + 1
    end
    return table.concat(pieces)
end

function Exclusions.apply(originalStem, text)
    if type(originalStem) ~= 'string' or #originalStem > 65536 then return failure('元ファイル名の形式または長さが不正です。') end
    if text == nil then text = '' end
    if type(text) ~= 'string' or #text > 16384 or text:find('[%z\1-\8\11\12\14-\31\127]') then
        return failure('除外文字列は16 KiB以内のテキストで、1行に1件指定してください。')
    end
    local patterns, seen, count = {}, {}, 0
    text = text:gsub('\r\n', '\n'):gsub('\r', '\n')
    for line in (text .. '\n'):gmatch('(.-)\n') do
        local pattern = line:match('^%s*(.-)%s*$')
        if pattern ~= '' then
            count = count + 1
            if count > 128 then return failure('除外文字列は128件以内で指定してください。') end
            -- Also accept an already hyphenated source name; template literals are never filtered.
            for _, value in ipairs { pattern, (pattern:gsub('[ \t]+', '-')) } do
                if not seen[value] then patterns[#patterns + 1] = value; seen[value] = true end
            end
        end
    end
    local stem = originalStem
    -- Every change shortens the stem, so newly joined matches can be removed without a cycle.
    local before
    repeat
        before = stem
        for _, pattern in ipairs(patterns) do stem = removeLiteral(stem, pattern) end
    until stem == before
    return stem
end

return Exclusions
