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
            -- Recipes are watched but no actions generated — explain why
            local lines = { string.format("%d watched recipe(s), but no actions to suggest.\n", watchedCount) }
            for recipeID in pairs(ns.DB.watchedRecipes) do
                local recipe = ns.RecipeGraph.GetRecipe(recipeID)
                if not recipe then
                    lines[#lines + 1] = string.format("  |cffff4444Recipe #%d:|r Not in recipe graph — open the profession window to scan it.", recipeID)
                else
                    local icon = ns.ItemUtil.GetIconString(recipe.outputItemID, 14)
                    local crafters = ns.Merge.GetRecipeOwners(recipeID)
                    local result = ns.MaxCraftable.Calculate(recipeID)
                    if #crafters == 0 then
                        lines[#lines + 1] = string.format("  %s |cffff4444%s:|r No character knows this recipe.", icon, recipe.recipeName or "?")
                    elseif not recipe.reagents or #recipe.reagents == 0 then
                        lines[#lines + 1] = string.format("  %s |cffffff00%s:|r No reagent data — reopen profession to rescan.", icon, recipe.recipeName or "?")
                    elseif result.maxCraftable > 0 then
                        lines[#lines + 1] = string.format("  %s |cff00cc66%s:|r Can craft %d — all materials already on crafter.", icon, recipe.recipeName or "?", result.maxCraftable)
                    else
                        lines[#lines + 1] = string.format("  %s |cffffff00%s:|r Missing materials, no transfers possible.", icon, recipe.recipeName or "?")
                    end
                end
            end
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
