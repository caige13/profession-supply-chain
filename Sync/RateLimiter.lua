local ADDON_NAME, ns = ...

ns.RateLimiter = {}

local queue = {}
local tokens = 0
local maxTokens = ns.Config.MAX_BURST
local tokensPerSecond = ns.Config.MAX_MESSAGES_PER_SECOND
local lastRefill = 0
local tickerFrame = nil

-- Stats for debug
local stats = {
    sent = 0,
    queued = 0,
    dropped = 0,
}

local function refillTokens()
    local now = GetTime()
    local elapsed = now - lastRefill
    if elapsed > 0 then
        tokens = math.min(maxTokens, tokens + elapsed * tokensPerSecond)
        lastRefill = now
    end
end

local function processQueue()
    if #queue == 0 then return end

    refillTokens()

    while #queue > 0 and tokens >= 1 do
        local item = table.remove(queue, 1)
        tokens = tokens - 1
        stats.sent = stats.sent + 1

        local ok, err = pcall(item.callback, unpack(item.args))
        if not ok then
            ns.Debug("RateLimiter send error: %s", tostring(err))
        end
    end
end

function ns.RateLimiter.Initialize()
    tokens = maxTokens
    lastRefill = GetTime()

    -- Ticker to drain queue
    if not tickerFrame then
        tickerFrame = CreateFrame("Frame")
        local elapsed = 0
        tickerFrame:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed >= 0.2 then  -- process queue 5 times/sec
                elapsed = 0
                processQueue()
            end
        end)
    end
end

-- Enqueue a send operation
-- callback will be called with args when a token is available
function ns.RateLimiter.Enqueue(callback, ...)
    stats.queued = stats.queued + 1
    queue[#queue + 1] = {
        callback = callback,
        args = { ... },
    }
end

-- Try to send immediately if tokens available, otherwise queue
function ns.RateLimiter.TrySend(callback, ...)
    refillTokens()
    if tokens >= 1 then
        tokens = tokens - 1
        stats.sent = stats.sent + 1
        callback(...)
        return true
    else
        ns.RateLimiter.Enqueue(callback, ...)
        return false
    end
end

function ns.RateLimiter.GetQueueSize()
    return #queue
end

function ns.RateLimiter.GetStats()
    return stats
end

function ns.RateLimiter.IsEnabled()
    return ns.DB and ns.DB.settings.syncEnabled
end

function ns.RateLimiter.Pause()
    if tickerFrame then
        tickerFrame:SetScript("OnUpdate", nil)
    end
end

function ns.RateLimiter.Resume()
    if tickerFrame then
        local elapsed = 0
        tickerFrame:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed >= 0.2 then
                elapsed = 0
                processQueue()
            end
        end)
    end
end
