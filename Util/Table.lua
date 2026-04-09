local ADDON_NAME, ns = ...

ns.TableUtil = {}

function ns.TableUtil.DeepCopy(orig)
    if type(orig) ~= "table" then
        return orig
    end
    local copy = {}
    for k, v in pairs(orig) do
        copy[ns.TableUtil.DeepCopy(k)] = ns.TableUtil.DeepCopy(v)
    end
    return setmetatable(copy, getmetatable(orig))
end

function ns.TableUtil.MergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            if type(v) == "table" then
                target[k] = ns.TableUtil.DeepCopy(v)
            else
                target[k] = v
            end
        elseif type(v) == "table" and type(target[k]) == "table" then
            ns.TableUtil.MergeDefaults(target[k], v)
        end
    end
    return target
end

function ns.TableUtil.Count(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

function ns.TableUtil.Keys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    return keys
end

function ns.TableUtil.Contains(t, value)
    for _, v in pairs(t) do
        if v == value then
            return true
        end
    end
    return false
end

function ns.TableUtil.Filter(t, predicate)
    local result = {}
    for k, v in pairs(t) do
        if predicate(v, k) then
            result[k] = v
        end
    end
    return result
end

function ns.TableUtil.Map(t, transform)
    local result = {}
    for k, v in pairs(t) do
        result[k] = transform(v, k)
    end
    return result
end
