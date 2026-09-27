local json = {}

local escapeMap = {
    ['"'] = '\\"',
    ['\\'] = '\\\\',
    ['\n'] = '\\n',
    ['\r'] = '\\r',
    ['\t'] = '\\t',
}

local function encodeString(s)
    local escaped = s:gsub('[%c"\\]', function(c)
        return escapeMap[c] or string.format("\\u%04x", string.byte(c))
    end)
    return '"' .. escaped .. '"'
end

local function isArray(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    if count == 0 then
        return true
    end
    for i = 1, count do
        if t[i] == nil then
            return false
        end
    end
    return true
end

local encodeValue

local function encodeArray(t)
    local parts = {}
    for i = 1, #t do
        parts[i] = encodeValue(t[i])
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

local function encodeObject(t)
    local parts = {}
    for k, v in pairs(t) do
        parts[#parts + 1] = encodeString(tostring(k)) .. ":" .. encodeValue(v)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

encodeValue = function(value)
    local valueType = type(value)

    if value == nil then
        return "null"
    elseif valueType == "boolean" then
        return tostring(value)
    elseif valueType == "number" then
        return tostring(value)
    elseif valueType == "string" then
        return encodeString(value)
    elseif valueType == "table" then
        if isArray(value) then
            return encodeArray(value)
        else
            return encodeObject(value)
        end
    end

    error("Tipo nao suportado para JSON: " .. valueType)
end

function json.encode(value)
    return encodeValue(value)
end

local decodeValue

local function skipWhitespace(s, i)
    local _, j = s:find("^%s*", i)
    return j + 1
end

local function decodeString(s, i)
    local result = {}
    while true do
        local c = s:sub(i, i)
        if c == "" then
            error("String JSON nao terminada")
        elseif c == '"' then
            return table.concat(result), i + 1
        elseif c == "\\" then
            local nextChar = s:sub(i + 1, i + 1)
            local map = { n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
            if map[nextChar] then
                result[#result + 1] = map[nextChar]
                i = i + 2
            elseif nextChar == "u" then
                local hex = s:sub(i + 2, i + 5)
                local codepoint = tonumber(hex, 16) or 63 -- 63 = '?'
                result[#result + 1] = utf8 and utf8.char(codepoint) or string.char(codepoint % 256)
                i = i + 6
            else
                error("Escape JSON invalido")
            end
        else
            result[#result + 1] = c
            i = i + 1
        end
    end
end

local function decodeNumber(s, i)
    local numStr = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", i)
    return tonumber(numStr), i + #numStr
end

local function decodeArray(s, i)
    local arr = {}
    i = skipWhitespace(s, i)
    if s:sub(i, i) == "]" then
        return arr, i + 1
    end
    while true do
        local value
        value, i = decodeValue(s, i)
        arr[#arr + 1] = value
        i = skipWhitespace(s, i)
        local c = s:sub(i, i)
        if c == "," then
            i = skipWhitespace(s, i + 1)
        elseif c == "]" then
            return arr, i + 1
        else
            error("Array JSON malformado")
        end
    end
end

local function decodeObject(s, i)
    local obj = {}
    i = skipWhitespace(s, i)
    if s:sub(i, i) == "}" then
        return obj, i + 1
    end
    while true do
        i = skipWhitespace(s, i)
        if s:sub(i, i) ~= '"' then
            error("Chave JSON esperada")
        end
        local key
        key, i = decodeString(s, i + 1)
        i = skipWhitespace(s, i)
        if s:sub(i, i) ~= ":" then
            error("Esperado ':' apos chave JSON")
        end
        i = skipWhitespace(s, i + 1)
        local value
        value, i = decodeValue(s, i)
        obj[key] = value
        i = skipWhitespace(s, i)
        local c = s:sub(i, i)
        if c == "," then
            i = i + 1
        elseif c == "}" then
            return obj, i + 1
        else
            error("Objeto JSON malformado")
        end
    end
end

decodeValue = function(s, i)
    i = skipWhitespace(s, i)
    local c = s:sub(i, i)

    if c == '"' then
        return decodeString(s, i + 1)
    elseif c == "{" then
        return decodeObject(s, i + 1)
    elseif c == "[" then
        return decodeArray(s, i + 1)
    elseif c == "t" and s:sub(i, i + 3) == "true" then
        return true, i + 4
    elseif c == "f" and s:sub(i, i + 4) == "false" then
        return false, i + 5
    elseif c == "n" and s:sub(i, i + 3) == "null" then
        return nil, i + 4
    elseif c:match("[%-%d]") then
        return decodeNumber(s, i)
    else
        error("Valor JSON invalido na posicao " .. i)
    end
end

function json.decode(s)
    local value = decodeValue(s, 1)
    return value
end

return json
