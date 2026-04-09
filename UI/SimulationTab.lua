local ADDON_NAME, ns = ...

ns.SimulationTab = {}

local contentFrame = nil
local headerRow = nil
local dataRows = {}
local summaryLabels = {}
local runButton = nil
local statusLabel = nil
local lastResults = nil

function ns.SimulationTab.Create(parent)
    contentFrame = CreateFrame("Frame", nil, parent)
    contentFrame:SetAllPoints()

    -- Run Simulation button
    runButton = CreateFrame("Button", nil, contentFrame, "UIPanelButtonTemplate")
    runButton:SetSize(160, 26)
    runButton:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, -8)
    runButton:SetText("Run Simulation")
    runButton:SetScript("OnClick", function()
        ns.SimulationTab.RunSimulation()
    end)

    statusLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusLabel:SetPoint("LEFT", runButton, "RIGHT", 10, 0)
    statusLabel:SetText("")

    -- Summary row at top
    local sy = -42
    summaryLabels.header = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    summaryLabels.header:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, sy)
    summaryLabels.header:SetText("Simulation Results")
    sy = sy - 22

    summaryLabels.totalProfit = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    summaryLabels.totalProfit:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, sy)
    summaryLabels.totalProfit:SetWidth(750)
    summaryLabels.totalProfit:SetJustifyH("LEFT")
    summaryLabels.totalProfit:SetText("")
    sy = sy - 20

    summaryLabels.rawSellValue = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    summaryLabels.rawSellValue:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, sy)
    summaryLabels.rawSellValue:SetWidth(750)
    summaryLabels.rawSellValue:SetJustifyH("LEFT")
    summaryLabels.rawSellValue:SetText("")
    sy = sy - 20

    summaryLabels.verdict = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    summaryLabels.verdict:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, sy)
    summaryLabels.verdict:SetWidth(750)
    summaryLabels.verdict:SetJustifyH("LEFT")
    summaryLabels.verdict:SetText("")
    sy = sy - 25

    -- Column headers — right edges define where numbers align
    -- Col right edges: Qty@250, Rev@340, Cost@430, Profit@530, Raw@620, Conc@700, Verdict@780
    local colY = sy
    local colHeaders = {
        { x = 10,  just = "LEFT",   text = "" },
        { x = 34,  just = "LEFT",   text = "Recipe" },
        { x = 230, just = "RIGHT",  text = "Qty" },
        { x = 270, just = "RIGHT",  text = "Rev/craft" },
        { x = 370, just = "RIGHT",  text = "Cost/craft" },
        { x = 470, just = "RIGHT",  text = "Profit/craft" },
        { x = 560, just = "RIGHT",  text = "Raw/craft" },
        { x = 640, just = "RIGHT",  text = "Conc" },
        { x = 700, just = "CENTER", text = "Verdict" },
    }
    for _, col in ipairs(colHeaders) do
        if col.text ~= "" then
            local label = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", col.x, colY)
            label:SetText("|cffffd100" .. col.text .. "|r")
        end
    end

    -- Scroll frame for data rows
    local scrollFrame = CreateFrame("ScrollFrame", "PSCSimScroll", contentFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, colY - 18)
    scrollFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -26, 5)

    contentFrame.scrollChild = CreateFrame("Frame", nil, scrollFrame)
    contentFrame.scrollChild:SetWidth(820)
    contentFrame.scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(contentFrame.scrollChild)

    return contentFrame
end

function ns.SimulationTab.Refresh()
    if lastResults then
        ns.SimulationTab.DisplayResults(lastResults)
    end
end

function ns.SimulationTab.RunSimulation()
    statusLabel:SetText("|cffffff00Simulating...|r")
    runButton:Disable()

    -- Invalidate cache to force fresh calculation
    ns.CraftSimPlanner.InvalidateCache()

    -- Run after a frame to let the UI update
    C_Timer.After(0.1, function()
        local csAvailable = ns.CraftSimAdapter.IsAvailable()
        local tsmAvailable = ns.TSMAdapter.IsAvailable()
        local optimized = ns.CraftSimPlanner.OptimizeWatchedRecipes()

        -- Enrich with raw sell values
        local results = ns.SimulationTab.EnrichWithRawSellValues(optimized)

        lastResults = results
        ns.SimulationTab.DisplayResults(results)

        runButton:Enable()

        local addonStatus = ""
        if not csAvailable then addonStatus = addonStatus .. " |cffff4444CraftSim: OFF|r" end
        if not tsmAvailable then addonStatus = addonStatus .. " |cffff4444TSM: OFF|r" end
        if csAvailable then addonStatus = addonStatus .. " |cff00cc66CraftSim: ON|r" end
        if tsmAvailable then addonStatus = addonStatus .. " |cff00cc66TSM: ON|r" end

        statusLabel:SetText(string.format("|cff00cc66Done|r — %d recipes |%s",
            #results, addonStatus))

        -- Print summary to chat
        ns.Print("Simulation complete — %d recipes:", #results)
        for _, r in ipairs(results) do
            local icon = ns.ItemUtil.GetIconString(r.outputItemID, 12)
            ns.Print("  %s %s: profit %s | rev %s | cost %s | qty %d",
                icon, r.recipeName or "?",
                ns.SimulationTab.FormatGoldSigned(r.perCraftProfit),
                ns.SimulationTab.FormatGoldCompact(r.perCraftRevenue),
                ns.SimulationTab.FormatGoldCompact(r.perCraftCost),
                r.maxCraftable or 0)
        end

        -- Fire event so other tabs can refresh
        ns.Events.Fire("PSC_SIMULATION_COMPLETE", results)
    end)
end

function ns.SimulationTab.EnrichWithRawSellValues(optimized)
    local results = {}

    for _, recipe in ipairs(optimized) do
        local entry = {
            recipeID = recipe.recipeID,
            recipeName = recipe.recipeName,
            outputItemID = nil,
            maxCraftable = recipe.maxCraftable or 0,
            perCraftProfit = recipe.profit or 0,
            perCraftCost = recipe.craftingCost or 0,
            targetQuality = recipe.targetQuality or 1,
            qualityPrices = recipe.qualityPrices,
            qualityResults = recipe.qualityResults or {},
            expanded = false,
            perCraftRevenue = 0,
            totalRevenue = 0,
            totalCost = 0,
            totalProfit = 0,
            perCraftRawSell = 0,
            totalRawSell = 0,
            craftVerdict = "unknown",
            source = recipe.crafters and #recipe.crafters > 0 and "craftsim" or "fallback",
            debugInfo = "",
        }

        -- Get output item from recipe graph
        local graphRecipe = ns.RecipeGraph.GetRecipe(recipe.recipeID)
        if graphRecipe then
            entry.outputItemID = graphRecipe.outputItemID
        end

        -- Calculate per-craft revenue from CraftSim quality prices
        if recipe.qualityPrices and recipe.targetQuality then
            entry.perCraftRevenue = recipe.qualityPrices[recipe.targetQuality] or 0
        end

        -- Fallback: try TSM for output item price
        if entry.perCraftRevenue == 0 and entry.outputItemID and ns.TSMAdapter.IsAvailable() then
            entry.perCraftRevenue = ns.TSMAdapter.GetItemValue(entry.outputItemID, "DBMarket") or 0
        end

        -- Per-craft raw material sell value
        entry.perCraftRawSell = ns.SimulationTab.CalcPerCraftRawSellValue(recipe)

        -- Per-craft profit: CraftSim profit if available, otherwise revenue - cost
        if entry.perCraftProfit == 0 and entry.perCraftRevenue > 0 then
            -- CraftSim didn't give us profit, calculate from revenue and cost
            -- Apply 5% AH cut
            entry.perCraftProfit = math.floor(entry.perCraftRevenue * 0.95) - entry.perCraftCost
        end

        -- Use at least 1 for calculations even if maxCraftable is 0
        local displayQty = math.max(entry.maxCraftable, 1)

        -- Totals
        entry.totalRevenue = entry.perCraftRevenue * displayQty
        entry.totalCost = entry.perCraftCost * displayQty
        entry.totalProfit = entry.perCraftProfit * displayQty
        entry.totalRawSell = entry.perCraftRawSell * displayQty

        -- Verdict
        if entry.perCraftProfit > entry.perCraftRawSell and entry.perCraftProfit > 0 then
            entry.craftVerdict = "craft"
        elseif entry.perCraftRawSell > 0 and entry.perCraftRawSell >= entry.perCraftProfit then
            entry.craftVerdict = "sell_raw"
        elseif entry.perCraftProfit < 0 then
            entry.craftVerdict = "loss"
        end

        -- Debug info
        entry.debugInfo = string.format("perProfit=%d perRev=%d perCost=%d perRaw=%d maxCraft=%d",
            entry.perCraftProfit, entry.perCraftRevenue, entry.perCraftCost,
            entry.perCraftRawSell, entry.maxCraftable)
        ns.Debug("Sim %s: %s", entry.recipeName or "?", entry.debugInfo)

        results[#results + 1] = entry
    end

    -- Sort by per-craft profit descending
    table.sort(results, function(a, b)
        return (a.perCraftProfit or 0) > (b.perCraftProfit or 0)
    end)

    return results
end

-- Calculate raw sell value per single craft's worth of materials
function ns.SimulationTab.CalcPerCraftRawSellValue(recipe)
    if not recipe.reagents then return 0 end
    if not ns.TSMAdapter.IsAvailable() then return 0 end

    local totalValue = 0
    for _, alloc in ipairs(recipe.reagents) do
        local unitPrice = ns.TSMAdapter.GetItemValue(alloc.itemID, "DBMarket") or 0
        totalValue = totalValue + (unitPrice * alloc.quantity)
    end
    return totalValue
end


function ns.SimulationTab.DisplayResults(results)
    if not contentFrame then return end

    -- Clear old rows
    for _, row in ipairs(dataRows) do
        row:Hide()
        row:SetParent(nil)
    end
    wipe(dataRows)

    if not results or #results == 0 then
        summaryLabels.totalProfit:SetText("|cff888888No simulation data. Click Run Simulation.|r")
        summaryLabels.rawSellValue:SetText("")
        summaryLabels.verdict:SetText("")
        return
    end

    -- Calculate totals
    local totalProfit = 0
    local totalRawSell = 0
    local totalRevenue = 0
    local totalCost = 0
    for _, r in ipairs(results) do
        totalProfit = totalProfit + (r.totalProfit or 0)
        totalRawSell = totalRawSell + (r.totalRawSell or 0)
        totalRevenue = totalRevenue + (r.totalRevenue or 0)
        totalCost = totalCost + (r.totalCost or 0)
    end

    -- Summary
    summaryLabels.totalProfit:SetText(string.format(
        "Revenue: %s | Cost: %s | Profit: %s",
        GetCoinTextureString(totalRevenue),
        GetCoinTextureString(totalCost),
        ns.SimulationTab.FormatGoldSigned(totalProfit)))

    if totalRawSell > 0 then
        summaryLabels.rawSellValue:SetText(string.format(
            "Raw material sell value: %s (if sold on AH instead of crafting)",
            GetCoinTextureString(totalRawSell)))
    else
        summaryLabels.rawSellValue:SetText("|cff888888Raw sell values require TSM for pricing|r")
    end

    if totalProfit > totalRawSell and totalProfit > 0 then
        summaryLabels.verdict:SetText(string.format(
            "|cff00cc66Crafting is more profitable|r by %s vs selling raw",
            GetCoinTextureString(totalProfit - totalRawSell)))
    elseif totalRawSell > totalProfit and totalRawSell > 0 then
        summaryLabels.verdict:SetText(string.format(
            "|cffff4444Selling raw is more profitable|r by %s vs crafting",
            GetCoinTextureString(totalRawSell - totalProfit)))
    elseif totalProfit < 0 then
        summaryLabels.verdict:SetText("|cffff4444Crafting at a loss — consider selling raw materials|r")
    else
        summaryLabels.verdict:SetText("")
    end

    -- Data rows (with expandable quality sub-rows)
    local y = 0
    for i, r in ipairs(results) do
        local row = ns.SimulationTab.CreateDataRow(contentFrame.scrollChild, y, r, i)
        dataRows[#dataRows + 1] = row
        y = y - 24

        -- Quality sub-rows (shown when expanded)
        if r.expanded and r.qualityResults and #r.qualityResults > 0 then
            for j, qr in ipairs(r.qualityResults) do
                local subRow = ns.SimulationTab.CreateQualitySubRow(contentFrame.scrollChild, y, qr, j)
                dataRows[#dataRows + 1] = subRow
                y = y - 20
            end
        end
    end
    contentFrame.scrollChild:SetHeight(math.max(1, math.abs(y)))
end

function ns.SimulationTab.CreateDataRow(parent, y, data, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(820, 22)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)

    if index % 2 == 0 then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.05)
    end

    -- Icon
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -2)
    local itemIcon = data.outputItemID and C_Item.GetItemIconByID(data.outputItemID)
    icon:SetTexture(itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark")

    -- Expand indicator + Recipe name
    local hasQuality = data.qualityResults and #data.qualityResults > 0
    local expandArrow = hasQuality and (data.expanded and "v " or "> ") or "  "
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("TOPLEFT", row, "TOPLEFT", 34, -4)
    nameText:SetWidth(180)
    nameText:SetJustifyH("LEFT")
    nameText:SetText(expandArrow .. (data.recipeName or "?"))

    -- Make clickable to expand/collapse quality sub-rows
    if hasQuality then
        local clickFrame = CreateFrame("Button", nil, row)
        clickFrame:SetAllPoints()
        clickFrame:SetScript("OnClick", function()
            data.expanded = not data.expanded
            ns.SimulationTab.DisplayResults(lastResults)
        end)
        clickFrame:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    end

    -- Qty
    local qtyText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    qtyText:SetPoint("TOPLEFT", row, "TOPLEFT", 230, -4)
    qtyText:SetWidth(30)
    qtyText:SetJustifyH("RIGHT")
    qtyText:SetText(tostring(data.maxCraftable or 0))

    -- Revenue
    ns.SimulationTab.AddColText(row, 270, 90, ns.SimulationTab.FormatGoldCompact(data.perCraftRevenue))

    -- Cost
    ns.SimulationTab.AddColText(row, 370, 90, ns.SimulationTab.FormatGoldCompact(data.perCraftCost))

    -- Profit
    ns.SimulationTab.AddColText(row, 470, 90, ns.SimulationTab.FormatGoldSigned(data.perCraftProfit))

    -- Raw sell
    ns.SimulationTab.AddColText(row, 560, 70, ns.SimulationTab.FormatGoldCompact(data.perCraftRawSell))

    -- Concentration (empty for parent row)
    ns.SimulationTab.AddColText(row, 640, 50, "")

    -- Verdict
    local verdictStr
    if data.craftVerdict == "craft" then verdictStr = "|cff00cc66Craft|r"
    elseif data.craftVerdict == "sell_raw" then verdictStr = "|cffff4444Sell Raw|r"
    elseif data.craftVerdict == "loss" then verdictStr = "|cffff4444Loss|r"
    else verdictStr = "|cff888888—|r" end
    ns.SimulationTab.AddColText(row, 700, 60, verdictStr, "CENTER")

    return row
end

-- Helper to add a right-aligned text column to a row
function ns.SimulationTab.AddColText(row, x, w, text, justify)
    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", row, "TOPLEFT", x, -4)
    fs:SetWidth(w)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetText(text or "")
    return fs
end

function ns.SimulationTab.CreateQualitySubRow(parent, y, qr, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(820, 20)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)

    -- Indent background
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.2, 0.3)

    -- Quality icon label
    local qIcon = ns.ItemUtil.GetQualityIcon(qr.qualityTarget, 14)
    local labelText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelText:SetPoint("TOPLEFT", row, "TOPLEFT", 50, -2)
    labelText:SetWidth(170)
    labelText:SetJustifyH("LEFT")
    labelText:SetText(string.format("    %s", qIcon))

    -- Revenue (sell price at this quality)
    ns.SimulationTab.AddSubColText(row, 270, 90, ns.SimulationTab.FormatGoldCompact(qr.revenue))

    -- Cost
    ns.SimulationTab.AddSubColText(row, 370, 90, ns.SimulationTab.FormatGoldCompact(qr.craftingCost))

    -- Profit
    ns.SimulationTab.AddSubColText(row, 470, 90, ns.SimulationTab.FormatGoldSigned(qr.profit))

    -- Raw sell (same as parent since reagents don't change per quality)
    ns.SimulationTab.AddSubColText(row, 560, 70, "")

    -- Concentration
    local concStr = ""
    if qr.useConcentration then
        if (qr.concentrationCost or 0) > 0 then
            concStr = string.format("|cffffff00%d pts|r", qr.concentrationCost)
        else
            concStr = "|cff00cc66Yes|r"
        end
    else
        concStr = "|cff888888No|r"
    end
    ns.SimulationTab.AddSubColText(row, 640, 50, concStr)

    -- Verdict for this quality
    local verdict = "|cff888888—|r"
    if (qr.profit or 0) > 0 then
        verdict = "|cff00cc66Profit|r"
    elseif (qr.profit or 0) < 0 then
        verdict = "|cffff4444Loss|r"
    end
    ns.SimulationTab.AddSubColText(row, 700, 60, verdict, "CENTER")

    return row
end

function ns.SimulationTab.AddSubColText(row, x, w, text, justify)
    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", row, "TOPLEFT", x, -3)
    fs:SetWidth(w)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetText(text or "")
    fs:SetDrawLayer("OVERLAY", 2)
    return fs
end

-- Format copper as compact gold string (always positive display)
function ns.SimulationTab.FormatGoldCompact(copper)
    if copper == nil then return "|cff888888--|r" end
    if copper == 0 then return "|cff8888880g|r" end
    local gold = math.floor(math.abs(copper) / 10000)
    local silver = math.floor((math.abs(copper) % 10000) / 100)
    if gold > 0 then
        return string.format("%dg %ds", gold, silver)
    else
        return string.format("%ds", silver)
    end
end

-- Format copper with sign and color: green positive, red negative
function ns.SimulationTab.FormatGoldSigned(copper)
    if copper == nil then return "|cff888888--|r" end
    if copper == 0 then return "|cff8888880g|r" end
    local absCopper = math.abs(copper)
    local gold = math.floor(absCopper / 10000)
    local silver = math.floor((absCopper % 10000) / 100)
    local formatted
    if gold > 0 then
        formatted = string.format("%dg %ds", gold, silver)
    else
        formatted = string.format("%ds", silver)
    end
    if copper > 0 then
        return "|cff00cc66+" .. formatted .. "|r"
    else
        return "|cffff4444-" .. formatted .. "|r"
    end
end

-- Get last simulation results (for other modules)
function ns.SimulationTab.GetLastResults()
    return lastResults
end
