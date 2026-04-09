local ADDON_NAME, ns = ...

ns.InventoryScanner = {}

local bagScanTimer = nil
local bankOpen = false

function ns.InventoryScanner.Initialize()
    ns.Events.Register("BAG_UPDATE_DELAYED", function()
        -- Debounce bag scans
        if bagScanTimer then
            bagScanTimer:Cancel()
        end
        bagScanTimer = C_Timer.NewTimer(ns.Config.BAG_SCAN_DELAY, function()
            bagScanTimer = nil
            ns.InventoryScanner.ScanBags()
            if bankOpen then
                ns.InventoryScanner.ScanBank()
            end
        end)
    end, "InventoryScanner")

    ns.Events.Register("BANKFRAME_OPENED", function()
        bankOpen = true
        C_Timer.After(0.5, function()
            ns.InventoryScanner.ScanBank()
            ns.InventoryScanner.ScanReagentBank()
        end)
    end, "InventoryScanner")

    ns.Events.Register("BANKFRAME_CLOSED", function()
        bankOpen = false
    end, "InventoryScanner")

    -- Reagent bank no longer exists as separate in Midnight; handled via BANKFRAME_OPENED

    -- Initial bag scan after entering world
    ns.Events.Register("PLAYER_ENTERING_WORLD", function()
        C_Timer.After(2, ns.InventoryScanner.ScanBags)
    end, "InventoryScanner")
end

local function getOrCreateEntry(inventory, itemID)
    if not inventory[itemID] then
        inventory[itemID] = {
            bags = 0,
            bank = 0,
            reagentBank = 0,
            mail = 0,
            total = 0,
            itemName = nil,
            itemLink = nil,
            lastUpdated = 0,
        }
    end
    return inventory[itemID]
end

local function updateTotals(entry)
    entry.total = entry.bags + entry.bank + entry.reagentBank + entry.mail
    entry.lastUpdated = ns.TimeUtil.Now()
end

local function scanContainerRange(inventory, startBag, endBag, bucket)
    for bag = startBag, endBag do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local entry = getOrCreateEntry(inventory, info.itemID)
                entry[bucket] = entry[bucket] + info.stackCount
                if info.itemName then
                    entry.itemName = info.itemName
                end
                if info.hyperlink then
                    entry.itemLink = info.hyperlink
                end
            end
        end
    end
end

function ns.InventoryScanner.ScanBags()
    local charKey = ns.CharacterScanner.GetCurrentCharacterKey()
    if not charKey then return end

    local charData = ns.DB.localScans.characters[charKey]
    if not charData then
        -- Character not scanned yet, do it now
        ns.CharacterScanner.Scan()
        charData = ns.DB.localScans.characters[charKey]
        if not charData then return end
    end

    -- Clear bag counts (preserve other buckets)
    for itemID, entry in pairs(charData.inventory) do
        entry.bags = 0
    end

    -- Scan bags 0–4 (backpack + 4 bag slots)
    scanContainerRange(charData.inventory, 0, 4, "bags")

    -- Scan reagent bag (bag 5 / Enum.BagIndex.ReagentBag) — crafting materials go here
    local reagentBagIndex = Enum.BagIndex and Enum.BagIndex.ReagentBag or 5
    scanContainerRange(charData.inventory, reagentBagIndex, reagentBagIndex, "bags")

    -- Update totals
    for itemID, entry in pairs(charData.inventory) do
        updateTotals(entry)
        -- Remove entries with zero total
        if entry.total == 0 then
            charData.inventory[itemID] = nil
        end
    end

    charData.scanFlags.bags = true
    charData.lastScan = ns.TimeUtil.Now()

    ns.Debug("Bags scanned for %s: %d items", charKey, ns.TableUtil.Count(charData.inventory))
    ns.Events.Fire("PSC_SCAN_COMPLETE", "inventory", charKey)
end

function ns.InventoryScanner.ScanBank()
    local charKey = ns.CharacterScanner.GetCurrentCharacterKey()
    if not charKey then return end

    local charData = ns.DB.localScans.characters[charKey]
    if not charData then return end

    -- Clear bank counts
    for itemID, entry in pairs(charData.inventory) do
        entry.bank = 0
    end

    -- Scan bank: bag -1 (main bank) and bags 5-12 (bank bags)
    -- Note: In Midnight, bank bag indices may vary; using Enum if available
    local bankBag = Enum.BagIndex and Enum.BagIndex.Bank or -1
    scanContainerRange(charData.inventory, bankBag, bankBag, "bank")

    -- Bank bag slots (5-12 in modern WoW)
    local firstBankBag = Enum.BagIndex and Enum.BagIndex.BankBag_1 or 5
    local lastBankBag = Enum.BagIndex and Enum.BagIndex.BankBag_7 or 12
    scanContainerRange(charData.inventory, firstBankBag, lastBankBag, "bank")

    -- Update totals
    for itemID, entry in pairs(charData.inventory) do
        updateTotals(entry)
        if entry.total == 0 then
            charData.inventory[itemID] = nil
        end
    end

    charData.scanFlags.bank = true
    charData.lastScan = ns.TimeUtil.Now()

    ns.Debug("Bank scanned for %s", charKey)
    ns.Events.Fire("PSC_SCAN_COMPLETE", "bank", charKey)
end

function ns.InventoryScanner.ScanReagentBank()
    local charKey = ns.CharacterScanner.GetCurrentCharacterKey()
    if not charKey then return end

    local charData = ns.DB.localScans.characters[charKey]
    if not charData then return end

    -- Clear reagent bank counts
    for itemID, entry in pairs(charData.inventory) do
        entry.reagentBank = 0
    end

    local reagentBag = Enum.BagIndex and Enum.BagIndex.ReagentBag or 5
    -- Reagent bank is a special container
    if C_Container.GetContainerNumSlots(reagentBag) > 0 then
        scanContainerRange(charData.inventory, reagentBag, reagentBag, "reagentBank")
    end

    -- Also check the dedicated reagent bank if it exists
    local reagentBankBag = Enum.BagIndex and Enum.BagIndex.Reagentbank
    if reagentBankBag and C_Container.GetContainerNumSlots(reagentBankBag) > 0 then
        scanContainerRange(charData.inventory, reagentBankBag, reagentBankBag, "reagentBank")
    end

    -- Update totals
    for itemID, entry in pairs(charData.inventory) do
        updateTotals(entry)
        if entry.total == 0 then
            charData.inventory[itemID] = nil
        end
    end

    charData.scanFlags.reagentBank = true
    charData.lastScan = ns.TimeUtil.Now()

    ns.Debug("Reagent bank scanned for %s", charKey)
    ns.Events.Fire("PSC_SCAN_COMPLETE", "reagentBank", charKey)
end
