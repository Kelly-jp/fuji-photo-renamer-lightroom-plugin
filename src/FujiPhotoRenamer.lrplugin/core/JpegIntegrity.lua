local Integrity = {}
local function failure(message) return nil, { code = 'InvalidJpeg', message = message } end
local function uint16(data, offset) return data:byte(offset) * 256 + data:byte(offset + 1) end
local function uint32(data, offset) return uint16(data, offset) * 65536 + uint16(data, offset + 2) end

function Integrity.inspect(data)
    if type(data) ~= 'string' or data:sub(1, 2) ~= '\255\216' then return failure('JPEG の SOI がありません。') end
    local segments, groups, position, sawScan, sawFrame, sawEnd = {}, {}, 3, false, false, false
    local function segment(first, last) segments[#segments + 1] = { first = first, last = last }; return segments[#segments] end
    segment(1, 2)
    while position <= #data do
        local first = position
        if data:byte(position) ~= 255 then return failure('JPEG マーカーの境界が不正です。') end
        while data:byte(position) == 255 do position = position + 1 end
        local marker = data:byte(position)
        if not marker then return failure('JPEG マーカーが途中で終わっています。') end
        if marker == 217 then
            segment(first, #data); sawEnd = true; break
        end
        if marker == 0 or marker == 216 or marker == 1 or marker >= 208 and marker <= 215 then
            return failure('対応しない JPEG マーカーがあります。')
        end
        if position + 2 > #data then return failure('JPEG セグメント長が欠落しています。') end
        local length = uint16(data, position + 1)
        local last, payload = position + length, position + 3
        if length < 2 or last > #data then return failure('JPEG セグメント長が不正です。') end
        local entry = segment(first, last)
        if marker == 192 or marker == 193 or marker == 194 then
            if length < 11 or (data:byte(payload) ~= 8 and data:byte(payload) ~= 12)
                or uint16(data, payload + 1) == 0 or uint16(data, payload + 3) == 0
                or data:byte(payload + 5) < 1 or length ~= 8 + 3 * data:byte(payload + 5) then
                return failure('JPEG フレームの構造が不正です。')
            end
            sawFrame = true
        end
        if marker == 235 and data:sub(payload, payload + 1) == 'JP' then
            if length < 10 then return failure('APP11 パケットが短すぎます。') end
            local instance, sequence = uint16(data, payload + 2), uint32(data, payload + 4)
            local group = groups[instance] or { packets = {}, total = 0 }; groups[instance] = group
            if sequence < 1 or group.packets[sequence] then return failure('APP11 パケット番号が不正です。') end
            group.packets[sequence] = entry; group.total = group.total + length - 10
            if sequence == 1 and length >= 18 and data:sub(payload + 12, payload + 15) == 'jumb' then
                group.jumbf = true; group.boxLength = uint32(data, payload + 8)
                if group.boxLength == 1 or group.boxLength == 0 then return failure('未対応の JUMBF ボックス長です。') end
            end
        end
        position = last + 1
        if marker == 218 then
            if not sawFrame or length < 8 or data:byte(payload) < 1 or length ~= 6 + 2 * data:byte(payload) then return failure('JPEG のフレーム / SOS が不正です。') end
            sawScan = true
            local scanStart = position
            while true do
                local nextMarker = data:find('\255', position, true)
                if not nextMarker then return failure('JPEG スキャンに終端がありません。') end
                local cursor = nextMarker + 1
                while data:byte(cursor) == 255 do cursor = cursor + 1 end
                local code = data:byte(cursor)
                if code == 0 or code and code >= 208 and code <= 215 then position = cursor + 1
                else
                    if nextMarker == scanStart then return failure('JPEG スキャンが空です。') end
                    segment(scanStart, nextMarker - 1); position = nextMarker; break
                end
            end
        end
    end
    if not sawScan or not sawEnd then return failure('JPEG のスキャン / EOI がありません。') end
    local jumbfCount = 0
    for _, group in pairs(groups) do
        if not group.packets[1] then return failure('APP11 の先頭パケットがありません。') end
        if group.jumbf then
            if group.boxLength ~= group.total then return failure('JUMBF ボックスとパケット長が一致しません。') end
            local count = 0; for _ in pairs(group.packets) do count = count + 1 end
            for index = 1, count do
                if not group.packets[index] then return failure('JUMBF パケットが欠落しています。') end
                group.packets[index].remove = true; jumbfCount = jumbfCount + 1
            end
        end
    end
    local kept = {}
    for _, entry in ipairs(segments) do if not entry.remove then kept[#kept + 1] = data:sub(entry.first, entry.last) end end
    return { withoutJumbf = table.concat(kept), jumbfSegments = jumbfCount }
end

function Integrity.verifyRemoval(before, after)
    local original, originalError = Integrity.inspect(before)
    if not original then return nil, originalError end
    local result, resultError = Integrity.inspect(after)
    if not result then return nil, resultError end
    if result.jumbfSegments ~= 0 then return nil, { code = 'JumbfRemaining', message = 'JUMBF が残っています。' } end
    if original.withoutJumbf ~= after then
        return nil, { code = 'JpegChanged', message = '画像データまたは JUMBF 以外の情報が変更されています。' }
    end
    return { removedSegments = original.jumbfSegments }
end
return Integrity
