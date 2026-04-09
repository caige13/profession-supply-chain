local ADDON_NAME, ns = ...

ns.ItemUtil = {}

-- Extract itemID from an item link
function ns.ItemUtil.GetItemIDFromLink(itemLink)
    if not itemLink then return nil end
    local itemID = itemLink:match("item:(%d+)")
    if itemID then
        return tonumber(itemID)
    end
    return nil
end

-- Extract itemID from various input types
function ns.ItemUtil.NormalizeItemID(input)
    if type(input) == "number" then
        return input
    elseif type(input) == "string" then
        local asNumber = tonumber(input)
        if asNumber then
            return asNumber
        end
        return ns.ItemUtil.GetItemIDFromLink(input)
    end
    return nil
end

-- Get a display-friendly item name, with fallback
function ns.ItemUtil.GetItemName(itemID)
    if not itemID then return "Unknown" end
    local itemName = C_Item.GetItemNameByID(itemID)
    return itemName or ("Item #" .. itemID)
end

-- Get inline icon+name string for use in FontStrings: "|Ticon:16|t Name"
function ns.ItemUtil.GetIconName(itemID, iconSize)
    if not itemID then return "Unknown" end
    iconSize = iconSize or 16
    local name = ns.ItemUtil.GetItemName(itemID)
    local icon = C_Item.GetItemIconByID(itemID)
    if icon then
        return string.format("|T%s:%d|t %s", icon, iconSize, name)
    end
    return name
end

-- Get just the inline icon texture string
function ns.ItemUtil.GetIconString(itemID, iconSize)
    if not itemID then return "" end
    iconSize = iconSize or 16
    local icon = C_Item.GetItemIconByID(itemID)
    if icon then
        return string.format("|T%s:%d|t", icon, iconSize)
    end
    return ""
end

-- Cache for vendor item detection
local vendorItemCache = {}

-- Check if an item is a vendor-purchasable reagent (vials, threads, etc.)
function ns.ItemUtil.IsVendorItem(itemID)
    if not itemID then return false end

    -- Check cache first
    if vendorItemCache[itemID] ~= nil then
        return vendorItemCache[itemID]
    end

    local classID, subclassID

    -- GetItemInfoInstant is always available (no server query)
    local infoFunc = GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant)
    if infoFunc then
        local ok, _, _, _, _, _, cID, scID = pcall(infoFunc, itemID)
        if ok then
            classID = cID
            subclassID = scID
        end
    end

    if not classID then
        -- Can't determine — request cache and assume not vendor for now
        pcall(C_Item.RequestLoadItemDataByID, itemID)
        return false
    end

    local isVendor = false

    -- Trade Goods class (7), subclass 0 = "Other/Trade Goods" — vendor reagents
    -- Real gathering materials: Herb(9), Ore(7), Gems(4), Cloth(5), Leather(6), etc.
    if classID == 7 and subclassID == 0 then
        -- Generic trade good — check quality via GetItemInfo
        local _, _, quality = C_Item.GetItemInfo(itemID)
        if quality and quality <= 1 then
            isVendor = true
        elseif not quality then
            pcall(C_Item.RequestLoadItemDataByID, itemID)
        end
    end

    -- Consumable class (0), subclass 0 (generic) with no quality = vendor food/water
    if classID == 0 and subclassID == 0 then
        local _, _, quality = C_Item.GetItemInfo(itemID)
        if quality and quality <= 1 then
            isVendor = true
        end
    end

    -- Name-based detection as fallback — runs regardless of class/subclass
    -- to catch vendor reagents with unexpected classifications (e.g., Midnight items)
    if not isVendor then
        local name = C_Item.GetItemNameByID(itemID)
        if name then
            local lowerName = name:lower()
            if lowerName:find("vial") or lowerName:find("phial$") or
               lowerName:find("thread") or lowerName:find("flux") or
               lowerName:find("coal") or lowerName:find("dye") or
               lowerName:find("spool") or lowerName:find("polish") or
               lowerName:find("solvent") or lowerName:find("bleach") then
                isVendor = true
            end
        end
    end

    vendorItemCache[itemID] = isVendor
    return isVendor
end

-- Clear vendor item cache (call if item info becomes available later)
function ns.ItemUtil.ClearVendorCache()
    wipe(vendorItemCache)
end

-- Get inline quality tier icon string for FontStrings: |A:atlas:h:w|a
-- qualityID: 1, 2, or 3
function ns.ItemUtil.GetQualityIcon(qualityID, size)
    size = size or 14
    local atlas = "Professions-ChatIcon-Quality-Tier" .. (qualityID or 1)
    return string.format("|A:%s:%d:%d|a", atlas, size, size)
end

-- Get quality label with icon: e.g. "|A:...|a Q2"
function ns.ItemUtil.GetQualityLabel(qualityID, size)
    if not qualityID or qualityID <= 0 then return "" end
    return ns.ItemUtil.GetQualityIcon(qualityID, size) .. " Q" .. qualityID
end

-- Get item quality color
function ns.ItemUtil.GetItemQualityColor(itemID)
    if not itemID then return 1, 1, 1 end
    local _, _, quality = C_Item.GetItemInfo(itemID)
    if quality then
        local r, g, b = C_Item.GetItemQualityColor(quality)
        return r, g, b
    end
    return 1, 1, 1
end

-- Create a character key from name and realm
function ns.ItemUtil.MakeCharacterKey(name, realm)
    if not name then return nil end
    if not realm or realm == "" then
        realm = GetNormalizedRealmName() or GetRealmName() or "UnknownRealm"
    end
    -- Remove spaces from realm name
    realm = realm:gsub("%s+", "")
    return name .. "-" .. realm
end

-- Parse a character key into name and realm
function ns.ItemUtil.ParseCharacterKey(charKey)
    if not charKey then return nil, nil end
    local name, realm = charKey:match("^(.+)-(.+)$")
    return name, realm
end

-- Get a friendly display name for an account key
-- Returns first character name on that account, or shortened key
function ns.ItemUtil.GetAccountDisplayName(accountKey)
    if not accountKey then return "Unknown" end

    -- Local account: use "My Account" or first char name
    if accountKey == ns.DB.localAccount.accountKey then
        local chars = ns.DB.localScans.characters
        for charKey in pairs(chars) do
            local name = charKey:match("^(.+)-")
            if name then return name .. "'s Account" end
        end
        return "My Account"
    end

    -- Network account: use first character name from snapshot
    local snapshot = ns.DB.networkSnapshots[accountKey]
    if snapshot and snapshot.characters then
        for charKey in pairs(snapshot.characters) do
            local name = charKey:match("^(.+)-")
            if name then return name .. "'s Account" end
        end
        if snapshot.sender then
            local name = snapshot.sender:match("^(.+)-")
            if name then return name .. "'s Account" end
        end
    end

    -- Fallback: shorten the key
    return accountKey:match("^acc_(.-)_") or accountKey:sub(1, 15)
end
