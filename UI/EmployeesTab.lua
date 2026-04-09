local ADDON_NAME, ns = ...

ns.EmployeesTab = {}

local contentFrame = nil
local rosterScrollFrame = nil
local rosterScrollChild = nil
local logScrollFrame = nil
local logScrollChild = nil
local rosterRows = {}
local logRows = {}
local sortField = "name"
local sortAscending = true

-- Gathering profession IDs mapped to InventoryTab categories
local GATHERING_PROFESSIONS = {
    [182] = { name = "Herbalism",  category = "herbs" },
    [186] = { name = "Mining",     category = "ores" },
    [393] = { name = "Skinning",   category = "cloth" },
}

-- Column definitions for roster
local ROSTER_COLUMNS = {
    { key = "name",        label = "Character",   x = 10,  width = 140, justify = "LEFT" },
    { key = "account",     label = "Account",     x = 155, width = 110, justify = "LEFT" },
    { key = "professions", label = "Professions",  x = 270, width = 180, justify = "LEFT" },
    { key = "gathered",    label = "Gathered",    x = 455, width = 80,  justify = "RIGHT" },
    { key = "craftable",   label = "Craftable",   x = 540, width = 80,  justify = "RIGHT" },
    { key = "lastScan",    label = "Last Scan",   x = 625, width = 100, justify = "LEFT" },
}

local function OnSortClicked(field)
    if sortField == field then
        sortAscending = not sortAscending
    else
        sortField = field
        sortAscending = true
    end
    ns.EmployeesTab.Refresh()
end

function ns.EmployeesTab.Create(parent)
    contentFrame = CreateFrame("Frame", nil, parent)
    contentFrame:SetAllPoints()

    -- =====================
    -- ROSTER SECTION (top)
    -- =====================
    local rosterHeader = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    rosterHeader:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 5, -5)
    rosterHeader:SetText("Character Roster")

    -- Column headers (clickable for sorting)
    local headerRow = CreateFrame("Frame", nil, contentFrame)
    headerRow:SetSize(840, 20)
    headerRow:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -28)

    local headerBg = headerRow:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints()
    headerBg:SetColorTexture(0.15, 0.15, 0.15, 0.8)

    for _, col in ipairs(ROSTER_COLUMNS) do
        local btn = CreateFrame("Button", nil, headerRow)
        btn:SetSize(col.width, 20)
        btn:SetPoint("TOPLEFT", headerRow, "TOPLEFT", col.x, 0)

        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetAllPoints()
        label:SetJustifyH(col.justify)
        label:SetText("|cffffd100" .. col.label .. "|r")
        btn.label = label

        btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        btn:SetScript("OnClick", function()
            OnSortClicked(col.key)
        end)
    end

    -- Roster scroll area
    local rosterPane = CreateFrame("Frame", nil, contentFrame, "InsetFrameTemplate")
    rosterPane:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -50)
    rosterPane:SetPoint("RIGHT", contentFrame, "RIGHT", 0, 0)
    rosterPane:SetHeight(250)

    rosterScrollFrame = CreateFrame("ScrollFrame", "PSCEmployeesRosterScroll", rosterPane, "UIPanelScrollFrameTemplate")
    rosterScrollFrame:SetPoint("TOPLEFT", rosterPane, "TOPLEFT", 5, -5)
    rosterScrollFrame:SetPoint("BOTTOMRIGHT", rosterPane, "BOTTOMRIGHT", -26, 5)

    rosterScrollChild = CreateFrame("Frame", nil, rosterScrollFrame)
    rosterScrollChild:SetWidth(rosterScrollFrame:GetWidth() or 800)
    rosterScrollChild:SetHeight(1)
    rosterScrollFrame:SetScrollChild(rosterScrollChild)

    -- =====================
    -- MAIL LOG SECTION (bottom)
    -- =====================
    local logHeader = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    logHeader:SetPoint("TOPLEFT", rosterPane, "BOTTOMLEFT", 5, -10)
    logHeader:SetText("Mail Activity Log")

    -- Log column headers
    local logHeaderRow = CreateFrame("Frame", nil, contentFrame)
    logHeaderRow:SetSize(840, 20)
    logHeaderRow:SetPoint("TOPLEFT", rosterPane, "BOTTOMLEFT", 0, -30)

    local logHeaderBg = logHeaderRow:CreateTexture(nil, "BACKGROUND")
    logHeaderBg:SetAllPoints()
    logHeaderBg:SetColorTexture(0.15, 0.15, 0.15, 0.8)

    local logColumns = {
        { label = "Time",  x = 10,  width = 110, justify = "LEFT" },
        { label = "From",  x = 125, width = 120, justify = "LEFT" },
        { label = "To",    x = 250, width = 120, justify = "LEFT" },
        { label = "Items", x = 375, width = 460, justify = "LEFT" },
    }

    for _, col in ipairs(logColumns) do
        local label = logHeaderRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", logHeaderRow, "TOPLEFT", col.x, -3)
        label:SetWidth(col.width)
        label:SetJustifyH(col.justify)
        label:SetText("|cffffd100" .. col.label .. "|r")
    end

    -- Log scroll area
    local logPane = CreateFrame("Frame", nil, contentFrame, "InsetFrameTemplate")
    logPane:SetPoint("TOPLEFT", rosterPane, "BOTTOMLEFT", 0, -52)
    logPane:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)

    logScrollFrame = CreateFrame("ScrollFrame", "PSCEmployeesLogScroll", logPane, "UIPanelScrollFrameTemplate")
    logScrollFrame:SetPoint("TOPLEFT", logPane, "TOPLEFT", 5, -5)
    logScrollFrame:SetPoint("BOTTOMRIGHT", logPane, "BOTTOMRIGHT", -26, 5)

    logScrollChild = CreateFrame("Frame", nil, logScrollFrame)
    logScrollChild:SetWidth(logScrollFrame:GetWidth() or 800)
    logScrollChild:SetHeight(1)
    logScrollFrame:SetScrollChild(logScrollChild)

    return contentFrame
end

-- Extract character name from "Name-Realm" key
local function CharName(charKey)
    local name = charKey:match("^(.+)-")
    return name or charKey
end

local function CreateRosterRow(parent, y, entry, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(820, 22)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)

    if index % 2 == 0 then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.04)
    end

    -- Character name (class-colored with level)
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -3)
    nameText:SetWidth(135)
    nameText:SetJustifyH("LEFT")
    local displayName = string.format("Lv%d %s", entry.level or 0, CharName(entry.charKey))
    if entry.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.class] then
        local cc = RAID_CLASS_COLORS[entry.class]
        nameText:SetTextColor(cc.r, cc.g, cc.b)
    end
    nameText:SetText(displayName)

    -- Account
    local accountText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    accountText:SetPoint("TOPLEFT", row, "TOPLEFT", 155, -3)
    accountText:SetWidth(110)
    accountText:SetJustifyH("LEFT")
    local accountLabel = ns.ItemUtil.GetAccountDisplayName(entry.accountKey)
    if entry.isLocal then
        accountLabel = "|cff00cc66" .. accountLabel .. "|r"
    end
    accountText:SetText(accountLabel)

    -- Professions
    local profText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    profText:SetPoint("TOPLEFT", row, "TOPLEFT", 270, -3)
    profText:SetWidth(180)
    profText:SetJustifyH("LEFT")
    profText:SetText(entry.professionList or "-")

    -- Gathered
    local gatheredText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gatheredText:SetPoint("TOPLEFT", row, "TOPLEFT", 455, -3)
    gatheredText:SetWidth(80)
    gatheredText:SetJustifyH("RIGHT")
    if entry.gatheringTotal > 0 then
        gatheredText:SetText("|cff00cc66" .. entry.gatheringTotal .. "|r")
    else
        gatheredText:SetText("|cff888888-|r")
    end

    -- Craftable
    local craftableText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    craftableText:SetPoint("TOPLEFT", row, "TOPLEFT", 540, -3)
    craftableText:SetWidth(80)
    craftableText:SetJustifyH("RIGHT")
    if entry.craftableTotal > 0 then
        craftableText:SetText("|cffffd100" .. entry.craftableTotal .. "|r")
    else
        craftableText:SetText("|cff888888-|r")
    end

    -- Last Scan
    local scanText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scanText:SetPoint("TOPLEFT", row, "TOPLEFT", 625, -3)
    scanText:SetWidth(100)
    scanText:SetJustifyH("LEFT")
    local freshness = ns.TimeUtil.GetFreshnessState(entry.lastScan)
    local r, g, b = ns.TimeUtil.GetFreshnessColor(freshness)
    scanText:SetTextColor(r, g, b)
    scanText:SetText(ns.TimeUtil.FormatAge(entry.lastScan))

    -- Tooltip with detailed breakdown
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(entry.charKey, 1, 1, 1)
        GameTooltip:AddLine(string.format("Level %d %s", entry.level or 0, entry.class or ""), 0.7, 0.7, 0.7)
        if entry.professionDetails and #entry.professionDetails > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Professions:", 1, 0.82, 0)
            for _, prof in ipairs(entry.professionDetails) do
                GameTooltip:AddLine(string.format("  %s  Rank %d/%d", prof.name, prof.rank, prof.maxRank), 1, 1, 1)
            end
        end
        if entry.gatheringTotal > 0 and entry.gatheringItems then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Gathering Resources: " .. entry.gatheringTotal .. " total", 0, 0.8, 0.4)
            local lastProf = nil
            for _, gi in ipairs(entry.gatheringItems) do
                if gi.profession ~= lastProf then
                    GameTooltip:AddLine("  " .. gi.profession .. ":", 1, 0.82, 0)
                    lastProf = gi.profession
                end
                GameTooltip:AddLine(string.format("    %dx %s", gi.quantity, gi.itemName), 1, 1, 1)
            end
        end
        if entry.craftableTotal > 0 then
            GameTooltip:AddLine("Max Craftable (watched): " .. entry.craftableTotal, 1, 0.82, 0)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Recipes known: " .. entry.recipeCount, 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return row
end

local function CreateLogRow(parent, y, logEntry, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(820, 20)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)

    if index % 2 == 0 then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.04)
    end

    -- Time
    local timeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeText:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -3)
    timeText:SetWidth(110)
    timeText:SetJustifyH("LEFT")
    timeText:SetText(ns.TimeUtil.FormatAge(logEntry.timestamp))

    -- From
    local fromText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fromText:SetPoint("TOPLEFT", row, "TOPLEFT", 125, -3)
    fromText:SetWidth(120)
    fromText:SetJustifyH("LEFT")
    fromText:SetText(CharName(logEntry.sender))

    -- To
    local toText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toText:SetPoint("TOPLEFT", row, "TOPLEFT", 250, -3)
    toText:SetWidth(120)
    toText:SetJustifyH("LEFT")
    toText:SetText(logEntry.recipient or "?")

    -- Items
    local itemParts = {}
    for _, item in ipairs(logEntry.items or {}) do
        local name = item.itemName or ("Item " .. (item.itemID or "?"))
        itemParts[#itemParts + 1] = string.format("%dx %s", item.quantity or 0, name)
    end
    local itemsText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemsText:SetPoint("TOPLEFT", row, "TOPLEFT", 375, -3)
    itemsText:SetWidth(440)
    itemsText:SetJustifyH("LEFT")
    itemsText:SetText(table.concat(itemParts, ", "))

    -- Tooltip with full item list
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Mail Details", 1, 1, 1)
        GameTooltip:AddLine(string.format("From: %s", logEntry.sender or "?"), 0.7, 0.7, 0.7)
        GameTooltip:AddLine(string.format("To: %s", logEntry.recipient or "?"), 0.7, 0.7, 0.7)
        GameTooltip:AddLine(string.format("Sent: %s", ns.TimeUtil.FormatTimestamp(logEntry.timestamp)), 0.7, 0.7, 0.7)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Items:", 1, 0.82, 0)
        for _, item in ipairs(logEntry.items or {}) do
            local name = item.itemName or ("Item " .. (item.itemID or "?"))
            GameTooltip:AddLine(string.format("  %dx %s", item.quantity or 0, name), 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return row
end

function ns.EmployeesTab.Refresh()
    if not contentFrame then return end

    -- Clear old rows
    for _, row in ipairs(rosterRows) do
        row:Hide()
        row:SetParent(nil)
    end
    wipe(rosterRows)
    for _, row in ipairs(logRows) do
        row:Hide()
        row:SetParent(nil)
    end
    wipe(logRows)

    -- =====================
    -- BUILD CHARACTER DATA
    -- =====================
    local characters = {}

    -- Cache MaxCraftable results to avoid redundant computation
    local craftableCache = {}

    ns.Repository.IterateAllCharacters(function(charKey, charData, accountKey, isLocal)
        local entry = {
            charKey = charKey,
            accountKey = accountKey,
            isLocal = isLocal,
            class = charData.class,
            level = charData.level or 0,
            lastScan = charData.lastScan,
            professionList = "",
            professionDetails = {},
            gatheringTotal = 0,
            gatheringItems = {},  -- { {itemID, itemName, quantity, profession}, ... }
            craftableTotal = 0,
            recipeCount = ns.TableUtil.Count(charData.recipes or {}),
        }

        -- Gather profession info
        local profNames = {}
        if charData.professions then
            for profID, profData in pairs(charData.professions) do
                profNames[#profNames + 1] = profData.name or "?"
                entry.professionDetails[#entry.professionDetails + 1] = {
                    name = profData.name or "?",
                    rank = profData.rank or 0,
                    maxRank = profData.maxRank or 0,
                }
            end
        end
        table.sort(profNames)
        entry.professionList = #profNames > 0 and table.concat(profNames, ", ") or "-"

        -- Calculate gathering totals with per-item breakdown
        if charData.professions and charData.inventory then
            for profID, catInfo in pairs(GATHERING_PROFESSIONS) do
                if charData.professions[profID] then
                    for itemID, invEntry in pairs(charData.inventory) do
                        if ns.InventoryTab.CategorizeItem(itemID) == catInfo.category then
                            local qty = invEntry.total or 0
                            if qty > 0 then
                                entry.gatheringTotal = entry.gatheringTotal + qty
                                entry.gatheringItems[#entry.gatheringItems + 1] = {
                                    itemID = itemID,
                                    itemName = ns.ItemUtil.GetItemName(itemID),
                                    quantity = qty,
                                    profession = catInfo.name,
                                }
                            end
                        end
                    end
                end
            end
            -- Sort by profession then quantity descending
            table.sort(entry.gatheringItems, function(a, b)
                if a.profession ~= b.profession then
                    return a.profession < b.profession
                end
                return a.quantity > b.quantity
            end)
        end

        -- Calculate max craftable for watched recipes this character knows
        if charData.recipes and ns.DB.watchedRecipes then
            for recipeID in pairs(ns.DB.watchedRecipes) do
                if charData.recipes[recipeID] then
                    if not craftableCache[recipeID] then
                        local result = ns.MaxCraftable.Calculate(recipeID)
                        craftableCache[recipeID] = result.maxCraftable or 0
                    end
                    entry.craftableTotal = entry.craftableTotal + craftableCache[recipeID]
                end
            end
        end

        characters[#characters + 1] = entry
    end)

    -- Sort characters
    table.sort(characters, function(a, b)
        local valA, valB
        if sortField == "name" then
            valA = a.charKey:lower()
            valB = b.charKey:lower()
        elseif sortField == "account" then
            valA = a.accountKey
            valB = b.accountKey
        elseif sortField == "professions" then
            valA = a.professionList:lower()
            valB = b.professionList:lower()
        elseif sortField == "gathered" then
            valA = a.gatheringTotal
            valB = b.gatheringTotal
        elseif sortField == "craftable" then
            valA = a.craftableTotal
            valB = b.craftableTotal
        elseif sortField == "lastScan" then
            valA = a.lastScan or 0
            valB = b.lastScan or 0
        else
            valA = a.charKey:lower()
            valB = b.charKey:lower()
        end
        if sortAscending then
            return valA < valB
        else
            return valA > valB
        end
    end)

    -- Render roster rows
    if #characters == 0 then
        local emptyText = rosterScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        emptyText:SetPoint("CENTER", rosterScrollChild, "CENTER", 0, 0)
        emptyText:SetText("|cff888888No characters scanned yet. Log in to each character to scan.|r")
        local emptyFrame = CreateFrame("Frame", nil, rosterScrollChild)
        emptyFrame:SetSize(1, 1)
        rosterRows[1] = emptyFrame
        rosterScrollChild:SetHeight(50)
    else
        local y = 0
        for i, entry in ipairs(characters) do
            local row = CreateRosterRow(rosterScrollChild, y, entry, i)
            rosterRows[#rosterRows + 1] = row
            y = y - 22
        end
        rosterScrollChild:SetHeight(math.max(1, math.abs(y)))
    end

    -- =====================
    -- RENDER MAIL LOG
    -- =====================
    local mailLog = ns.DB.mailLog or {}

    if #mailLog == 0 then
        local emptyText = logScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        emptyText:SetPoint("CENTER", logScrollChild, "CENTER", 0, 0)
        emptyText:SetText("|cff888888No mail activity recorded. Use the mailbox Fill button to track sends.|r")
        local emptyFrame = CreateFrame("Frame", nil, logScrollChild)
        emptyFrame:SetSize(1, 1)
        logRows[1] = emptyFrame
        logScrollChild:SetHeight(50)
    else
        local y = 0
        local count = 0
        -- Show newest first
        for i = #mailLog, 1, -1 do
            count = count + 1
            local row = CreateLogRow(logScrollChild, y, mailLog[i], count)
            logRows[#logRows + 1] = row
            y = y - 20
        end
        logScrollChild:SetHeight(math.max(1, math.abs(y)))
    end
end
