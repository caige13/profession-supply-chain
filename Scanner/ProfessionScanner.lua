local ADDON_NAME, ns = ...

ns.ProfessionScanner = {}

local scanTimer = nil

local knownProfTimer = nil

function ns.ProfessionScanner.Initialize()
    -- SKILL_LINES_CHANGED fires multiple times on login (once per skill line) — debounce
    ns.Events.Register("SKILL_LINES_CHANGED", function()
        if knownProfTimer then knownProfTimer:Cancel() end
        knownProfTimer = C_Timer.NewTimer(2, function()
            knownProfTimer = nil
            ns.ProfessionScanner.ScanKnownProfessions()
        end)
    end, "ProfessionScanner")

    ns.Events.Register("TRADE_SKILL_SHOW", function()
        if scanTimer then scanTimer:Cancel() end
        scanTimer = C_Timer.NewTimer(ns.Config.PROFESSION_SCAN_DELAY, function()
            scanTimer = nil
            ns.ProfessionScanner.Scan()
        end)
        -- Hook our watch button into the profession frame
        C_Timer.After(0.5, function()
            ns.RecipesTab.HookProfessionFrame()
        end)
    end, "ProfessionScanner")

    ns.Events.Register("TRADE_SKILL_DATA_SOURCE_CHANGED", function()
        if scanTimer then scanTimer:Cancel() end
        scanTimer = C_Timer.NewTimer(ns.Config.PROFESSION_SCAN_DELAY, function()
            scanTimer = nil
            ns.ProfessionScanner.Scan()
        end)
    end, "ProfessionScanner")
end

function ns.ProfessionScanner.Scan()
    local charKey = ns.CharacterScanner.GetCurrentCharacterKey()
    if not charKey then return end

    local charData = ns.DB.localScans.characters[charKey]
    if not charData then return end

    -- Get the currently open profession info
    local profInfo = C_TradeSkillUI.GetBaseProfessionInfo()
    if not profInfo or not profInfo.professionID then
        ns.Debug("No profession data available")
        return
    end

    local profID = profInfo.professionID
    local now = ns.TimeUtil.Now()

    -- Skip legacy expansion professions (maxSkillLevel > 200 = classic/BC/Wrath etc.)
    if profInfo.maxSkillLevel and profInfo.maxSkillLevel > 200 then
        ns.Debug("Skipping legacy profession: %s (%d/%d)",
            profInfo.professionName or "?", profInfo.skillLevel or 0, profInfo.maxSkillLevel)
        return
    end

    -- Clean out any legacy professions stored from previous scans
    for existingID, existingProf in pairs(charData.professions) do
        if existingProf.maxRank and existingProf.maxRank > 200 then
            charData.professions[existingID] = nil
            ns.Debug("Cleaned legacy profession: %s", existingProf.name or "?")
        end
    end

    charData.professions[profID] = {
        name = profInfo.professionName or "Unknown",
        skillLineID = profInfo.professionID,
        parentProfessionID = profInfo.parentProfessionID,
        rank = profInfo.skillLevel or 0,
        maxRank = profInfo.maxSkillLevel or 0,
        expansionName = profInfo.expansionName,
        specializations = {},
        lastUpdated = now,
    }

    -- Scan specializations for this profession
    ns.ProfessionScanner.ScanSpecializations(charData.professions[profID], profInfo)

    charData.scanFlags.professions = true
    charData.lastScan = now

    ns.Debug("Profession scanned: %s (skill %d/%d) for %s",
        profInfo.professionName or "?",
        profInfo.skillLevel or 0,
        profInfo.maxSkillLevel or 0,
        charKey)

    -- Trigger recipe scan for this profession
    ns.RecipeScanner.ScanCurrentProfession(charKey, profID)

    ns.Events.Fire("PSC_SCAN_COMPLETE", "profession", charKey)
end

-- Scan all known professions for the current character (on login)
function ns.ProfessionScanner.ScanKnownProfessions()
    local charKey = ns.CharacterScanner.GetCurrentCharacterKey()
    if not charKey then
        ns.Debug("ScanKnownProfessions: no charKey yet")
        return
    end

    local charData = ns.DB.localScans.characters[charKey]
    if not charData then
        ns.Debug("ScanKnownProfessions: no charData for %s, running character scan first", charKey)
        ns.CharacterScanner.Scan()
        charData = ns.DB.localScans.characters[charKey]
        if not charData then return end
    end

    local prof1, prof2 = GetProfessions()
    ns.Debug("ScanKnownProfessions: GetProfessions() returned %s, %s", tostring(prof1), tostring(prof2))

    local profIDs = {}
    if prof1 then profIDs[#profIDs + 1] = prof1 end
    if prof2 then profIDs[#profIDs + 1] = prof2 end

    local scanned = 0
    for _, profIndex in ipairs(profIDs) do
        local name, icon, skillLevel, maxSkillLevel, _, _, skillLineID = GetProfessionInfo(profIndex)
        ns.Debug("ScanKnownProfessions: index=%d name=%s skillLine=%s",
            profIndex, tostring(name), tostring(skillLineID))

        if name then
            -- Skip legacy professions (classic/BC/Wrath etc. have maxSkillLevel > 200)
            if maxSkillLevel and maxSkillLevel > 200 then
                ns.Debug("ScanKnownProfessions: skipping legacy %s (%d/%d)", name, skillLevel or 0, maxSkillLevel)
            else
                local key = skillLineID or profIndex
                -- Preserve existing specializations if already scanned
                local existingSpecs = charData.professions[key]
                    and charData.professions[key].specializations or {}
                charData.professions[key] = {
                    name = name,
                    skillLineID = skillLineID or profIndex,
                    rank = skillLevel or 0,
                    maxRank = maxSkillLevel or 0,
                    specializations = existingSpecs,
                    lastUpdated = ns.TimeUtil.Now(),
                }
                scanned = scanned + 1
            end
        end
    end

    if scanned > 0 then
        charData.scanFlags.professions = true
        ns.Debug("ScanKnownProfessions: scanned %d professions for %s", scanned, charKey)
        ns.Events.Fire("PSC_SCAN_COMPLETE", "profession", charKey)
    end
end

-- Scan profession specialization tree (requires profession UI to be open)
function ns.ProfessionScanner.ScanSpecializations(profEntry, profInfo)
    if not C_ProfSpecs or not profInfo then return end

    local skillLineID = profInfo.professionID
    if not skillLineID then return end

    -- Check if this profession supports specializations
    local ok, hasSpecs = pcall(function()
        return C_ProfSpecs.SkillLineHasSpecialization(skillLineID)
    end)
    if not ok or not hasSpecs then
        ns.Debug("No specializations for %s", profInfo.professionName or "?")
        return
    end

    -- Get the trait config for this profession
    local configID = nil
    local okConfig
    okConfig, configID = pcall(function()
        return C_ProfSpecs.GetConfigIDForSkillLine(skillLineID)
    end)
    if not okConfig or not configID then return end

    -- Get specialization tabs
    local tabIDs = nil
    local okTabs
    okTabs, tabIDs = pcall(function()
        return C_ProfSpecs.GetSpecTabIDs()
    end)
    if not okTabs or not tabIDs then return end

    profEntry.specializations = {}

    for _, tabID in ipairs(tabIDs) do
        local tabInfo = C_ProfSpecs.GetSpecTabInfo(tabID)
        if tabInfo then
            local spec = {
                tabID = tabID,
                name = tabInfo.name or ("Spec " .. tabID),
                description = tabInfo.description,
                pointsSpent = 0,
                maxPoints = 0,
                state = nil,
                children = {},
            }

            -- Get state (locked, unlocked, etc.)
            local okState, state = pcall(function()
                return C_ProfSpecs.GetStateForTab(skillLineID, tabID)
            end)
            if okState then
                spec.state = state
            end

            -- Get the root node for this tab and walk the tree for points
            local okRoot, rootNodeID = pcall(function()
                return C_ProfSpecs.GetRootPathForTab(tabID)
            end)

            if okRoot and rootNodeID then
                ns.ProfessionScanner.ScanSpecNode(configID, rootNodeID, spec, 0)
            end

            -- Also try getting all tab children for point counts
            local okChildren, tabChildren = pcall(function()
                return C_ProfSpecs.GetChildrenForPath(tabID)
            end)

            if okChildren and tabChildren then
                for _, childID in ipairs(tabChildren) do
                    local childInfo = C_ProfSpecs.GetSpecTabInfo(childID)
                    if childInfo then
                        local child = {
                            tabID = childID,
                            name = childInfo.name or ("Spec " .. childID),
                            pointsSpent = 0,
                            maxPoints = 0,
                        }

                        -- Get points for this child path
                        local okChildRoot, childRootNode = pcall(function()
                            return C_ProfSpecs.GetRootPathForTab(childID)
                        end)
                        if okChildRoot and childRootNode then
                            ns.ProfessionScanner.ScanSpecNode(configID, childRootNode, child, 0)
                        end

                        spec.children[#spec.children + 1] = child
                        spec.pointsSpent = spec.pointsSpent + child.pointsSpent
                    end
                end
            end

            profEntry.specializations[#profEntry.specializations + 1] = spec
            ns.Debug("  Spec: %s — %d points", spec.name, spec.pointsSpent)
        end
    end
end

function ns.ProfessionScanner.ScanSpecNode(configID, nodeID, specEntry, depth)
    if depth > 20 then return end  -- safety

    local ok, nodeInfo = pcall(function()
        return C_Traits.GetNodeInfo(configID, nodeID)
    end)
    if not ok or not nodeInfo then return end

    if nodeInfo.currentRank and nodeInfo.currentRank > 0 then
        specEntry.pointsSpent = specEntry.pointsSpent + nodeInfo.currentRank
    end
    if nodeInfo.maxRanks then
        specEntry.maxPoints = specEntry.maxPoints + nodeInfo.maxRanks
    end

    -- Recurse into child nodes
    if nodeInfo.nextNodeIDs then
        for _, childNodeID in ipairs(nodeInfo.nextNodeIDs) do
            ns.ProfessionScanner.ScanSpecNode(configID, childNodeID, specEntry, depth + 1)
        end
    end
end
