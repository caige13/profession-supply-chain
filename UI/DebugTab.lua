local ADDON_NAME, ns = ...

ns.DebugTab = {}

local contentFrame = nil
local debugText = nil

function ns.DebugTab.Create(parent)
    contentFrame = CreateFrame("Frame", nil, parent)
    contentFrame:SetAllPoints()

    local header = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, -10)
    header:SetText("Debug Information")

    -- Refresh button
    local refreshBtn = CreateFrame("Button", nil, contentFrame, "UIPanelButtonTemplate")
    refreshBtn:SetSize(80, 22)
    refreshBtn:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -10, -8)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        ns.DebugTab.Refresh()
    end)

    -- Scroll frame for debug text
    local scrollFrame = CreateFrame("ScrollFrame", "PSCDebugScroll", contentFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, -35)
    scrollFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -30, 10)

    debugText = CreateFrame("EditBox", nil, scrollFrame)
    debugText:SetMultiLine(true)
    debugText:SetFontObject("GameFontNormalSmall")
    debugText:SetWidth(700)
    debugText:SetAutoFocus(false)
    debugText:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    scrollFrame:SetScrollChild(debugText)

    return contentFrame
end

function ns.DebugTab.Refresh()
    if not debugText then return end

    local lines = {}

    -- Local account
    lines[#lines + 1] = "|cffffd100=== Local Account ===|r"
    lines[#lines + 1] = "Account Key: " .. (ns.DB.localAccount.accountKey or "?")
    lines[#lines + 1] = "Addon Version: " .. ns.Config.ADDON_VERSION
    lines[#lines + 1] = "Protocol Version: " .. ns.Config.PROTOCOL_VERSION
    lines[#lines + 1] = ""

    -- Local scan timestamps
    lines[#lines + 1] = "|cffffd100=== Local Scan Timestamps ===|r"
    for charKey, charData in pairs(ns.DB.localScans.characters) do
        local freshness = ns.TimeUtil.GetFreshnessState(charData.lastScan)
        lines[#lines + 1] = string.format("  %s: %s (%s)",
            charKey,
            ns.TimeUtil.FormatTimestamp(charData.lastScan),
            freshness)
    end
    lines[#lines + 1] = ""

    -- Network snapshots
    lines[#lines + 1] = "|cffffd100=== Network Snapshots ===|r"
    for accountKey, snapshot in pairs(ns.DB.networkSnapshots) do
        local freshness = ns.TimeUtil.GetFreshnessState(snapshot.lastReceived)
        local charCount = snapshot.characters and ns.TableUtil.Count(snapshot.characters) or 0
        lines[#lines + 1] = string.format("  %s: received %s (%s), %d chars",
            accountKey,
            ns.TimeUtil.FormatTimestamp(snapshot.lastReceived),
            freshness,
            charCount)
    end
    if ns.TableUtil.Count(ns.DB.networkSnapshots) == 0 then
        lines[#lines + 1] = "  (none)"
    end
    lines[#lines + 1] = ""

    -- Connected peers
    lines[#lines + 1] = "|cffffd100=== Connected Peers ===|r"
    local peers = ns.Comm.GetPeers()
    for senderID, peer in pairs(peers) do
        lines[#lines + 1] = string.format("  %s (%s) — last seen %.0fs ago via %s",
            peer.characterKey or "?",
            peer.accountKey or "?",
            GetTime() - peer.lastSeen,
            peer.channel or "?")
    end
    if ns.Comm.GetPeerCount() == 0 then
        lines[#lines + 1] = "  (none connected)"
    end
    lines[#lines + 1] = ""

    -- Rate limiter stats
    lines[#lines + 1] = "|cffffd100=== Comm Stats ===|r"
    local rlStats = ns.RateLimiter.GetStats()
    lines[#lines + 1] = string.format("  Messages sent: %d", rlStats.sent)
    lines[#lines + 1] = string.format("  Messages queued: %d", rlStats.queued)
    lines[#lines + 1] = string.format("  Current queue: %d", ns.RateLimiter.GetQueueSize())
    lines[#lines + 1] = ""

    -- Chunk reassembly
    lines[#lines + 1] = "|cffffd100=== Chunk Reassembly ===|r"
    local pending = ns.Chunking.GetPendingSnapshots()
    for snapID, info in pairs(pending) do
        lines[#lines + 1] = string.format("  %s: %d/%d chunks (%.0fs old)",
            snapID, info.received, info.total, info.age)
    end
    if ns.TableUtil.Count(pending) == 0 then
        lines[#lines + 1] = "  (no pending snapshots)"
    end
    lines[#lines + 1] = ""

    -- Adapter availability
    lines[#lines + 1] = "|cffffd100=== Adapters ===|r"
    lines[#lines + 1] = string.format("  TSM: %s (setting: %s)",
        ns.TSMAdapter.IsAvailable() and "|cff00ff00Available|r" or "|cffff0000Not found|r",
        ns.DB.settings.enableTSM and "enabled" or "disabled")
    lines[#lines + 1] = string.format("  CraftSim: %s (setting: %s)",
        ns.CraftSimAdapter.IsAvailable() and "|cff00ff00Available|r" or "|cffff0000Not found|r",
        ns.DB.settings.enableCraftSim and "enabled" or "disabled")
    lines[#lines + 1] = ""

    -- Merged index summary
    lines[#lines + 1] = "|cffffd100=== Merged Index ===|r"
    lines[#lines + 1] = string.format("  Items: %d", ns.TableUtil.Count(ns.DB.mergedIndex.itemTotals))
    lines[#lines + 1] = string.format("  Recipes: %d", ns.TableUtil.Count(ns.DB.mergedIndex.recipeOwners))
    lines[#lines + 1] = string.format("  Professions: %d", ns.TableUtil.Count(ns.DB.mergedIndex.professionOwners))
    lines[#lines + 1] = string.format("  Watched recipes: %d", ns.TableUtil.Count(ns.DB.watchedRecipes))

    debugText:SetText(table.concat(lines, "\n"))
end
