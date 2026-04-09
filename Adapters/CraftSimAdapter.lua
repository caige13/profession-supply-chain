local ADDON_NAME, ns = ...

ns.CraftSimAdapter = {}

local craftSimAvailable = false

function ns.CraftSimAdapter.Initialize()
    craftSimAvailable = ns.CraftSimAdapter.DetectCraftSim()
    if craftSimAvailable then
        ns.Debug("CraftSim detected and available")
    else
        ns.Debug("CraftSim not detected — adapter disabled")
    end
end

function ns.CraftSimAdapter.DetectCraftSim()
    return CraftSimAPI ~= nil
end

function ns.CraftSimAdapter.IsAvailable()
    if not ns.DB.settings.enableCraftSim then
        return false
    end
    return craftSimAvailable
end

-- Get recipe data for a specific recipe ID
-- options: { isRecraft, isWorkOrder, crafterData }
function ns.CraftSimAdapter.GetRecipeData(recipeID, options)
    if not ns.CraftSimAdapter.IsAvailable() then return nil end

    options = options or {}
    local requestOptions = {
        recipeID = recipeID,
        isRecraft = options.isRecraft or false,
        isWorkOrder = options.isWorkOrder or false,
    }

    if options.crafterData then
        requestOptions.crafterData = options.crafterData
    end

    local ok, result = pcall(function()
        return CraftSimAPI:GetRecipeData(requestOptions)
    end)

    if ok and result then
        return result
    end

    ns.Debug("CraftSim GetRecipeData failed for recipe %d", recipeID)
    return nil
end

-- Get the currently open recipe data
function ns.CraftSimAdapter.GetOpenRecipeData()
    if not ns.CraftSimAdapter.IsAvailable() then return nil end

    local ok, result = pcall(function()
        return CraftSimAPI:GetOpenRecipeData()
    end)

    if ok and result then
        return result
    end
    return nil
end

-- Get profit estimate for a recipe
-- Returns: profit in copper, or nil
function ns.CraftSimAdapter.GetProfitEstimate(recipeID)
    if not ns.CraftSimAdapter.IsAvailable() then return nil end

    local recipeData = ns.CraftSimAdapter.GetRecipeData(recipeID)
    if not recipeData then return nil end

    local ok, profit, probabilityTable = pcall(function()
        return recipeData:GetAverageProfit()
    end)

    if ok and profit then
        return profit, probabilityTable
    end
    return nil
end

-- Get crafting cost for a recipe
-- Returns: cost in copper, or nil
function ns.CraftSimAdapter.GetCraftingCost(recipeID)
    if not ns.CraftSimAdapter.IsAvailable() then return nil end

    local recipeData = ns.CraftSimAdapter.GetRecipeData(recipeID)
    if not recipeData or not recipeData.priceData then return nil end

    return recipeData.priceData.craftingCosts
end

-- Get optimized reagent allocation for a recipe
function ns.CraftSimAdapter.GetOptimizedReagents(recipeID)
    if not ns.CraftSimAdapter.IsAvailable() then return nil end

    local recipeData = ns.CraftSimAdapter.GetRecipeData(recipeID)
    if not recipeData then return nil end

    local ok, err = pcall(function()
        recipeData:OptimizeReagents({ maxQuality = recipeData.maxQuality })
        recipeData:Update()
    end)

    if ok then
        return recipeData
    end

    ns.Debug("CraftSim reagent optimization failed for recipe %d: %s", recipeID, tostring(err))
    return nil
end

-- Get last known crafting cost for an item
function ns.CraftSimAdapter.GetLastCraftingCost(itemIDOrLink)
    if not ns.CraftSimAdapter.IsAvailable() then return nil end

    local ok, cost, timestamp, crafterUID = pcall(function()
        return CraftSimAPI:GetLastCraftingCost(itemIDOrLink)
    end)

    if ok then
        return cost, timestamp, crafterUID
    end
    return nil
end

-- Get a summary of CraftSim data for display in recipe detail
function ns.CraftSimAdapter.GetRecipeSummary(recipeID)
    if not ns.CraftSimAdapter.IsAvailable() then return nil end

    local recipeData = ns.CraftSimAdapter.GetRecipeData(recipeID)
    if not recipeData then return nil end

    local summary = {
        recipeName = recipeData.recipeName,
        supportsQualities = recipeData.supportsQualities,
        maxQuality = recipeData.maxQuality,
        craftingCost = recipeData.priceData and recipeData.priceData.craftingCosts,
    }

    -- Profit
    local ok, profit = pcall(function()
        return recipeData:GetAverageProfit()
    end)
    if ok then
        summary.averageProfit = profit
    end

    -- Quality prices
    if recipeData.priceData and recipeData.priceData.qualityPriceList then
        summary.qualityPrices = recipeData.priceData.qualityPriceList
    end

    return summary
end

-- Optimize a recipe for highest profit and return full allocation details
-- Returns an OptimizedRecipe table with per-quality breakdown, or nil
function ns.CraftSimAdapter.GetOptimizedRecipeForProfit(recipeID, crafterCharKey)
    if not ns.CraftSimAdapter.IsAvailable() then return nil end

    -- Determine which character knows this recipe for cross-character support
    local crafterData = nil
    local targetCrafter = crafterCharKey
    if not targetCrafter then
        local crafters = ns.Merge.GetRecipeOwners(recipeID)
        targetCrafter = crafters and crafters[1]
    end
    if targetCrafter then
        local name, realm = ns.ItemUtil.ParseCharacterKey(targetCrafter)
        if name and realm then
            crafterData = { name = name, realm = realm }
        end
    end

    local options = {}
    if crafterData then
        options.crafterData = crafterData
    end

    -- Initial probe to check recipe capabilities
    local probeRd = ns.CraftSimAdapter.GetRecipeData(recipeID, options)
    if not probeRd then return nil end

    if not probeRd.supportsQualities then
        local result = ns.CraftSimAdapter.RunSingleOptimization(probeRd, nil, false)
        if result then
            result.qualityResults = {}
            return result
        end
        return nil
    end

    local maxQuality = probeRd.maxQuality or 2

    -- Check concentration support once
    local canConcentrate = false
    pcall(function()
        canConcentrate = probeRd.concentrationData
            and probeRd.concentrationData.maxQuantity
            and probeRd.concentrationData.maxQuantity > 0
    end)

    local qualityResults = {}
    local seenKeys = {}

    -- Run per-quality optimizations
    local concentrationModes = { false }
    if canConcentrate then
        concentrationModes[2] = true
    end

    for _, useConcentration in ipairs(concentrationModes) do
        for q = 1, maxQuality do
            local key = string.format("Q%d%s", q, useConcentration and "+C" or "")
            if not seenKeys[key] then
                local rd = ns.CraftSimAdapter.GetRecipeData(recipeID, options)
                if rd then
                    if useConcentration then
                        pcall(function() rd.concentrating = true end)
                    end

                    local result = ns.CraftSimAdapter.RunSingleOptimization(rd, q, useConcentration)
                    if result then
                        local revenue = (result.qualityPrices and result.qualityPrices[q])
                            or (result.profit and result.craftingCost and (result.craftingCost + result.profit))
                            or 0
                        qualityResults[#qualityResults + 1] = {
                            key = key,
                            qualityTarget = q,
                            useConcentration = useConcentration,
                            profit = result.profit or 0,
                            craftingCost = result.craftingCost or 0,
                            concentrationCost = result.concentrationCost or 0,
                            revenue = revenue,
                        }
                        seenKeys[key] = true
                    end
                end
            end
        end
    end

    -- Best result: use highest profit run (no separate redundant run)
    local bestRd = ns.CraftSimAdapter.GetRecipeData(recipeID, options)
    if not bestRd then return nil end

    local bestResult = ns.CraftSimAdapter.RunSingleOptimization(bestRd, nil, false)
    if not bestResult then return nil end

    -- Sort quality results by profit descending
    table.sort(qualityResults, function(a, b)
        return (a.profit or 0) > (b.profit or 0)
    end)

    bestResult.qualityResults = qualityResults
    bestResult.maxQuality = maxQuality
    return bestResult
end

-- Run a single optimization pass for a given quality target
function ns.CraftSimAdapter.RunSingleOptimization(recipeData, targetQuality, useConcentration)
    local ok, err = pcall(function()
        if targetQuality then
            recipeData:OptimizeReagents({ maxQuality = targetQuality })
        else
            recipeData:OptimizeReagents({
                maxQuality = recipeData.maxQuality,
                highestProfit = true,
            })
        end
    end)

    if not ok then
        ns.Debug("CraftSim optimization failed: %s", tostring(err))
        return nil
    end

    local profit = nil
    ok, err = pcall(function()
        profit = recipeData:GetAverageProfit()
    end)

    local reagentAllocations = ns.CraftSimAdapter.GetReagentAllocations(recipeData)
    local concentrationInfo = ns.CraftSimAdapter.GetConcentrationInfo(recipeData)

    return {
        recipeID = recipeData.recipeID,
        recipeName = recipeData.recipeName,
        profit = profit or 0,
        craftingCost = recipeData.priceData and recipeData.priceData.craftingCosts or 0,
        targetQuality = recipeData.resultData and recipeData.resultData.expectedQuality or 1,
        concentrationCost = (useConcentration and concentrationInfo) and concentrationInfo.costPerCraft or 0,
        concentrationInfo = concentrationInfo,
        supportsQualities = recipeData.supportsQualities,
        maxQuality = recipeData.maxQuality,
        reagents = reagentAllocations,
        qualityPrices = recipeData.priceData and recipeData.priceData.qualityPriceList,
    }
end

-- Read back per-quality reagent allocations from an optimized RecipeData
-- Returns array of { itemID, qualityID, quantity, baseItemID, name }
function ns.CraftSimAdapter.GetReagentAllocations(recipeData)
    local allocations = {}
    if not recipeData or not recipeData.reagentData then return allocations end

    local ok, err = pcall(function()
        for _, reagent in ipairs(recipeData.reagentData.requiredReagents) do
            if reagent.hasQuality and reagent.items then
                local baseItemID = reagent.items[1] and reagent.items[1].item
                    and reagent.items[1].item:GetItemID() or nil
                for _, reagentItem in ipairs(reagent.items) do
                    if reagentItem.quantity and reagentItem.quantity > 0 then
                        local itemID = reagentItem.item and reagentItem.item:GetItemID() or nil
                        if itemID then
                            allocations[#allocations + 1] = {
                                itemID = itemID,
                                qualityID = reagentItem.qualityID or 1,
                                quantity = reagentItem.quantity,
                                baseItemID = baseItemID,
                                requiredTotal = reagent.requiredQuantity,
                            }
                        end
                    end
                end
            else
                -- Non-quality reagent: single item
                local itemID = reagent.items and reagent.items[1]
                    and reagent.items[1].item and reagent.items[1].item:GetItemID() or nil
                if itemID then
                    allocations[#allocations + 1] = {
                        itemID = itemID,
                        qualityID = 0,  -- no quality
                        quantity = reagent.requiredQuantity,
                        baseItemID = itemID,
                        requiredTotal = reagent.requiredQuantity,
                    }
                end
            end
        end
    end)

    if not ok then
        ns.Debug("Failed reading reagent allocations: %s", tostring(err))
    end

    return allocations
end

-- Get concentration info for a recipe
function ns.CraftSimAdapter.GetConcentrationInfo(recipeData)
    if not recipeData then return nil end

    local info = {
        current = 0,
        max = 0,
        costPerCraft = 0,
        isConcentrating = recipeData.concentrating or false,
        rechargePerHour = 0,
    }

    local ok = pcall(function()
        if recipeData.concentrationData then
            info.current = recipeData.concentrationData:GetCurrentAmount() or 0
            info.max = recipeData.concentrationData.maxQuantity or 0
            if recipeData.concentrationData.rechargingDurationMS and
               recipeData.concentrationData.rechargingDurationMS > 0 then
                info.rechargePerHour = 3600000 / recipeData.concentrationData.rechargingDurationMS
            end
        end
        info.costPerCraft = recipeData.concentrationCost or 0
    end)

    return info
end
