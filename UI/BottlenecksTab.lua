local ADDON_NAME, ns = ...

ns.BottlenecksTab = {}

local contentFrame = nil
local leftPane = nil
local rightPane = nil
local resourceRows = {}
local selectedResource = nil
local detailLabels = {}

function ns.BottlenecksTab.Create(parent)
    contentFrame = CreateFrame("Frame", nil, parent)
    contentFrame:SetAllPoints()

    -- Left pane: resource list with scroll
    leftPane = CreateFrame("Frame", nil, contentFrame, "InsetFrameTemplate")
    leftPane:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
    leftPane:SetSize(320, 440)

    local leftHeader = leftPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    leftHeader:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 10, -8)
    leftHeader:SetText("|cffffd100Resource Demands (merged across recipes)|r")

    local scrollFrame = CreateFrame("ScrollFrame", "PSCBottleneckScroll", leftPane, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 5, -24)
    scrollFrame:SetPoint("BOTTOMRIGHT", leftPane, "BOTTOMRIGHT", -26, 5)

    leftPane.listArea = CreateFrame("Frame", nil, scrollFrame)
    leftPane.listArea:SetWidth(280)
    leftPane.listArea:SetHeight(1)
    scrollFrame:SetScrollChild(leftPane.listArea)

    -- Right pane: resource detail
    rightPane = CreateFrame("Frame", nil, contentFrame, "InsetFrameTemplate")
    rightPane:SetPoint("TOPLEFT", leftPane, "TOPRIGHT", 5, 0)
    rightPane:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)

    local y = -10
    detailLabels.header = ns.BottlenecksTab.CreateLabel(rightPane, y, "Select a resource")
    y = y - 30

    detailLabels.summary = ns.BottlenecksTab.CreateLabel(rightPane, y, "")
    y = y - 30

    detailLabels.qualityHeader = ns.BottlenecksTab.CreateLabel(rightPane, y, "|cffffd100Quality Breakdown|r")
    y = y - 20

    -- Quality rows (up to 3 tiers)
    detailLabels.qualityRows = {}
    for i = 1, 3 do
        local row = CreateFrame("Frame", nil, rightPane)
        row:SetSize(400, 22)
        row:SetPoint("TOPLEFT", rightPane, "TOPLEFT", 20, y)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWidth(370)

        row:Hide()
        detailLabels.qualityRows[i] = row
        y = y - 24
    end

    y = y - 10
    detailLabels.locationHeader = ns.BottlenecksTab.CreateLabel(rightPane, y, "|cffffd100Location by Character|r")
    y = y - 20
    detailLabels.locations = ns.BottlenecksTab.CreateLabel(rightPane, y, "")
    y = y - 80

    detailLabels.usedByHeader = ns.BottlenecksTab.CreateLabel(rightPane, y, "|cffffd100Demanded By|r")
    y = y - 20
    detailLabels.usedBy = ns.BottlenecksTab.CreateLabel(rightPane, y, "")

    return contentFrame
end

function ns.BottlenecksTab.CreateLabel(parent, y, text)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y)
    label:SetJustifyH("LEFT")
    label:SetWidth(420)
    label:SetText(text)
    return label
end

function ns.BottlenecksTab.Refresh()
    if not contentFrame then return end

    -- Clear old rows
    for _, row in ipairs(resourceRows) do
        row:Hide()
        row:SetParent(nil)
    end
    wipe(resourceRows)

    local optimized = ns.CraftSimPlanner.OptimizeWatchedRecipes()
    local pool = ns.ResourcePool.Build(optimized)
    local sorted = ns.ResourcePool.GetSortedByDemand(pool)

    if #sorted == 0 then
        local noData = leftPane.listArea:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noData:SetPoint("TOPLEFT", leftPane.listArea, "TOPLEFT", 10, -10)
        noData:SetWidth(260)
        noData:SetText("|cff888888No resource demands. Watch recipes\nusing PSC: Watch Recipe in the\nprofession window.|r")
        resourceRows[1] = noData
        leftPane.listArea:SetHeight(60)
        return
    end

    local y = 0
    for i, entry in ipairs(sorted) do
        local row = ns.BottlenecksTab.CreateResourceRow(leftPane.listArea, y, entry, i)
        resourceRows[#resourceRows + 1] = row
        y = y - 26
    end
    leftPane.listArea:SetHeight(math.max(1, math.abs(y)))

    -- Auto-select first if nothing selected
    if not selectedResource and #sorted > 0 then
        selectedResource = sorted[1]
        ns.BottlenecksTab.ShowDetail(sorted[1])
    elseif selectedResource then
        -- Refresh detail for current selection
        for _, entry in ipairs(sorted) do
            if entry.baseItemID == selectedResource.baseItemID then
                selectedResource = entry
                ns.BottlenecksTab.ShowDetail(entry)
                break
            end
        end
    end
end

function ns.BottlenecksTab.CreateResourceRow(parent, y, entry, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(280, 24)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)

    -- Alternating background
    if index % 2 == 0 then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.05)
    end

    -- Item icon
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    local itemIcon = C_Item.GetItemIconByID(entry.baseItemID)
    icon:SetTexture(itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark")

    -- Name + counts
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    text:SetWidth(180)
    text:SetJustifyH("LEFT")

    local deficitColor = entry.deficit > 0 and "|cffff4444" or "|cff00cc66"
    text:SetText(string.format("%s", entry.name or "?"))

    -- Counts on right
    local counts = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    counts:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    counts:SetJustifyH("RIGHT")
    if entry.deficit > 0 then
        counts:SetText(string.format("|cffff4444%d/%d|r", entry.totalAvailable, entry.totalDemand))
    else
        counts:SetText(string.format("|cff00cc66%d/%d|r", entry.totalAvailable, entry.totalDemand))
    end

    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row:SetScript("OnClick", function()
        selectedResource = entry
        ns.BottlenecksTab.ShowDetail(entry)
    end)

    return row
end

function ns.BottlenecksTab.ShowDetail(entry)
    if not entry then return end

    local headerIcon = ns.ItemUtil.GetIconString(entry.baseItemID, 18)
    detailLabels.header:SetText(string.format("%s |cffffd100%s|r", headerIcon, entry.name or "?"))

    local deficitText = entry.deficit > 0
        and string.format("|cffff4444Deficit: %d|r", entry.deficit)
        or "|cff00cc66Fully stocked|r"
    detailLabels.summary:SetText(string.format(
        "Total demand: %d | Available: %d | %s",
        entry.totalDemand, entry.totalAvailable, deficitText))

    -- Quality breakdown
    local hasQuality = false
    for i, row in ipairs(detailLabels.qualityRows) do
        row:Hide()
    end

    if entry.qualityItems then
        for i, qi in ipairs(entry.qualityItems) do
            if i <= 3 then
                local row = detailLabels.qualityRows[i]
                local demand = entry.demand[qi.itemID] or 0
                local have = entry.available[qi.itemID] or 0
                local itemIcon = C_Item.GetItemIconByID(qi.itemID)
                row.icon:SetTexture(itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark")

                local qIcon = qi.qualityID > 0 and ns.ItemUtil.GetQualityIcon(qi.qualityID, 16) or ""
                local color = have >= demand and "|cff00cc66" or "|cffff4444"
                row.text:SetText(string.format("%s %s: %shave %d / need %d|r",
                    ns.ItemUtil.GetItemName(qi.itemID), qIcon, color, have, demand))
                row:Show()
                hasQuality = true
            end
        end
    end

    if not hasQuality then
        detailLabels.qualityRows[1].icon:SetTexture(C_Item.GetItemIconByID(entry.baseItemID) or "Interface\\Icons\\INV_Misc_QuestionMark")
        detailLabels.qualityRows[1].text:SetText(string.format("have %d / need %d",
            entry.totalAvailable, entry.totalDemand))
        detailLabels.qualityRows[1]:Show()
    end

    -- Location by character
    local locationLines = {}
    local allQualityItems = {}
    if entry.qualityItems then
        for _, qi in ipairs(entry.qualityItems) do
            allQualityItems[#allQualityItems + 1] = qi.itemID
        end
    else
        allQualityItems[1] = entry.baseItemID
    end

    local charBreakdown = ns.InventoryIndex.GetQualityByCharacter(allQualityItems)
    for charKey, items in pairs(charBreakdown) do
        local parts = {}
        for itemID, qty in pairs(items) do
            if qty > 0 then
                parts[#parts + 1] = string.format("%s %s: %d", ns.ItemUtil.GetIconString(itemID, 14), ns.ItemUtil.GetItemName(itemID), qty)
            end
        end
        if #parts > 0 then
            locationLines[#locationLines + 1] = string.format("  %s — %s", charKey, table.concat(parts, ", "))
        end
    end
    detailLabels.locations:SetText(#locationLines > 0 and table.concat(locationLines, "\n") or "  Not found in any inventory")

    -- Demanded by (with recipe output icons)
    local demandLines = {}
    if entry.demandedBy then
        for i, recipeID in ipairs(entry.demandedBy) do
            local recipe = ns.RecipeGraph.GetRecipe(recipeID)
            local icon = recipe and ns.ItemUtil.GetIconString(recipe.outputItemID, 14) or ""
            local name = entry.demandedByNames and entry.demandedByNames[i] or ("Recipe #" .. recipeID)
            demandLines[#demandLines + 1] = string.format("  %s %s", icon, name)
        end
    end
    detailLabels.usedBy:SetText(#demandLines > 0 and table.concat(demandLines, "\n") or "  None")
end
