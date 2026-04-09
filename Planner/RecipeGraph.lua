local ADDON_NAME, ns = ...

ns.RecipeGraph = {}

local graph = {
    byRecipeID = {},
    byOutputItemID = {},
}

function ns.RecipeGraph.Initialize()
    ns.Events.Register("PSC_MERGE_UPDATED", function()
        ns.RecipeGraph.Rebuild()
    end, "RecipeGraph")
end

function ns.RecipeGraph.Rebuild()
    graph = {
        byRecipeID = {},
        byOutputItemID = {},
    }

    ns.Repository.IterateAllCharacters(function(charKey, charData, accountKey, isLocal)
        if not charData.recipes then return end

        for recipeID, recipeData in pairs(charData.recipes) do
            -- Store recipe data (latest scan wins)
            if not graph.byRecipeID[recipeID] or
               (recipeData.lastUpdated or 0) > (graph.byRecipeID[recipeID].lastUpdated or 0) then
                graph.byRecipeID[recipeID] = recipeData
            end

            -- Index by output item
            if recipeData.outputItemID then
                if not graph.byOutputItemID[recipeData.outputItemID] then
                    graph.byOutputItemID[recipeData.outputItemID] = {}
                end
                -- Add recipe if not already indexed
                local found = false
                for _, existingID in ipairs(graph.byOutputItemID[recipeData.outputItemID]) do
                    if existingID == recipeID then
                        found = true
                        break
                    end
                end
                if not found then
                    table.insert(graph.byOutputItemID[recipeData.outputItemID], recipeID)
                end
            end
        end
    end)

    ns.Debug("Recipe graph rebuilt: %d recipes, %d output items",
        ns.TableUtil.Count(graph.byRecipeID),
        ns.TableUtil.Count(graph.byOutputItemID))
end

function ns.RecipeGraph.GetRecipe(recipeID)
    return graph.byRecipeID[recipeID]
end

function ns.RecipeGraph.GetRecipesByOutput(outputItemID)
    local recipeIDs = graph.byOutputItemID[outputItemID]
    if not recipeIDs then return {} end

    local recipes = {}
    for _, recipeID in ipairs(recipeIDs) do
        recipes[#recipes + 1] = {
            recipeID = recipeID,
            data = graph.byRecipeID[recipeID],
        }
    end
    return recipes
end

-- Check if an item can be crafted by any known recipe
function ns.RecipeGraph.IsCraftable(itemID)
    return graph.byOutputItemID[itemID] ~= nil and #graph.byOutputItemID[itemID] > 0
end

-- Get the default recipe for crafting an item (first known recipe)
function ns.RecipeGraph.GetDefaultRecipe(itemID)
    local recipeIDs = graph.byOutputItemID[itemID]
    if not recipeIDs or #recipeIDs == 0 then return nil end
    return recipeIDs[1], graph.byRecipeID[recipeIDs[1]]
end

function ns.RecipeGraph.GetAllRecipes()
    return graph.byRecipeID
end

function ns.RecipeGraph.GetGraph()
    return graph
end
