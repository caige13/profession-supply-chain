local ADDON_NAME, ns = ...

ns.ResourceAllocator = {}

-- Profit-maximizing resource allocator
-- Given watched recipes, available inventory, and CraftSim profit data,
-- determines the optimal number of each recipe to craft to maximize total profit.
--
-- Algorithm:
-- 1. Get all recipe variants (each quality × concentration combination)
-- 2. Calculate profit-per-bottleneck-unit for each variant
-- 3. Greedily allocate: pick the variant with best profit/bottleneck ratio,
--    craft as many as possible given remaining resources, repeat
-- 4. Output: { recipeID, quantity, quality, useConcentration, totalProfit }

function ns.ResourceAllocator.Allocate(optimizedRecipes)
    if not optimizedRecipes or #optimizedRecipes == 0 then
        return {}
    end

    -- Build resource pool: how much of each item we have
    local pool = {}
    local allItems = ns.InventoryIndex.GetAllItems()
    for itemID, entry in pairs(allItems) do
        if entry.total > 0 then
            pool[itemID] = entry.total
        end
    end

    -- Determine available concentration
    local concAvailable = 0
    for _, recipe in ipairs(optimizedRecipes) do
        if recipe.concentrationInfo and recipe.concentrationInfo.current then
            concAvailable = math.max(concAvailable, math.floor(recipe.concentrationInfo.current))
            break  -- all recipes share the same concentration pool
        end
    end

    -- Build list of all craftable variants with their resource costs
    local variants = {}
    for _, recipe in ipairs(optimizedRecipes) do
        -- Add quality sub-variants if available
        if recipe.qualityResults and #recipe.qualityResults > 0 then
            for _, qr in ipairs(recipe.qualityResults) do
                if qr.profit and qr.profit ~= 0 then
                    variants[#variants + 1] = {
                        recipeID = recipe.recipeID,
                        recipeName = recipe.recipeName,
                        outputItemID = recipe.outputItemID or (ns.RecipeGraph.GetRecipe(recipe.recipeID) or {}).outputItemID,
                        qualityTarget = qr.qualityTarget,
                        useConcentration = qr.useConcentration,
                        profit = qr.profit,
                        craftingCost = qr.craftingCost,
                        concentrationCost = qr.concentrationCost or 0,
                        revenue = qr.revenue or 0,
                        reagents = recipe.reagents or {},
                        crafters = recipe.crafters,
                    }
                end
            end
        end

        -- Always add the base recipe variant
        if recipe.profit and recipe.profit ~= 0 then
            -- Check if this is already covered by quality results
            local alreadyCovered = false
            if recipe.qualityResults then
                for _, qr in ipairs(recipe.qualityResults) do
                    if not qr.useConcentration and qr.qualityTarget == recipe.targetQuality then
                        alreadyCovered = true
                        break
                    end
                end
            end
            if not alreadyCovered then
                variants[#variants + 1] = {
                    recipeID = recipe.recipeID,
                    recipeName = recipe.recipeName,
                    outputItemID = recipe.outputItemID or (ns.RecipeGraph.GetRecipe(recipe.recipeID) or {}).outputItemID,
                    qualityTarget = recipe.targetQuality or 1,
                    useConcentration = false,
                    profit = recipe.profit,
                    craftingCost = recipe.craftingCost or 0,
                    concentrationCost = 0,
                    revenue = 0,
                    reagents = recipe.reagents or {},
                    crafters = recipe.crafters,
                }
            end
        end
    end

    if #variants == 0 then
        return {}
    end

    -- Identify the bottleneck resource (scarcest relative to total demand)
    local bottleneckItemID = ns.ResourceAllocator.FindBottleneck(variants, pool)

    -- Calculate profit-per-bottleneck-unit for ranking
    for _, v in ipairs(variants) do
        local bottleneckUsage = 0
        for _, r in ipairs(v.reagents) do
            local itemID = r.itemID or r.baseItemID
            if itemID == bottleneckItemID then
                bottleneckUsage = r.quantity or r.requiredTotal or 0
                break
            end
        end
        -- Profit per unit of bottleneck resource (higher = better use of scarce resource)
        if bottleneckUsage > 0 then
            v.profitPerBottleneck = v.profit / bottleneckUsage
        else
            v.profitPerBottleneck = v.profit  -- doesn't use bottleneck, pure profit
        end
    end

    -- Sort by profitPerBottleneck descending (best use of scarce resources first)
    table.sort(variants, function(a, b)
        return a.profitPerBottleneck > b.profitPerBottleneck
    end)

    -- Greedy allocation
    local allocations = {}
    local concRemaining = concAvailable

    for _, variant in ipairs(variants) do
        -- Skip concentration variants if no charges left
        if variant.useConcentration and concRemaining <= 0 then
            -- skip
        else
            -- How many can we craft with remaining resources?
            local maxCrafts = ns.ResourceAllocator.MaxCraftsFromPool(variant, pool)

            -- Limit by concentration if applicable
            if variant.useConcentration and variant.concentrationCost > 0 then
                local concCrafts = math.floor(concRemaining / variant.concentrationCost)
                maxCrafts = math.min(maxCrafts, concCrafts)
            elseif variant.useConcentration then
                maxCrafts = math.min(maxCrafts, concRemaining)
            end

            if maxCrafts > 0 then
                -- Deduct resources from pool
                for _, r in ipairs(variant.reagents) do
                    local itemID = r.itemID or r.baseItemID
                    local needed = (r.quantity or r.requiredTotal or 0) * maxCrafts
                    if itemID and pool[itemID] then
                        pool[itemID] = pool[itemID] - needed
                        if pool[itemID] < 0 then pool[itemID] = 0 end
                    end
                end

                -- Deduct concentration
                if variant.useConcentration then
                    local concUsed = (variant.concentrationCost or 1) * maxCrafts
                    concRemaining = concRemaining - concUsed
                end

                local qIcon = variant.qualityTarget and variant.qualityTarget > 0
                    and ns.ItemUtil.GetQualityIcon(variant.qualityTarget, 12) or ""
                local concLabel = variant.useConcentration and " +Conc" or ""

                allocations[#allocations + 1] = {
                    recipeID = variant.recipeID,
                    recipeName = variant.recipeName,
                    outputItemID = variant.outputItemID,
                    qualityTarget = variant.qualityTarget,
                    useConcentration = variant.useConcentration,
                    quantity = maxCrafts,
                    profitPerCraft = variant.profit,
                    totalProfit = variant.profit * maxCrafts,
                    craftingCost = variant.craftingCost,
                    totalCost = variant.craftingCost * maxCrafts,
                    revenue = variant.revenue,
                    totalRevenue = variant.revenue * maxCrafts,
                    reagents = variant.reagents,
                    crafters = variant.crafters,
                    displayName = string.format("%s %s%s", variant.recipeName or "?", qIcon, concLabel),
                }
            end
        end
    end

    -- Sort allocations by total profit descending
    table.sort(allocations, function(a, b)
        return a.totalProfit > b.totalProfit
    end)

    ns.Debug("ResourceAllocator: %d allocations, conc remaining: %d", #allocations, concRemaining)
    return allocations
end

-- Find the bottleneck resource: the one with the lowest (supply / total demand) ratio
function ns.ResourceAllocator.FindBottleneck(variants, pool)
    local demand = {}  -- itemID → total demand across all variants

    for _, v in ipairs(variants) do
        for _, r in ipairs(v.reagents) do
            local itemID = r.itemID or r.baseItemID
            if itemID then
                local qty = r.quantity or r.requiredTotal or 0
                demand[itemID] = (demand[itemID] or 0) + qty
            end
        end
    end

    local worstRatio = math.huge
    local bottleneck = nil

    for itemID, totalDemand in pairs(demand) do
        if totalDemand > 0 then
            local supply = pool[itemID] or 0
            local ratio = supply / totalDemand
            if ratio < worstRatio then
                worstRatio = ratio
                bottleneck = itemID
            end
        end
    end

    if bottleneck then
        ns.Debug("Bottleneck resource: %s (ratio %.2f)",
            ns.ItemUtil.GetItemName(bottleneck), worstRatio)
    end

    return bottleneck
end

-- How many times can we craft this variant given the current resource pool?
function ns.ResourceAllocator.MaxCraftsFromPool(variant, pool)
    local minCrafts = math.huge

    for _, r in ipairs(variant.reagents) do
        local itemID = r.itemID or r.baseItemID
        local needed = r.quantity or r.requiredTotal or 0
        if needed > 0 and itemID then
            local available = pool[itemID] or 0
            -- Also check quality variants
            if r.qualityItems then
                available = 0
                for _, qID in ipairs(r.qualityItems) do
                    available = available + (pool[qID] or 0)
                end
            end
            local crafts = math.floor(available / needed)
            minCrafts = math.min(minCrafts, crafts)
        end
    end

    if minCrafts == math.huge then
        return 0
    end
    return minCrafts
end