local ADDON_NAME, ns = ...

ns.AccountsTab = {}

local contentFrame = nil
local leftPane = nil
local rightPane = nil
local accountButtons = {}
local selectedAccountKey = nil
local selectedCharKey = nil
local detailLabels = {}

function ns.AccountsTab.Create(parent)
    contentFrame = CreateFrame("Frame", nil, parent)
    contentFrame:SetAllPoints()

    -- Left pane (account/character list)
    leftPane = CreateFrame("Frame", nil, contentFrame, "InsetFrameTemplate")
    leftPane:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
    leftPane:SetSize(220, 470)

    -- Right pane (character details)
    rightPane = CreateFrame("Frame", nil, contentFrame, "InsetFrameTemplate")
    rightPane:SetPoint("TOPLEFT", leftPane, "TOPRIGHT", 5, 0)
    rightPane:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)

    -- Detail labels in right pane
    local y = -10
    detailLabels.charName = ns.AccountsTab.CreateDetailLabel(rightPane, y, "Select a character")
    y = y - 30
    detailLabels.account = ns.AccountsTab.CreateDetailLabel(rightPane, y, "")
    y = y - 20
    detailLabels.level = ns.AccountsTab.CreateDetailLabel(rightPane, y, "")
    y = y - 20
    detailLabels.faction = ns.AccountsTab.CreateDetailLabel(rightPane, y, "")
    y = y - 20
    detailLabels.gold = ns.AccountsTab.CreateDetailLabel(rightPane, y, "")
    y = y - 20
    detailLabels.lastScan = ns.AccountsTab.CreateDetailLabel(rightPane, y, "")
    y = y - 30

    detailLabels.profHeader = ns.AccountsTab.CreateDetailLabel(rightPane, y, "|cffffd100Professions & Specializations|r")
    y = y - 20
    detailLabels.professions = ns.AccountsTab.CreateDetailLabel(rightPane, y, "")
    y = y - 180

    detailLabels.invHeader = ns.AccountsTab.CreateDetailLabel(rightPane, y, "|cffffd100Inventory Summary|r")
    y = y - 20
    detailLabels.inventory = ns.AccountsTab.CreateDetailLabel(rightPane, y, "")
    y = y - 40

    detailLabels.recipeHeader = ns.AccountsTab.CreateDetailLabel(rightPane, y, "|cffffd100Recipes|r")
    y = y - 20
    detailLabels.recipeCount = ns.AccountsTab.CreateDetailLabel(rightPane, y, "")

    return contentFrame
end

function ns.AccountsTab.CreateDetailLabel(parent, y, text)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y)
    label:SetJustifyH("LEFT")
    label:SetWidth(520)
    label:SetText(text)
    return label
end

function ns.AccountsTab.Refresh()
    if not contentFrame then return end

    -- Clear old buttons
    for _, btn in ipairs(accountButtons) do
        btn:Hide()
        btn:SetParent(nil)
    end
    wipe(accountButtons)

    local y = -10
    local accountKeys = ns.Repository.GetAllAccountKeys()

    for _, accountKey in ipairs(accountKeys) do
        local isLocal = accountKey == ns.DB.localAccount.accountKey
        local label = isLocal and ("|cff00cc66[Local]|r " .. accountKey) or accountKey

        -- Account header button
        local accountBtn = CreateFrame("Button", nil, leftPane, "UIPanelButtonTemplate")
        accountBtn:SetSize(200, 20)
        accountBtn:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 10, y)
        accountBtn:SetText(label)
        accountBtn:SetNormalFontObject("GameFontNormalSmall")
        accountBtn:SetScript("OnClick", function()
            selectedAccountKey = accountKey
            selectedCharKey = nil
            ns.AccountsTab.Refresh()
        end)
        accountButtons[#accountButtons + 1] = accountBtn
        y = y - 24

        -- Character buttons under this account
        if selectedAccountKey == accountKey then
            local characters = ns.Repository.GetCharactersForAccount(accountKey)
            for charKey, charData in pairs(characters) do
                local freshness = ns.TimeUtil.GetFreshnessState(charData.lastScan)
                local r, g, b = ns.TimeUtil.GetFreshnessColor(freshness)
                local colorHex = string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)

                local charBtn = CreateFrame("Button", nil, leftPane, "UIPanelButtonTemplate")
                charBtn:SetSize(180, 18)
                charBtn:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 25, y)
                charBtn:SetText(colorHex .. charKey .. "|r")
                charBtn:SetNormalFontObject("GameFontNormalSmall")
                charBtn:SetScript("OnClick", function()
                    selectedCharKey = charKey
                    ns.AccountsTab.ShowCharacterDetail(charKey, charData, accountKey)
                end)
                accountButtons[#accountButtons + 1] = charBtn
                y = y - 20
            end
        end

        y = y - 4
    end

    -- Show selected character detail
    if selectedCharKey then
        local charData = nil
        if selectedAccountKey == ns.DB.localAccount.accountKey then
            charData = ns.DB.localScans.characters[selectedCharKey]
        else
            local snapshot = ns.DB.networkSnapshots[selectedAccountKey]
            if snapshot and snapshot.characters then
                charData = snapshot.characters[selectedCharKey]
            end
        end
        if charData then
            ns.AccountsTab.ShowCharacterDetail(selectedCharKey, charData, selectedAccountKey)
        end
    end
end

function ns.AccountsTab.ShowCharacterDetail(charKey, charData, accountKey)
    detailLabels.charName:SetText("|cffffd100" .. charKey .. "|r")
    detailLabels.account:SetText("Account: " .. (accountKey or "?"))
    detailLabels.level:SetText(string.format("Level %d %s", charData.level or 0, charData.class or "?"))
    detailLabels.faction:SetText("Faction: " .. (charData.faction or "?"))
    detailLabels.gold:SetText(string.format("Gold: %s", GetCoinTextureString(charData.gold or 0)))
    detailLabels.lastScan:SetText("Last Scan: " .. ns.TimeUtil.FormatAge(charData.lastScan))

    -- Professions + Specializations
    local profLines = {}
    if charData.professions then
        for profID, profData in pairs(charData.professions) do
            profLines[#profLines + 1] = string.format("  |cffffd100%s|r — Rank %d/%d",
                profData.name or "?", profData.rank or 0, profData.maxRank or 0)

            -- Show specializations if scanned
            if profData.specializations and #profData.specializations > 0 then
                for _, spec in ipairs(profData.specializations) do
                    local pointsColor = spec.pointsSpent > 0 and "|cff00cc66" or "|cff888888"
                    profLines[#profLines + 1] = string.format("      %s%s|r — %d pts",
                        pointsColor, spec.name or "?", spec.pointsSpent or 0)

                    -- Show child specializations
                    if spec.children then
                        for _, child in ipairs(spec.children) do
                            if child.pointsSpent > 0 then
                                profLines[#profLines + 1] = string.format("          %s — %d pts",
                                    child.name or "?", child.pointsSpent or 0)
                            end
                        end
                    end
                end
            else
                profLines[#profLines + 1] = "      |cff888888Open profession window to scan specs|r"
            end
        end
    end
    detailLabels.professions:SetText(#profLines > 0 and table.concat(profLines, "\n") or "  None scanned")

    -- Inventory summary
    local itemCount = charData.inventory and ns.TableUtil.Count(charData.inventory) or 0
    local flags = charData.scanFlags or {}
    detailLabels.inventory:SetText(string.format(
        "  Unique items: %d\n  Bags: %s | Bank: %s | Reagent Bank: %s",
        itemCount,
        flags.bags and "|cff00ff00Yes|r" or "|cffff0000No|r",
        flags.bank and "|cff00ff00Yes|r" or "|cffff0000No|r",
        flags.reagentBank and "|cff00ff00Yes|r" or "|cffff0000No|r"
    ))

    -- Recipe count
    local recipeCount = charData.recipes and ns.TableUtil.Count(charData.recipes) or 0
    detailLabels.recipeCount:SetText("  Learned recipes: " .. recipeCount)
end
