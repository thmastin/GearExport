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
                return { learned = id == 61001 }
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
    check(coldMeta.retry, "empty enumeration uses bounded readiness retry")
    S.professionRecipeOpen = false
    local closed = S.collectors.professionRecipes()
    equal(closed, nil, "closed profession window is not enumerated")

    setFixture({ 61001, 61002, 61003 })
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
    equal(byID[61002].learnedState, "UNKNOWN", "conflicting learned APIs fail closed")
    equal(byID[61003].learnedState, "UNKNOWN", "unavailable learned API result remains unknown")
    equal(byID[61001].outputItemID, 2862, "schematic output item ID captured")
    equal(byID[61001].outputItemInfo.state, "OBSERVED", "output equip metadata comes from live client item API")
    equal(byID[61001].outputItemInfo.equipLocation, "INVTYPE_WRIST", "output equipment slot evidence captured")
    equal(byID[61001].outputQuantityMax, 5, "schematic output range captured")
    equal(#byID[61001].reagentSlots[1].reagents, 2, "alternative reagents remain alternatives")
    equal(byID[61001].reagentSlots[1].quantityRequired, 1, "required reagent quantity captured")
    equal(data.coverage.candidateCompleteness, "UNKNOWN", "enumeration is not treated as exhaustive")
    check(data.coverage.unknownLearnedCount >= 2, "unknown and contradictory learned results are counted")
    equal(filterCalls, 0, "no recipe filters are changed or trusted")
    equal(craftCalls, 0, "no crafting action occurs")
    S.CommitProfessionRecipes(data, meta)
    local stored = S.record.sections.professionRecipes.data.professions[1]
    equal(stored.recipes[1].evidence, "OBSERVED", "captured profession gets current provenance")
    check(stored.observedAt ~= nil, "profession observation time persisted")

    -- Missing optional GetRecipeInfo is expected for this API version. The
    -- spellbook check still proves learned state; schematics remain separate.
    setFixture({ 61001 })
    C_TradeSkillUI.GetRecipeInfo = nil
    data = S.collectors.professionRecipes()
    equal(data.professions[1].recipes[1].learnedState, "OBSERVED_TRUE", "Forever does not require an unsupported GetRecipeInfo function")
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
