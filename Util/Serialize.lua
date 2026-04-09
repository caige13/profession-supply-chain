local ADDON_NAME, ns = ...

ns.Serializer = {}

-- Simple serialization for snapshot data
-- Uses a compact format: type prefix + value
-- t = table, s = string, n = number, b = boolean, z = nil

local function serialize(value, depth)
    depth = depth or 0
    if depth > 50 then
        return "z"  -- prevent infinite recursion
    end

    local vtype = type(value)
    if vtype == "nil" then
        return "z"
    elseif vtype == "boolean" then
        return value and "bt" or "bf"
    elseif vtype == "number" then
        if value == math.floor(value) then
            return "i" .. tostring(value)
        else
            return "n" .. tostring(value)
        end
    elseif vtype == "string" then
        -- Escape delimiter characters
        local escaped = value:gsub("\\", "\\\\"):gsub("|", "\\p"):gsub("~", "\\t")
        return "s" .. escaped
    elseif vtype == "table" then
        local parts = {}
        -- Check if array-like
        local maxN = 0
        local count = 0
        for k in pairs(value) do
            count = count + 1
            if type(k) == "number" and k > 0 and k == math.floor(k) then
                maxN = math.max(maxN, k)
            end
        end

        if maxN == count and maxN > 0 then
            -- Array serialization
            parts[1] = "a" .. maxN
            for i = 1, maxN do
                parts[#parts + 1] = serialize(value[i], depth + 1)
            end
        else
            -- Map serialization
            parts[1] = "m" .. count
            for k, v in pairs(value) do
                parts[#parts + 1] = serialize(k, depth + 1)
                parts[#parts + 1] = serialize(v, depth + 1)
            end
        end
        return table.concat(parts, "|")
    end
    return "z"
end

local function findDelimiter(data, pos)
    while pos <= #data do
        local ch = data:sub(pos, pos)
        if ch == "|" then
            return pos
        end
        pos = pos + 1
    end
    return nil
end

local function readToken(data, pos)
    local nextDelim = findDelimiter(data, pos)
    if nextDelim then
        return data:sub(pos, nextDelim - 1), nextDelim + 1
    else
        return data:sub(pos), #data + 1
    end
end

local function deserialize(data, pos)
    if pos > #data then
        return nil, pos
    end

    local token, nextPos = readToken(data, pos)
    if not token or #token == 0 then
        return nil, nextPos
    end

    local prefix = token:sub(1, 1)

    if prefix == "z" then
        return nil, nextPos
    elseif prefix == "b" then
        return token:sub(2, 2) == "t", nextPos
    elseif prefix == "i" or prefix == "n" then
        return tonumber(token:sub(2)), nextPos
    elseif prefix == "s" then
        local str = token:sub(2)
        str = str:gsub("\\t", "~"):gsub("\\p", "|"):gsub("\\\\", "\\")
        return str, nextPos
    elseif prefix == "a" then
        local count = tonumber(token:sub(2))
        local arr = {}
        local curPos = nextPos
        for i = 1, count do
            arr[i], curPos = deserialize(data, curPos)
        end
        return arr, curPos
    elseif prefix == "m" then
        local count = tonumber(token:sub(2))
        local map = {}
        local curPos = nextPos
        for i = 1, count do
            local key, val
            key, curPos = deserialize(data, curPos)
            val, curPos = deserialize(data, curPos)
            if key ~= nil then
                map[key] = val
            end
        end
        return map, curPos
    end

    return nil, nextPos
end

function ns.Serializer.Serialize(data)
    return serialize(data, 0)
end

function ns.Serializer.Deserialize(str)
    if not str or #str == 0 then
        return nil
    end
    local result, _ = deserialize(str, 1)
    return result
end
