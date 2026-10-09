local Parser = {}
local supported = { Date = true, Time = true, DateTime = true, Original = true,
    CameraMaker = true, Camera = true, LensMaker = true, Lens = true, FilmSim = true,
    Sequence = true }
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
    local i = 1
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
            i = close + 1
        elseif character == '}' then
            return failure('InvalidSyntax', '対応する開き括弧がありません。', i)
        else
            literal = literal .. character; i = i + 1
        end
    end
    flush()
    return { segments = segments, tokens = tokens }
end

return Parser
