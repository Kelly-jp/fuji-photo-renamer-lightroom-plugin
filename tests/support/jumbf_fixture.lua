local Fixture = {}
local function u16(value) return string.char(math.floor(value / 256), value % 256) end
local function u32(value) return u16(math.floor(value / 65536)) .. u16(value % 65536) end
local function box(kind, data) return u32(#data + 8) .. kind .. data end
function Fixture.add(jpeg, fragmented)
    local body = box('jumb', box('jumd', 'c2pa' .. string.rep('\0', 12) .. '\2c2pa\0') .. box('json', '{}'))
    local function packet(sequence, bytes)
        local data = 'JP' .. u16(1) .. u32(sequence) .. bytes
        return '\255\235' .. u16(#data + 2) .. data
    end
    local segment
    if fragmented then segment = packet(1, body:sub(1, 32)) .. packet(2, body:sub(33))
    else segment = packet(1, body) end
    return jpeg:sub(1, 2) .. segment .. jpeg:sub(3)
end
return Fixture
