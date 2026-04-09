local ADDON_NAME, ns = ...

ns.ADDON_NAME = ADDON_NAME
ns.VERSION = "0.1.0"
ns.PROTOCOL_VERSION = 1
ns.PREFIX = "PSC"

-- Debug logging
ns.debug = false
ns.debugLog = {}
local DEBUG_LOG_MAX = 200

function ns.Debug(...)
    if ns.debug then
        local msg = string.format(...)
        print("|cff88ccff[PSC]|r " .. msg)
        -- Buffer for Debug tab
        ns.debugLog[#ns.debugLog + 1] = date("%H:%M:%S") .. " " .. msg
        if #ns.debugLog > DEBUG_LOG_MAX then
            table.remove(ns.debugLog, 1)
        end
    end
end

function ns.ClearDebugLog()
    wipe(ns.debugLog)
end

function ns.Print(...)
    local msg = string.format(...)
    print("|cff00cc66[Profession Supply Chain]|r " .. msg)
end

-- Initialization
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")

    -- Initialize saved variables
    ns.SavedVariables.Initialize()

    -- Set debug from saved settings
    ns.debug = ns.DB.settings.debug

    -- Register addon message prefix for sync
    C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)

    -- Initialize subsystems
    ns.Events.Initialize()
    ns.CharacterScanner.Initialize()
    ns.InventoryScanner.Initialize()
    ns.ProfessionScanner.Initialize()
    ns.RecipeScanner.Initialize()
    ns.Repository.Initialize()
    ns.Merge.Initialize()
    ns.InventoryIndex.Initialize()
    ns.RecipeGraph.Initialize()
    ns.Comm.Initialize()
    ns.TSMAdapter.Initialize()
    ns.CraftSimAdapter.Initialize()
    ns.MainFrame.Initialize()
    ns.ProfessionOverlay.Initialize()
    ns.MailHelper.Initialize()

    ns.Print("v%s loaded. Type /psc to open.", ns.VERSION)
    ns.Debug("Debug mode enabled")
end)

-- Slash commands
SLASH_PSC1 = "/psc"
SLASH_PSC2 = "/profsc"
SlashCmdList["PSC"] = function(msg)
    msg = (msg or ""):trim():lower()
    if msg == "help" then
        ns.Print("Commands:")
        ns.Print("  /psc — Open the planner window")
        ns.Print("  /psc scan — Rescan bags and character")
        ns.Print("  /psc sync — Broadcast hello to peers")
        ns.Print("  /psc status — Show network summary")
        ns.Print("  /psc debug — Toggle debug mode")
        ns.Print("  /psc help — Show this help")
    elseif msg == "debug" then
        ns.debug = not ns.debug
        ns.DB.settings.debug = ns.debug
        ns.Print("Debug mode %s", ns.debug and "enabled" or "disabled")
    elseif msg == "scan" then
        ns.CharacterScanner.Scan()
        ns.InventoryScanner.ScanBags()
        ns.Print("Manual scan triggered")
    elseif msg == "sync" then
        if ns.DB.settings.syncEnabled then
            ns.Comm.BroadcastHello()
            ns.Print("Sync hello broadcast sent")
        else
            ns.Print("Sync is disabled in settings")
        end
    elseif msg == "status" then
        local charCount = ns.TableUtil.Count(ns.DB.localScans.characters)
        local peerCount = ns.TableUtil.Count(ns.DB.networkSnapshots)
        ns.Print("Local characters: %d | Network peers: %d", charCount, peerCount)
    else
        ns.MainFrame.Toggle()
    end
end
