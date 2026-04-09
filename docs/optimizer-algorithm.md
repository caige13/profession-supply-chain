# Supply Chain Optimizer Algorithm

## Overview

The optimizer determines the most profitable way to use available raw materials across all watched recipes, factoring in concentration charges, intermediate crafting, and cross-account inventory.

## Concepts

### Watched Recipes (Terminal)
Recipes the user explicitly watches via the PSC button in the profession window. These are the **final products** intended for sale. Only watched recipes generate profit in the optimizer.

### Support Recipes (Intermediate)
Recipes that exist only to fulfill missing reagents for watched recipes. If a watched recipe needs Pigment Dust and you have none, but a support recipe can craft Pigment Dust from Herb C, the optimizer will recursively craft the intermediate. Support recipes do **not** add profit themselves — they're a means to an end.

### Vendor Items
Items purchasable from NPC vendors (vials, threads, etc.) are excluded from resource calculations. They're always available and never a bottleneck.

## Algorithm

### Phase: Exhaustive Search with Memoization

For each watched recipe (in order), try crafting it 0 times, 1 time, 2 times, and so on until resources are exhausted.

For each craft count N of a watched recipe:

1. **Fulfill reagents:**
   - For each reagent the recipe needs (quantity * N):
     - Use inventory first
     - If inventory is short, check if a support recipe can craft the missing reagent
     - If yes, recursively consume the support recipe's reagents and produce the intermediate
     - If no support recipe exists and inventory is insufficient, N crafts is infeasible — stop

2. **Allocate concentration:**
   - Concentration is limited by:
     - The crafter's remaining concentration pool
     - The recipe's concentration cost per craft
     - The number of crafts
   - Number of concentrated crafts = `min(N, floor(crafterConcentration / recipeConcentrationCost))`
   - Try every value from 0 to max concentrated crafts

3. **Calculate profit:**
   - `profit = (N * baseProfit) + (concentratedCrafts * concentrationBonus)`
   - `concentrationBonus = concentratedProfit - baseProfit`

4. **Recurse:** Solve the remaining watched recipes with updated inventory and concentration.

5. **Memoize:** Cache results by (recipe index, resource state, concentration state per crafter).

6. **Pick the best:** Among all combinations of craft counts and concentration allocations, return the one with the highest total profit.

### Support Recipe Resolution

When a reagent is missing during fulfillment:

```
consumeOrCraftItem(itemID, qtyNeeded, resources, supportRecipes):
    have = resources[itemID]
    if have >= qtyNeeded:
        resources[itemID] -= qtyNeeded
        return success

    shortage = qtyNeeded - have
    resources[itemID] = 0

    supportRecipe = supportRecipes[itemID]
    if not supportRecipe: return failure (infeasible)

    batchesNeeded = ceil(shortage / supportRecipe.outputQuantity)

    for each reagent in supportRecipe.costs:
        consumeOrCraftItem(reagent, qty * batchesNeeded, ...)  -- recurse

    resources[itemID] += batchesNeeded * outputQuantity
    resources[itemID] -= shortage
    return success
```

Cycle detection prevents infinite recursion (if A needs B and B needs A).

### Sell Raw Fallback

If the best crafting plan has total profit <= 0, the optimizer recommends selling raw materials on the auction house instead. Raw values come from TSM market data.

## Example Walkthrough

### Setup
- Inventory: Herb A = 10, Herb B = 100, Herb C = 30, Pigment Dust = 0
- Concentration: AlchOne = 300, ScribeOne = 120
- Watched recipes:
  - R1: 1A + 2 Pigment Dust -> 11k profit, conc cost 100, conc bonus 18k
  - R2: 4A + 1B -> 50k profit, conc cost 150, conc bonus 35k
- Support recipes:
  - Make Pigment Dust: 2 Herb C -> 1 Pigment Dust (crafter: ScribeOne)

### Optimizer runs:

**Try R1=0:** Skip to R2. Try R2=0,1,2 with conc variations. Best: R2=2 + 2 conc = 170k.

**Try R1=1:** Needs 2 Pigment Dust. None in inventory. Support recipe crafts 2 from 4 Herb C. Resources after: A=9, B=100, C=26, Dust=0. Then try R2=0,1,2... Best combo with R1=1+conc + R2=2+conc.

**Try R1=2:** Uses 4 Herb C for Pigment Dust via support. Then R2 options...

...continues until R1 is infeasible.

The memoization ensures each unique state is only computed once.

### Result
The optimizer returns the exact combination that maximizes total profit, including how many support crafts are needed.

## Data Structures

### Watched Recipe
```lua
{
    id = recipeID,
    name = "Flask of Example",
    crafter = "Priestname-Realm",
    costs = { [itemID] = quantityPerCraft, ... },
    baseProfit = 14000,           -- copper, from CraftSim without concentration
    concentrationCost = 180,       -- concentration points per craft
    concentrationBonus = 9000,     -- additional profit when concentrated
    concentratedProfit = 23000,    -- total profit when concentrated (baseProfit + bonus)
}
```

### Support Recipe
```lua
{
    id = recipeID,
    name = "Craft Pigment Dust",
    crafter = "Scribename-Realm",
    outputItemID = itemID,
    outputQuantity = 1,
    costs = { [itemID] = quantityPerCraft, ... },
}
```

### Optimizer Output
```lua
{
    totalProfit = 182000,
    plan = {
        {
            type = "watched",
            recipeId = 1001,
            recipeName = "Flask of Example",
            crafter = "Priestname-Realm",
            crafts = 3,
            concentratedCrafts = 2,
            unconcentratedCrafts = 1,
            concentrationCostPerCraft = 180,
            totalConcentrationUsed = 360,
            baseProfit = 42000,
            concentrationProfit = 18000,
            totalProfit = 60000,
            supportPlan = {
                [2001] = {
                    recipeId = 2001,
                    recipeName = "Craft Pigment Dust",
                    crafter = "Scribename-Realm",
                    batches = 6,
                }
            },
        },
        -- ... more watched recipe steps
    }
}
```

## Simulation Tab vs Actions Tab

### Simulation Tab
Shows a **profit-ranked recipe list** — each watched recipe with its per-craft profit at each quality tier, with and without concentration. This is informational: "here's what CraftSim says about each recipe."

### Actions Tab  
Shows the **optimal production plan** — the exact output of the optimizer: which recipes to craft, how many, with how much concentration, what intermediates to craft first, and what to mail where. Includes brief reasoning (e.g., "R2 has highest profit per Herb A with concentration").

## Constraints for v1

- Support recipe graph must be acyclic (no circular dependencies)
- One preferred support recipe per output item
- Watched recipes are terminal products (sold for profit)
- Support recipes do not earn direct profit during fulfillment
- Concentration is only applied to watched terminal crafts (not intermediates)
- Vendor-purchasable items are excluded from resource tracking

## Future Extensions

- Concentration on intermediate recipes
- Multiple support recipes per output item (pick cheapest)
- Quality-aware intermediate crafting (use Q1 herbs for intermediates, Q3 for finals)
- Multi-crafter optimization (split work across crafters on different accounts)
- AH listing integration (auto-suggest what to post)

## Simulation Results Reference

| Sim | Inventory | Result | Profit |
|-----|-----------|--------|--------|
| 2a | A=100, B=5, C=30 | R2x5, 3 conc | 310k |
| 2b | A=10, B=100, C=30 | R2x2, R1x2, 3 conc | 182k |
| 3 | A=6, B=20, C=10 | R2x1, R1x2, R3x5, 2 conc | 152k |
| 4 | A=20, B=50 | R1(conc)x4, R2x7 | 156k |
| 5 | A=30, B=40 | Sell raw | 23,000g |
