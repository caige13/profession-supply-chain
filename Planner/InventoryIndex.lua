local ADDON_NAME, ns = ...

ns.InventoryIndex = {}

function ns.InventoryIndex.Initialize()
    -- Index is built as part of Merge.RebuildIndex
end

-- Get total quantity of an item across all characters/accounts
function ns.InventoryIndex.GetTotal(itemID)
    local entry = ns.DB.mergedIndex.itemTotals[itemID]
    return entry and entry.total or 0
end

-- Get quantity of an item held by a specific character
function ns.InventoryIndex.GetByCharacter(itemID, charKey)
    local entry = ns.DB.mergedIndex.itemTotals[itemID]
    if entry and entry.byCharacter then
        return entry.byCharacter[charKey] or 0
    end
    return 0
end

-- Get quantity of an item held by a specific account
function ns.InventoryIndex.GetByAccount(itemID, accountKey)
    local entry = ns.DB.mergedIndex.itemTotals[itemID]
    if entry and entry.byAccount then
        return entry.byAccount[accountKey] or 0
    end
    return 0
end

-- Get breakdown of where an item is located
function ns.InventoryIndex.GetBreakdown(itemID)
    local entry = ns.DB.mergedIndex.itemTotals[itemID]
    if not entry then
        return { total = 0, byCharacter = {}, byAccount = {} }
    end
    return entry
end

-- Get all items with quantity > 0
function ns.InventoryIndex.GetAllItems()
    return ns.DB.mergedIndex.itemTotals
end

-- Search items by name (partial match)
function ns.InventoryIndex.SearchByName(searchText)
    local results = {}
    searchText = searchText:lower()

    for itemID, entry in pairs(ns.DB.mergedIndex.itemTotals) do
        local itemName = ns.ItemUtil.GetItemName(itemID)
        if itemName and itemName:lower():find(searchText, 1, true) then
            results[itemID] = entry
        end
    end

    return results
end

-- Get source bucket breakdown for a specific character's item
function ns.InventoryIndex.GetCharacterItemBuckets(charKey, itemID)
    local charData = nil

    -- Check local characters
    charData = ns.DB.localScans.characters[charKey]

    -- Check network characters
    if not charData then
        for _, snapshot in pairs(ns.DB.networkSnapshots) do
            if snapshot.characters and snapshot.characters[charKey] then
                charData = snapshot.characters[charKey]
                break
            end
        end
    end

    if not charData or not charData.inventory or not charData.inventory[itemID] then
        return { bags = 0, bank = 0, reagentBank = 0, mail = 0, total = 0 }
    end

    return charData.inventory[itemID]
end

-- Get inventory breakdown per quality tier for a reagent with quality variants
-- qualityItems: { q1ItemID, q2ItemID, q3ItemID }
-- Returns: { [itemID] = totalQty, ... }
function ns.InventoryIndex.GetQualityBreakdown(qualityItems)
    if not qualityItems then return {} end
    local breakdown = {}
    for _, itemID in ipairs(qualityItems) do
        breakdown[itemID] = ns.InventoryIndex.GetTotal(itemID)
    end
    return breakdown
end

-- Sum total inventory across all quality variants of a reagent
function ns.InventoryIndex.GetTotalAcrossQualities(qualityItems)
    if not qualityItems then return 0 end
    local total = 0
    for _, itemID in ipairs(qualityItems) do
        total = total + ns.InventoryIndex.GetTotal(itemID)
    end
    return total
end

-- Get per-character breakdown for a quality item set
-- Returns: { [charKey] = { [itemID] = qty, ... }, ... }
function ns.InventoryIndex.GetQualityByCharacter(qualityItems)
    if not qualityItems then return {} end
    local result = {}
    for _, itemID in ipairs(qualityItems) do
        local entry = ns.DB.mergedIndex.itemTotals[itemID]
        if entry and entry.byCharacter then
            for charKey, qty in pairs(entry.byCharacter) do
                if not result[charKey] then result[charKey] = {} end
                result[charKey][itemID] = qty
            end
        end
    end
    return result
end
