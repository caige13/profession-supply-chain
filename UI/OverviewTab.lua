local ADDON_NAME, ns = ...

ns.OverviewTab = {}

local contentFrame = nil
local labels = {}

function ns.OverviewTab.Create(parent)
    contentFrame = CreateFrame("Frame", nil, parent)
    contentFrame:SetAllPoints()

    local yOffset = -10

    -- Run Simulation button (top-right)
    local simButton = CreateFrame("Button", nil, contentFrame, "UIPanelButtonTemplate")
    simButton:SetSize(150, 24)
    simButton:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -10, -8)
    simButton:SetText("Run Simulation")
    simButton:SetScript("OnClick", function()
        ns.SimulationTab.RunSimulation()
        ns.MainFrame.SelectTab("simulation")
    end)

    -- Section: Network Status
    labels.networkHeader = ns.OverviewTab.CreateLabel(contentFrame, 10, yOffset, "|cffffd100Network Status|r")
    yOffset = yOffset - 20

    labels.accounts = ns.OverviewTab.CreateLabel(contentFrame, 20, yOffset, "Tracked Accounts: 0")
    yOffset = yOffset - 18
    labels.characters = ns.OverviewTab.CreateLabel(contentFrame, 20, yOffset, "Total Characters: 0")
    yOffset = yOffset - 18
    labels.peers = ns.OverviewTab.CreateLabel(contentFrame, 20, yOffset, "Connected Peers: 0")
    yOffset = yOffset - 18
    labels.lastSync = ns.OverviewTab.CreateLabel(contentFrame, 20, yOffset, "Last Sync: never")
    yOffset = yOffset - 30

    -- Section: Scan Freshness
    labels.freshnessHeader = ns.OverviewTab.CreateLabel(contentFrame, 10, yOffset, "|cffffd100Scan Freshness|r")
    yOffset = yOffset - 20

    labels.freshCount = ns.OverviewTab.CreateLabel(contentFrame, 20, yOffset, "Fresh: 0")
    yOffset = yOffset - 18
    labels.agingCount = ns.OverviewTab.CreateLabel(contentFrame, 20, yOffset, "Aging: 0")
    yOffset = yOffset - 18
    labels.staleCount = ns.OverviewTab.CreateLabel(contentFrame, 20, yOffset, "Stale: 0")
    yOffset = yOffset - 30

    -- Section: Watched Products
    labels.watchedHeader = ns.OverviewTab.CreateLabel(contentFrame, 10, yOffset, "|cffffd100Watched Products|r")
    yOffset = yOffset - 20

    labels.watchedList = ns.OverviewTab.CreateLabel(contentFrame, 20, yOffset, "No watched recipes.")
    yOffset = yOffset - 80

    -- Section: Top Bottlenecks
    labels.bottleneckHeader = ns.OverviewTab.CreateLabel(contentFrame, 10, yOffset, "|cffffd100Top Bottlenecks|r")
    yOffset = yOffset - 24

    -- Bottleneck rows with icons (up to 5)
    labels.bottleneckRows = {}
    for i = 1, 5 do
        local row = CreateFrame("Frame", nil, contentFrame)
        row:SetSize(700, 20)
        row:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 20, yOffset)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWidth(660)

        row:Hide()
        labels.bottleneckRows[i] = row
        yOffset = yOffset - 22
    end

    labels.noBottlenecks = ns.OverviewTab.CreateLabel(contentFrame, 20, yOffset + (5 * 22), "No bottlenecks detected.")

    return contentFrame
end

function ns.OverviewTab.CreateLabel(parent, x, y, text)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetJustifyH("LEFT")
    label:SetWidth(750)
    label:SetText(text)
    return label
end

function ns.OverviewTab.Refresh()
    if not contentFrame then return end

    -- Network status
    local accountKeys = ns.Repository.GetAllAccountKeys()
    labels.accounts:SetText("Tracked Accounts: " .. #accountKeys)

    local totalChars = 0
    local freshCount, agingCount, staleCount = 0, 0, 0

    ns.Repository.IterateAllCharacters(function(charKey, charData, accountKey, isLocal)
        totalChars = totalChars + 1
        local freshness = ns.TimeUtil.GetFreshnessState(charData.lastScan)
        if freshness == "fresh" then
            freshCount = freshCount + 1
        elseif freshness == "aging" then
            agingCount = agingCount + 1
        else
            staleCount = staleCount + 1
        end
    end)

    labels.characters:SetText("Total Characters: " .. totalChars)
    labels.peers:SetText("Connected Peers: " .. ns.Comm.GetPeerCount())
    labels.lastSync:SetText("Last Sync: " .. ns.TimeUtil.FormatAge(ns.DB.syncState.lastBroadcast))

    -- Freshness
    labels.freshCount:SetText(string.format("|cff00ff00Fresh: %d|r", freshCount))
    labels.agingCount:SetText(string.format("|cffffff00Aging: %d|r", agingCount))
    labels.staleCount:SetText(string.format("|cffff6600Stale: %d|r", staleCount))

    -- Watched products
    local watchedLines = {}
    for recipeID in pairs(ns.DB.watchedRecipes) do
        local recipe = ns.RecipeGraph.GetRecipe(recipeID)
        if recipe then
            local result = ns.MaxCraftable.Calculate(recipeID)
            local icon = ns.ItemUtil.GetIconString(recipe.outputItemID, 14)
            watchedLines[#watchedLines + 1] = string.format("  %s %s — Estimated max craftable: %d",
                icon, recipe.recipeName or "?", result.maxCraftable)
        end
    end
    if #watchedLines > 0 then
        labels.watchedList:SetText(table.concat(watchedLines, "\n"))
    else
        labels.watchedList:SetText(
            "|cff888888No watched recipes yet.|r\n\n" ..
            "  To get started, open a profession window and click\n" ..
            "  |cffffd100PSC: Watch Recipe|r in the bottom-right corner.\n\n" ..
            "  Watched recipes drive the supply chain planner:\n" ..
            "  - Shows how many you can craft with current materials\n" ..
            "  - Identifies bottleneck reagents across all characters\n" ..
            "  - Generates a suggested transfer and crafting plan\n" ..
            "  - Powers the mailbox fill helper for quick mailing"
        )
    end

    -- Top bottlenecks (with item icons)
    local bottlenecks = ns.Bottlenecks.Analyze()

    if #bottlenecks > 0 then
        labels.noBottlenecks:Hide()
        for i = 1, 5 do
            local row = labels.bottleneckRows[i]
            if i <= #bottlenecks then
                local bn = bottlenecks[i]
                -- Set item icon if available
                if bn.itemID then
                    local itemIcon = C_Item.GetItemIconByID(bn.itemID)
                    if itemIcon then
                        row.icon:SetTexture(itemIcon)
                        row.icon:Show()
                    else
                        row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                        row.icon:Show()
                    end
                else
                    row.icon:Hide()
                end
                row.text:SetText(bn.message)
                row:Show()
            else
                row:Hide()
            end
        end
    else
        labels.noBottlenecks:Show()
        for i = 1, 5 do
            labels.bottleneckRows[i]:Hide()
        end
    end
end
