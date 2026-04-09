local ADDON_NAME, ns = ...

ns.Repository = {}

function ns.Repository.Initialize()
    -- Ensure DB structures exist
    if not ns.DB.localScans.characters then
        ns.DB.localScans.characters = {}
    end
    if not ns.DB.networkSnapshots then
        ns.DB.networkSnapshots = {}
    end
    if not ns.DB.mergedIndex then
        ns.DB.mergedIndex = { itemTotals = {}, recipeOwners = {}, professionOwners = {} }
    end
    if not ns.DB.watchedRecipes then
        ns.DB.watchedRecipes = {}
    end
end

-- Local character data
function ns.Repository.GetLocalCharacter(charKey)
    return ns.DB.localScans.characters[charKey]
end

function ns.Repository.GetAllLocalCharacters()
    return ns.DB.localScans.characters
end

function ns.Repository.GetLocalCharacterKeys()
    return ns.TableUtil.Keys(ns.DB.localScans.characters)
end

-- Network snapshots
function ns.Repository.GetNetworkSnapshot(accountKey)
    return ns.DB.networkSnapshots[accountKey]
end

function ns.Repository.GetAllNetworkSnapshots()
    return ns.DB.networkSnapshots
end

function ns.Repository.RemoveNetworkSnapshot(accountKey)
    ns.DB.networkSnapshots[accountKey] = nil
end

-- Merged index
function ns.Repository.GetMergedIndex()
    return ns.DB.mergedIndex
end

-- Watched recipes
function ns.Repository.IsWatched(recipeID)
    return ns.DB.watchedRecipes[recipeID] == true
end

function ns.Repository.SetWatched(recipeID, watched)
    ns.DB.watchedRecipes[recipeID] = watched and true or nil
    ns.CraftSimPlanner.InvalidateCache()
    ns.Events.Fire("PSC_WATCHED_RECIPES_CHANGED")
end

function ns.Repository.GetWatchedRecipes()
    return ns.DB.watchedRecipes
end

-- Freshness queries
function ns.Repository.GetScanAge(charKey)
    local char = ns.DB.localScans.characters[charKey]
    if not char then return math.huge end
    return ns.TimeUtil.GetAge(char.lastScan)
end

function ns.Repository.GetFreshnessState(charKey)
    local char = ns.DB.localScans.characters[charKey]
    if not char then return "expired" end
    return ns.TimeUtil.GetFreshnessState(char.lastScan)
end

function ns.Repository.GetSnapshotFreshnessState(accountKey)
    local snapshot = ns.DB.networkSnapshots[accountKey]
    if not snapshot then return "expired" end
    return ns.TimeUtil.GetFreshnessState(snapshot.lastReceived)
end

-- Iterate all characters (local + network)
function ns.Repository.IterateAllCharacters(callback)
    -- Local characters
    for charKey, charData in pairs(ns.DB.localScans.characters) do
        callback(charKey, charData, ns.DB.localAccount.accountKey, true)
    end
    -- Network characters
    for accountKey, snapshot in pairs(ns.DB.networkSnapshots) do
        if snapshot.characters then
            for charKey, charData in pairs(snapshot.characters) do
                callback(charKey, charData, accountKey, false)
            end
        end
    end
end

-- Get all account keys (local + network)
function ns.Repository.GetAllAccountKeys()
    local keys = { ns.DB.localAccount.accountKey }
    for accountKey in pairs(ns.DB.networkSnapshots) do
        keys[#keys + 1] = accountKey
    end
    return keys
end

-- Get characters for a specific account
function ns.Repository.GetCharactersForAccount(accountKey)
    if accountKey == ns.DB.localAccount.accountKey then
        return ns.DB.localScans.characters
    end
    local snapshot = ns.DB.networkSnapshots[accountKey]
    if snapshot and snapshot.characters then
        return snapshot.characters
    end
    return {}
end
