return function(S, check, equal, event, advance)
    local globals = { "IsTradeSkillLinked", "GetTradeSkillLine", "GetNumTradeSkills", "GetTradeSkillInfo",
        "GetTradeSkillItemLink", "GetTradeSkillNumReagents", "GetTradeSkillReagentInfo",
        "GetTradeSkillReagentItemLink", "GetTradeSkillNumMade", "GetTradeSkillRecipeLink",
        "GetCraftDisplaySkillLine", "GetNumCrafts", "GetCraftInfo", "GetCraftItemLink",
        "GetCraftNumReagents", "GetCraftReagentInfo", "GetCraftReagentItemLink", "GetCraftRecipeLink" }
    local saved = {}
    for _, key in ipairs(globals) do saved[key] = _G[key] end
    local lineName, linked, malformed = "Blacksmithing", nil, false
    local recipes = {
        { "Category", "header" },
        { "Copper Bracers", "medium", 0, "|cffffffff|Hitem:2853:0:0:0:0:0:0:0|h[Copper Bracers]|h|r", "|cffffffff|Hitem:2840:0:0:0:0:0:0:0|h[Copper Bar]|h|r", 2 },
        { "Rough Copper Vest", "easy", 0, "|cffffffff|Hitem:10421:0:0:0:0:0:0:0|h[Rough Copper Vest]|h|r", "|cffffffff|Hitem:2840:0:0:0:0:0:0:0|h[Copper Bar]|h|r", 4 },
    }
    IsTradeSkillLinked = function() return linked end
    GetTradeSkillLine = function() return lineName, 1, 75, 0 end
    GetNumTradeSkills = function() return #recipes end
    GetTradeSkillInfo = function(index)
        local row = recipes[index]
        return row and row[1], row and row[2], row and row[3]
    end
    GetTradeSkillItemLink = function(index)
        if malformed and index == 2 then return "prefix|cffffffff|Hitem:2853:0|h[bad]|h|r" end
        return recipes[index] and recipes[index][4]
    end
    GetTradeSkillNumReagents = function(index) return recipes[index] and (index == 1 and 0 or 1) end
    GetTradeSkillReagentInfo = function(index) return "Copper Bar", "icon", recipes[index][6], 9 end
    GetTradeSkillReagentItemLink = function(index) return recipes[index][5] end
    GetTradeSkillNumMade = function() return 1, 1 end
    GetTradeSkillRecipeLink = function() return "|cffffd000|Henchant:123|h[Recipe]|h|r" end

    check(S.collectors.professionRecipes ~= nil, "Classic recipe observer registered in Era/TBC profile")
    check(table.concat(S.order, ","):find("professionRecipes", 1, true) ~= nil, "Classic sync order includes recipes")
    local data = S.collectors.professionRecipes()
    equal(data, nil, "closed profession window is not treated as an empty recipe list")
    S.professionRecipeOpen = true
    linked = 1
    data = S.collectors.professionRecipes()
    equal(data, nil, "remote/unowned skill list remains unavailable")
    linked = nil
    local meta
    data, meta = S.collectors.professionRecipes()
    check(data and #data.professions[1].recipes == 2, "visible learned recipe rows collected")
    equal(data.professions[1].recipes[1].name, "Copper Bracers", "recipe names retained")
    equal(data.professions[1].recipes[1].outputItemID, 2853, "exact output base ID observed from output link")
    equal(data.professions[1].recipes[1].outputItemString, "item:2853:0:0:0:0:0:0:0", "complete item variant payload preserved")
    equal(data.professions[1].recipes[1].reagents[1].itemID, 2840, "reagent item identity observed")
    equal(data.professions[1].recipes[1].reagents[1].required, 2, "reagent requirement captured from API")
    equal(data.professions[1].recipes[1].reagents[1].carriedByClient, 9, "client-reported carried count labeled and retained")
    equal(data.professions[1].recipes[1].difficulty, "medium", "difficulty is recorded only as difficulty")
    equal(data.professions[1].recipes[1].minimumSkill, nil, "difficulty is never converted to minimum skill")
    equal(data.professions[1].recipes[1].recipeID, nil, "output item ID is not misrepresented as a recipe ID")
    equal(data.professions[1].recipes[1].learnedState, "OBSERVED_TRUE", "own visible row is observed as learned")
    equal(meta.completeness, "partial", "current filtered/collapsed list is never called a full catalogue")
    check(type(data.professions[1].recipes[1].recipeKey) == "string", "unique exact output/name pair has explicit opaque identity")

    S.CommitProfessionRecipes(data, meta)
    local stored = S.record.sections.professionRecipes.data.professions
    equal(#stored, 1, "first visible profession persists")
    equal(stored[1].recipes[1].evidence, "OBSERVED", "fresh recipe has observed provenance")
    data, meta = S.collectors.professionRecipes(); S.CommitProfessionRecipes(data, meta)
    equal(#S.record.sections.professionRecipes.data.professions[1].recipes, 2, "repeat scan does not duplicate stable recipes")

    lineName = "Engineering"
    recipes = { { "Category", "header" }, { "Gnomish Goggles", "easy", 0,
        "|Hitem:10545:1:2:3|h[Gnomish Goggles]|h", "|Hitem:2841:0:0|h[Bronze Bar]|h", 2 } }
    data, meta = S.collectors.professionRecipes(); S.CommitProfessionRecipes(data, meta)
    stored = S.record.sections.professionRecipes.data.professions
    equal(#stored, 2, "separate professions accumulate across natural visits")
    equal(stored[1].evidence, "LAST_SEEN", "previous profession becomes last-seen when another profession is scanned")

    lineName = "Blacksmithing"
    malformed = true
    recipes = { { "Category", "header" }, { "Bad link", "easy", 0,
        "|cffffffff|Hitem:2853:0:0|h[bad]|h|r", "|Hitem:2840:0|h[Copper Bar]|h", 2 } }
    data, meta = S.collectors.professionRecipes()
    equal(data.professions[1].recipes[1].outputItemID, nil, "malformed wrapped link is not accepted")
    equal(data.professions[1].recipes[1].recipeKey, nil, "malformed identity cannot form a stable recipe key")
    equal(meta.completeness, "partial", "malformed item evidence degrades coverage")
    S.Attempt("professionRecipes", "temporary list failure", true)
    local retained = false
    for _, profession in ipairs(S.record.sections.professionRecipes.data.professions) do
        if profession.name == "Engineering" then retained = true end
    end
    check(retained, "failed scan preserves prior profession evidence")

    linked = 1
    equal(S.collectors.professionRecipes(), nil, "linked recipe list is rejected")

    -- The legacy Craft UI is a separate API. Its rows can be trainer/UI
    -- context, so visible presence does not prove the character learned it.
    local craftRows = {
        { "Synthetic Enchant Recipe", nil, "easy", 2, nil, nil, nil, nil,
            "|cffffffff|Henchant:42424242|h[Synthetic Enchant Recipe]|h|r",
            "|cffffffff|Hitem:9999991:0:0:0:0:0:0:0|h[Fixture Reagent]|h|r", 1 },
        { "Trainer Header", nil, "header", nil, true },
    }
    GetCraftDisplaySkillLine = function() return "Enchanting", 50, 75 end
    GetNumCrafts = function() return #craftRows end
    GetCraftInfo = function(index)
        local row = craftRows[index]
        if not row then return nil end
        return row[1], row[2], row[3], row[4], row[5], row[6], row[7], row[8]
    end
    GetCraftItemLink = function(index) return craftRows[index] and craftRows[index][9] end
    GetCraftNumReagents = function(index) return index == 1 and 1 or 0 end
    GetCraftReagentInfo = function() return "Fixture Reagent", "icon", 1, 3 end
    GetCraftReagentItemLink = function(index) return craftRows[index] and craftRows[index][10] end
    S.professionRecipeOpen, S.professionRecipeWindowType = true, "CRAFT"
    data, meta = S.collectors.professionRecipes()
    check(data and #data.professions[1].recipes == 1, "Craft API visible recipe row collected, header excluded")
    equal(data.professions[1].name, "Enchanting", "Craft API profession identity retained")
    equal(data.professions[1].recipes[1].outputKind, "ENCHANTMENT", "Enchanting Craft link is typed as an enchantment, not an item")
    equal(data.professions[1].recipes[1].enchantID, 42424242, "Craft enchant link identity observed")
    equal(data.professions[1].recipes[1].enchantString, "enchant:42424242", "opaque enchant string preserved")
    equal(data.professions[1].recipes[1].outputItemID, nil, "enchant identity is never mislabeled as output item")
    equal(data.professions[1].recipes[1].craftLink, craftRows[1][9], "exact client enchant link preserved")
    equal(data.professions[1].recipes[1].reagents[1].itemID, 9999991, "Craft API reagent identity observed")
    equal(data.professions[1].recipes[1].reagents[1].required, 1, "Craft API reagent quantity observed")
    equal(data.professions[1].recipes[1].reagents[1].carriedByClient, 3, "Craft API carried quantity explicitly scoped")
    equal(data.professions[1].recipes[1].clientAvailableCount, 2, "Craft API availability retained as a neutral client field")
    equal(data.professions[1].recipes[1].currentlyCraftableCount, nil, "Craft API availability is not promoted to craftability")
    equal(data.professions[1].recipes[1].learnedState, "UNKNOWN", "Craft API row is not misrepresented as learned")
    equal(data.professions[1].recipes[1].recipeID, nil, "Craft API row does not invent recipe ID")
    equal(data.professions[1].recipes[1].minimumSkill, nil, "Craft API row does not infer a minimum skill")
    check(type(data.professions[1].recipes[1].recipeKey) == "string", "validated enchant payload supplies an opaque stable row key")
    equal(data.professions[1].recipes[1].trainerRequiredLevel, nil, "nil trainer level stays unknown")
    equal(meta.completeness, "partial", "Craft API list remains explicitly partial")
    S.CommitProfessionRecipes(data, meta)
    local craftStored
    for _, profession in ipairs(S.record.sections.professionRecipes.data.professions) do
        if profession.name == "Enchanting" then craftStored = profession.recipes[1] end
    end
    equal(craftStored.evidence, "OBSERVED", "persisted Craft row retains observed row provenance")
    equal(craftStored.learnedEvidence, "UNKNOWN", "persisted Craft row keeps learned-state evidence independently unknown")
    equal(craftStored.learnedState, "UNKNOWN", "persisted Craft row is not treated as learned")
    equal(craftStored.enchantID, 42424242, "observed Craft enchant identity survives persistence")
    local oldCraftLink = GetCraftItemLink
    GetCraftItemLink = function() return "prefix|Henchant:42424242|h[bad]|h" end
    local badEnchant = S.collectors.professionRecipes()
    equal(badEnchant.professions[1].recipes[1].enchantID, nil, "malformed enchant wrapper is not accepted")
    equal(badEnchant.professions[1].recipes[1].recipeKey, nil, "malformed enchant wrapper cannot become identity")
    GetCraftItemLink = oldCraftLink

    GetCraftInfo = nil
    data = S.collectors.professionRecipes()
    equal(data, nil, "missing Craft API is unknown, not an empty recipe list")
    GetCraftInfo = function(index)
        local row = craftRows[index]
        if not row then return nil end
        return row[1], row[2], row[3], row[4], row[5], row[6], row[7], row[8]
    end
    GetNumCrafts = function() return 501 end
    data = S.collectors.professionRecipes()
    equal(data, nil, "out-of-bound Craft result is rejected without unbounded scan")
    GetNumCrafts = function() return #craftRows end
    S.professionRecipeWindowType = "TRADE_SKILL"
    S.professionRecipeOpen = false
    equal(S.collectors.professionRecipes(), nil, "closed window never becomes empty catalogue")

    event("TRADE_SKILL_SHOW"); advance(0.4)
    check(S.record.sections.professionRecipes ~= nil, "natural player-open event schedules observation")
    event("TRADE_SKILL_LIST_UPDATE")
    check(S.dirty.professionRecipes ~= nil, "trade-skill list update refreshes without polling")
    event("TRADE_SKILL_CLOSE")
    event("CRAFT_SHOW")
    equal(S.professionRecipeWindowType, "CRAFT", "legacy Craft show event selects the distinct API adapter")
    event("CRAFT_UPDATE")
    check(S.dirty.professionRecipes ~= nil, "Craft updates schedule observation without polling")
    event("CRAFT_CLOSE")
    equal(S.professionRecipeWindowType, nil, "Craft close clears only its own window state")
    local oldIsForever = WoWSyncCompat.IsForever
    WoWSyncCompat.IsForever = function() return true end
    S.dirty.professionRecipes = nil
    event("CRAFT_SHOW")
    equal(S.professionRecipeOpen, false, "Forever never enters the legacy Classic Craft collector path")
    event("CRAFT_UPDATE")
    equal(S.dirty.professionRecipes, nil, "Forever Craft events do not schedule a Classic recipe observation")
    WoWSyncCompat.IsForever = oldIsForever
    S.dirty.professionRecipes = nil
    for _, key in ipairs(globals) do _G[key] = saved[key] end
end
