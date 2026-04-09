local ADDON_NAME, ns = ...

ns.MaxCraftable = {}

-- Calculate maximum craftable for a recipe, with recursive sub-craft support
-- Returns: { maxCraftable, bottleneckItemID, deficits, subcrafts }
function ns.MaxCraftable.Calculate(recipeID, preferredCrafter)
    local recipe = ns.RecipeGraph.GetRecipe(recipeID)
    if not recipe then
        return {
            maxCraftable = 0,
            bottleneckItemID = nil,
            deficits = {},
            subcrafts = {},
            error = "Recipe not found",
        }
    end

    local visited = {}  -- cycle detection
    return ns.MaxCraftable.CalculateRecursive(recipeID, recipe, visited, preferredCrafter)
end

function ns.MaxCraftable.CalculateRecursive(recipeID, recipe, visited, preferredCrafter)
    -- Cycle detection
    if visited[recipeID] then
        return {
            maxCraftable = 0,
            bottleneckItemID = nil,
            deficits = {},
            subcrafts = {},
            error = "Circular dependency detected",
        }
    end
    visited[recipeID] = true

    if not recipe.reagents or #recipe.reagents == 0 then
        visited[recipeID] = nil
        return {
            maxCraftable = math.huge,
            bottleneckItemID = nil,
            deficits = {},
            subcrafts = {},
        }
    end

    local minCraftable = math.huge
    local bottleneckItemID = nil
    local allDeficits = {}
    local allSubcrafts = {}

    for _, reagent in ipairs(recipe.reagents) do
        local itemID = reagent.itemID
        local requiredPerCraft = reagent.quantity

        -- Get available quantity across all characters
        -- For quality-tiered reagents, sum all quality variants
        local available = 0
        if reagent.qualityItems then
            for _, qItemID in ipairs(reagent.qualityItems) do
                available = available + ns.InventoryIndex.GetTotal(qItemID)
            end
        else
            available = ns.InventoryIndex.GetTotal(itemID)
        end

        -- Check if this reagent can be sub-crafted
        local subcraftAvailable = 0
        if ns.RecipeGraph.IsCraftable(itemID) then
            local subRecipeID, subRecipe = ns.RecipeGraph.GetDefaultRecipe(itemID)
            if subRecipeID and not visited[subRecipeID] then
                local subResult = ns.MaxCraftable.CalculateRecursive(
                    subRecipeID, subRecipe, visited, preferredCrafter)
                if subResult.maxCraftable > 0 then
                    local subOutputQty = subRecipe.outputQuantity or 1
                    subcraftAvailable = subResult.maxCraftable * subOutputQty

                    -- Find the crafter for this sub-recipe
                    local crafters = ns.Merge.GetRecipeOwners(subRecipeID)
                    local crafter = preferredCrafter
                    if not crafter or not ns.TableUtil.Contains(crafters, crafter) then
                        crafter = crafters[1]
                    end

                    allSubcrafts[#allSubcrafts + 1] = {
                        recipeID = subRecipeID,
                        recipeName = subRecipe.recipeName,
                        outputItemID = itemID,
                        count = 0,  -- will be calculated later
                        crafter = crafter,
                        maxAvailable = subResult.maxCraftable,
                    }
                end
            end
        end

        local totalAvailable = available + subcraftAvailable
        local craftableFromThis = math.floor(totalAvailable / requiredPerCraft)

        if craftableFromThis < minCraftable then
            minCraftable = craftableFromThis
            bottleneckItemID = itemID
        end

        -- Track deficit
        local deficit = requiredPerCraft - available
        if deficit > 0 and subcraftAvailable == 0 then
            allDeficits[itemID] = deficit
        end
    end

    if minCraftable == math.huge then
        minCraftable = 0
    end

    -- Calculate actual sub-craft counts needed
    for _, subcraft in ipairs(allSubcrafts) do
        local reagentNeeded = 0
        for _, reagent in ipairs(recipe.reagents) do
            if reagent.itemID == subcraft.outputItemID then
                reagentNeeded = reagent.quantity * minCraftable
                break
            end
        end
        local available = ns.InventoryIndex.GetTotal(subcraft.outputItemID)
        local needToCraft = math.max(0, reagentNeeded - available)
        local outputQty = ns.RecipeGraph.GetRecipe(subcraft.recipeID)
        outputQty = outputQty and outputQty.outputQuantity or 1
        subcraft.count = math.ceil(needToCraft / outputQty)
    end

    visited[recipeID] = nil

    return {
        maxCraftable = minCraftable,
        bottleneckItemID = bottleneckItemID,
        deficits = allDeficits,
        subcrafts = allSubcrafts,
    }
end
