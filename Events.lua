local ADDON_NAME, ns = ...

ns.Events = {}

local listeners = {}
local wowEventFrame = CreateFrame("Frame")

function ns.Events.Initialize()
    wowEventFrame:SetScript("OnEvent", function(self, event, ...)
        ns.Events.Fire(event, ...)
    end)
end

-- Register for a custom or WoW event
function ns.Events.Register(event, callback, owner)
    if not listeners[event] then
        listeners[event] = {}
    end
    listeners[event][#listeners[event] + 1] = {
        callback = callback,
        owner = owner,
    }
    -- Register with WoW frame only if it's a real game event (not our custom PSC_ events)
    if not event:find("^PSC_") and event:match("^[A-Z_]+$") and event:find("_") then
        wowEventFrame:RegisterEvent(event)
    end
end

-- Unregister all callbacks for a given owner
function ns.Events.UnregisterAll(owner)
    for event, cbs in pairs(listeners) do
        for i = #cbs, 1, -1 do
            if cbs[i].owner == owner then
                table.remove(cbs, i)
            end
        end
        if #cbs == 0 then
            listeners[event] = nil
            if not event:find("^PSC_") and event:match("^[A-Z_]+$") and event:find("_") then
                pcall(function() wowEventFrame:UnregisterEvent(event) end)
            end
        end
    end
end

-- Fire an event (both WoW events and custom events)
function ns.Events.Fire(event, ...)
    local cbs = listeners[event]
    if not cbs then return end
    for i = 1, #cbs do
        local ok, err = pcall(cbs[i].callback, ...)
        if not ok then
            ns.Debug("Event handler error [%s]: %s", event, tostring(err))
        end
    end
end

-- Unregister a WoW event from the frame
function ns.Events.UnregisterWoWEvent(event)
    pcall(function() wowEventFrame:UnregisterEvent(event) end)
end
