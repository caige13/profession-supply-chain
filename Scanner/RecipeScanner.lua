local ADDON_NAME, ns = ...

ns.RecipeScanner = {}

function ns.RecipeScanner.Initialize()
    -- Recipe scanning is triggered by ProfessionScanner
end

function ns.RecipeScanner.ScanCurrentProfession(charKey, professionID)
    local charData = ns.DB.localScans.characters[charKey]
    if not charData then return end

    local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs()
    if not recipeIDs or #recipeIDs == 0 then
        ns.Debug("No recipes found for profession %d", professionID)
        return
    end

    local scannedCount = 0
    local skippedCount = 0
    local now = ns.TimeUtil.Now()

    for _, recipeID in ipairs(recipeIDs) do
        local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
        if recipeInfo and recipeInfo.learned then
            local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)

            -- Only scan modern recipes (Dragonflight+) — legacy recipes lack hasCraftingOperationInfo
            if schematic and schematic.hasCraftingOperationInfo then
                local reagents = ns.RecipeScanner.ExtractReagents(schematic)
                local outputItemID, outputQuantity = ns.RecipeScanner.ExtractOutput(schematic, recipeInfo)

                charData.recipes[recipeID] = {
                    professionID = professionID,
                    recipeName = recipeInfo.name or ("Recipe #" .. recipeID),
                    outputItemID = outputItemID,
                    outputQuantity = outputQuantity or 1,
                    reagents = reagents,
                    supportsQualities = true,
                    categoryID = recipeInfo.categoryID,
                    icon = recipeInfo.icon,
                    lastUpdated = now,
                }
                scannedCount = scannedCount + 1
            else
                skippedCount = skippedCount + 1
            end
        end
    end

    charData.scanFlags.professions = true
    charData.lastScan = now

    ns.Debug("Recipes scanned: %d modern recipes (%d legacy skipped) for profession %d on %s",
        scannedCount, skippedCount, professionID, charKey)
    ns.Events.Fire("PSC_SCAN_COMPLETE", "recipes", charKey)
end

function ns.RecipeScanner.ExtractReagents(schematic)
    local reagents = {}
    if not schematic or not schematic.reagentSlotSchematics then
        return reagents
    end

    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        -- Only capture required reagents (not optional/finishing)
        if slot.reagentType == Enum.CraftingReagentType.Basic then
            local reagentEntry = {
                quantity = slot.quantityRequired or 1,
            }

            -- Get the item ID(s) for this reagent slot
            if slot.reagents and #slot.reagents > 0 then
                -- For quality-tiered reagents, store the base (Q1) item
                reagentEntry.itemID = slot.reagents[1].itemID
                reagentEntry.hasQuality = #slot.reagents > 1

                -- Store all quality variants with tier metadata
                if reagentEntry.hasQuality then
                    reagentEntry.qualityItems = {}
                    reagentEntry.qualityTiers = {}
                    for qi, r in ipairs(slot.reagents) do
                        reagentEntry.qualityItems[qi] = r.itemID
                        reagentEntry.qualityTiers[qi] = {
                            itemID = r.itemID,
                            qualityID = qi,
                        }
                    end
                end
            end

            if reagentEntry.itemID then
                reagents[#reagents + 1] = reagentEntry
            end
        end
    end

    return reagents
end

function ns.RecipeScanner.ExtractOutput(schematic, recipeInfo)
    local outputItemID = nil
    local outputQuantity = 1

    if schematic then
        -- Try to get output from schematic
        if schematic.outputItemID then
            outputItemID = schematic.outputItemID
        end
        if schematic.quantityMin then
            outputQuantity = schematic.quantityMin
        end
    end

    -- Fallback: try recipe info
    if not outputItemID and recipeInfo then
        if recipeInfo.hyperlink then
            outputItemID = ns.ItemUtil.GetItemIDFromLink(recipeInfo.hyperlink)
        end
    end

    return outputItemID, outputQuantity
end
