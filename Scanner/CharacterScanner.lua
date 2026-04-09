local ADDON_NAME, ns = ...

ns.CharacterScanner = {}

function ns.CharacterScanner.Initialize()
    ns.Events.Register("PLAYER_ENTERING_WORLD", function()
        C_Timer.After(1, ns.CharacterScanner.Scan)
    end, "CharacterScanner")
end

function ns.CharacterScanner.Scan()
    local name = UnitName("player")
    local realm = GetNormalizedRealmName() or GetRealmName()
    if not name or not realm then return end

    local charKey = ns.ItemUtil.MakeCharacterKey(name, realm)
    local now = ns.TimeUtil.Now()

    local existing = ns.DB.localScans.characters[charKey] or {}

    ns.DB.localScans.characters[charKey] = {
        accountKey = ns.DB.localAccount.accountKey,
        name = name,
        realm = realm,
        faction = UnitFactionGroup("player") or "Neutral",
        class = select(2, UnitClass("player")) or "UNKNOWN",
        level = UnitLevel("player") or 0,
        gold = GetMoney() or 0,
        lastScan = now,
        scanFlags = existing.scanFlags or {
            bags = false,
            bank = false,
            reagentBank = false,
            professions = false,
        },
        inventory = existing.inventory or {},
        professions = existing.professions or {},
        recipes = existing.recipes or {},
    }

    ns.Debug("Character scanned: %s (level %d %s)", charKey, UnitLevel("player") or 0, select(2, UnitClass("player")) or "?")
    ns.Events.Fire("PSC_SCAN_COMPLETE", "character", charKey)
end

function ns.CharacterScanner.GetCurrentCharacterKey()
    local name = UnitName("player")
    local realm = GetNormalizedRealmName() or GetRealmName()
    if not name or not realm then return nil end
    return ns.ItemUtil.MakeCharacterKey(name, realm)
end
