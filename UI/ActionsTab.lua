local ADDON_NAME, ns = ...

ns.ActionsTab = {}

local contentFrame = nil
local actionRows = {}
local headerLabel = nil
local noActionsLabel = nil

function ns.ActionsTab.Create(parent)
    contentFrame = CreateFrame("Frame", nil, parent)
    contentFrame:SetAllPoints()

    headerLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    headerLabel:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, -10)
    headerLabel:SetText("Suggested Action Plan")

    -- Column headers
    local colY = -35
    local headers = {
        { x = 10,  text = "Action" },
        { x = 100, text = "From" },
        { x = 240, text = "To" },
        { x = 370, text = "Item" },
        { x = 600, text = "Qty" },
    }
    for _, h in ipairs(headers) do
        local label = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", h.x, colY)
        label:SetText("|cffffd100" .. h.text .. "|r")
    end

    noActionsLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    noActionsLabel:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, -60)
    noActionsLabel:SetWidth(750)
    noActionsLabel:SetJustifyH("LEFT")
    noActionsLabel:SetText("No actions needed. Watch recipes using |cffffd100PSC: Watch Recipe|r in the profession window to generate a plan.")

    return contentFrame
end

function ns.ActionsTab.Refresh()
    if not contentFrame then return end

    -- Clear old rows
    for _, row in ipairs(actionRows) do
        row:Hide()
        row:SetParent(nil)
    end
    wipe(actionRows)

    local actions = ns.ActionPlanner.GeneratePlan()

    if #actions == 0 then
        local watchedCount = ns.TableUtil.Count(ns.DB.watchedRecipes)
        if watchedCount == 0 then
            noActionsLabel:SetText(
                "No actions needed.\n\n" ..
                "Open a profession window and click |cffffd100PSC: Watch Recipe|r\n" ..
                "to start tracking recipes in the supply chain planner."
            )
        else
            local lines = {}
            local optimized = ns.CraftSimPlanner.OptimizeWatchedRecipes()
            local pool = ns.ResourcePool.Build(optimized)
            local deficits = ns.ResourcePool.GetSortedDeficits(pool)

            -- Analyze the situation
            local hasMaterials = #deficits == 0
            local hasAnyProfitable = false
            local hasConcentrationProfitable = false
            local missingMaterials = #deficits > 0

            for _, recipe in ipairs(optimized) do
                if (recipe.profit or 0) > 0 then
                    hasAnyProfitable = true
                end
                -- Check concentration variants in quality results
                if recipe.qualityResults then
                    for _, qr in ipairs(recipe.qualityResults) do
                        if qr.useConcentration and (qr.profit or 0) > 0 then
                            hasConcentrationProfitable = true
                        end
                        if (qr.profit or 0) > 0 then
                            hasAnyProfitable = true
                        end
                    end
                end
            end

            -- CASE 1: Missing materials
            if missingMaterials then
                lines[#lines + 1] = "|cffffd100No actions available — missing materials.|r"
                lines[#lines + 1] = ""
                lines[#lines + 1] = "The following resources are needed to craft watched recipes:"
                lines[#lines + 1] = ""
                for i, entry in ipairs(deficits) do
                    if i > 10 then break end
                    local itemIcon = ns.ItemUtil.GetIconString(entry.baseItemID, 14)
                    lines[#lines + 1] = string.format("  %s %s — need %d, have %d |cffff4444(short %d)|r",
                        itemIcon, entry.name or "?",
                        entry.totalDemand, entry.totalAvailable, entry.deficit)
                end

            -- CASE 2: Have materials but nothing profitable
            elseif not hasAnyProfitable then
                lines[#lines + 1] = "|cffffd100No profitable crafts available.|r"
                lines[#lines + 1] = ""
                lines[#lines + 1] = "All watched recipes cost more to craft than the output sells for"
                lines[#lines + 1] = "at current market prices."
                lines[#lines + 1] = ""
                lines[#lines + 1] = "Consider selling raw materials on the auction house instead."

            -- CASE 3: Concentration makes it profitable but base doesn't
            elseif hasConcentrationProfitable and not hasAnyProfitable then
                lines[#lines + 1] = "|cffffd100Crafting is only profitable with concentration.|r"
                lines[#lines + 1] = ""
                lines[#lines + 1] = "Without concentration, all recipes are a loss."
                lines[#lines + 1] = "Use the Simulation tab to see which quality + concentration"
                lines[#lines + 1] = "combinations are profitable, then craft those manually."

            -- CASE 4: Something else
            else
                lines[#lines + 1] = "|cffffd100No actions generated.|r"
                lines[#lines + 1] = ""
                lines[#lines + 1] = "Profitable recipes exist but resources could not be allocated."
                lines[#lines + 1] = "Check the Simulation tab for details."
            end

            noActionsLabel:SetText(table.concat(lines, "\n"))

            noActionsLabel:SetText(table.concat(lines, "\n"))
        end
        noActionsLabel:Show()
        return
    end
    noActionsLabel:Hide()

    local y = -55
    for i, action in ipairs(actions) do
        local row = ns.ActionsTab.CreateActionRow(contentFrame, y, action, i)
        actionRows[#actionRows + 1] = row
        y = y - 22

        if i >= 30 then break end  -- limit displayed rows
    end

    -- Mail log section
    ns.ActionsTab.RenderMailLog(contentFrame, y - 15)
end

function ns.ActionsTab.RenderMailLog(parent, startY)
    if not ns.DB.mailLog or #ns.DB.mailLog == 0 then return end

    -- Show last 5 entries
    local recentCount = math.min(#ns.DB.mailLog, 5)

    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, startY)
    header:SetText("|cffffd100Recent Mail|r")
    actionRows[#actionRows + 1] = header

    local y = startY - 16
    for i = #ns.DB.mailLog, math.max(1, #ns.DB.mailLog - recentCount + 1), -1 do
        local entry = ns.DB.mailLog[i]
        if entry then
            local timeStr = entry.timestamp and ns.TimeUtil.FormatTimestamp(entry.timestamp) or "?"
            local senderName = entry.sender and (entry.sender:match("^(.+)-") or entry.sender) or "?"
            local recipientName = entry.recipient or "?"

            local itemParts = {}
            if entry.items then
                for _, item in ipairs(entry.items) do
                    local name = item.itemName or ns.ItemUtil.GetItemName(item.itemID)
                    -- Strip color codes and icons for compact display
                    name = name:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):trim()
                    itemParts[#itemParts + 1] = string.format("%dx %s", item.quantity or 0, name)
                end
            end
            local itemStr = table.concat(itemParts, ", ")

            local logLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            logLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y)
            logLabel:SetWidth(750)
            logLabel:SetJustifyH("LEFT")
            logLabel:SetText(string.format("|cff888888%s|r  %s |cff4488ff→|r %s: %s",
                timeStr, senderName, recipientName, itemStr))
            actionRows[#actionRows + 1] = logLabel
            y = y - 14
        end
    end
end

function ns.ActionsTab.CreateActionRow(parent, y, action, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(800, 22)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)

    if index % 2 == 0 then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.05)
    end

    local typeColor = action.actionType == "transfer" and "|cff4488ff" or "|cff00cc66"
    local typeLabel = action.actionType == "transfer" and "Send" or "Craft"

    -- Action type
    local typeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    typeText:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -4)
    typeText:SetText(typeColor .. typeLabel .. "|r")

    -- From (character name only, no realm)
    local sourceText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sourceText:SetPoint("TOPLEFT", row, "TOPLEFT", 100, -4)
    sourceText:SetWidth(130)
    sourceText:SetJustifyH("LEFT")
    local sourceName = action.source and (action.source:match("^(.+)-") or action.source) or "-"
    sourceText:SetText(sourceName)

    -- To
    local destText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    destText:SetPoint("TOPLEFT", row, "TOPLEFT", 240, -4)
    destText:SetWidth(120)
    destText:SetJustifyH("LEFT")
    local destName = action.destination and (action.destination:match("^(.+)-") or action.destination) or "-"
    destText:SetText(destName)

    -- Item (already includes icon from ActionPlanner)
    local itemText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemText:SetPoint("TOPLEFT", row, "TOPLEFT", 370, -4)
    itemText:SetWidth(220)
    itemText:SetJustifyH("LEFT")
    itemText:SetText(action.itemName or action.recipeName or "?")

    -- Qty
    local qtyText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    qtyText:SetPoint("TOPLEFT", row, "TOPLEFT", 600, -4)
    qtyText:SetWidth(40)
    qtyText:SetJustifyH("RIGHT")
    qtyText:SetText("|cffffd100" .. tostring(action.quantity or 0) .. "|r")

    -- Concentration indicator (glowing icon after qty)
    if action.concentratedCrafts and action.concentratedCrafts > 0 then
        local concFrame = CreateFrame("Frame", nil, row)
        concFrame:SetSize(20, 20)
        concFrame:SetPoint("LEFT", qtyText, "RIGHT", 8, 2)

        local concIcon = concFrame:CreateTexture(nil, "ARTWORK")
        concIcon:SetSize(16, 16)
        concIcon:SetPoint("CENTER")
        concIcon:SetAtlas("Professions-Icon-Concentration")

        -- Pulsing glow behind the icon
        local glow = concFrame:CreateTexture(nil, "BACKGROUND")
        glow:SetSize(24, 24)
        glow:SetPoint("CENTER")
        glow:SetAtlas("Professions-Icon-Concentration")
        glow:SetBlendMode("ADD")
        glow:SetAlpha(0)

        local ag = concFrame:CreateAnimationGroup()
        local fadeIn = ag:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0)
        fadeIn:SetToAlpha(0.5)
        fadeIn:SetDuration(0.6)
        fadeIn:SetOrder(1)
        local fadeOut = ag:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(0.5)
        fadeOut:SetToAlpha(0)
        fadeOut:SetDuration(0.6)
        fadeOut:SetOrder(2)
        ag:SetLooping("REPEAT")

        glow:SetAnimationGroup(ag)
        ag:Play()

        -- Tooltip
        concFrame:EnableMouse(true)
        concFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(string.format("Use Concentration on %d of %d crafts",
                action.concentratedCrafts, action.quantity or 0), 1, 0.5, 0)
            GameTooltip:Show()
        end)
        concFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- Tooltip with full note
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if action.note then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(action.note, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return row
end
