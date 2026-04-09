local ADDON_NAME, ns = ...

ns.TSMAdapter = {}

local tsmAvailable = false

function ns.TSMAdapter.Initialize()
    tsmAvailable = ns.TSMAdapter.DetectTSM()
    if tsmAvailable then
        ns.Debug("TSM detected and available")
    else
        ns.Debug("TSM not detected — adapter disabled")
    end
end

function ns.TSMAdapter.DetectTSM()
    -- TSM exposes its API through the TSM_API global
    if TSM_API then
        return true
    end
    -- Fallback: check for the old-style global
    if TSMAPI_FOUR or TSMAPI then
        return true
    end
    return false
end

function ns.TSMAdapter.IsAvailable()
    if not ns.DB.settings.enableTSM then
        return false
    end
    return tsmAvailable
end

-- Get the market value of an item
-- priceSource: "DBMarket", "DBMinBuyout", "DBRegionMarketAvg", etc.
function ns.TSMAdapter.GetItemValue(itemString, priceSource)
    if not ns.TSMAdapter.IsAvailable() then return nil end

    priceSource = priceSource or "DBMarket"

    -- Normalize to TSM item string format
    if type(itemString) == "number" then
        itemString = "i:" .. itemString
    end

    if TSM_API and TSM_API.GetCustomPriceValue then
        local value = TSM_API.GetCustomPriceValue(priceSource, itemString)
        return value
    end

    return nil
end

-- Get AH quantity for an item
function ns.TSMAdapter.GetAuctionQuantity(itemString)
    if not ns.TSMAdapter.IsAvailable() then return nil end

    if type(itemString) == "number" then
        itemString = "i:" .. itemString
    end

    if TSM_API and TSM_API.GetCustomPriceValue then
        return TSM_API.GetCustomPriceValue("DBRegionSoldPerDay", itemString)
    end

    return nil
end

-- Get a formatted gold string for an item value
function ns.TSMAdapter.GetFormattedValue(itemID, priceSource)
    local value = ns.TSMAdapter.GetItemValue(itemID, priceSource)
    if not value or value == 0 then
        return nil
    end
    -- Convert copper to gold string
    return GetCoinTextureString(value)
end

-- Get total value of items across the network
function ns.TSMAdapter.GetTotalValue(itemID, priceSource)
    local unitValue = ns.TSMAdapter.GetItemValue(itemID, priceSource)
    if not unitValue then return nil end

    local totalQty = ns.InventoryIndex.GetTotal(itemID)
    return unitValue * totalQty
end
