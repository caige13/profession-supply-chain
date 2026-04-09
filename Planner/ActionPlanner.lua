local ADDON_NAME, ns = ...

ns.ActionPlanner = {}

local ACTION_TRANSFER = "transfer"
local ACTION_CRAFT = "craft"

-- Generate a full action plan driven by ResourceAllocator
function ns.ActionPlanner.GeneratePlan()
    local actions = {}
    local optimized = ns.CraftSimPlanner.OptimizeWatchedRecipes()
    local allocations = ns.ResourceAllocator.Allocate(optimized)

    if #allocations == 0 then
        return actions
    end

    -- Merge all reagent needs across allocations, then generate transfers
    local transferNeeds = {}  -- { [itemID] = { crafter = charKey, totalNeeded = N } }

    for _, alloc in ipairs(allocations) do
        local crafter = alloc.crafters and alloc.crafters[1]
        if not crafter then
            -- Skip recipes with no known crafter
        else
            -- Accumulate reagent needs for this crafter
            for _, r in ipairs(alloc.reagents) do
                local itemID = r.itemID or r.baseItemID
                if itemID then
                    local needed = (r.quantity or r.requiredTotal or 0) * alloc.quantity
                    local key = itemID .. ":" .. crafter
                    if not transferNeeds[key] then
                        transferNeeds[key] = {
                            itemID = itemID,
                            crafter = crafter,
                            totalNeeded = 0,
                            qualityID = r.qualityID,
                        }
                    end
                    transferNeeds[key].totalNeeded = transferNeeds[key].totalNeeded + needed
                end
            end

            -- Craft action
            local qIcon = alloc.qualityTarget and alloc.qualityTarget > 0
                and (" " .. ns.ItemUtil.GetQualityIcon(alloc.qualityTarget, 12)) or ""
            local concLabel = alloc.useConcentration and " +Conc" or ""
            local profitStr = ""
            if alloc.totalProfit ~= 0 then
                profitStr = string.format(" (est. profit: %s)",
                    GetCoinTextureString(math.abs(alloc.totalProfit)))
            end

            actions[#actions + 1] = {
                actionType = ACTION_CRAFT,
                source = crafter,
                destination = nil,
                itemID = alloc.outputItemID or alloc.recipeID,
                itemName = ns.ItemUtil.GetIconString(alloc.outputItemID, 14) ..
                    " " .. (alloc.recipeName or "?") .. qIcon .. concLabel,
                recipeID = alloc.recipeID,
                recipeName = alloc.recipeName,
                quantity = alloc.quantity,
                qualityID = alloc.qualityTarget,
                note = string.format("Suggested: Craft %d %s%s%s on %s%s",
                    alloc.quantity, alloc.recipeName or "?", qIcon, concLabel, crafter, profitStr),
            }
        end
    end

    -- Generate transfer actions from merged needs
    for _, need in pairs(transferNeeds) do
        local crafterHas = ns.InventoryIndex.GetByCharacter(need.itemID, need.crafter)
        local deficit = need.totalNeeded - crafterHas

        if deficit > 0 then
            local breakdown = ns.InventoryIndex.GetBreakdown(need.itemID)
            if breakdown.byCharacter then
                for sourceChar, qty in pairs(breakdown.byCharacter) do
                    if sourceChar ~= need.crafter and qty > 0 and deficit > 0 then
                        local sendQty = math.min(qty, deficit)
                        local qualityIcon = need.qualityID and need.qualityID > 0
                            and (" " .. ns.ItemUtil.GetQualityIcon(need.qualityID, 12)) or ""

                        actions[#actions + 1] = {
                            actionType = ACTION_TRANSFER,
                            source = sourceChar,
                            destination = need.crafter,
                            itemID = need.itemID,
                            itemName = ns.ItemUtil.GetIconString(need.itemID, 14) ..
                                " " .. ns.ItemUtil.GetItemName(need.itemID) .. qualityIcon,
                            quantity = sendQty,
                            qualityID = need.qualityID,
                            note = string.format("Suggested: Send %d %s from %s to %s",
                                sendQty, ns.ItemUtil.GetItemName(need.itemID), sourceChar, need.crafter),
                        }
                        deficit = deficit - sendQty
                    end
                end
            end
        end
    end

    -- Sort: transfers first, then crafts
    table.sort(actions, function(a, b)
        if a.actionType ~= b.actionType then
            return a.actionType == ACTION_TRANSFER
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