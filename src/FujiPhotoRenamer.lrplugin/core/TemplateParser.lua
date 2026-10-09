local Parser = {}
local supported = { Date = true, Time = true, DateTime = true, Original = true,
    CameraMaker = true, Camera = true, LensMaker = true, Lens = true, FilmSim = true,
    ISO = true, FocalLength = true, Sequence = true, Extension = true }
local function failure(code, message, position)
    return nil, { code = code, message = message, position = position }
end

function Parser.parse(template)
    if type(template) ~= 'string' or template == '' then return failure('InvalidTemplate', 'テンプレートは空でない文字列が必要です。') end
    if template:find('[/\\%c]') then return failure('InvalidTemplate', 'テンプレートにパス区切り・制御文字は使用できません。') end
    local segments, tokens, literal = {}, {}, ''
    local function flush()
        if literal ~= '' then segments[#segments + 1] = { kind = 'literal', value = literal }; literal = '' end
    end
    local i, extensionCount = 1, 0
    while i <= #template do
        local character, pair = template:sub(i, i), template:sub(i, i + 1)
        if pair == '{{' or pair == '}}' then
            literal = literal .. character; i = i + 2
        elseif character == '{' then
            local close = template:find('}', i + 1, true)
            if not close then return failure('InvalidSyntax', 'トークンの閉じ括弧がありません。', i) end
            local name = template:sub(i + 1, close - 1)
            if name:find('{', 1, true) then return failure('InvalidSyntax', 'トークンを入れ子にできません。', i) end
            if not supported[name] then return failure('UnknownToken', '不明なトークンです：' .. name, i) end
            flush(); segments[#segments + 1] = { kind = 'token', name = name }; tokens[name] = true
            if name == 'Extension' then extensionCount = extensionCount + 1 end
            i = close + 1
        elseif character == '}' then
            return failure('InvalidSyntax', '対応する開き括弧がありません。', i)
        else
            literal = literal .. character; i = i + 1
        end
    end
    flush()
    if extensionCount > 0 then
        local last, previous = segments[#segments], segments[#segments - 1]
        if extensionCount ~= 1 or last.kind ~= 'token' or last.name ~= 'Extension'
            or not previous or previous.kind ~= 'literal' or previous.value:sub(-1) ~= '.' then
            return failure('InvalidExtension', 'Extension は末尾の .{Extension} に一度だけ指定してください。')
        end
    end
    return { segments = segments, tokens = tokens, hasExtension = extensionCount == 1 }
end

return Parser
