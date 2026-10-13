return function(S, check, equal)
    local passed = 0
    local function c(value, message) check(value, "talents: " .. message); passed = passed + 1 end
    local function e(a, b, message) equal(a, b, "talents: " .. message); passed = passed + 1 end
    local spent = 0
    LearnTalent = function() spent = spent + 1; error("talent collector must never learn talents") end

    c(S.collectors.talents ~= nil, "Forever talent collector registered")
    c(S.structuredOnly.talents == true, "talents travel only in the structured sidecar")
    local inOrder = false
    for _, key in ipairs(S.order) do if key == "talents" then inOrder = true end end
    c(inOrder, "talents are in the Forever section order")

    local savedTabs, savedTab, savedNum, savedInfo, savedPoints = GetNumTalentTabs, GetTalentTabInfo, GetNumTalents, GetTalentInfo, UnitCharacterPoints
    GetNumTalentTabs, GetTalentTabInfo, GetNumTalents, GetTalentInfo = nil, nil, nil, nil
    local probed = 0
    local savedSpec = C_SpecializationInfo
    C_FakeTalentProbe = { GetTalentTreeInfo = function() probed = probed + 1 end, Other = function() probed = probed + 1 end }
    C_SpecializationInfo = { GetSpecialization = function() probed = probed + 1 end }
    local data, meta = S.collectors.talents()
    e(data.state, "LEGACY_API_UNAVAILABLE", "missing legacy APIs are recorded as such")
    e(#data.trees, 0, "missing APIs produce no trees")
    e(meta.completeness, "unknown", "missing APIs are unknown, not empty")
    local names = table.concat(data.apiInventory.namespaces, ",")
    c(names:find("C_FakeTalentProbe.GetTalentTreeInfo", 1, true) ~= nil, "talent namespaces are inventoried by name")
    c(names:find("C_SpecializationInfo.GetSpecialization", 1, true) ~= nil, "specialization namespace inventoried")
    e(probed, 0, "inventoried functions are never called")
    C_FakeTalentProbe, C_SpecializationInfo = nil, savedSpec

    GetNumTalentTabs = function() return 3 end
    GetTalentTabInfo = function(tab) return ({ "Balance", "Feral Combat", "Restoration" })[tab], "icon", tab == 1 and 2 or 0 end
    GetNumTalents = function(tab) return tab == 3 and 1 or 2 end
    GetTalentInfo = function(tab, index)
        if tab == 2 and index == 2 then return nil end
        return "Talent " .. tab .. "-" .. index, "icon", index, 1, tab == 1 and index == 1 and 2 or 0, 5
    end
    UnitCharacterPoints = function() return 1 end
    data, meta = S.collectors.talents()
    e(#data.trees, 3, "three trees observed")
    e(data.trees[1].name, "Balance", "tree name retained")
    e(data.trees[1].pointsSpent, 2, "points spent retained")
    e(data.trees[1].talents[1].currentRank, 2, "talent rank retained")
    e(data.trees[1].talents[1].maxRank, 5, "talent max rank retained")
    e(#data.trees[2].talents, 1, "a missing talent row is skipped, not invented")
    e(meta.completeness, "partial", "a missing talent row makes coverage partial")
    e(data.unspentPoints, 1, "unspent points observed")
    c(type(data.clientProfile) == "string" and data.clientProfile:match("^Forever:") ~= nil, "Forever profile recorded")

    GetNumTalentTabs = function() return 50 end
    data, meta = S.collectors.talents()
    e(data, nil, "an out-of-bound tree count is refused")
    e(meta.completeness, "unknown", "out-of-bound count is unknown")
    e(spent, 0, "no talent was learned")

    -- Forever 1.60.1: legacy APIs absent, Retail trait system present. Only getters may be called.
    GetNumTalentTabs, GetTalentTabInfo, GetNumTalents, GetTalentInfo = nil, nil, nil, nil
    local mutated = 0
    local function forbid() mutated = mutated + 1; error("talent collector must not change talents") end
    local savedClassTalents, savedTraits, savedSpell, savedGetSpec, savedSpecInfo = C_ClassTalents, C_Traits, C_Spell, GetSpecialization, GetSpecializationInfo
    local activeConfig = nil
    C_ClassTalents = {
        GetActiveConfigID = function() return activeConfig end,
        HasUnspentTalentPoints = function() return true end,
        CommitConfig = forbid, LoadConfig = forbid, SwitchToLoadoutByIndex = forbid,
    }
    local nodes = {
        [11] = { ID = 11, currentRank = 2, maxRanks = 5, ranksPurchased = 2, posX = 100, posY = 200, isVisible = true, subTreeID = 7, activeEntry = { entryID = 111, rank = 2 },
            isAvailable = true, canPurchaseRank = true, meetsEdgeRequirements = true, visibleEdges = { { targetNode = 12 } }, conditionIDs = { 77 } },
        [12] = { ID = 12, currentRank = 0, maxRanks = 1, ranksPurchased = 0, isVisible = true, subTreeID = 8, entryIDs = { 112 } },
        [13] = { ID = 13, currentRank = 0, maxRanks = 1, isVisible = false, subTreeID = 8, entryIDs = { 113 } },
    }
    C_Traits = {
        GetConfigInfo = function() return { ID = 55, treeIDs = { 900 } } end,
        GetTreeNodes = function() return { 11, 12, 13 } end,
        GetNodeInfo = function(_, nodeID) return nodes[nodeID] end,
        GetEntryInfo = function(_, entryID) return { definitionID = entryID + 1000 } end,
        GetDefinitionInfo = function(definitionID) return { spellID = definitionID + 5000 } end,
        GetSubTreeInfo = function(_, subTreeID) return { name = subTreeID == 7 and "Balance" or "Feral Combat" } end,
        GetTreeCurrencyInfo = function() return { { traitCurrencyID = 3, quantity = 1, maxQuantity = 3, spent = 2 } } end,
        GetConditionInfo = function() return { isMet = true, spentAmountRequired = 5, traitCurrencyID = 3 } end,
        PurchaseRank = forbid, RefundRank = forbid, ResetTree = forbid, RollbackConfig = forbid,
    }
    C_Spell = { GetSpellName = function(spellID) return "Spell " .. spellID end }
    GetSpecialization = function() return 1 end
    GetSpecializationInfo = function() return 102, "Balance" end

    data, meta = S.collectors.talents()
    e(data, nil, "no active config yet produces no data")
    c(meta.stale == true and meta.completeness == "unknown", "missing config keeps the last observation")

    activeConfig = 55
    data, meta = S.collectors.talents()
    e(data.source, "C_ClassTalents/C_Traits", "trait source recorded")
    e(#data.trees, 2, "sub-trees become trees")
    e(data.trees[1].name, "Balance", "sub-tree name observed")
    e(data.trees[1].pointsSpent, 2, "points spent summed from purchased ranks")
    e(data.trees[1].talents[1].name, "Spell 6111", "talent named from its definition spell")
    e(data.trees[1].talents[1].currentRank, 2, "trait rank retained")
    e(data.trees[1].talents[1].maxRank, 5, "trait max rank retained")
    e(#data.trees[2].talents, 1, "invisible nodes are skipped")
    e(data.trees[1].talents[1].canPurchaseRank, true, "purchasability observed")
    e(data.trees[1].talents[1].unlocksNodeIDs[1], 12, "outgoing edge recorded")
    e(data.trees[1].talents[1].conditions[1].spentAmountRequired, 5, "points-in-tree gate recorded")
    e(data.unspentPoints, 1, "unspent points from the single talent currency")
    e(data.specialization.name, "Balance", "specialization observed")
    e(meta.completeness, "complete", "complete trait read")
    e(mutated, 0, "no trait function that changes talents was called")

    C_ClassTalents, C_Traits, C_Spell, GetSpecialization, GetSpecializationInfo = savedClassTalents, savedTraits, savedSpell, savedGetSpec, savedSpecInfo
    GetNumTalentTabs, GetTalentTabInfo, GetNumTalents, GetTalentInfo, UnitCharacterPoints = savedTabs, savedTab, savedNum, savedInfo, savedPoints
    LearnTalent = nil
    return passed
end
