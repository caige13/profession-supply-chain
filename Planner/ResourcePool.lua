local ADDON_NAME, ns = ...

ns.ResourcePool = {}

-- Build a merged resource demand pool from optimized recipes
-- Merges the same reagent across multiple recipes into one entry
function ns.ResourcePool.Build(optimizedRecipes)
    local pool = {}

    if not optimizedRecipes then return pool end

    for _, recipe in ipairs(optimizedRecipes) do
        if recipe.reagents then
            local craftCount = math.max(recipe.maxCraftable or 1, 1)

            for _, alloc in ipairs(recipe.reagents) do
                local baseID = alloc.baseItemID or alloc.itemID
                local itemID = alloc.itemID

                -- Skip vendor-purchasable reagents (vials, threads, etc.)
                if ns.ItemUtil.IsVendorItem(baseID) then
                    -- vendor item, always available, not a bottleneck
                else

                local needed = alloc.quantity * craftCount

                if not pool[baseID] then
                    pool[baseID] = {
                        baseItemID = baseID,
                        name = ns.ItemUtil.GetItemName(baseID),
                        qualityItems = {},
                        qualityItemSet = {},  -- for dedup
                        demand = {},
                        available = {},
                        totalDemand = 0,
                        totalAvailable = 0,
                        deficit = 0,
                        demandedBy = {},
                        demandedByNames = {},
                    }
                end

                local entry = pool[baseID]

                -- Track quality variants
                if not entry.qualityItemSet[itemID] then
                    entry.qualityItemSet[itemID] = true
                    entry.qualityItems[#entry.qualityItems + 1] = {
                        itemID = itemID,
                        qualityID = alloc.qualityID or 0,
                    }
                end

                -- Accumulate demand per quality item
                entry.demand[itemID] = (entry.demand[itemID] or 0) + needed
                entry.totalDemand = entry.totalDemand + needed

                -- Track which recipes need this
                local found = false
                for _, rid in ipairs(entry.demandedBy) do
                    if rid == recipe.recipeID then found = true; break end
                end
                if not found then
                    entry.demandedBy[#entry.demandedBy + 1] = recipe.recipeID
                    entry.demandedByNames[#entry.demandedByNames + 1] = recipe.recipeName or ("Recipe #" .. recipe.recipeID)
                end

                end -- end vendor item else
            end
        end
    end

    -- Fill in available quantities and compute deficits
    for baseID, entry in pairs(pool) do
        entry.totalAvailable = 0
        for _, qi in ipairs(entry.qualityItems) do
            local have = ns.InventoryIndex.GetTotal(qi.itemID)
            entry.available[qi.itemID] = have
            entry.totalAvailable = entry.totalAvailable + have
        end

        -- Also check the base item itself if it's not in qualityItems
        if not entry.qualityItemSet[baseID] then
            local baseHave = ns.InventoryIndex.GetTotal(baseID)
            if baseHave > 0 then
                entry.available[baseID] = baseHave
                entry.totalAvailable = entry.totalAvailable + baseHave
            end
        end

        entry.deficit = math.max(0, entry.totalDemand - entry.totalAvailable)
    end

    return pool
end

-- Get resources sorted by deficit (most impactful first)
function ns.ResourcePool.GetSortedDeficits(pool)
    local deficits = {}
    for baseID, entry in pairs(pool) do
        if entry.deficit > 0 then
            deficits[#deficits + 1] = entry
        end
    end
    table.sort(deficits, function(a, b)
        return a.deficit > b.deficit
    end)
    return deficits
end

-- Get all resources sorted by total demand
function ns.ResourcePool.GetSortedByDemand(pool)
    local sorted = {}
    for baseID, entry in pairs(pool) do
        sorted[#sorted + 1] = entry
    end
    table.sort(sorted, function(a, b)
        return a.totalDemand > b.totalDemand
    end)
    return sorted
end
