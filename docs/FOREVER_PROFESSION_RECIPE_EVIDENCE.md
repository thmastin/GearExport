# Forever profession recipe evidence

GearExport captures Forever 1.60.1 recipe observations only while the character's own profession panel is open. The scan is read-only: it does not open windows, change filters, visit trainers, or craft.

The collector uses the version-documented `C_TradeSkillUI.GetAllRecipeIDs`, `GetTradeSkillLineForRecipe`, and `GetRecipeSchematic` APIs. The candidate list is explicitly partial: Forever may return no recipes before the relevant panel is hydrated, and a returned recipe list is not an exhaustive profession catalogue. Each candidate's learned state is checked independently with `C_SpellBook.IsSpellKnown`; unavailable or conflicting results remain UNKNOWN. The optional `GetRecipeInfo` result is corroborating evidence only.

When the client supplies it, each record includes recipe spell ID, profession association, schematic name, output item ID and quantity range, reagent slots with alternative item/currency choices and quantities, and required skill rank. `C_Item.GetItemInfoInstant` is used opportunistically for output type, subtype, equipment location, and class IDs. An unavailable item fact stays UNKNOWN. Trainer service observations remain a separate window-scoped feed: the available Forever trainer APIs do not establish that the trainer list is exhaustive or consistently bind each displayed service to a recipe spell ID.

To capture: open the character's own profession panel, allow the list to populate, then run `/wowsync`. Closing the panel or receiving an empty/unhydrated candidate list does not erase earlier evidence; retained rows become LAST_SEEN. Reopening the panel and capturing again refreshes them. No crafting is needed to discover recipes.

## Validation boundary

Fixtures exercise builds 70291 and 70338, candidate hydration, known/unlearned/unknown states, output and reagent data, linked panels, and unsupported API results. These are synthetic API-contract tests, not proof against a running client. Live recipe semantics still require the Windows Forever 1.60.1 client checkpoint. The tested addon makes no gameplay calls.
