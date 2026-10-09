local Normalizer = {}
local aliases = {
    FUJIFILM = 'FUJIFILM', ['FUJI FILM'] = 'FUJIFILM',
    ['FUJIFILM CORPORATION'] = 'FUJIFILM',
    TAMRON = 'TAMRON', ['TAMRON CO., LTD.'] = 'TAMRON',
    SIGMA = 'SIGMA', ['SIGMA CORPORATION'] = 'SIGMA',
}

local function asciiUpper(value)
    return (value:gsub('[a-z]', function(character)
        return string.char(string.byte(character) - 32)
    end))
end

function Normalizer.normalize(value)
    if value == nil then return nil end
    if type(value) ~= 'string' then
        return nil, { code = 'InvalidManufacturer', message = 'メーカー名は文字列で指定してください。' }
    end
    local displayName = value:match('^%s*(.-)%s*$'):gsub('%s+', ' ')
    if displayName == '' then return nil end
    if displayName:find('[%z\1-\31\127]') then
        return nil, { code = 'InvalidManufacturer', message = 'メーカー名に不正な制御文字があります。' }
    end
    local key = asciiUpper(displayName)
    local knownName = aliases[key]
    return { key = knownName or key, displayName = knownName or displayName, known = knownName ~= nil }
end

function Normalizer.sameManufacturer(cameraMaker, lensMaker)
    local camera, cameraError = Normalizer.normalize(cameraMaker)
    if cameraError then return nil, cameraError end
    local lens, lensError = Normalizer.normalize(lensMaker)
    if lensError then return nil, lensError end
    -- Absence is not evidence that the manufacturers are the same.
    return camera ~= nil and lens ~= nil and camera.key == lens.key
end

return Normalizer
