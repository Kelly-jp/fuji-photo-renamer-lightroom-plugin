local sanitizer = assert(assert(..., 'CollisionResolver requires core dependencies').sanitizer)
local Resolver = {}
local function failure(code, message)
    return nil, { code = code, message = message }
end

function Resolver.resolve(filename, options)
    if type(options) ~= 'table' or type(options.nameKey) ~= 'function' then
        return failure('InvalidOptions', 'OS の名前比較規則に対応した純粋な nameKey 関数が必要です。')
    end
    local safe, err = sanitizer.sanitize(filename, options.limits)
    if not safe then return nil, err end
    if safe.changed then return failure('InvalidFilename', '先に FilenameSanitizer で整形してください。') end
    local maxAttempts = options.maxAttempts
    if maxAttempts == nil then maxAttempts = 10000 end
    if type(maxAttempts) ~= 'number' or maxAttempts ~= maxAttempts or maxAttempts < 1
        or maxAttempts > 1000000 or maxAttempts ~= math.floor(maxAttempts) then
        return failure('InvalidOptions', 'maxAttempts は 1〜1000000 の整数が必要です。')
    end
    local function keyFor(name)
        local ok, key = pcall(options.nameKey, name)
        if not ok or type(key) ~= 'string' or key == '' then
            return failure('InvalidNameKey', 'ファイル名の比較キーを生成できません。')
        end
        return key
    end
    local occupied = {}
    for _, field in ipairs { 'existingNames', 'reservedNames' } do
        local names = options[field]
        if names == nil then names = {} end
        if type(names) ~= 'table' then return failure('InvalidOptions', field .. ' は名前の配列が必要です。') end
        local count = 0
        for index, name in pairs(names) do
            if type(index) ~= 'number' or index < 1 or index ~= math.floor(index)
                or type(name) ~= 'string' or name == '' or name:find('[/\\%z]') then
                return failure('InvalidOptions', field .. ' はファイル名だけの連続した配列が必要です。')
            end
            count = count + 1
            local key, keyError = keyFor(name)
            if not key then return nil, keyError end
            occupied[key] = true
        end
        for index = 1, count do
            if names[index] == nil then return failure('InvalidOptions', field .. ' に配列の欠落があります。') end
        end
    end
    local stem, extension = filename:match('^(.*)%.([A-Za-z0-9]+)$')
    for number = 0, maxAttempts - 1 do
        local candidate = number == 0 and filename or stem .. string.format('_%03d', number) .. '.' .. extension
        local checked, candidateError = sanitizer.sanitize(candidate, options.limits)
        if not checked then return nil, candidateError end
        local key, keyError = keyFor(candidate)
        if not key then return nil, keyError end
        if not occupied[key] then return { filename = candidate, collisionNumber = number } end
    end
    return failure('CollisionLimitReached', '衝突回避の候補数上限に達しました。')
end

return Resolver
