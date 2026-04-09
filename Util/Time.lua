local ADDON_NAME, ns = ...

ns.TimeUtil = {}

local FRESH_THRESHOLD = 6 * 3600      -- 6 hours
local AGING_THRESHOLD = 24 * 3600     -- 24 hours
local STALE_THRESHOLD = 72 * 3600     -- 72 hours

function ns.TimeUtil.Now()
    return time()
end

function ns.TimeUtil.GetAge(timestamp)
    if not timestamp or timestamp == 0 then
        return math.huge
    end
    return time() - timestamp
end

-- Returns "fresh", "aging", "stale", or "expired"
function ns.TimeUtil.GetFreshnessState(timestamp)
    local age = ns.TimeUtil.GetAge(timestamp)
    if age < FRESH_THRESHOLD then
        return "fresh"
    elseif age < AGING_THRESHOLD then
        return "aging"
    elseif age < STALE_THRESHOLD then
        return "stale"
    else
        return "expired"
    end
end

function ns.TimeUtil.GetFreshnessColor(state)
    if state == "fresh" then
        return 0.0, 1.0, 0.0  -- green
    elseif state == "aging" then
        return 1.0, 1.0, 0.0  -- yellow
    elseif state == "stale" then
        return 1.0, 0.5, 0.0  -- orange
    else
        return 1.0, 0.0, 0.0  -- red
    end
end

function ns.TimeUtil.FormatAge(timestamp)
    local age = ns.TimeUtil.GetAge(timestamp)
    if age == math.huge then
        return "never"
    elseif age < 60 then
        return "just now"
    elseif age < 3600 then
        return string.format("%dm ago", math.floor(age / 60))
    elseif age < 86400 then
        return string.format("%dh ago", math.floor(age / 3600))
    else
        return string.format("%dd ago", math.floor(age / 86400))
    end
end

function ns.TimeUtil.FormatTimestamp(timestamp)
    if not timestamp or timestamp == 0 then
        return "never"
    end
    return date("%Y-%m-%d %H:%M", timestamp)
end
