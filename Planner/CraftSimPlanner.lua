local ADDON_NAME, ns = ...

ns.CraftSimPlanner = {}

local cachedResults = nil
local cacheTime = 0
local CACHE_TTL = 5  -- seconds before re-optimizing

-- Optimize all watched recipes via CraftSim (or fallback to MaxCraftable)
-- Returns array of OptimizedRecipe objects
function ns.CraftSimPlanner.OptimizeWatchedRecipes()
    -- Return cached results if fresh
    if cachedResults and (GetTime() - cacheTime) < CACHE_TTL then
        return cachedResults
    end

    local results = {}

    for recipeID in pairs(ns.DB.watchedRecipes) do
        local optimized = ns.CraftSimPlanner.OptimizeRecipe(recipeID)
        if optimized then
            results[#results + 1] = optimized
        end
    end

    -- Sort by profit descending
    table.sort(results, function(a, b)
        return (a.profit or 0) > (b.profit or 0)
    end)

    cachedResults = results
    cacheTime = GetTime()
    return results
end

-- Optimize a single recipe
function ns.CraftSimPlanner.OptimizeRecipe(recipeID)
    local crafters = ns.Merge.GetRecipeOwners(recipeID)
    local primaryCrafter = crafters and crafters[1]

    -- Try CraftSim first, passing crafter info for cross-character support
    if ns.CraftSimAdapter.IsAvailable() then
        local csResult = ns.CraftSimAdapter.GetOptimizedRecipeForProfit(recipeID, primaryCrafter)
        if csResult then
            csResult.crafters = crafters
            csResult.maxCraftable = ns.CraftSimPlanner.CalcMaxFromAllocations(csResult)
            ns.Debug("CraftSim optimized %s: profit=%d, maxCraftable=%d, crafter=%s",
                csResult.recipeName or "?",
                csResult.profit or 0,
                csResult.maxCraftable or 0,
                primaryCrafter or "current")
            return csResult
        else
            ns.Debug("CraftSim returned nil for %d, falling back", recipeID)
        end
    end

    -- Fallback: use our own MaxCraftable + RecipeGraph
    return ns.CraftSimPlanner.FallbackOptimize(recipeID)
end

-- Calculate how many we can craft based on CraftSim's quality allocations vs inventory
function ns.CraftSimPlanner.CalcMaxFromAllocations(optimized)
    if not optimized.reagents or #optimized.reagents == 0 then
        return 0
    end

    local minCraftable = math.huge

    -- Group allocations by base item to handle multiple quality entries for same reagent
    local reagentGroups = {}
    for _, alloc in ipairs(optimized.reagents) do
        local base = alloc.baseItemID or alloc.itemID
        if not reagentGroups[base] then
            reagentGroups[base] = {
                allocations = {},
                requiredTotal = alloc.requiredTotal or 0,
            }
        end
        reagentGroups[base].allocations[#reagentGroups[base].allocations + 1] = alloc
    end

    for _, group in pairs(reagentGroups) do
        local totalAvailable = 0
        local hasSpecificAllocation = false

        for _, alloc in ipairs(group.allocations) do
            local have = ns.InventoryIndex.GetTotal(alloc.itemID)
            totalAvailable = totalAvailable + have
            if alloc.quantity > 0 then
                hasSpecificAllocation = true
                local craftsFromThis = math.floor(have / alloc.quantity)
                minCraftable = math.min(minCraftable, craftsFromThis)
            end
        end

        -- Fallback: if CraftSim didn't allocate specific quantities (all 0),
        -- use total available across all quality variants vs requiredTotal
        if not hasSpecificAllocation and group.requiredTotal > 0 then
            local craftsFromTotal = math.floor(totalAvailable / group.requiredTotal)
            minCraftable = math.min(minCraftable, craftsFromTotal)
        end
    end

    if minCraftable == math.huge then
        minCraftable = 0
    end
    return minCraftable
end

-- Fallback when CraftSim is unavailable
function ns.CraftSimPlanner.FallbackOptimize(recipeID)
    local recipe = ns.RecipeGraph.GetRecipe(recipeID)
    if not recipe then return nil end

    local result = ns.MaxCraftable.Calculate(recipeID)
    local crafters = ns.Merge.GetRecipeOwners(recipeID)

    -- Build reagent list from our scanner data
    -- Store the per-craft requirement + quality variant info for the allocator
    local reagents = {}
    if recipe.reagents then
        for _, reagent in ipairs(recipe.reagents) do
            -- Always add the base item with full per-craft requirement
            local entry = {
                itemID = reagent.itemID,
                qualityID = 0,
                quantity = reagent.quantity,       -- per craft requirement
                baseItemID = reagent.itemID,
                requiredTotal = reagent.quantity,
            }
            -- Include quality variant itemIDs so allocator can check all of them
            if reagent.hasQuality and reagent.qualityItems then
                entry.qualityItems = reagent.qualityItems
            end
            reagents[#reagents + 1] = entry
        end
    end

    return {
        recipeID = recipeID,
        recipeName = recipe.recipeName,
        profit = 0,
        craftingCost = 0,
        targetQuality = 1,
        concentrationCost = 0,
        concentrationInfo = nil,
        supportsQualities = recipe.supportsQualities,
        maxQuality = 1,
        reagents = reagents,
        qualityPrices = nil,
        qualityResults = {},
        crafters = crafters,
        maxCraftable = result.maxCraftable,
        deficits = result.deficits,
        subcrafts = result.subcrafts,
    }
end

-- Invalidate the cache (call when watched recipes change)
function ns.CraftSimPlanner.InvalidateCache()
    cachedResults = nil
    cacheTime = 0
end
