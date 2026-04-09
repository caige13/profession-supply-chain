local ADDON_NAME, ns = ...

ns.InventoryTab = {}

local contentFrame = nil
local leftPane = nil
local rightPane = nil
local categoryButtons = {}
local itemRows = {}
local selectedCategory = "all"
local scrollFrame = nil

-- Item categories by WoW item class/subclass
local CATEGORIES = {
    { key = "all",          name = "All Items" },
    { key = "herbs",        name = "Herbs" },
    { key = "ores",         name = "Ores & Gems" },
    { key = "cloth",        name = "Cloth & Leather" },
    { key = "reagents",     name = "Crafting Reagents" },
    { key = "potions",      name = "Potions" },
    { key = "flasks",       name = "Flasks & Phials" },
    { key = "food",         name = "Food & Cooking" },
    { key = "enchants",     name = "Enchants & Scrolls" },
    { key = "gear",         name = "Crafted Gear" },
    { key = "other",        name = "Other" },
}

function ns.InventoryTab.Create(parent)
    contentFrame = CreateFrame("Frame", nil, parent)
    contentFrame:SetAllPoints()

    -- Left pane: category filters
    leftPane = CreateFrame("Frame", nil, contentFrame, "InsetFrameTemplate")
    leftPane:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
    leftPane:SetSize(150, 440)

    local catHeader = leftPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    catHeader:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 10, -8)
    catHeader:SetText("|cffffd100Categories|r")

    local y = -26
    for _, cat in ipairs(CATEGORIES) do
        local btn = CreateFrame("Button", nil, leftPane)
        btn:SetSize(130, 18)
        btn:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 10, y)

        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetAllPoints()
        text:SetJustifyH("LEFT")
        btn.label = text
        btn.catKey = cat.key

        btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        btn:SetScript("OnClick", function()
            selectedCategory = cat.key
            ns.InventoryTab.Refresh()
        end)

        categoryButtons[#categoryButtons + 1] = btn
        y = y - 20
    end

    -- Right pane: item list with scroll
    rightPane = CreateFrame("Frame", nil, contentFrame, "InsetFrameTemplate")
    rightPane:SetPoint("TOPLEFT", leftPane, "TOPRIGHT", 5, 0)
    rightPane:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)

    scrollFrame = CreateFrame("ScrollFrame", "PSCInventoryScroll", rightPane, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", rightPane, "TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", rightPane, "BOTTOMRIGHT", -26, 5)

    rightPane.listArea = CreateFrame("Frame", nil, scrollFrame)
    rightPane.listArea:SetWidth(scrollFrame:GetWidth() or 600)
    rightPane.listArea:SetHeight(1)
    scrollFrame:SetScrollChild(rightPane.listArea)

    return contentFrame
end

function ns.InventoryTab.Refresh()
    if not contentFrame then return end

    -- Clear old rows
    for _, row in ipairs(itemRows) do
        row:Hide()
        row:SetParent(nil)
    end
    wipe(itemRows)

    -- Gather and categorize ALL items first for counts
    local allItems = ns.InventoryIndex.GetAllItems()
    local categoryCounts = {}
    local allCategorized = {}

    for itemID, entry in pairs(allItems) do
        if entry.total > 0 then
            local category = ns.InventoryTab.CategorizeItem(itemID)
            categoryCounts[category] = (categoryCounts[category] or 0) + 1
            allCategorized[#allCategorized + 1] = {
                itemID = itemID,
                total = entry.total,
                byCharacter = entry.byCharacter,
                byAccount = entry.byAccount,
                category = category,
            }
        end
    end

    local totalItems = #allCategorized
    categoryCounts["all"] = totalItems

    -- Update category button highlights with counts
    for _, btn in ipairs(categoryButtons) do
        local cat = nil
        for _, c in ipairs(CATEGORIES) do
            if c.key == btn.catKey then cat = c; break end
        end
        if cat then
            local count = categoryCounts[cat.key] or 0
            if btn.catKey == selectedCategory then
                btn.label:SetText(string.format("|cff00cc66> %s|r (%d)", cat.name, count))
            else
                btn.label:SetText(string.format("  %s (%d)", cat.name, count))
            end
        end
    end

    -- Filter to selected category
    local sortedItems = {}
    for _, item in ipairs(allCategorized) do
        if selectedCategory == "all" or item.category == selectedCategory then
            sortedItems[#sortedItems + 1] = item
        end
    end

    -- Sort by name
    table.sort(sortedItems, function(a, b)
        local nameA = ns.ItemUtil.GetItemName(a.itemID)
        local nameB = ns.ItemUtil.GetItemName(b.itemID)
        return nameA < nameB
    end)

    -- Render rows
    local y = 0
    for i, item in ipairs(sortedItems) do
        local row = ns.InventoryTab.CreateItemRow(rightPane.listArea, y, item, i)
        itemRows[#itemRows + 1] = row
        y = y - 22
    end

    rightPane.listArea:SetHeight(math.max(1, math.abs(y)))
end

function ns.InventoryTab.CreateItemRow(parent, y, item, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(600, 20)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)

    if index % 2 == 0 then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.04)
    end

    -- Icon
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    local itemIcon = C_Item.GetItemIconByID(item.itemID)
    icon:SetTexture(itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark")

    -- Name
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    nameText:SetWidth(350)
    nameText:SetJustifyH("LEFT")
    nameText:SetText(ns.ItemUtil.GetItemName(item.itemID))

    -- Total count
    local countText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countText:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    countText:SetJustifyH("RIGHT")
    countText:SetText("|cffffd100" .. item.total .. "|r")

    -- Tooltip on hover showing per-character breakdown
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(item.itemID)

        -- Add character breakdown
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Location Breakdown:", 1, 0.82, 0)

        if item.byAccount then
            for accountKey, qty in pairs(item.byAccount) do
                if qty > 0 then
                    local accountName = ns.ItemUtil.GetAccountDisplayName(accountKey)
                    GameTooltip:AddLine(string.format("  %s: %d total", accountName, qty), 0.7, 0.7, 0.7)
                end
            end
        end

        if item.byCharacter then
            GameTooltip:AddLine(" ")
            for charKey, qty in pairs(item.byCharacter) do
                if qty > 0 then
                    local name = charKey:match("^(.+)-") or charKey
                    local buckets = ns.InventoryIndex.GetCharacterItemBuckets(charKey, item.itemID)
                    local details = {}
                    if buckets.bags > 0 then details[#details + 1] = buckets.bags .. " bags" end
                    if buckets.bank > 0 then details[#details + 1] = buckets.bank .. " bank" end
                    if buckets.reagentBank > 0 then details[#details + 1] = buckets.reagentBank .. " reagent" end
                    if buckets.mail > 0 then details[#details + 1] = buckets.mail .. " mail" end

                    local detailStr = #details > 0 and (" (" .. table.concat(details, ", ") .. ")") or ""
                    GameTooltip:AddLine(string.format("    %s: %d%s", name, qty, detailStr), 1, 1, 1)
                end
            end
        end

        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return row
end

-- Categorize an item by its WoW item class/subclass
function ns.InventoryTab.CategorizeItem(itemID)
    local classID, subclassID

    -- Try GetItemInfoInstant (global or C_Item) — instant, no server query
    local infoFunc = GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant)
    if infoFunc then
        local ok, id, itemType, itemSubType, itemEquipLoc, icon, cID, scID = pcall(infoFunc, itemID)
        if ok and cID then
            classID = cID
            subclassID = scID
        end
    end

    -- Fallback to GetItemInfo
    if not classID then
        local ok, results = pcall(function()
            return { C_Item.GetItemInfo(itemID) }
        end)
        if ok and results then
            classID = results[12]
            subclassID = results[13]
        end
    end

    if not classID then
        -- Request cache for next refresh
        pcall(C_Item.RequestLoadItemDataByID, itemID)
        return "reagents"
    end

    -- Tradeskill (classID 7)
    if classID == 7 then
        if subclassID == 9 then return "herbs" end      -- Herb
        if subclassID == 7 then return "ores" end       -- Metal & Stone
        if subclassID == 4 then return "ores" end       -- Jewelcrafting
        if subclassID == 5 then return "cloth" end      -- Cloth
        if subclassID == 6 then return "cloth" end      -- Leather
        if subclassID == 12 then return "enchants" end   -- Enchanting
        if subclassID == 16 then return "reagents" end   -- Inscription
        return "reagents"
    end

    -- Consumable (classID 0)
    if classID == 0 then
        if subclassID == 1 then return "potions" end     -- Potion
        if subclassID == 2 then return "potions" end     -- Elixir
        if subclassID == 3 then return "flasks" end      -- Flask/Phial
        if subclassID == 5 then return "food" end        -- Food & Drink
        if subclassID == 6 then return "enchants" end    -- Bandage
        return "potions"
    end

    -- Item Enhancement (classID 8)
    if classID == 8 then return "enchants" end

    -- Armor (classID 4) or Weapon (classID 2)
    if classID == 4 or classID == 2 then return "gear" end

    return "other"
end
