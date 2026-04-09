local ADDON_NAME, ns = ...

ns.ActionPlanner = {}

local ACTION_TRANSFER = "transfer"
local ACTION_CRAFT = "craft"

-- Generate a full action plan driven by ResourceAllocator
function ns.ActionPlanner.GeneratePlan()
    local actions = {}
    local optimized = ns.CraftSimPlanner.OptimizeWatchedRecipes()
    local result = ns.ResourceAllocator.Allocate(optimized)

    if not result or not result.plan or #result.plan == 0 then
        return actions
    end

    -- Merge all reagent transfer needs across plan entries
    local transferNeeds = {}  -- { ["itemID:crafter"] = { itemID, crafter, totalNeeded } }

    local function addTransferNeed(itemID, crafter, qty)
        if not itemID or not crafter or qty <= 0 then return end
        local key = itemID .. ":" .. crafter
        if not transferNeeds[key] then
            transferNeeds[key] = { itemID = itemID, crafter = crafter, totalNeeded = 0 }
        end
        transferNeeds[key].totalNeeded = transferNeeds[key].totalNeeded + qty
    end

    -- Build a lookup of watched recipe costs from the optimizer inputs
    -- (we need per-craft reagent quantities for transfer calculation)
    local watchedCosts = {}  -- { [recipeId] = { [itemID] = qtyPerCraft } }
    for _, entry in ipairs(result.plan) do
        if entry.type == "watched" then
            -- Reconstruct costs from CraftSimPlanner data
            for _, recipe in ipairs(optimized) do
                if recipe.recipeID == entry.recipeId then
                    local costs = {}
                    if recipe.reagents then
                        for _, r in ipairs(recipe.reagents) do
                            local baseID = r.baseItemID or r.itemID
                            if baseID and not ns.ItemUtil.IsVendorItem(baseID) then
                                costs[baseID] = (costs[baseID] or 0) + (r.requiredTotal or r.quantity or 0)
                            end
                        end
                    end
                    watchedCosts[entry.recipeId] = costs
                    break
                end
            end
        end
    end

    for _, entry in ipairs(result.plan) do
        if entry.type == "watched" and entry.crafts > 0 then
            local crafter = entry.crafter
            local crafterName = crafter and (crafter:match("^(.+)-") or crafter) or "?"

            -- Support craft actions (emitted before watched craft)
            if entry.supportPlan then
                for _, support in pairs(entry.supportPlan) do
                    if support.batches and support.batches > 0 then
                        local supportCrafter = support.crafter
                        local supportCrafterName = supportCrafter
                            and (supportCrafter:match("^(.+)-") or supportCrafter) or "?"

                        local supportRecipeData = ns.RecipeGraph.GetRecipe(support.recipeId)
                        local supportOutputItemID = supportRecipeData and supportRecipeData.outputItemID

                        actions[#actions + 1] = {
                            actionType = ACTION_CRAFT,
                            source = supportCrafter,
                            destination = nil,
                            itemID = supportOutputItemID or support.recipeId,
                            itemName = ns.ItemUtil.GetIconString(supportOutputItemID, 14) ..
                                " " .. (support.recipeName or "?"),
                            recipeID = support.recipeId,
                            recipeName = support.recipeName,
                            quantity = support.batches,
                            qualityID = nil,
                            isSupport = true,
                            note = string.format("Craft %d %s on %s (intermediate)",
                                support.batches, support.recipeName or "?", supportCrafterName),
                        }
                        if supportRecipeData and supportRecipeData.reagents and supportCrafter then
                            for _, r in ipairs(supportRecipeData.reagents) do
                                local baseID = r.itemID
                                if baseID and not ns.ItemUtil.IsVendorItem(baseID) then
                                    addTransferNeed(baseID, supportCrafter, (r.quantity or 0) * support.batches)
                                end
                            end
                        end

                        -- If support crafter differs from watched crafter,
                        -- the intermediate output needs to be transferred
                        if supportCrafter and crafter and supportCrafter ~= crafter then
                            if supportOutputItemID then
                                local outputQty = (supportRecipeData.outputQuantity or 1) * support.batches
                                addTransferNeed(supportOutputItemID, crafter, outputQty)
                            end
                        end
                    end
                end
            end

            -- Watched recipe craft action
            local concLabel = ""
            if entry.concentratedCrafts and entry.concentratedCrafts > 0 then
                concLabel = string.format(" (%d with Concentration)", entry.concentratedCrafts)
            end

            actions[#actions + 1] = {
                actionType = ACTION_CRAFT,
                source = crafter,
                destination = nil,
                itemID = entry.outputItemID or entry.recipeId,
                itemName = ns.ItemUtil.GetIconString(entry.outputItemID, 14) ..
                    " " .. (entry.recipeName or "?"),
                recipeID = entry.recipeId,
                recipeName = entry.recipeName,
                quantity = entry.crafts,
                qualityID = nil,
                concentratedCrafts = entry.concentratedCrafts or 0,
                note = string.format("Craft %d %s on %s%s",
                    entry.crafts, entry.recipeName or "?", crafterName, concLabel),
            }

            -- Transfer needs for watched recipe reagents
            local costs = watchedCosts[entry.recipeId]
            if costs and crafter then
                for itemID, qtyPerCraft in pairs(costs) do
                    addTransferNeed(itemID, crafter, qtyPerCraft * entry.crafts)
                end
            end
        end
    end

    -- Generate transfer actions from merged needs
    for _, need in pairs(transferNeeds) do
        local crafterHas = ns.InventoryIndex.GetByCharacter(need.itemID, need.crafter)
        local deficit = need.totalNeeded - crafterHas

        if deficit > 0 then
            local breakdown = ns.InventoryIndex.GetBreakdown(need.itemID)
            if breakdown and breakdown.byCharacter then
                for sourceChar, qty in pairs(breakdown.byCharacter) do
                    if sourceChar ~= need.crafter and qty > 0 and deficit > 0 then
                        local sendQty = math.min(qty, deficit)

                        actions[#actions + 1] = {
                            actionType = ACTION_TRANSFER,
                            source = sourceChar,
                            destination = need.crafter,
                            itemID = need.itemID,
                            itemName = ns.ItemUtil.GetIconString(need.itemID, 14) ..
                                " " .. ns.ItemUtil.GetItemName(need.itemID),
                            quantity = sendQty,
                            qualityID = nil,
                            note = string.format("Send %d %s from %s to %s",
                                sendQty, ns.ItemUtil.GetItemName(need.itemID),
                                sourceChar:match("^(.+)-") or sourceChar,
                                need.crafter:match("^(.+)-") or need.crafter),
                        }
                        deficit = deficit - sendQty
                    end
                end
            end
        end
    end

    -- Sort: transfers first, then support crafts, then watched crafts
    table.sort(actions, function(a, b)
        if a.actionType ~= b.actionType then
            return a.actionType == ACTION_TRANSFER
        end
        -- Within crafts: support first, then watched
        if a.actionType == ACTION_CRAFT and b.actionType == ACTION_CRAFT then
            if (a.isSupport or false) ~= (b.isSupport or false) then
                return a.isSupport or false
            end
        end
        return (a.note or "") < (b.note or "")
    end)

    return actions
end

-- Get transfers intended for a specific destination character
function ns.ActionPlanner.GetTransfersForRecipient(recipientCharKey)
    local plan = ns.ActionPlanner.GeneratePlan()
    local transfers = {}
    for _, action in ipairs(plan) do
        if action.actionType == ACTION_TRANSFER and action.destination == recipientCharKey then
            transfers[#transfers + 1] = action
        end
    end
    return transfers
end

-- Get transfers that the current character should send
function ns.ActionPlanner.GetTransfersFromCurrentCharacter()
    local currentChar = ns.CharacterScanner.GetCurrentCharacterKey()
    if not currentChar then return {} end

    local plan = ns.ActionPlanner.GeneratePlan()
    local transfers = {}
    for _, action in ipairs(plan) do
        if action.actionType == ACTION_TRANSFER and action.source == currentChar then
            transfers[#transfers + 1] = action
        end
    end
    return transfers
end

-- Get the next recommended transfer action for the current character
function ns.ActionPlanner.GetNextTransfer()
    local transfers = ns.ActionPlanner.GetTransfersFromCurrentCharacter()
    return transfers[1]
end