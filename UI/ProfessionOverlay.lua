local ADDON_NAME, ns = ...

ns.ProfessionOverlay = {}

local overlayFrame = nil
local actionRows = {}
local concGlow = nil
local hooked = false
local lastSelectedRecipeID = nil

-- Blizzard frame paths
local CONC_TOGGLE_PATH = {
    "ProfessionsFrame", "CraftingPage", "SchematicForm", "Details",
    "CraftingChoicesContainer", "ConcentrateContainer", "ConcentrateToggleButton"
}

-- ============================================================================
-- Initialization
-- ============================================================================

function ns.ProfessionOverlay.Initialize()
    ns.Events.Register("TRADE_SKILL_SHOW", function()
        C_Timer.After(0.6, function()
            ns.ProfessionOverlay.Hook()
            ns.ProfessionOverlay.Refresh()
        end)
    end, "ProfessionOverlay")

    ns.Events.Register("TRADE_SKILL_CLOSE", function()
        ns.ProfessionOverlay.Hide()
    end, "ProfessionOverlayClose")
end

-- ============================================================================
-- Hook into profession frame
-- ============================================================================

function ns.ProfessionOverlay.Hook()
    if hooked then return end

    local profFrame = ProfessionsFrame
    if not profFrame then return end

    -- Create overlay panel anchored to right side of profession frame
    overlayFrame = CreateFrame("Frame", "PSCProfessionOverlay", profFrame, "BackdropTemplate")
    overlayFrame:SetSize(260, 200)
    overlayFrame:SetFrameStrata("DIALOG")
    overlayFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    overlayFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.95)

    -- Draggable
    overlayFrame:SetMovable(true)
    overlayFrame:EnableMouse(true)
    overlayFrame:RegisterForDrag("LeftButton")
    overlayFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    overlayFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        if ns.DB and ns.DB.settings then
            ns.DB.settings.overlayPosition = { point, relPoint, x, y }
        end
    end)

    -- Restore saved position or default to top-right of profession frame
    local pos = ns.DB and ns.DB.settings and ns.DB.settings.overlayPosition
    if pos then
        overlayFrame:ClearAllPoints()
        overlayFrame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        overlayFrame:SetPoint("TOPLEFT", profFrame, "TOPRIGHT", 4, 0)
    end

    -- Title
    local title = overlayFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", 10, -8)
    title:SetText("|cff00cc66PSC|r Action Plan")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, overlayFrame, "UIPanelCloseButtonNoScripts")
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", overlayFrame, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
        overlayFrame:Hide()
    end)

    -- Poll for recipe selection changes (to update concentration glow)
    local elapsed = 0
    overlayFrame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 0.3 then return end
        elapsed = 0

        local recipeID = ns.RecipesTab.GetCurrentRecipeID()
        if recipeID ~= lastSelectedRecipeID then
            lastSelectedRecipeID = recipeID
            ns.ProfessionOverlay.UpdateConcentrationGlow()
        end
    end)

    hooked = true
    ns.Debug("ProfessionOverlay: hooked to profession frame")
end

-- ============================================================================
-- Resolve a Blizzard frame path safely
-- ============================================================================

local function resolveFramePath(pathParts)
    local frame = _G[pathParts[1]]
    if not frame then return nil end
    for i = 2, #pathParts do
        frame = frame[pathParts[i]]
        if not frame then return nil end
    end
    return frame
end

-- ============================================================================
-- Concentration Glow
-- ============================================================================

local function createConcGlow(parent)
    if concGlow then
        concGlow:SetParent(parent)
        concGlow:ClearAllPoints()
        concGlow:SetAllPoints(parent)
        return concGlow
    end

    concGlow = CreateFrame("Frame", nil, parent)
    concGlow:SetAllPoints(parent)
    concGlow:SetFrameLevel(parent:GetFrameLevel() + 5)

    -- Use Blizzard's ActionButtonOverlayGlow
    local ag = concGlow:CreateAnimationGroup()
    local glow = concGlow:CreateTexture(nil, "OVERLAY")
    glow:SetAllPoints()
    glow:SetAtlas("bags-glow-flash")
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0)

    local fadeIn = ag:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(0.6)
    fadeIn:SetDuration(0.5)
    fadeIn:SetOrder(1)

    local fadeOut = ag:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(0.6)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(0.5)
    fadeOut:SetOrder(2)

    ag:SetLooping("REPEAT")

    concGlow.glow = glow
    concGlow.anim = ag

    return concGlow
end

function ns.ProfessionOverlay.UpdateConcentrationGlow()
    local concToggle = resolveFramePath(CONC_TOGGLE_PATH)
    if not concToggle then
        if concGlow then concGlow:Hide() end
        return
    end

    local recipeID = lastSelectedRecipeID
    if not recipeID then
        if concGlow then concGlow:Hide() end
        return
    end

    -- Check if this recipe has a concentration action in the plan
    local shouldGlow = false
    local actions = ns.ProfessionOverlay.GetCurrentCharacterActions()
    for _, action in ipairs(actions) do
        if action.recipeID == recipeID and action.useConcentration then
            shouldGlow = true
            break
        end
    end

    if shouldGlow then
        local glow = createConcGlow(concToggle)
        glow:Show()
        glow.glow:SetAlpha(0)
        glow.anim:Play()
    else
        if concGlow then
            concGlow.anim:Stop()
            concGlow:Hide()
        end
    end
end

-- ============================================================================
-- Get actions for the current character's open profession
-- ============================================================================

function ns.ProfessionOverlay.GetCurrentCharacterActions()
    local currentChar = ns.CharacterScanner.GetCurrentCharacterKey()
    if not currentChar then return {} end

    local optimized = ns.CraftSimPlanner.OptimizeWatchedRecipes()
    local result = ns.ResourceAllocator.Allocate(optimized)
    if not result or not result.plan then return {} end

    local actions = {}
    for _, entry in ipairs(result.plan) do
        if entry.type == "watched" and entry.crafts > 0 then
            -- Watched recipe craft on this character
            if entry.crafter == currentChar then
                actions[#actions + 1] = {
                    recipeID = entry.recipeId,
                    recipeName = entry.recipeName,
                    crafts = entry.crafts,
                    concentratedCrafts = entry.concentratedCrafts or 0,
                    useConcentration = (entry.concentratedCrafts or 0) > 0,
                    totalProfit = entry.totalProfit or 0,
                    isSupport = false,
                }
            end

            -- Support recipe crafts on this character
            if entry.supportPlan then
                for _, support in pairs(entry.supportPlan) do
                    if support.crafter == currentChar and support.batches > 0 then
                        actions[#actions + 1] = {
                            recipeID = support.recipeId,
                            recipeName = support.recipeName,
                            crafts = support.batches,
                            concentratedCrafts = 0,
                            useConcentration = false,
                            totalProfit = 0,
                            isSupport = true,
                        }
                    end
                end
            end
        end
    end

    return actions
end

-- ============================================================================
-- Refresh the overlay panel
-- ============================================================================

function ns.ProfessionOverlay.Refresh()
    if not overlayFrame then return end

    -- Clear old rows
    for _, row in ipairs(actionRows) do
        row:Hide()
        row:SetParent(nil)
    end
    wipe(actionRows)

    local actions = ns.ProfessionOverlay.GetCurrentCharacterActions()

    if #actions == 0 then
        overlayFrame:SetSize(260, 50)
        local noActions = overlayFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        noActions:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", 10, -26)
        noActions:SetText("|cff888888No craft actions for this character.|r")
        actionRows[1] = noActions
        overlayFrame:Show()
        return
    end

    local y = -26
    for i, action in ipairs(actions) do
        local row = ns.ProfessionOverlay.CreateActionRow(overlayFrame, y, action, i)
        actionRows[#actionRows + 1] = row
        y = y - 36
        if i >= 8 then break end
    end

    overlayFrame:SetSize(260, math.abs(y) + 10)
    overlayFrame:Show()

    -- Update glow for currently selected recipe
    ns.ProfessionOverlay.UpdateConcentrationGlow()
end

-- ============================================================================
-- Create a single action row
-- ============================================================================

function ns.ProfessionOverlay.CreateActionRow(parent, y, action, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(240, 32)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)

    -- Background
    if index % 2 == 0 then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.04)
    end

    -- Recipe name
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
    nameText:SetWidth(180)
    nameText:SetJustifyH("LEFT")

    local label = action.recipeName or "?"
    if action.isSupport then
        label = "|cffaaaaaa(support)|r " .. label
    end
    nameText:SetText(label)

    -- Craft count + concentration info line
    local infoText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -14)
    infoText:SetWidth(180)
    infoText:SetJustifyH("LEFT")

    local info = string.format("|cffffd100x%d|r", action.crafts)
    if action.useConcentration then
        info = info .. string.format("  |cffff8800Concentrate %d|r", action.concentratedCrafts)
    end
    if action.totalProfit > 0 then
        info = info .. string.format("  |cff00ff00%s|r", GetCoinTextureString(action.totalProfit))
    end
    infoText:SetText(info)

    -- "Go" button — navigates to this recipe and sets concentration glow
    local goBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    goBtn:SetSize(40, 20)
    goBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -6)
    goBtn:SetText("Go")
    goBtn:SetNormalFontObject("GameFontNormalSmall")
    goBtn:SetScript("OnClick", function()
        -- Navigate to this recipe in the profession frame
        local ok, err = pcall(function()
            C_TradeSkillUI.OpenRecipe(action.recipeID)
        end)
        if not ok then
            ns.Debug("ProfessionOverlay: failed to open recipe %d: %s", action.recipeID, tostring(err))
        end

        -- Try to set the craft count input
        C_Timer.After(0.1, function()
            ns.ProfessionOverlay.TrySetCraftCount(action.crafts)
        end)

        -- Update glow after navigation
        C_Timer.After(0.2, function()
            lastSelectedRecipeID = action.recipeID
            ns.ProfessionOverlay.UpdateConcentrationGlow()
        end)
    end)

    goBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Open recipe and set craft count", 1, 1, 1)
        if action.useConcentration then
            GameTooltip:AddLine("Remember to enable Concentration!", 1, 0.5, 0, true)
        end
        GameTooltip:Show()
    end)
    goBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return row
end

-- ============================================================================
-- Try to set the craft count in Blizzard's input box
-- ============================================================================

function ns.ProfessionOverlay.TrySetCraftCount(count)
    local profFrame = ProfessionsFrame
    if not profFrame or not profFrame.CraftingPage then return end

    local schematicForm = profFrame.CraftingPage.SchematicForm
    if not schematicForm then return end

    -- Try known input box paths for retail WoW profession UI
    local inputBox = nil

    -- Method 1: Direct child search for an EditBox with numeric input
    local function findInputBox(frame, depth)
        if depth > 3 then return nil end
        local children = { frame:GetChildren() }
        for _, child in ipairs(children) do
            if child:IsObjectType("EditBox") and child:IsShown() then
                local text = child:GetText()
                -- Craft count input typically shows a number
                if text and tonumber(text) then
                    return child
                end
            end
            local found = findInputBox(child, depth + 1)
            if found then return found end
        end
        return nil
    end

    -- Search in the crafting page area
    inputBox = findInputBox(profFrame.CraftingPage, 0)

    if inputBox then
        inputBox:SetText(tostring(count))
        inputBox:SetCursorPosition(0)
        ns.Debug("ProfessionOverlay: set craft count to %d", count)
    else
        ns.Debug("ProfessionOverlay: could not find craft count input box")
    end
end

-- ============================================================================
-- Show / Hide
-- ============================================================================

function ns.ProfessionOverlay.Show()
    if overlayFrame then
        ns.ProfessionOverlay.Refresh()
    end
end

function ns.ProfessionOverlay.Hide()
    if overlayFrame then
        overlayFrame:Hide()
    end
    if concGlow then
        concGlow.anim:Stop()
        concGlow:Hide()
    end
end
