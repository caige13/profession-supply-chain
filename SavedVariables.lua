local ADDON_NAME, ns = ...

ns.SavedVariables = {}

local DB_VERSION = 1

local DB_DEFAULTS = {
    version = DB_VERSION,
    settings = ns.TableUtil.DeepCopy(ns.Config.DEFAULT_SETTINGS),
    localAccount = {
        accountKey = nil,
        addonVersion = ns.Config.ADDON_VERSION,
        lastSeen = 0,
    },
    localScans = {
        characters = {},
    },
    networkSnapshots = {},
    mergedIndex = {
        itemTotals = {},
        recipeOwners = {},
        professionOwners = {},
    },
    watchedRecipes = {},
    mailLog = {},
    syncState = {
        peers = {},
        lastBroadcast = 0,
    },
}

local function generateAccountKey()
    -- Generate a stable unique key for this addon installation
    local realm = GetNormalizedRealmName() or GetRealmName() or "Unknown"
    local t = time()
    local r = math.random(100000, 999999)
    return string.format("acc_%s_%d_%d", realm, t, r)
end

function ns.SavedVariables.Initialize()
    -- Create DB if missing
    if not ProfessionPlannerDB then
        ProfessionPlannerDB = ns.TableUtil.DeepCopy(DB_DEFAULTS)
    end

    -- Reference for convenience
    ns.DB = ProfessionPlannerDB

    -- Merge any missing defaults (for upgrades)
    ns.TableUtil.MergeDefaults(ns.DB, DB_DEFAULTS)

    -- Generate account key if first run
    if not ns.DB.localAccount.accountKey then
        ns.DB.localAccount.accountKey = generateAccountKey()
        ns.Debug("Generated account key: %s", ns.DB.localAccount.accountKey)
    end

    -- Update version info
    ns.DB.localAccount.addonVersion = ns.Config.ADDON_VERSION
    ns.DB.localAccount.lastSeen = time()

    -- Run migrations if needed
    ns.SavedVariables.Migrate()
end

function ns.SavedVariables.Migrate()
    local currentVersion = ns.DB.version or 0

    if currentVersion < DB_VERSION then
        -- Future migrations go here
        -- if currentVersion < 2 then ... end

        ns.DB.version = DB_VERSION
        ns.Debug("Database migrated to version %d", DB_VERSION)
    end
end

function ns.SavedVariables.ResetAll()
    ProfessionPlannerDB = ns.TableUtil.DeepCopy(DB_DEFAULTS)
    ns.DB = ProfessionPlannerDB
    ns.DB.localAccount.accountKey = generateAccountKey()
    ns.Print("All data has been reset.")
end
