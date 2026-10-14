return function(S, check, equal)
    local oldTrade, oldSpellbook, oldItem, oldPlayerInfo = C_TradeSkillUI, C_SpellBook, C_Item, C_PlayerInfo
    local oldProfessionList, oldProfessionInfo = GetProfessions, GetProfessionInfo
    local oldRecipePanel = S.professionRecipeOpen
    local filterCalls, craftCalls, outputLoadRequests = 0, 0, {}
    local function setFixture(ids)
        S.foreverRecipeItemRequests, S.foreverRecipeItemRequestCount, S.foreverRecipeItemLoadResults = {}, 0, {}
        C_Item = { GetItemInfoInstant = function(id)
            return id, "Armor", "Miscellaneous", "INVTYPE_WRIST", 123, 4, 0
        end,
            GetItemInfo = function(id)
                equal(type(id), "number", "full output item metadata is queried by observed item ID")
                return "Synthetic Bracers", nil, 2, 4, 2, "Armor", "Mail", 1, "INVTYPE_WRIST", 123, 10, 4, 3, 1
            end,
            GetItemStats = function(reference)
                equal(reference, "item:2862", "unowned output stat query uses the documented minimal ID reference, not a fabricated variant")
                return { RESISTANCE0_NAME = 2, ITEM_MOD_STAMINA_SHORT = 1 }
            end,
            IsEquippableItem = function(id) return id == 2862 end,
            RequestLoadItemDataByID = function(id) outputLoadRequests[#outputLoadRequests + 1] = id end,
        }
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
            GetRecipeRequirements = function(id)
                if id == 61001 then return { { name = "Anvil", met = false, type = 2 } } end
                return {}
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
    local sparseArray, sparseArrayMeta = S.collectors.professionRecipes()
    check(sparseArray ~= nil, "sparse numeric array from GetAllRecipeIDs is accepted as candidate enumeration")
    equal(sparseArray.coverage.returnedRecipeCount, 2, "sparse numeric array preserves every returned candidate")
    equal(sparseArray.professions[1].recipes[1].recipeID, 61001, "sparse numeric array retains numeric-key order")
    equal(sparseArray.professions[1].recipes[2].recipeID, 61002, "sparse numeric array retains later candidate")
    equal(sparseArray.coverage.candidateCompleteness, "UNKNOWN", "sparse candidate enumeration does not claim complete recipe knowledge")
    equal(sparseArrayMeta.completeness, "partial", "sparse candidate list is still reported partial")
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
    equal(byID[61001].outputItemEvidence.itemID, 2862, "learned output evidence is keyed by exact recipe output item ID")
    equal(byID[61001].outputItemEvidence.returnedItemID, 2862, "client metadata identity is preserved separately from the exact recipe output identity")
    equal(byID[61001].outputItemEvidence.itemReferenceKind, "MINIMAL_ID_REFERENCE_NO_VARIANT",
        "unowned candidate is not assigned a fabricated exact variant")
    equal(byID[61001].outputItemEvidence.name, "Synthetic Bracers", "cached candidate item name is retained")
    equal(byID[61001].outputItemEvidence.requiredLevel, 2, "cached candidate required level is retained from GetItemInfo")
    equal(byID[61001].outputItemEvidence.quality, 2, "cached candidate quality is retained")
    equal(byID[61001].outputItemEvidence.itemStats.table.entries[1].key, "ITEM_MOD_STAMINA_SHORT",
        "candidate stats are captured in deterministic raw-key order")
    equal(byID[61001].outputItemEvidence.itemStats.table.entries[2].key, "RESISTANCE0_NAME",
        "raw Armor key is preserved without evaluating upgrade value")
    equal(byID[61001].outputItemEvidence.isEquippableItem.returns[1].observation.value, true,
        "item-specific usability signal is retained as raw player-scoped evidence")
    equal(byID[61001].outputItemEvidence.eligibilityInterpretation,
        "RAW_PLAYER_SCOPED_SIGNALS_ONLY_NOT_FULL_EQUIP_ELIGIBILITY", "positive API signal is not promoted to full eligibility")
    equal(byID[61001].requirements.requirements[1].name, "Anvil", "recipe facility/tool requirement is preserved only from API result")
    equal(byID[61001].requirements.requirements[1].met, false, "requirement met state is raw API evidence")
    equal(byID[61001].requirements.requirements[1].requirementType, 2, "requirement type stays numeric and uninterpreted")
    check(type(byID[61001].requirements.observedAt) == "number", "recipe requirements retain an independent observation timestamp")
    equal(byID[61001].maxTrivialLevel, 25, "maximum trivial skill is not transformed into a minimum-skill requirement")
    equal(byID[61002].outputItemEvidence, nil, "unlearned or contradictory recipes do not trigger candidate item evidence")
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
    equal(#outputLoadRequests, 0, "cached output needs no asynchronous load request")
    S.CommitProfessionRecipes(data, meta)
    local stored = S.record.sections.professionRecipes.data.professions[1]
    equal(stored.recipes[1].evidence, "OBSERVED", "captured profession gets current provenance")
    equal(stored.recipes[2].evidence, "UNKNOWN", "unknown learned state without prior evidence remains UNKNOWN")
    equal(stored.recipes[3].evidence, "UNKNOWN", "candidate missing learned and schematic evidence remains UNKNOWN")
    check(stored.observedAt ~= nil, "profession observation time persisted")

    setFixture({ 61001 })
    C_TradeSkillUI.GetRecipeRequirements = function()
        local requirements = {}
        for index = 1, 33 do requirements[index] = { name = "Requirement " .. index, met = false, type = 2 } end
        return requirements
    end
    data = S.collectors.professionRecipes()
    local boundedRequirements = data.professions[1].recipes[1].requirements
    equal(boundedRequirements.state, "PARTIAL", "oversized requirement response is explicitly partial")
    equal(#boundedRequirements.requirements, 32, "one recipe requirement response is bounded")
    equal(boundedRequirements.returnedCount, 33, "raw returned requirement count is retained")
    equal(boundedRequirements.truncated, true, "truncated requirement rows are explicitly marked")

    setFixture({ 61001 })
    C_Item.IsEquippableItem = nil
    C_PlayerInfo = nil
    data = S.collectors.professionRecipes()
    local unknownEligibility = data.professions[1].recipes[1].outputItemEvidence
    equal(unknownEligibility.isEquippableItem.state, "API_MISSING", "unavailable candidate equipability stays unknown")
    equal(unknownEligibility.canUseItem.state, "API_MISSING", "unavailable character use check stays unknown")
    equal(unknownEligibility.eligibilityInterpretation,
        "RAW_PLAYER_SCOPED_SIGNALS_ONLY_NOT_FULL_EQUIP_ELIGIBILITY", "missing signals do not become positive eligibility")
    C_PlayerInfo = oldPlayerInfo

    -- Missing optional GetRecipeInfo is expected for this API version. The
    -- spellbook check still proves learned state; schematics remain separate.
    setFixture({ 61001 })
    C_TradeSkillUI.GetRecipeInfo = nil
    data = S.collectors.professionRecipes()
    equal(data.professions[1].recipes[1].learnedState, "OBSERVED_TRUE", "Forever does not require an unsupported GetRecipeInfo function")
    equal(data.professions[1].recipes[1].recipeProgressionInfoState, "UNKNOWN", "missing optional progression API remains UNKNOWN")
    setFixture({ 61001 })
    local requestCount = 0
    C_Item.GetItemInfo = function() return nil end
    C_Item.GetItemStats = function() return nil end
    C_Item.RequestLoadItemDataByID = function(id) equal(id, 2862, "async request uses only the observed output ID"); requestCount = requestCount + 1 end
    data = S.collectors.professionRecipes()
    local uncached = data.professions[1].recipes[1].outputItemEvidence
    equal(uncached.cacheState, "CACHE_PENDING", "uncached output remains pending rather than empty")
    equal(uncached.itemInfo.state, "NIL_RESULT", "uncached GetItemInfo nil return is explicit")
    equal(uncached.itemStats.table.state, "NIL", "uncached stats nil return is explicit")
    equal(uncached.loadRequestState, "REQUEST_CALL_SUCCEEDED_AWAITING_EVENT", "nil-returning load call is not treated as loaded data")
    equal(uncached.loadRequestResult.state, "ZERO_RETURNS", "request call return shape is recorded separately from load completion")
    S.collectors.professionRecipes()
    equal(requestCount, 1, "same item is not repeatedly requested while pending")
    S.eventFrame.scripts.OnEvent(S.eventFrame, "ITEM_DATA_LOAD_RESULT", 2862, true)
    C_Item.GetItemInfo = function() return nil end
    C_Item.GetItemStats = function() return nil end
    data = S.collectors.professionRecipes()
    equal(data.professions[1].recipes[1].outputItemEvidence.cacheState,
        "LOAD_SUCCEEDED_BUT_METADATA_OR_STATS_NIL", "successful load event does not fabricate usable metadata or stats")
    check(S.dirty.professionRecipes ~= nil, "item-load event schedules a fresh recipe evidence pass while its panel remains open")
    setFixture({ 61001 })
    C_Item.GetItemInfo = function() return nil end
    C_Item.GetItemStats = function() return nil end
    data = S.collectors.professionRecipes()
    local failedRequestCount = #outputLoadRequests
    S.eventFrame.scripts.OnEvent(S.eventFrame, "ITEM_DATA_LOAD_RESULT", 2862, false)
    data = S.collectors.professionRecipes()
    equal(data.professions[1].recipes[1].outputItemEvidence.cacheState, "LOAD_FAILED",
        "failed asynchronous load remains explicit and does not become empty stats")
    equal(#outputLoadRequests, failedRequestCount, "failed asynchronous loads are not repeatedly requested in the same session")
    setFixture({})
    local manyIDs = {}
    for id = 62001, 62040 do manyIDs[#manyIDs + 1] = id end
    C_TradeSkillUI.GetAllRecipeIDs = function() return manyIDs end
    C_TradeSkillUI.GetTradeSkillLineForRecipe = function() return 164, "Blacksmithing", 164 end
    C_TradeSkillUI.GetRecipeInfo = function(id) return { recipeID = id, learned = true } end
    C_TradeSkillUI.GetRecipeSchematic = function(id) return { recipeID = id, name = "Synthetic learned output", outputItemID = id + 100000 } end
    C_TradeSkillUI.GetRecipeRequirements = function() return {} end
    C_SpellBook.IsSpellKnown = function() return true end
    C_Item.GetItemInfo = function() return nil end
    C_Item.GetItemStats = function() return nil end
    C_Item.RequestLoadItemDataByID = function(id) outputLoadRequests[#outputLoadRequests + 1] = id end
    local requestsBeforeBound = #outputLoadRequests
    data = S.collectors.professionRecipes()
    equal(#outputLoadRequests - requestsBeforeBound, 32, "candidate item cache requests have a fixed per-session bound")
    local lastRecipe = data.professions[1].recipes[#data.professions[1].recipes]
    equal(lastRecipe.outputItemEvidence.loadRequestState, "REQUEST_BOUND_REACHED",
        "items beyond the request bound retain their identity but are not requested")
    setFixture({ 61001 })
    C_Item.GetItemInfo = function() return nil end
    C_Item.GetItemStats = function() return nil end
    C_Item.RequestLoadItemDataByID = nil
    data = S.collectors.professionRecipes()
    equal(data.professions[1].recipes[1].outputItemEvidence.cacheState, "CACHE_REQUEST_UNAVAILABLE",
        "missing cache request API remains unknown and does not block recipe capture")
    setFixture({ 61001 })
    C_Item.GetItemStats = function() error("stats unavailable") end
    data = S.collectors.professionRecipes()
    equal(data.professions[1].recipes[1].outputItemEvidence.itemStats.state, "API_ERROR",
        "throwing stats API is recorded without zero fallback")
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
    local noMatch, noMatchMeta = S.collectors.professionRecipes()
    equal(noMatch, nil, "recipe panel must match a learned player profession")
    check(noMatchMeta.reason:find("recipe 61001 -> Unknown, parent skill line 999", 1, true) ~= nil, "failure names the mismatched recipe")
    setFixture({ 61001, 61002 })
    C_TradeSkillUI.GetTradeSkillLineForRecipe = function(id) if id == 61002 then return 999, "Unknown", 999 end return 164, "Blacksmithing", 164 end
    local mixed = S.collectors.professionRecipes()
    check(mixed ~= nil, "one stray row from an unlearned profession does not discard the panel")
    equal(#mixed.professions[1].recipes, 1, "the stray row is skipped")
    equal(mixed.professions[1].coverage.unmatchedProfessionCount, 1, "the stray row is counted")
    equal(mixed.professions[1].coverage.unmatchedProfessionExamples[1].recipeID, 61002, "the stray row is named")

    -- A stray row from another profession the character HAS learned (Mining 186) inside the Blacksmithing panel.
    local strayLine = function(id) if id == 61002 then return 186, "Mining", 186 end return 164, "Blacksmithing", 164 end
    setFixture({ 61001, 61002 })
    C_TradeSkillUI.GetTradeSkillLineForRecipe = strayLine
    C_TradeSkillUI.GetBaseProfessionInfo = function() return { professionID = 164, professionName = "Blacksmithing" } end
    local anchored = S.collectors.professionRecipes()
    check(anchored ~= nil, "the open profession anchors the panel even when the stray profession is learned")
    equal(anchored.professions[1].professionName, "Blacksmithing", "anchored to the open profession")
    equal(anchored.professions[1].coverage.anchorBasis, "C_TradeSkillUI.GetBaseProfessionInfo", "anchor basis recorded")
    equal(anchored.professions[1].coverage.unmatchedProfessionCount, 1, "the learned-profession stray is counted")
    local many = {}
    for id = 61005, 61023 do many[#many + 1] = id end
    many[#many + 1] = 61002
    setFixture(many)
    C_TradeSkillUI.GetTradeSkillLineForRecipe = strayLine
    local majority = S.collectors.professionRecipes()
    check(majority ~= nil, "without an anchor, a 95% majority identifies the panel")
    equal(majority.professions[1].coverage.anchorBasis, "DERIVED_MAJORITY", "majority basis recorded")
    equal(#majority.professions[1].recipes, 19, "majority rows kept")
    setFixture({ 61001, 61002 })
    C_TradeSkillUI.GetTradeSkillLineForRecipe = strayLine
    local split, splitMeta = S.collectors.professionRecipes()
    equal(split, nil, "an evenly split panel without an anchor is still refused")
    check(splitMeta.reason:find("Mining", 1, true) ~= nil and splitMeta.reason:find("Blacksmithing", 1, true) ~= nil, "refusal names both professions")

    -- Source text for unlearned recipes, raw and read-only.
    setFixture({ 61002 })
    C_TradeSkillUI.GetRecipeInfo = function() return { learned = false } end
    C_TradeSkillUI.GetRecipeSourceText = function(id) return "Trainer: Blacksmithing\nRequires Blacksmithing (50)" end
    local sourced = S.collectors.professionRecipes()
    equal(sourced.professions[1].recipes[1].learned, false, "fixture recipe is unlearned")
    equal(sourced.professions[1].recipes[1].sourceText, "Trainer: Blacksmithing\nRequires Blacksmithing (50)", "client source text recorded raw")
    equal(sourced.professions[1].recipes[1].sourceTextState, "OBSERVED", "source text state")
    C_TradeSkillUI.GetRecipeSourceText = nil
    sourced = S.collectors.professionRecipes()
    equal(sourced.professions[1].recipes[1].sourceTextState, "API_UNAVAILABLE", "missing API recorded, not guessed")
    setFixture({ 61001, 61001 })
    local duplicateIDs, duplicateMeta = S.collectors.professionRecipes()
    check(duplicateIDs ~= nil, "duplicate recipe IDs are deduplicated rather than discarding the whole API result")
    equal(duplicateIDs.coverage.returnedRecipeCount, 2, "raw API candidate count preserves duplicate entries")
    equal(duplicateIDs.coverage.uniqueCandidateCount, 1, "unique candidate count excludes duplicate recipe IDs")
    equal(duplicateIDs.coverage.duplicateRecipeIDCount, 1, "duplicate recipe ID count is explicit")
    equal(#duplicateIDs.professions[1].recipes, 1, "a repeated recipe is emitted only once")
    equal(duplicateIDs.coverage.candidateCompleteness, "UNKNOWN", "deduplication does not imply complete catalogue coverage")
    equal(duplicateMeta.completeness, "partial", "deduplicated recipe data remains partial")
    setFixture({ [61001] = true })
    equal(S.collectors.professionRecipes(), nil, "boolean ID-set dictionary is not mistaken for a number array")

    C_TradeSkillUI, C_SpellBook, C_Item, C_PlayerInfo = oldTrade, oldSpellbook, oldItem, oldPlayerInfo
    GetProfessions, GetProfessionInfo = oldProfessionList, oldProfessionInfo
    S.professionRecipeOpen = oldRecipePanel
end
