return function(S, check, equal)
    local oldTrade, oldSpellbook, oldItem = C_TradeSkillUI, C_SpellBook, C_Item
    local oldProfessionList, oldProfessionInfo = GetProfessions, GetProfessionInfo
    local oldRecipePanel = S.professionRecipeOpen
    local filterCalls, craftCalls = 0, 0
    local function setFixture(ids)
        C_Item = { GetItemInfoInstant = function(id)
            return id, "Armor", "Miscellaneous", "INVTYPE_WRIST", 123, 4, 0
        end }
        C_TradeSkillUI = {
            IsTradeSkillLinked = function() return false end,
            GetAllRecipeIDs = function() return ids end,
            GetFilteredRecipeIDs = function() filterCalls = filterCalls + 1; error("filtered candidates are not authoritative") end,
            GetTradeSkillLineForRecipe = function(id)
                if id == 61004 then return nil end -- enumerated, but not enough evidence to associate
                if id == 61003 then return 164, "Blacksmithing", 164 end
                return 164, "Blacksmithing", 164
            end,
            GetRecipeSchematic = function(id, recraft)
                equal(recraft, false, "ordinary recipe schematic only")
                if id == 61003 then return nil end
                return {
                    recipeID = id, name = id == 61001 and "Rough Sharpening Stone" or "Copper Bracers",
                    outputItemID = id == 61001 and 2862 or 2853, quantityMin = 1, quantityMax = id == 61001 and 5 or 1,
                    reagentSlotSchematics = {
                        { quantityRequired = id == 61001 and 1 or 6, required = true, slotInfo = { requiredSkillRank = 1 }, reagents = { { itemID = 2835 }, { itemID = 2836 } } },
                    },
                }
            end,
            GetRecipeInfo = function(id)
                if id == 61002 then return { learned = true } end -- conflicts with spellbook false
                if id == 61001 then return { recipeID = id, learned = true, name = "Info name fallback", relativeDifficulty = 2, maxTrivialLevel = 25, numSkillUps = 1, canSkillUp = true } end
                return { learned = false }
            end,
            CraftRecipe = function() craftCalls = craftCalls + 1; error("collector must never craft") end,
        }
        C_SpellBook = { IsSpellKnown = function(id)
            if id == 61001 then return true end
            if id == 61002 then return false end
            return nil
        end }
        GetProfessions = function() return 1, 2, nil, nil, nil end
        GetProfessionInfo = function(index)
            if index == 1 then return "Mining", nil, 3, 75, nil, nil, 186 end
            if index == 2 then return "Blacksmithing", nil, 1, 75, nil, nil, 164 end
        end
        S.professionRecipeOpen = true
    end

    check(S.collectors.professionRecipes ~= nil, "Forever recipe collector registered")
    setFixture({})
    local cold, coldMeta = S.collectors.professionRecipes()
    equal(cold, nil, "empty/unhydrated candidate enumeration is not an empty learned set")
    check(coldMeta.reason:match("empty table %(0 candidates%)") ~= nil, "empty API table is distinguished from an API error or malformed result")
    check(coldMeta.retry, "empty enumeration uses bounded readiness retry")
    C_TradeSkillUI.GetAllRecipeIDs = function() error("recipe panel data pending") end
    local failed, failedMeta = S.collectors.professionRecipes()
    equal(failed, nil, "API exceptions do not produce recipe evidence")
    check(failedMeta.reason:match("raised an API error: .*recipe panel data pending") ~= nil, "API exception detail is retained for diagnosis")
    C_TradeSkillUI.GetAllRecipeIDs = function() return nil end
    local nilResult, nilMeta = S.collectors.professionRecipes()
    equal(nilResult, nil, "nil enumeration does not produce recipe evidence")
    check(nilMeta.reason:match("returned nil") ~= nil, "nil API return is distinguished")
    C_TradeSkillUI.GetAllRecipeIDs = function() return false end
    local malformedResult, malformedMeta = S.collectors.professionRecipes()
    equal(malformedResult, nil, "non-table enumeration does not produce recipe evidence")
    check(malformedMeta.reason:match("returned boolean, expected a recipe ID array") ~= nil, "non-table API shape is identified")
    C_TradeSkillUI.GetAllRecipeIDs = function() return { [1] = 61001, [3] = 61002 } end
    local malformedArray, malformedArrayMeta = S.collectors.professionRecipes()
    equal(malformedArray, nil, "sparse enumeration does not produce recipe evidence")
    check(malformedArrayMeta.reason:match("malformed array %(keys=2, numericKeys=2%)") ~= nil, "malformed array shape is distinguished from an empty list")
    S.professionRecipeOpen = false
    local closed = S.collectors.professionRecipes()
    equal(closed, nil, "closed profession window is not enumerated")

    setFixture({ 61001, 61002, 61003, 61004 })
    local data, meta = S.collectors.professionRecipes()
    if not data then error("Forever recipe fixture was rejected: " .. tostring(meta and meta.reason)) end
    equal(meta.completeness, "partial", "candidate list never claims global catalogue completeness")
    equal(data.ownerScope, "CHARACTER", "recipe data is character scoped")
    equal(data.client.clientFamily, "Forever", "Forever data remains version isolated")
    equal(data.client.clientVersion, "1.60.1", "client version attached to observation")
    equal(data.professions[1].name, "Blacksmithing", "recipe association identifies learned profession")
    equal(data.professions[1].skill, 1, "current skill comes from learned profession tuple")
    local byID = {}
    for _, recipe in ipairs(data.professions[1].recipes) do byID[recipe.recipeID] = recipe end
    equal(byID[61001].learnedState, "OBSERVED_TRUE", "known recipe uses spellbook true")
    equal(byID[61001].relativeDifficulty, 2, "Forever recipe difficulty API value captured without reinterpretation")
    equal(byID[61001].maxTrivialLevel, 25, "Forever maximum trivial skill value captured as reported")
    equal(byID[61001].numSkillUps, 1, "Forever recipe skill-up count captured")
    equal(byID[61001].canSkillUp, true, "Forever can-skill-up boolean captured")
    equal(byID[61001].recipeProgressionInfoState, "OBSERVED", "progression info has explicit API provenance")
    equal(byID[61001].name, "Rough Sharpening Stone", "schematic name takes precedence over recipe info fallback")
    equal(byID[61002].learnedState, "UNKNOWN", "conflicting learned APIs fail closed")
    equal(byID[61003].learnedState, "UNKNOWN", "unavailable learned API result remains unknown")
    equal(byID[61001].outputItemID, 2862, "schematic output item ID captured")
    equal(byID[61001].outputItemInfo.state, "OBSERVED", "output equip metadata comes from live client item API")
    equal(byID[61001].outputItemInfo.equipLocation, "INVTYPE_WRIST", "output equipment slot evidence captured")
    equal(byID[61001].outputQuantityMax, 5, "schematic output range captured")
    equal(#byID[61001].reagentSlots[1].reagents, 2, "alternative reagents remain alternatives")
    equal(byID[61001].reagentSlots[1].quantityRequired, 1, "required reagent quantity captured")
    equal(data.coverage.candidateCompleteness, "UNKNOWN", "enumeration is not treated as exhaustive")
    equal(data.coverage.returnedRecipeCount, 4, "coverage count reflects every ID returned by GetAllRecipeIDs")
    equal(data.professions[1].coverage.returnedRecipeCount, 4, "profession coverage retains raw enumeration count despite unresolved association")
    equal(#data.professions[1].recipes, 3, "candidate with unresolved association is not fabricated into a recipe row")
    check(data.coverage.unknownLearnedCount >= 2, "unknown and contradictory learned results are counted")
    equal(filterCalls, 0, "no recipe filters are changed or trusted")
    equal(craftCalls, 0, "no crafting action occurs")
    S.CommitProfessionRecipes(data, meta)
    local stored = S.record.sections.professionRecipes.data.professions[1]
    equal(stored.recipes[1].evidence, "OBSERVED", "captured profession gets current provenance")
    equal(stored.recipes[2].evidence, "UNKNOWN", "unknown learned state without prior evidence remains UNKNOWN")
    equal(stored.recipes[3].evidence, "UNKNOWN", "candidate missing learned and schematic evidence remains UNKNOWN")
    check(stored.observedAt ~= nil, "profession observation time persisted")

    -- Missing optional GetRecipeInfo is expected for this API version. The
    -- spellbook check still proves learned state; schematics remain separate.
    setFixture({ 61001 })
    C_TradeSkillUI.GetRecipeInfo = nil
    data = S.collectors.professionRecipes()
    equal(data.professions[1].recipes[1].learnedState, "OBSERVED_TRUE", "Forever does not require an unsupported GetRecipeInfo function")
    equal(data.professions[1].recipes[1].recipeProgressionInfoState, "UNKNOWN", "missing optional progression API remains UNKNOWN")
    setFixture({ 61001 })
    C_TradeSkillUI.GetRecipeSchematic = function() return { recipeID = 61001 } end
    data = S.collectors.professionRecipes()
    equal(data.professions[1].recipes[1].name, "Info name fallback", "recipe name falls back to GetRecipeInfo")
    setFixture({ 61001 })
    C_TradeSkillUI.GetRecipeInfo = function() return { learned = true, relativeDifficulty = "2", maxTrivialLevel = -1, numSkillUps = true, canSkillUp = 1 } end
    data = S.collectors.professionRecipes()
    local malformed = data.professions[1].recipes[1]
    equal(malformed.relativeDifficulty, nil, "string difficulty is not coerced")
    equal(malformed.maxTrivialLevel, nil, "negative maximum trivial skill is omitted")
    equal(malformed.numSkillUps, nil, "boolean skill-up count is omitted")
    equal(malformed.canSkillUp, nil, "numeric can-skill-up value is omitted")
    C_TradeSkillUI.GetRecipeInfo = function() return { recipeID = 61002, learned = true, relativeDifficulty = 2 } end
    equal(S.collectors.professionRecipes(), nil, "recipe info identity cannot be attached to another enumerated recipe")
    setFixture({ 61001 })
    C_TradeSkillUI.GetRecipeInfo = function() return { recipeID = 61001, learned = true, relativeDifficulty = 4 } end
    data = S.collectors.professionRecipes()
    equal(data.professions[1].recipes[1].relativeDifficulty, nil, "out-of-domain relative difficulty is omitted")
    C_TradeSkillUI.IsTradeSkillLinked = function() return true end
    equal(S.collectors.professionRecipes(), nil, "another character's linked profession is rejected")
    C_TradeSkillUI.IsTradeSkillLinked = function() return nil end
    equal(S.collectors.professionRecipes(), nil, "missing linked-source evidence is unknown")
    setFixture({ 61001 })
    C_TradeSkillUI.GetTradeSkillLineForRecipe = function() return 999, "Unknown", 999 end
    equal(S.collectors.professionRecipes(), nil, "recipe panel must match a learned player profession")
    setFixture({ 61001, 61001 })
    equal(S.collectors.professionRecipes(), nil, "duplicate candidate IDs are rejected")
    setFixture({ [1] = 61001, [3] = 61002 })
    equal(S.collectors.professionRecipes(), nil, "sparse candidate arrays are rejected")

    C_TradeSkillUI, C_SpellBook, C_Item = oldTrade, oldSpellbook, oldItem
    GetProfessions, GetProfessionInfo = oldProfessionList, oldProfessionInfo
    S.professionRecipeOpen = oldRecipePanel
end
