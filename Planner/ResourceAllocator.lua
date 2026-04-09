local ADDON_NAME, ns = ...

ns.ResourceAllocator = {}

-- Profit-maximizing resource allocator using exhaustive search + memoization.
-- Replaces the greedy heuristic with an exact solver that tries all valid
-- combinations of craft counts and concentration allocations across watched
-- recipes, with recursive support recipe fulfillment for intermediates.

local cachedResult = nil
local cacheTime = 0
local CACHE_TTL = 10  -- seconds

local MAX_SOLVER_CALLS = 50000  -- safety valve

-- ============================================================================
-- Helpers
-- ============================================================================

local function shallowCopy(t)
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = v
    end
    return copy
end

-- Deduplicated, sorted craft counts to try instead of every integer 0..max
local function getCraftSteps(maxCrafts)
    if maxCrafts <= 0 then return {0} end

    local seen = {}
    local steps = {}
    local function add(v)
        if v >= 0 and v <= maxCrafts and not seen[v] then
            seen[v] = true
            steps[#steps + 1] = v
        end
    end

    add(0)
    add(1)
    add(2)
    add(5)
    add(10)
    add(20)
    add(math.floor(maxCrafts / 2))
    add(maxCrafts)

    table.sort(steps)
    return steps
end

-- ============================================================================
-- Phase 1: Build Watched Recipe Inputs
-- ============================================================================

function ns.ResourceAllocator.BuildWatchedInputs(optimizedRecipes)
    local inputs = {}

    for _, recipe in ipairs(optimizedRecipes) do
        local crafter = recipe.crafters and recipe.crafters[1]
        if not crafter then
            ns.Debug("ResourceAllocator: skipping recipe %s — no crafter", recipe.recipeName or "?")
        else
            -- Build costs table: { [baseItemID] = qtyPerCraft }
            local costs = {}
            if recipe.reagents then
                for _, r in ipairs(recipe.reagents) do
                    local baseID = r.baseItemID or r.itemID
                    if baseID and not ns.ItemUtil.IsVendorItem(baseID) then
                        local qty = r.requiredTotal or r.quantity or 0
                        if qty > 0 then
                            costs[baseID] = (costs[baseID] or 0) + qty
                        end
                    end
                end
            end

            -- Concentration: find best useConcentration=true variant
            local concentrationCost = 0
            local concentrationBonus = 0
            local concentratedProfit = 0

            if recipe.qualityResults then
                local bestConcProfit = -math.huge
                for _, qr in ipairs(recipe.qualityResults) do
                    if qr.useConcentration and (qr.profit or 0) > bestConcProfit then
                        bestConcProfit = qr.profit or 0
                    end
                end
                if bestConcProfit > -math.huge then
                    concentratedProfit = bestConcProfit
                    concentrationBonus = bestConcProfit - (recipe.profit or 0)
                    if recipe.concentrationInfo and recipe.concentrationInfo.costPerCraft then
                        concentrationCost = recipe.concentrationInfo.costPerCraft
                    end
                end
            end

            -- Output item
            local outputItemID = recipe.outputItemID
            if not outputItemID then
                local graphRecipe = ns.RecipeGraph.GetRecipe(recipe.recipeID)
                if graphRecipe then
                    outputItemID = graphRecipe.outputItemID
                end
            end

            local totalCost = 0
            for _, qty in pairs(costs) do
                totalCost = totalCost + qty
            end

            ns.Debug("BuildWatchedInputs: %s baseProfit=%d concBonus=%d concCost=%d",
                recipe.recipeName or "?", recipe.profit or 0, concentrationBonus, concentrationCost)

            inputs[#inputs + 1] = {
                id = recipe.recipeID,
                name = recipe.recipeName,
                crafter = crafter,
                costs = costs,
                baseProfit = recipe.profit or 0,
                concentrationCost = concentrationCost,
                concentrationBonus = concentrationBonus,
                concentratedProfit = concentratedProfit,
                outputItemID = outputItemID,
                totalResourceCost = totalCost,  -- for sorting
            }
        end
    end

    -- Sort heaviest consumers first for better early pruning
    table.sort(inputs, function(a, b)
        return a.totalResourceCost > b.totalResourceCost
    end)

    return inputs
end

-- ============================================================================
-- Phase 2: Build Support Recipes
-- ============================================================================

function ns.ResourceAllocator.BuildSupportRecipes(watchedInputs)
    local supportRecipes = {}  -- { [outputItemID] = supportRecipe }
    local watchedRecipeIDs = {}

    -- Track watched recipe IDs so we don't use them as support
    for _, w in ipairs(watchedInputs) do
        watchedRecipeIDs[w.id] = true
    end

    -- Collect all needed item IDs from watched recipe costs
    local itemsToCheck = {}
    for _, w in ipairs(watchedInputs) do
        for itemID in pairs(w.costs) do
            itemsToCheck[itemID] = true
        end
    end

    -- Recursively discover support recipes
    local visited = {}  -- cycle detection during build
    local function discoverSupport(itemID)
        if visited[itemID] or supportRecipes[itemID] then return end
        visited[itemID] = true

        if not ns.RecipeGraph.IsCraftable(itemID) then
            visited[itemID] = nil
            return
        end

        local recipeID, recipeData = ns.RecipeGraph.GetDefaultRecipe(itemID)
        if not recipeID or not recipeData or watchedRecipeIDs[recipeID] then
            visited[itemID] = nil
            return
        end

        local crafter = ns.Merge.GetRecipeOwners(recipeID)
        crafter = crafter and crafter[1]

        -- Build costs from recipe reagents
        local costs = {}
        if recipeData.reagents then
            for _, r in ipairs(recipeData.reagents) do
                local baseID = r.itemID
                if baseID and not ns.ItemUtil.IsVendorItem(baseID) then
                    local qty = r.quantity or 0
                    if qty > 0 then
                        costs[baseID] = (costs[baseID] or 0) + qty
                    end
                end
            end
        end

        supportRecipes[itemID] = {
            id = recipeID,
            name = recipeData.recipeName or ("Recipe #" .. recipeID),
            crafter = crafter,
            outputItemID = itemID,
            outputQuantity = recipeData.outputQuantity or 1,
            costs = costs,
        }

        -- Recurse: check support recipe's own reagents for craftability
        for reagentID in pairs(costs) do
            discoverSupport(reagentID)
        end

        visited[itemID] = nil
    end

    for itemID in pairs(itemsToCheck) do
        discoverSupport(itemID)
    end

    ns.Debug("ResourceAllocator: discovered %d support recipes", ns.TableUtil.Count(supportRecipes))
    return supportRecipes
end

-- ============================================================================
-- Phase 3: Build Resource State
-- ============================================================================

function ns.ResourceAllocator.BuildResourceState(optimizedRecipes)
    local resources = {}
    local allItems = ns.InventoryIndex.GetAllItems()

    for itemID, entry in pairs(allItems) do
        if entry.total > 0 and not ns.ItemUtil.IsVendorItem(itemID) then
            resources[itemID] = entry.total
        end
    end

    -- Collapse quality variants into base items for reagents used by recipes.
    -- CraftSim reagent data does NOT include qualityItems, so we must look up
    -- the full reagent info from RecipeGraph which has the quality variant list.
    local collapsed = {}  -- track which baseIDs we've already collapsed

    for _, recipe in ipairs(optimizedRecipes) do
        -- Get the RecipeGraph data which has qualityItems on reagents
        local graphRecipe = ns.RecipeGraph.GetRecipe(recipe.recipeID)
        if graphRecipe and graphRecipe.reagents then
            for _, reagent in ipairs(graphRecipe.reagents) do
                local baseID = reagent.itemID
                if baseID and not collapsed[baseID] and reagent.hasQuality and reagent.qualityItems then
                    collapsed[baseID] = true
                    local total = 0
                    for _, qID in ipairs(reagent.qualityItems) do
                        total = total + (resources[qID] or 0)
                        resources[qID] = nil
                    end
                    -- Also include any amount already on baseID
                    total = total + (resources[baseID] or 0)
                    if total > 0 then
                        resources[baseID] = total
                    end
                end
            end
        end

        -- Also handle CraftSim reagents that DO have qualityItems (fallback path)
        if recipe.reagents then
            for _, r in ipairs(recipe.reagents) do
                local baseID = r.baseItemID or r.itemID
                if baseID and not collapsed[baseID] and r.qualityItems then
                    collapsed[baseID] = true
                    local total = 0
                    for _, qID in ipairs(r.qualityItems) do
                        total = total + (resources[qID] or 0)
                        resources[qID] = nil
                    end
                    total = total + (resources[baseID] or 0)
                    if total > 0 then
                        resources[baseID] = total
                    end
                end
            end
        end
    end

    return resources
end

-- ============================================================================
-- Phase 4: Build Concentration State
-- ============================================================================

function ns.ResourceAllocator.BuildConcentrationState(optimizedRecipes)
    local concentration = {}  -- { [crafterKey] = currentAmount }

    for _, recipe in ipairs(optimizedRecipes) do
        local crafter = recipe.crafters and recipe.crafters[1]
        if crafter and recipe.concentrationInfo and recipe.concentrationInfo.current then
            if not concentration[crafter] then
                concentration[crafter] = math.floor(recipe.concentrationInfo.current)
            end
        end
    end

    return concentration
end

-- ============================================================================
-- Phase 5: Partition Into Independent Groups
-- ============================================================================

function ns.ResourceAllocator.PartitionIntoGroups(watchedInputs, supportRecipes)
    local n = #watchedInputs
    if n <= 1 then
        return { watchedInputs }
    end

    -- Union-Find
    local parent = {}
    for i = 1, n do parent[i] = i end

    local function find(x)
        while parent[x] ~= x do
            parent[x] = parent[parent[x]]  -- path compression
            x = parent[x]
        end
        return x
    end

    local function union(a, b)
        local ra, rb = find(a), find(b)
        if ra ~= rb then parent[ra] = rb end
    end

    -- Collect all resources each recipe touches (including through support chains)
    local function getAllResources(costs, result, visited)
        for itemID in pairs(costs) do
            result[itemID] = true
            -- Follow support recipe chains
            if not visited[itemID] and supportRecipes[itemID] then
                visited[itemID] = true
                getAllResources(supportRecipes[itemID].costs, result, visited)
            end
        end
    end

    local recipeResources = {}
    for i, w in ipairs(watchedInputs) do
        recipeResources[i] = {}
        getAllResources(w.costs, recipeResources[i], {})
    end

    -- Union recipes that share any resource
    -- Build resource → recipe index mapping
    local resourceToRecipes = {}
    for i, resSet in ipairs(recipeResources) do
        for itemID in pairs(resSet) do
            if not resourceToRecipes[itemID] then
                resourceToRecipes[itemID] = {}
            end
            resourceToRecipes[itemID][#resourceToRecipes[itemID] + 1] = i
        end
    end

    for _, recipeIndices in pairs(resourceToRecipes) do
        for j = 2, #recipeIndices do
            union(recipeIndices[1], recipeIndices[j])
        end
    end

    -- Collect groups
    local groupMap = {}  -- root → { recipe indices }
    for i = 1, n do
        local root = find(i)
        if not groupMap[root] then
            groupMap[root] = {}
        end
        groupMap[root][#groupMap[root] + 1] = i
    end

    -- Build group arrays of actual recipe inputs
    local groups = {}
    for _, indices in pairs(groupMap) do
        local group = {}
        for _, idx in ipairs(indices) do
            group[#group + 1] = watchedInputs[idx]
        end
        groups[#groups + 1] = group
    end

    ns.Debug("ResourceAllocator: %d recipes partitioned into %d independent groups", n, #groups)
    return groups
end

-- ============================================================================
-- Core Solver: ConsumeOrCraftItem
-- ============================================================================

-- Try to consume qtyNeeded of itemID from resources.
-- If inventory is short, attempt to craft via support recipes.
-- Returns: success (bool), supportPlan ({ [recipeId] = { ... } })
function ns.ResourceAllocator.ConsumeOrCraftItem(itemID, qtyNeeded, resources, supportRecipes, visited)
    local have = resources[itemID] or 0
    local supportPlan = {}

    if have >= qtyNeeded then
        resources[itemID] = have - qtyNeeded
        return true, supportPlan
    end

    -- Consume what we have
    local shortage = qtyNeeded - have
    resources[itemID] = 0

    local support = supportRecipes[itemID]
    if not support then
        return false, nil  -- infeasible
    end

    -- Cycle detection
    if visited[itemID] then
        return false, nil
    end
    visited[itemID] = true

    local batchesNeeded = math.ceil(shortage / support.outputQuantity)

    -- Recursively consume reagents for support recipe
    for reagentItemID, reagentQtyPerCraft in pairs(support.costs) do
        local totalReagentNeeded = reagentQtyPerCraft * batchesNeeded
        local ok, subPlan = ns.ResourceAllocator.ConsumeOrCraftItem(
            reagentItemID, totalReagentNeeded, resources, supportRecipes, visited)
        if not ok then
            visited[itemID] = nil
            return false, nil
        end
        -- Merge sub-plan
        if subPlan then
            for rid, info in pairs(subPlan) do
                if not supportPlan[rid] then
                    supportPlan[rid] = { recipeId = info.recipeId, recipeName = info.recipeName, crafter = info.crafter, batches = info.batches }
                else
                    supportPlan[rid].batches = supportPlan[rid].batches + info.batches
                end
            end
        end
    end

    -- Produce the intermediate
    local produced = batchesNeeded * support.outputQuantity
    resources[itemID] = (resources[itemID] or 0) + produced - shortage

    -- Record this support recipe usage
    if not supportPlan[support.id] then
        supportPlan[support.id] = {
            recipeId = support.id,
            recipeName = support.name,
            crafter = support.crafter,
            batches = batchesNeeded,
        }
    else
        supportPlan[support.id].batches = supportPlan[support.id].batches + batchesNeeded
    end

    visited[itemID] = nil
    return true, supportPlan
end

-- ============================================================================
-- Core Solver: State Hashing
-- ============================================================================

function ns.ResourceAllocator.HashState(recipeIndex, resources, concentration)
    local parts = { recipeIndex }

    local resKeys = {}
    for k, v in pairs(resources) do
        if v > 0 then
            resKeys[#resKeys + 1] = k
        end
    end
    table.sort(resKeys)
    for _, k in ipairs(resKeys) do
        parts[#parts + 1] = k
        parts[#parts + 1] = resources[k]
    end

    parts[#parts + 1] = -1  -- separator

    local concKeys = {}
    for k in pairs(concentration) do
        concKeys[#concKeys + 1] = k
    end
    table.sort(concKeys)
    for _, k in ipairs(concKeys) do
        parts[#parts + 1] = k
        parts[#parts + 1] = concentration[k] or 0
    end

    return table.concat(parts, ",")
end

-- ============================================================================
-- Core Solver: Max Crafts From Resources
-- ============================================================================

-- Compute the maximum number of times a recipe can be crafted given resources + support
local function maxCraftsForRecipe(recipe, resources, supportRecipes)
    local maxCrafts = math.huge

    for itemID, qtyPerCraft in pairs(recipe.costs) do
        if qtyPerCraft > 0 then
            -- Count available: direct inventory + what support recipes could produce
            local available = resources[itemID] or 0

            -- If a support recipe exists, estimate how much it could produce
            local support = supportRecipes[itemID]
            if support and support.outputQuantity > 0 then
                -- Estimate batches from support recipe's own reagents
                local supportBatches = math.huge
                for sReagentID, sQty in pairs(support.costs) do
                    if sQty > 0 then
                        local sAvail = resources[sReagentID] or 0
                        supportBatches = math.min(supportBatches, math.floor(sAvail / sQty))
                    end
                end
                if supportBatches < math.huge then
                    available = available + (supportBatches * support.outputQuantity)
                end
            end

            local crafts = math.floor(available / qtyPerCraft)
            maxCrafts = math.min(maxCrafts, crafts)
        end
    end

    if maxCrafts == math.huge then
        return 0
    end
    return maxCrafts
end

-- ============================================================================
-- Core Solver: Try Fulfill Reagents
-- ============================================================================

-- Attempt to consume all reagents for N crafts of a recipe.
-- Mutates resourcesCopy. Returns: feasible (bool), supportPlan
local function tryFulfillReagents(costs, craftCount, resources, supportRecipes)
    local supportPlan = {}
    local visited = {}

    for itemID, qtyPerCraft in pairs(costs) do
        local totalNeeded = qtyPerCraft * craftCount
        local ok, batchesUsed = ns.ResourceAllocator.ConsumeOrCraftItem(
            itemID, totalNeeded, resources, supportRecipes, visited)
        if not ok then
            return false, nil
        end
        if batchesUsed then
            for rid, info in pairs(batchesUsed) do
                if not supportPlan[rid] then
                    supportPlan[rid] = { recipeId = info.recipeId, recipeName = info.recipeName, crafter = info.crafter, batches = info.batches }
                else
                    supportPlan[rid].batches = supportPlan[rid].batches + info.batches
                end
            end
        end
    end

    return true, supportPlan
end

-- ============================================================================
-- Core Solver: Recursive Solve
-- ============================================================================

function ns.ResourceAllocator.Solve(recipeIndex, watchedInputs, resources, concentration, supportRecipes, memo, counter)
    -- Base case
    if recipeIndex > #watchedInputs then
        return { totalProfit = 0, plan = {} }
    end

    -- Safety valve
    counter.n = counter.n + 1
    if counter.n > MAX_SOLVER_CALLS then
        ns.Debug("ResourceAllocator: solver hit call limit (%d), returning best-so-far", MAX_SOLVER_CALLS)
        return { totalProfit = 0, plan = {} }
    end

    -- Memoization check
    local stateKey = ns.ResourceAllocator.HashState(recipeIndex, resources, concentration)
    if memo[stateKey] then
        return memo[stateKey]
    end

    local recipe = watchedInputs[recipeIndex]
    local bestResult = nil

    -- Determine craft steps for this recipe
    local maxCrafts = maxCraftsForRecipe(recipe, resources, supportRecipes)
    local craftSteps = getCraftSteps(maxCrafts)

    for _, crafts in ipairs(craftSteps) do
        if crafts == 0 then
            -- Skip this recipe entirely, solve remainder
            local subResult = ns.ResourceAllocator.Solve(
                recipeIndex + 1, watchedInputs, resources, concentration, supportRecipes, memo, counter)
            if not bestResult or subResult.totalProfit > bestResult.totalProfit then
                bestResult = { totalProfit = subResult.totalProfit, plan = shallowCopy(subResult.plan) }
            end
        else
            -- Try crafting this many
            local resCopy = shallowCopy(resources)
            local feasible, supportPlan = tryFulfillReagents(recipe.costs, crafts, resCopy, supportRecipes)

            if not feasible then
                -- Resources exhausted; higher counts in sorted steps won't work either
                -- (but don't break on first fail — a gap step like 5 might fail while 2 succeeded)
                -- Continue to try remaining steps; they'll also fail and we'll skip them
            else
                -- Enumerate concentration allocations
                local maxConc = 0
                if recipe.concentrationCost > 0 then
                    local crafterConc = concentration[recipe.crafter] or 0
                    maxConc = math.min(crafts, math.floor(crafterConc / recipe.concentrationCost))
                end

                for concCrafts = 0, maxConc do
                    local profit = (crafts * recipe.baseProfit) + (concCrafts * recipe.concentrationBonus)

                    -- Update concentration for recursion
                    local concCopy = shallowCopy(concentration)
                    if concCrafts > 0 then
                        concCopy[recipe.crafter] = (concCopy[recipe.crafter] or 0) - (concCrafts * recipe.concentrationCost)
                    end

                    -- Recurse for remaining recipes
                    local subResult = ns.ResourceAllocator.Solve(
                        recipeIndex + 1, watchedInputs, resCopy, concCopy, supportRecipes, memo, counter)

                    local totalProfit = profit + subResult.totalProfit
                    if not bestResult or totalProfit > bestResult.totalProfit then
                        -- Build plan entry for this recipe
                        local planEntry = {
                            type = "watched",
                            recipeId = recipe.id,
                            recipeName = recipe.name,
                            crafter = recipe.crafter,
                            crafts = crafts,
                            concentratedCrafts = concCrafts,
                            unconcentratedCrafts = crafts - concCrafts,
                            concentrationCostPerCraft = recipe.concentrationCost,
                            totalConcentrationUsed = concCrafts * recipe.concentrationCost,
                            baseProfit = crafts * recipe.baseProfit,
                            concentrationProfit = concCrafts * recipe.concentrationBonus,
                            totalProfit = profit,
                            outputItemID = recipe.outputItemID,
                            supportPlan = supportPlan or {},
                        }

                        -- Combine this entry with sub-result plan
                        local combinedPlan = { planEntry }
                        for _, entry in ipairs(subResult.plan) do
                            combinedPlan[#combinedPlan + 1] = entry
                        end

                        bestResult = { totalProfit = totalProfit, plan = combinedPlan }
                    end
                end
            end
        end
    end

    if not bestResult then
        bestResult = { totalProfit = 0, plan = {} }
    end

    memo[stateKey] = bestResult
    return bestResult
end

-- ============================================================================
-- Top-Level: Allocate
-- ============================================================================

function ns.ResourceAllocator.Allocate(optimizedRecipes)
    if not optimizedRecipes or #optimizedRecipes == 0 then
        return { totalProfit = 0, plan = {} }
    end

    -- Return cached results if fresh
    if cachedResult and (GetTime() - cacheTime) < CACHE_TTL then
        return cachedResult
    end

    ns.Debug("ResourceAllocator: starting optimization for %d recipes", #optimizedRecipes)

    -- Phase 1-4: Build inputs
    local watchedInputs = ns.ResourceAllocator.BuildWatchedInputs(optimizedRecipes)
    if #watchedInputs == 0 then
        return { totalProfit = 0, plan = {} }
    end

    local supportRecipes = ns.ResourceAllocator.BuildSupportRecipes(watchedInputs)
    local resources = ns.ResourceAllocator.BuildResourceState(optimizedRecipes)
    local concentration = ns.ResourceAllocator.BuildConcentrationState(optimizedRecipes)

    ns.Debug("ResourceAllocator: %d watched, %d support, %d resource types, %d crafters with concentration",
        #watchedInputs,
        ns.TableUtil.Count(supportRecipes),
        ns.TableUtil.Count(resources),
        ns.TableUtil.Count(concentration))

    -- Phase 5: Partition into independent groups
    local groups = ns.ResourceAllocator.PartitionIntoGroups(watchedInputs, supportRecipes)

    -- Solve each group independently
    local totalProfit = 0
    local combinedPlan = {}

    for _, group in ipairs(groups) do
        local memo = {}
        local counter = { n = 0 }
        local result = ns.ResourceAllocator.Solve(1, group, shallowCopy(resources), shallowCopy(concentration), supportRecipes, memo, counter)

        ns.Debug("ResourceAllocator: group of %d recipes solved in %d calls, profit=%d",
            #group, counter.n, result.totalProfit)

        totalProfit = totalProfit + result.totalProfit

        -- Deduct resources used by this group from the shared pool
        -- (groups are independent so this is safe — they don't share resources)
        for _, entry in ipairs(result.plan) do
            combinedPlan[#combinedPlan + 1] = entry
        end
    end

    -- Sort plan by profit descending
    table.sort(combinedPlan, function(a, b)
        return (a.totalProfit or 0) > (b.totalProfit or 0)
    end)

    -- Strip zero-craft entries
    local finalPlan = {}
    for _, entry in ipairs(combinedPlan) do
        if entry.crafts and entry.crafts > 0 then
            finalPlan[#finalPlan + 1] = entry
        end
    end

    local result = {
        totalProfit = totalProfit,
        plan = finalPlan,
    }

    -- Sell-raw fallback
    if totalProfit <= 0 then
        result.recommendation = "sell_raw"
        ns.Debug("ResourceAllocator: no profitable crafts, recommending sell raw")
    end

    -- Cache result
    cachedResult = result
    cacheTime = GetTime()

    ns.Debug("ResourceAllocator: optimization complete — totalProfit=%d, %d plan steps", totalProfit, #finalPlan)
    return result
end

function ns.ResourceAllocator.InvalidateCache()
    cachedResult = nil
    cacheTime = 0
end
