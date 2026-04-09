local ADDON_NAME, ns = ...

ns.Bottlenecks = {}

-- Analyze bottlenecks across all watched recipes using CraftSimPlanner + ResourcePool
function ns.Bottlenecks.Analyze()
    local bottlenecks = {}

    local optimized = ns.CraftSimPlanner.OptimizeWatchedRecipes()
    if #optimized == 0 then return bottlenecks end

    local pool = ns.ResourcePool.Build(optimized)
    local deficits = ns.ResourcePool.GetSortedDeficits(pool)

    -- Resource deficits (merged across recipes)
    for _, entry in ipairs(deficits) do
        local qualityBreakdown = {}
        for _, qi in ipairs(entry.qualityItems) do
            local demand = entry.demand[qi.itemID] or 0
            local have = entry.available[qi.itemID] or 0
            if demand > 0 then
                qualityBreakdown[#qualityBreakdown + 1] = {
                    itemID = qi.itemID,
                    qualityID = qi.qualityID,
                    demand = demand,
                    have = have,
                    deficit = math.max(0, demand - have),
                }
            end
        end

        bottlenecks[#bottlenecks + 1] = {
            type = "missing_resource",
            itemID = entry.baseItemID,
            itemName = entry.name,
            deficit = entry.deficit,
            totalDemand = entry.totalDemand,
            totalAvailable = entry.totalAvailable,
            qualityBreakdown = qualityBreakdown,
            demandedBy = entry.demandedBy,
            demandedByNames = entry.demandedByNames,
            severity = entry.deficit,
            message = string.format("Need %d %s — have %d (deficit %d) — used by: %s",
                entry.totalDemand, entry.name,
                entry.totalAvailable, entry.deficit,
                table.concat(entry.demandedByNames, ", ")),
        }
    end

    -- Missing crafter checks
    for _, recipe in ipairs(optimized) do
        if not recipe.crafters or #recipe.crafters == 0 then
            bottlenecks[#bottlenecks + 1] = {
                type = "missing_crafter",
                recipeID = recipe.recipeID,
                recipeName = recipe.recipeName,
                severity = 100,
                message = string.format("No character knows recipe: %s", recipe.recipeName or "?"),
            }
        end
    end

    -- Concentration limits
    for _, recipe in ipairs(optimized) do
        if recipe.concentrationInfo and recipe.concentrationCost > 0 then
            local ci = recipe.concentrationInfo
            if ci.current < recipe.concentrationCost then
                bottlenecks[#bottlenecks + 1] = {
                    type = "concentration_limited",
                    recipeID = recipe.recipeID,
                    recipeName = recipe.recipeName,
                    concentrationCost = recipe.concentrationCost,
                    concentrationCurrent = ci.current,
                    severity = 50,
                    message = string.format("%s needs %d concentration — have %d",
                        recipe.recipeName or "?", recipe.concentrationCost, ci.current),
                }
            end
        end
    end

    -- Stale scan checks
    for _, recipe in ipairs(optimized) do
        if recipe.crafters then
            for _, charKey in ipairs(recipe.crafters) do
                local freshness = ns.Repository.GetFreshnessState(charKey)
                if freshness == "stale" or freshness == "expired" then
                    bottlenecks[#bottlenecks + 1] = {
                        type = "stale_scan",
                        recipeID = recipe.recipeID,
                        recipeName = recipe.recipeName,
                        characterKey = charKey,
                        freshness = freshness,
                        severity = 10,
                        message = string.format("Scan data for %s is %s", charKey, freshness),
                    }
                end
            end
        end
    end

    -- Sort by severity
    table.sort(bottlenecks, function(a, b)
        return (a.severity or 0) > (b.severity or 0)
    end)

    return bottlenecks
end

-- Get the single most impactful bottleneck
function ns.Bottlenecks.GetTopBottleneck()
    local all = ns.Bottlenecks.Analyze()
    return all[1]
end

-- Get bottlenecks for a specific recipe
function ns.Bottlenecks.GetForRecipe(recipeID)
    local all = ns.Bottlenecks.Analyze()
    local filtered = {}
    for _, bn in ipairs(all) do
        if bn.recipeID == recipeID or
           (bn.demandedBy and ns.TableUtil.Contains(bn.demandedBy, recipeID)) then
            filtered[#filtered + 1] = bn
        end
    end
    return filtered
end
