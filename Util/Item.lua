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
