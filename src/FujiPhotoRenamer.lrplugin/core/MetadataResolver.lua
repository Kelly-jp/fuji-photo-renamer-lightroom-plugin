local Resolver = {}
local priority = { 'xmp', 'raw', 'jpeg' }
local textFields = { cameraMaker = true, camera = true, lensMaker = true, lens = true, filmSim = true }
local canonicalFields = { 'captureDateTime', 'cameraMaker', 'camera', 'lensMaker', 'lens', 'filmSim', 'iso', 'focalLength' }

local function validDateTime(value)
    local text = value:match('^%s*(.-)%s*$')
    local year, month, day, hour, minute, second, tail = text:match(
        '^(%d%d%d%d):(%d%d):(%d%d) (%d%d):(%d%d):(%d%d)(.*)$')
    if not year then
        year, month, day, hour, minute, second, tail = text:match(
            '^(%d%d%d%d)%-(%d%d)%-(%d%d)[T ](%d%d):(%d%d):(%d%d)(.*)$')
    end
    if not year then return false end
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
    hour, minute, second = tonumber(hour), tonumber(minute), tonumber(second)
    if year < 1 or month < 1 or month > 12 or hour > 23 or minute > 59 or second > 59 then return false end
    local days = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0) then days[2] = 29 end
    if day < 1 or day > days[month] then return false end
    if tail:sub(1, 1) == '.' then
        local fraction
        fraction, tail = tail:match('^(%.%d+)(.*)$')
        if not fraction then return false end
    end
    if tail == '' or tail == 'Z' then return true end
    local zoneHour, zoneMinute = tail:match('^[+-](%d%d):(%d%d)$')
    return zoneHour ~= nil and tonumber(zoneHour) <= 23 and tonumber(zoneMinute) <= 59
end

local function invalidReason(field, value)
    local kind = type(value)
    if kind == 'string' and not value:find('%S') then return 'EmptyValue' end
    if kind ~= 'string' and kind ~= 'number' and kind ~= 'boolean' then return 'UnsupportedType' end
    if kind == 'number' and (value ~= value or value == math.huge or value == -math.huge) then return 'NonFiniteNumber' end
    if textFields[field] and kind ~= 'string' then return 'InvalidText' end
    if field == 'captureDateTime' and (kind ~= 'string' or not validDateTime(value)) then return 'InvalidDateTime' end
    if field == 'iso' then
        if kind ~= 'number' or value <= 0 or value ~= math.floor(value) then return 'InvalidISO' end
    elseif field == 'focalLength' then
        if kind ~= 'number' or value <= 0 then return 'InvalidFocalLength' end
    elseif field == 'rating' then
        if kind ~= 'number' or value < 0 or value > 5 or value ~= math.floor(value) then return 'InvalidRating' end
    end
    return nil
end

local function failure(code, message, sourceKind)
    return nil, { code = code, message = message, sourceKind = sourceKind }
end

function Resolver.resolve(sources)
    if sources == nil then sources = {} end
    if type(sources) ~= 'table' then return failure('InvalidInput', '入力元はテーブルで指定してください。') end
    for kind in pairs(sources) do
        if kind ~= 'xmp' and kind ~= 'raw' and kind ~= 'jpeg' then
            return failure('InvalidSourceKind', '対応していない入力元です：' .. tostring(kind))
        end
    end
    local fields = {}
    for _, name in ipairs(canonicalFields) do fields[name] = true end
    for _, kind in ipairs(priority) do
        local source = sources[kind]
        if source ~= nil then
            if type(source) ~= 'table' then return failure('InvalidSource', '入力元の形式が不正です。', kind) end
            if source.readError ~= nil then return failure('ReadError', '読み取りに失敗した入力は統合しません。', kind) end
            if type(source.metadata) ~= 'table' then return failure('InvalidMetadata', 'metadata テーブルが必要です。', kind) end
            if source.fieldSources ~= nil and type(source.fieldSources) ~= 'table' then
                return failure('InvalidProvenance', 'fieldSources の形式が不正です。', kind)
            end
            for field in pairs(source.metadata) do
                if type(field) ~= 'string' or field == '' then return failure('InvalidField', '項目名は空でない文字列が必要です。', kind) end
                fields[field] = true
            end
            for field, origin in pairs(source.fieldSources or {}) do
                if type(field) ~= 'string' or type(origin) ~= 'table'
                    or origin.sourcePath ~= nil and type(origin.sourcePath) ~= 'string'
                    or origin.tag ~= nil and type(origin.tag) ~= 'string' then
                    return failure('InvalidProvenance', '項目の採用元の形式が不正です。', kind)
                end
            end
        end
    end
    local names = {}
    for field in pairs(fields) do names[#names + 1] = field end
    table.sort(names)
    local result = { metadata = {}, fieldSources = {}, missingFields = {}, rejectedValues = {} }
    for _, field in ipairs(names) do
        local found = false
        for _, kind in ipairs(priority) do
            local source = sources[kind]
            local value = source and source.metadata[field]
            if value ~= nil then
                local reason = invalidReason(field, value)
                if reason then
                    result.rejectedValues[#result.rejectedValues + 1] = { field = field, sourceKind = kind, reason = reason }
                else
                    result.metadata[field] = value
                    local origin = source.fieldSources and source.fieldSources[field] or {}
                    result.fieldSources[field] = { sourceKind = kind, sourcePath = origin.sourcePath, tag = origin.tag }
                    found = true
                    break
                end
            end
        end
        if not found then result.missingFields[#result.missingFields + 1] = field end
    end
    return result
end

return Resolver
