local ADDON_NAME, ns = ...

ns.RecipesTab = {}

local contentFrame = nil
local leftPane = nil
local rightPane = nil
local recipeButtons = {}
local selectedRecipeID = nil
local searchBox = nil
local detailLabels = {}

function ns.RecipesTab.Create(parent)
    contentFrame = CreateFrame("Frame", nil, parent)
    contentFrame:SetAllPoints()

    -- Left pane (recipe list)
    leftPane = CreateFrame("Frame", nil, contentFrame, "InsetFrameTemplate")
    leftPane:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
    leftPane:SetSize(250, 470)

    -- Search box
    searchBox = CreateFrame("EditBox", "PSCRecipeSearch", leftPane, "InputBoxTemplate")
    searchBox:SetSize(210, 20)
    searchBox:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 15, -10)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(self)
        ns.RecipesTab.RefreshRecipeList()
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    -- Scroll frame for recipe list
    local scrollFrame = CreateFrame("ScrollFrame", "PSCRecipeListScroll", leftPane, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 5, -38)
    scrollFrame:SetPoint("BOTTOMRIGHT", leftPane, "BOTTOMRIGHT", -26, 5)

    leftPane.listArea = CreateFrame("Frame", nil, scrollFrame)
    leftPane.listArea:SetWidth(scrollFrame:GetWidth() or 210)
    leftPane.listArea:SetHeight(1) -- will be resized dynamically
    scrollFrame:SetScrollChild(leftPane.listArea)
    leftPane.scrollFrame = scrollFrame

    -- Right pane (recipe detail)
    rightPane = CreateFrame("Frame", nil, contentFrame, "InsetFrameTemplate")
    rightPane:SetPoint("TOPLEFT", leftPane, "TOPRIGHT", 5, 0)
    rightPane:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)

    local y = -10
    detailLabels.recipeName = ns.RecipesTab.CreateDetailLabel(rightPane, y, "Select a recipe")
    y = y - 25

    detailLabels.output = ns.RecipesTab.CreateDetailLabel(rightPane, y, "")
    y = y - 20
    detailLabels.maxCraftable = ns.RecipesTab.CreateDetailLabel(rightPane, y, "")
    y = y - 30

    detailLabels.reagentHeader = ns.RecipesTab.CreateDetailLabel(rightPane, y, "|cffffd100Direct Reagents|r")
    y = y - 20
    detailLabels.reagents = ns.RecipesTab.CreateDetailLabel(rightPane, y, "")
    y = y - 80

    detailLabels.crafterHeader = ns.RecipesTab.CreateDetailLabel(rightPane, y, "|cffffd100Eligible Crafters|r")
    y = y - 20
    detailLabels.crafters = ns.RecipesTab.CreateDetailLabel(rightPane, y, "")
    y = y - 40

    detailLabels.bottleneckHeader = ns.RecipesTab.CreateDetailLabel(rightPane, y, "|cffffd100Bottlenecks|r")
    y = y - 20
    detailLabels.bottlenecks = ns.RecipesTab.CreateDetailLabel(rightPane, y, "")
    y = y - 60

    -- Watch/unwatch button
    local watchBtn = CreateFrame("Button", nil, rightPane, "UIPanelButtonTemplate")
    watchBtn:SetSize(120, 24)
    watchBtn:SetPoint("BOTTOMRIGHT", rightPane, "BOTTOMRIGHT", -10, 10)
    watchBtn:SetText("Watch Recipe")
    watchBtn:SetScript("OnClick", function()
        if selectedRecipeID then
            local isWatched = ns.Repository.IsWatched(selectedRecipeID)
            ns.Repository.SetWatched(selectedRecipeID, not isWatched)
            ns.RecipesTab.RefreshDetail()
            ns.RecipesTab.RefreshRecipeList()
        end
    end)
    detailLabels.watchBtn = watchBtn

    return contentFrame
end

function ns.RecipesTab.CreateDetailLabel(parent, y, text)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y)
    label:SetJustifyH("LEFT")
    label:SetWidth(480)
    label:SetText(text)
    return label
end

function ns.RecipesTab.Refresh()
    ns.RecipesTab.RefreshRecipeList()
    if selectedRecipeID then
        ns.RecipesTab.RefreshDetail()
    end
end

function ns.RecipesTab.RefreshRecipeList()
    if not contentFrame then return end

    -- Clear old buttons
    for _, btn in ipairs(recipeButtons) do
        btn:Hide()
        btn:SetParent(nil)
    end
    wipe(recipeButtons)

    local searchText = searchBox and searchBox:GetText():lower() or ""
    local y = 0
    local allRecipes = ns.RecipeGraph.GetAllRecipes()

    -- Show watched recipes first
    for recipeID in pairs(ns.DB.watchedRecipes) do
        local recipe = allRecipes[recipeID]
        if recipe then
            local name = recipe.recipeName or ("Recipe #" .. recipeID)
            if searchText == "" or name:lower():find(searchText, 1, true) then
                local btn = ns.RecipesTab.CreateRecipeButton(leftPane.listArea, y, recipeID, "|cff00cc66★|r " .. name)
                recipeButtons[#recipeButtons + 1] = btn
                y = y - 20
            end
        end
    end

    -- Then other recipes
    for recipeID, recipe in pairs(allRecipes) do
        if not ns.Repository.IsWatched(recipeID) then
            local name = recipe.recipeName or ("Recipe #" .. recipeID)
            if searchText == "" or name:lower():find(searchText, 1, true) then
                local btn = ns.RecipesTab.CreateRecipeButton(leftPane.listArea, y, recipeID, name)
                recipeButtons[#recipeButtons + 1] = btn
                y = y - 20
            end
        end
    end

    -- Resize scroll child to fit all buttons
    leftPane.listArea:SetHeight(math.max(1, math.abs(y)))
end

function ns.RecipesTab.CreateRecipeButton(parent, y, recipeID, label)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(230, 18)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, y)

    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetAllPoints()
    text:SetJustifyH("LEFT")
    text:SetText(label)

    btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    btn:SetScript("OnClick", function()
        selectedRecipeID = recipeID
        ns.RecipesTab.RefreshDetail()
    end)

    return btn
end

function ns.RecipesTab.RefreshDetail()
    if not selectedRecipeID then return end

    local recipe = ns.RecipeGraph.GetRecipe(selectedRecipeID)
    if not recipe then
        detailLabels.recipeName:SetText("Recipe not found")
        return
    end

    detailLabels.recipeName:SetText("|cffffd100" .. (recipe.recipeName or "?") .. "|r")

    -- Output
    local outputName = recipe.outputItemID and ns.ItemUtil.GetItemName(recipe.outputItemID) or "Unknown"
    detailLabels.output:SetText(string.format("Output: %s x%d", outputName, recipe.outputQuantity or 1))

    -- Max craftable
    local result = ns.MaxCraftable.Calculate(selectedRecipeID)
    detailLabels.maxCraftable:SetText(string.format("|cff00ff00Estimated max craftable: %d|r", result.maxCraftable))

    -- Reagents
    local reagentLines = {}
    if recipe.reagents then
        for _, reagent in ipairs(recipe.reagents) do
            local name = ns.ItemUtil.GetItemName(reagent.itemID)
            local have = ns.InventoryIndex.GetTotal(reagent.itemID)
            local color = have >= reagent.quantity and "|cff00ff00" or "|cffff0000"
            reagentLines[#reagentLines + 1] = string.format("  %s x%d — have %s%d|r",
                name, reagent.quantity, color, have)
        end
    end
    detailLabels.reagents:SetText(#reagentLines > 0 and table.concat(reagentLines, "\n") or "  No reagents")

    -- Crafters
    local crafters = ns.Merge.GetRecipeOwners(selectedRecipeID)
    local crafterText = #crafters > 0 and ("  " .. table.concat(crafters, ", ")) or "  No characters know this recipe"
    detailLabels.crafters:SetText(crafterText)

    -- Bottlenecks
    local bottlenecks = ns.Bottlenecks.GetForRecipe(selectedRecipeID)
    local bottleneckLines = {}
    for _, bn in ipairs(bottlenecks) do
        bottleneckLines[#bottleneckLines + 1] = "  " .. bn.message
    end
    detailLabels.bottlenecks:SetText(#bottleneckLines > 0 and table.concat(bottleneckLines, "\n") or "  None")

    -- Watch button
    local isWatched = ns.Repository.IsWatched(selectedRecipeID)
    detailLabels.watchBtn:SetText(isWatched and "Unwatch" or "Watch Recipe")
end

---------------------------------------------------------------------------
-- PSC Watch Button on Blizzard's Profession Frame
---------------------------------------------------------------------------

local pscWatchButton = nil
local pscHooked = false
local lastKnownRecipeID = nil

function ns.RecipesTab.HookProfessionFrame()
    if pscHooked then return end

    local profFrame = ProfessionsFrame
    if not profFrame then
        ns.Debug("ProfessionsFrame not found")
        return
    end

    -- Create the watch toggle button anchored to bottom-right of the crafting page
    local craftingPage = profFrame.CraftingPage
    local anchorFrame = craftingPage and craftingPage.SchematicForm or profFrame

    pscWatchButton = CreateFrame("Button", "PSCWatchButton", anchorFrame, "UIPanelButtonTemplate")
    pscWatchButton:SetSize(150, 22)
    pscWatchButton:SetFrameStrata("DIALOG")
    pscWatchButton:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", -8, 8)
    pscWatchButton:SetText("PSC: Watch Recipe")
    pscWatchButton:SetNormalFontObject("GameFontNormalSmall")

    pscWatchButton:SetScript("OnClick", function()
        local recipeID = ns.RecipesTab.GetCurrentRecipeID()
        if not recipeID then
            ns.Print("Select a recipe first.")
            return
        end

        local isWatched = ns.Repository.IsWatched(recipeID)
        ns.Repository.SetWatched(recipeID, not isWatched)
        ns.RecipesTab.UpdateWatchButton()

        local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
        local name = recipeInfo and recipeInfo.name or ("Recipe #" .. recipeID)
        if not isWatched then
            ns.Print("|cff00cc66+|r Added to watch list: %s", name)
        else
            ns.Print("|cffff4444-|r Removed from watch list: %s", name)
        end

        -- Rebuild graph and merge so Actions tab picks it up immediately
        ns.RecipeGraph.Rebuild()
        ns.Merge.RebuildIndex()
    end)

    pscWatchButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        local recipeID = ns.RecipesTab.GetCurrentRecipeID()
        if recipeID and ns.Repository.IsWatched(recipeID) then
            GameTooltip:SetText("|cff00cc66Watching|r — Click to remove", 1, 1, 1)
        else
            GameTooltip:SetText("Watch in Supply Chain", 1, 1, 1)
        end
        GameTooltip:AddLine("Adds this recipe to your PSC planner.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("Does NOT affect the objectives tracker.", 0.5, 0.5, 0.5, true)
        GameTooltip:Show()
    end)

    pscWatchButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Poll for recipe selection changes (simple and reliable)
    local elapsed = 0
    pscWatchButton:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 0.3 then return end
        elapsed = 0

        local recipeID = ns.RecipesTab.GetCurrentRecipeID()
        if recipeID ~= lastKnownRecipeID then
            lastKnownRecipeID = recipeID
            ns.RecipesTab.UpdateWatchButton()
        end
    end)

    pscHooked = true
    ns.RecipesTab.UpdateWatchButton()
    ns.Debug("PSC watch button added to profession frame")
end

function ns.RecipesTab.GetCurrentRecipeID()
    local profFrame = ProfessionsFrame
    if not profFrame or not profFrame.CraftingPage then return nil end

    -- Try SchematicForm.currentRecipeInfo
    local schematicForm = profFrame.CraftingPage.SchematicForm
    if schematicForm then
        if schematicForm.currentRecipeInfo and schematicForm.currentRecipeInfo.recipeID then
            return schematicForm.currentRecipeInfo.recipeID
        end
        -- Try transaction
        if schematicForm.transaction then
            local ok, schematic = pcall(function()
                return schematicForm.transaction:GetRecipeSchematic()
            end)
            if ok and schematic and schematic.recipeID then
                return schematic.recipeID
            end
        end
    end

    return nil
end

function ns.RecipesTab.UpdateWatchButton()
    if not pscWatchButton then return end

    local recipeID = ns.RecipesTab.GetCurrentRecipeID()
    if not recipeID then
        pscWatchButton:SetText("PSC: Watch Recipe")
        pscWatchButton:Disable()
        ns.RecipesTab.UpdateProfessionSimPanel(nil)
        return
    end

    pscWatchButton:Enable()
    if ns.Repository.IsWatched(recipeID) then
        pscWatchButton:SetText("|cff00cc66PSC: Watching|r")
    else
        pscWatchButton:SetText("PSC: Watch Recipe")
    end

    -- Update simulation panel for this recipe
    ns.RecipesTab.UpdateProfessionSimPanel(recipeID)
end

---------------------------------------------------------------------------
-- Simulation Info Panel on Profession Frame
---------------------------------------------------------------------------

local simPanel = nil

function ns.RecipesTab.CreateSimPanel(anchorFrame)
    simPanel = CreateFrame("Frame", "PSCSimPanel", anchorFrame, "InsetFrameTemplate")
    simPanel:SetSize(200, 95)
    simPanel:SetPoint("BOTTOMLEFT", anchorFrame, "BOTTOMLEFT", 8, 8)
    simPanel:SetFrameStrata("DIALOG")

    local title = simPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", simPanel, "TOPLEFT", 8, -6)
    title:SetText("|cffffd100PSC Simulation|r")

    simPanel.profitLabel = simPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    simPanel.profitLabel:SetPoint("TOPLEFT", simPanel, "TOPLEFT", 8, -22)
    simPanel.profitLabel:SetWidth(184)
    simPanel.profitLabel:SetJustifyH("LEFT")

    simPanel.costLabel = simPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    simPanel.costLabel:SetPoint("TOPLEFT", simPanel, "TOPLEFT", 8, -36)
    simPanel.costLabel:SetWidth(184)
    simPanel.costLabel:SetJustifyH("LEFT")

    simPanel.rawLabel = simPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    simPanel.rawLabel:SetPoint("TOPLEFT", simPanel, "TOPLEFT", 8, -50)
    simPanel.rawLabel:SetWidth(184)
    simPanel.rawLabel:SetJustifyH("LEFT")

    simPanel.verdictLabel = simPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    simPanel.verdictLabel:SetPoint("TOPLEFT", simPanel, "TOPLEFT", 8, -66)
    simPanel.verdictLabel:SetWidth(184)
    simPanel.verdictLabel:SetJustifyH("LEFT")

    simPanel.maxLabel = simPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    simPanel.maxLabel:SetPoint("TOPLEFT", simPanel, "TOPLEFT", 8, -80)
    simPanel.maxLabel:SetWidth(184)
    simPanel.maxLabel:SetJustifyH("LEFT")

    simPanel:Hide()
end

function ns.RecipesTab.UpdateProfessionSimPanel(recipeID)
    if not simPanel then
        local profFrame = ProfessionsFrame
        if not profFrame then return end
        local anchorFrame = profFrame.CraftingPage and profFrame.CraftingPage.SchematicForm or profFrame
        ns.RecipesTab.CreateSimPanel(anchorFrame)
    end

    if not recipeID then
        simPanel:Hide()
        return
    end

    -- Only show for watched recipes
    if not ns.Repository.IsWatched(recipeID) then
        simPanel:Hide()
        return
    end

    -- Try to get CraftSim data
    if not ns.CraftSimAdapter.IsAvailable() then
        simPanel.profitLabel:SetText("|cff888888CraftSim not available|r")
        simPanel.costLabel:SetText("")
        simPanel.rawLabel:SetText("")
        simPanel.verdictLabel:SetText("")
        simPanel.maxLabel:SetText("")
        simPanel:Show()
        return
    end

    local optimized = ns.CraftSimAdapter.GetOptimizedRecipeForProfit(recipeID)
    if not optimized then
        simPanel.profitLabel:SetText("|cff888888No sim data|r")
        simPanel.costLabel:SetText("")
        simPanel.rawLabel:SetText("")
        simPanel.verdictLabel:SetText("")
        simPanel.maxLabel:SetText("")
        simPanel:Show()
        return
    end

    -- Profit + quality
    local profit = optimized.profit or 0
    local profitColor = profit >= 0 and "|cff00cc66" or "|cffff4444"
    local tqIcon = optimized.targetQuality and optimized.targetQuality > 0
        and (" " .. ns.ItemUtil.GetQualityIcon(optimized.targetQuality, 12)) or ""
    simPanel.profitLabel:SetText(string.format("Profit/craft%s: %s%s|r",
        tqIcon, profitColor, GetCoinTextureString(math.abs(profit))))

    -- Cost
    simPanel.costLabel:SetText(string.format("Cost: %s",
        GetCoinTextureString(optimized.craftingCost or 0)))

    -- Raw sell value
    local rawSell = 0
    if ns.TSMAdapter.IsAvailable() and optimized.reagents then
        for _, alloc in ipairs(optimized.reagents) do
            local unitPrice = ns.TSMAdapter.GetItemValue(alloc.itemID, "DBMarket") or 0
            rawSell = rawSell + (unitPrice * alloc.quantity)
        end
    end

    if rawSell > 0 then
        simPanel.rawLabel:SetText(string.format("Raw sell: %s", GetCoinTextureString(rawSell)))
        if profit > rawSell then
            simPanel.verdictLabel:SetText("|cff00cc66Craft is better|r")
        elseif rawSell > profit then
            simPanel.verdictLabel:SetText("|cffff4444Sell raw is better|r")
        else
            simPanel.verdictLabel:SetText("|cffffff00Break even|r")
        end
    else
        simPanel.rawLabel:SetText("")
        simPanel.verdictLabel:SetText("")
    end

    -- Max craftable
    local graphRecipe = ns.RecipeGraph.GetRecipe(recipeID)
    if graphRecipe then
        local maxResult = ns.MaxCraftable.Calculate(recipeID)
        simPanel.maxLabel:SetText(string.format("Max craftable: %d", maxResult.maxCraftable))
    else
        simPanel.maxLabel:SetText("")
    end

    simPanel:Show()
end
