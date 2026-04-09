local ADDON_NAME, ns = ...

ns.Merge = {}

local rebuildTimer = nil

local function debouncedRebuild()
    if rebuildTimer then
        rebuildTimer:Cancel()
    end
    rebuildTimer = C_Timer.NewTimer(0.5, function()
        rebuildTimer = nil
        ns.Merge.RebuildIndex()
    end)
end

function ns.Merge.Initialize()
    -- Rebuild index when scans complete (debounced)
    ns.Events.Register("PSC_SCAN_COMPLETE", function(scanType, charKey)
        debouncedRebuild()
    end, "Merge")

    -- Rebuild on snapshot received (debounced)
    ns.Events.Register("PSC_SNAPSHOT_RECEIVED", function(accountKey)
        debouncedRebuild()
    end, "Merge")

    -- Initial build
    C_Timer.After(3, ns.Merge.RebuildIndex)
end

function ns.Merge.RebuildIndex()
    local index = {
        itemTotals = {},
        recipeOwners = {},
        professionOwners = {},
    }

    ns.Repository.IterateAllCharacters(function(charKey, charData, accountKey, isLocal)
        -- Merge inventory
        if charData.inventory then
            for itemID, entry in pairs(charData.inventory) do
                if not index.itemTotals[itemID] then
                    index.itemTotals[itemID] = {
                        total = 0,
                        byCharacter = {},
                        byAccount = {},
                    }
                end

                local itemTotal = index.itemTotals[itemID]
                local charTotal = entry.total or 0
                itemTotal.total = itemTotal.total + charTotal
                itemTotal.byCharacter[charKey] = charTotal

                if not itemTotal.byAccount[accountKey] then
                    itemTotal.byAccount[accountKey] = 0
                end
                itemTotal.byAccount[accountKey] = itemTotal.byAccount[accountKey] + charTotal
            end
        end

        -- Merge recipes
        if charData.recipes then
            for recipeID, recipeData in pairs(charData.recipes) do
                if not index.recipeOwners[recipeID] then
                    index.recipeOwners[recipeID] = {}
                end
                -- Add this character as a recipe owner if not already listed
                local found = false
                for _, existingChar in ipairs(index.recipeOwners[recipeID]) do
                    if existingChar == charKey then
                        found = true
                        break
                    end
                end
                if not found then
                    index.recipeOwners[recipeID][#index.recipeOwners[recipeID] + 1] = charKey
                end
            end
        end

        -- Merge professions
        if charData.professions then
            for profID, profData in pairs(charData.professions) do
                if not index.professionOwners[profID] then
                    index.professionOwners[profID] = {}
                end
                local found = false
                for _, existingChar in ipairs(index.professionOwners[profID]) do
                    if existingChar == charKey then
                        found = true
                        break
                    end
                end
                if not found then
                    index.professionOwners[profID][#index.professionOwners[profID] + 1] = charKey
                end
            end
        end
    end)

    ns.DB.mergedIndex = index
    ns.Debug("Merged index rebuilt: %d items, %d recipes, %d professions",
        ns.TableUtil.Count(index.itemTotals),
        ns.TableUtil.Count(index.recipeOwners),
        ns.TableUtil.Count(index.professionOwners))

    -- Invalidate planner cache so bottlenecks recalculate with new inventory
    ns.CraftSimPlanner.InvalidateCache()

    ns.Events.Fire("PSC_MERGE_UPDATED")
end

-- Get total quantity of an item across all characters
function ns.Merge.GetItemTotal(itemID)
    local entry = ns.DB.mergedIndex.itemTotals[itemID]
    if entry then
        return entry.total
    end
    return 0
end

-- Get which characters know a recipe
function ns.Merge.GetRecipeOwners(recipeID)
    return ns.DB.mergedIndex.recipeOwners[recipeID] or {}
end

-- Get which characters have a profession
function ns.Merge.GetProfessionOwners(professionID)
    return ns.DB.mergedIndex.professionOwners[professionID] or {}
end
