-- Structured character progression domains. These observations are deliberately
-- separate from the compatibility text export and never invoke gameplay APIs.
local ADDON_NAME, addon = ...
local S, C = addon.Sync, WoWSyncCompat
if not S or not C or not C.IsRetail or not C.IsRetail() then return end
local unpackValues = unpack or table.unpack
if S.eventFrame and type(S.eventFrame.RegisterEvent) == "function" then
    for _, event in ipairs({ "TRAIT_CONFIG_UPDATED", "TRAIT_SUB_TREE_CHANGED", "TRAIT_TREE_CURRENCY_INFO_UPDATED",
        "SKILL_LINE_SPECS_RANKS_CHANGED", "SKILL_LINE_SPECS_UNLOCKED", "UPDATE_FACTION", "FACTION_STANDING_CHANGED",
        "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "MAJOR_FACTION_UNLOCKED" }) do
        pcall(S.eventFrame.RegisterEvent, S.eventFrame, event)
    end
end

local function validNumber(v, positive)
    if issecretvalue and issecretvalue(v) then return nil end
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge or positive and v <= 0 then return nil end
    return v
end
local function validString(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return type(v) == "string" and v ~= "" and v or nil
end
local function validBoolean(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return type(v) == "boolean" and v or type(v) == "boolean" and false or nil
end
local function safeCall(fn, ...)
    if type(fn) ~= "function" then return "API_MISSING" end
    local packed = { pcall(fn, ...) }
    if not packed[1] then return "API_ERROR", tostring(packed[2]) end
    if packed[2] == nil then return "NIL_RESULT" end
    return "OBSERVED_VALUE", unpackValues(packed, 2)
end
local function clientIdentity()
    local version, build, buildDate, interface
    if type(GetBuildInfo) == "function" then version, build, buildDate, interface = GetBuildInfo() end
    local buildNumber = type(build) == "string" and tonumber(build) or build
    return { clientFamily = "Retail", clientVersion = validString(version), clientBuild = validNumber(buildNumber), interface = validNumber(interface) }
end

S.collectors.combatSpecialization = function()
    local indexState, index = safeCall(GetSpecialization)
    if indexState ~= "OBSERVED_VALUE" then return nil, { reason = "Active specialization " .. indexState, retry = indexState == "NIL_RESULT" } end
    local infoState, specID, name, _, _, role = safeCall(GetSpecializationInfo, index)
    if infoState ~= "OBSERVED_VALUE" or not validNumber(specID, true) then
        return nil, { reason = "Specialization details " .. infoState, retry = infoState == "NIL_RESULT" }
    end
    local configState, configID = safeCall(C_ClassTalents and C_ClassTalents.GetActiveConfigID)
    local heroState, heroID = safeCall(C_ClassTalents and C_ClassTalents.GetActiveHeroTalentSpec)
    local hero = validNumber(heroID, true)
    local _, _, _, classID = safeCall(UnitClass, "player")
    local heroName
    if hero and C_Traits and type(C_Traits.GetSubTreeInfo) == "function" then
        local activeConfig = configState == "OBSERVED_VALUE" and validNumber(configID, true) or nil
        local _, detail = safeCall(C_Traits.GetSubTreeInfo, activeConfig, hero)
        if type(detail) == "table" then heroName = validString(detail.name) end
    end
    local data = { formatVersion = 1, observedAt = S.Now(), ownerScope = "CHARACTER", client = clientIdentity(),
        activeSpec = { evidence = "OBSERVED", index = validNumber(index), specID = validNumber(specID, true),
            classID = validNumber(classID, true), name = validString(name), role = validString(role) },
        talentConfig = { evidence = configState == "OBSERVED_VALUE" and validNumber(configID, true) and "OBSERVED" or "UNKNOWN",
            configID = configState == "OBSERVED_VALUE" and validNumber(configID, true) or nil, result = configState },
        heroTalent = { evidence = hero and "OBSERVED" or "UNKNOWN", subtreeID = hero, name = heroName, result = heroState } }
    local complete = data.activeSpec.specID ~= nil and data.activeSpec.classID ~= nil and data.talentConfig.configID ~= nil and hero ~= nil
    return data, { completeness = complete and "complete" or "partial",
        reason = not complete and "Some active talent identity APIs returned no value" or nil }
end

local function professionBaseRows()
    local result = {}
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return nil, "profession identity APIs missing" end
    local indices = { GetProfessions() }
    for pos = 1, 5 do
        local index = indices[pos]
        if index then
            local ok, name, _, rank, maxRank, _, _, lineID, _, _, tier = pcall(GetProfessionInfo, index)
            if not ok or not validNumber(lineID, true) then return nil, "profession identity API error or incomplete" end
            result[lineID] = { name = validString(name), genericSkillLineID = lineID, skill = validNumber(rank), maxSkill = validNumber(maxRank),
                tier = validNumber(tier), category = pos <= 2 and "PRIMARY" or "SECONDARY" }
        end
    end
    return result
end

local function treeNode(configID, nodeID)
    local result, err = safeCall(C_Traits and C_Traits.GetNodeInfo, configID, nodeID)
    if result ~= "OBSERVED_VALUE" or type(err) ~= "table" then return { nodeID = nodeID, evidence = result, error = err } end
    local entryIDs = {}
    for _, id in ipairs(type(err.entryIDsWithCommittedRanks) == "table" and err.entryIDsWithCommittedRanks or {}) do
        local n = validNumber(id, true); if n then entryIDs[#entryIDs + 1] = n end
    end
    return { nodeID = nodeID, evidence = "OBSERVED", ranksPurchased = validNumber(err.ranksPurchased), currentRank = validNumber(err.currentRank),
        activeRank = validNumber(err.activeRank), maxRanks = validNumber(err.maxRanks), committedEntryIDs = entryIDs,
        isAvailable = validBoolean(err.isAvailable), isVisible = validBoolean(err.isVisible) }
end

S.collectors.professionSpecializations = function()
    if not C_TradeSkillUI or type(C_TradeSkillUI.GetAllProfessionTradeSkillLines) ~= "function"
        or not C_ProfSpecs or type(C_ProfSpecs.GetConfigIDForSkillLine) ~= "function"
        or not C_Traits or type(C_Traits.GetConfigInfo) ~= "function" then
        return nil, { reason = "Profession specialization APIs unavailable" }
    end
    local bases, baseErr = professionBaseRows()
    if not bases then return nil, { reason = baseErr, retry = true } end
    local linesState, lines = safeCall(C_TradeSkillUI.GetAllProfessionTradeSkillLines)
    if linesState ~= "OBSERVED_VALUE" or type(lines) ~= "table" then return nil, { reason = "Trade skill lines " .. linesState, retry = true } end
    local data, incomplete = { formatVersion = 1, observedAt = S.Now(), ownerScope = "CHARACTER", client = clientIdentity(), professions = {} }, false
    for baseID, base in pairs(bases) do
        local profession = { baseSkillLineID = baseID, name = base.name, skill = base.skill, maxSkill = base.maxSkill, category = base.category, tiers = {} }
        local seenConfigs, seenCurrencies = {}, {}
        for _, lineID in ipairs(lines) do
            local metaState, meta = safeCall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, lineID)
            if metaState == "OBSERVED_VALUE" and type(meta) == "table" and validNumber(meta.parentProfessionID) == baseID then
                local cfgState, configID = safeCall(C_ProfSpecs.GetConfigIDForSkillLine, lineID)
                configID = cfgState == "OBSERVED_VALUE" and validNumber(configID, true) or nil
                if configID and not seenConfigs[configID] then
                    seenConfigs[configID] = true
                    local configState, config = safeCall(C_Traits.GetConfigInfo, configID)
                    if configState ~= "OBSERVED_VALUE" or type(config) ~= "table" then incomplete = true
                    else
                        local skillLineID = validNumber(lineID, true)
                        local tier = { skillLineID = skillLineID, parentProfessionID = baseID, professionID = validNumber(meta.professionID, true),
                            expansionName = validString(meta.expansionName), configID = configID, evidence = "OBSERVED", trees = {} }
                        local treeIDs, seenTrees = {}, {}
                        for _, id in ipairs(type(config.treeIDs) == "table" and config.treeIDs or {}) do
                            id = validNumber(id, true); if id and not seenTrees[id] then seenTrees[id] = true; treeIDs[#treeIDs + 1] = id end
                        end
                        if C_ProfSpecs.GetSpecTabIDsForSkillLine then
                            local tabState, tabs = safeCall(C_ProfSpecs.GetSpecTabIDsForSkillLine, lineID)
                            if tabState == "OBSERVED_VALUE" and type(tabs) == "table" then
                                for _, id in ipairs(tabs) do id = validNumber(id, true); if id and not seenTrees[id] then seenTrees[id] = true; treeIDs[#treeIDs + 1] = id end end
                            elseif tabState ~= "API_MISSING" then incomplete = true end
                        end
                        if #treeIDs == 0 then incomplete = true end
                        for _, treeID in ipairs(treeIDs) do
                            local tree = { treeID = treeID }
                            local tabState, tabValue = safeCall(C_ProfSpecs.GetStateForTab, treeID, configID)
                            tree.tabState = tabState == "OBSERVED_VALUE" and tabValue or nil
                            tree.tabStateEvidence = tabState
                            local currencyState, currencies = safeCall(C_Traits.GetTreeCurrencyInfo, configID, treeID, true)
                            if currencyState == "OBSERVED_VALUE" and type(currencies) == "table" then
                                for _, ccy in ipairs(currencies) do
                                    local id = type(ccy) == "table" and validNumber(ccy.traitCurrencyID or ccy.currencyID, true)
                                    if id and not seenCurrencies[id] then
                                        seenCurrencies[id] = true
                                        tier.currencies = tier.currencies or {}
                                        tier.currencies[#tier.currencies + 1] = { currencyID = id,
                                            quantity = validNumber(ccy.quantity), spent = validNumber(ccy.spent) }
                                    end
                                end
                            else incomplete = true; tree.currencyEvidence = currencyState end
                            local nodeState, nodeIDs = safeCall(C_Traits.GetTreeNodes, treeID)
                            if nodeState == "OBSERVED_VALUE" and type(nodeIDs) == "table" then
                                tree.nodes = {}
                                for _, nodeID in ipairs(nodeIDs) do
                                    nodeID = validNumber(nodeID, true)
                                    if nodeID then
                                        local node = treeNode(configID, nodeID); tree.nodes[#tree.nodes + 1] = node
                                        if node.evidence ~= "OBSERVED" then incomplete = true end
                                    end
                                end
                            else incomplete = true; tree.nodesEvidence = nodeState end
                            tier.trees[#tier.trees + 1] = tree
                        end
                        profession.tiers[#profession.tiers + 1] = tier
                    end
                elseif cfgState ~= "OBSERVED_VALUE" and cfgState ~= "API_MISSING" then incomplete = true end
            elseif metaState == "API_ERROR" then incomplete = true end
        end
        if #profession.tiers > 0 then
            profession.specializationState, profession.specializationEvidence = "OBSERVED", "queryable profession config and trees returned"
        else
            local supportState, hasSpecialization = safeCall(C_ProfSpecs.SkillLineHasSpecialization, baseID)
            if supportState == "OBSERVED_VALUE" and type(hasSpecialization) == "boolean" and not hasSpecialization then
                profession.specializationState, profession.specializationEvidence = "NOT_APPLICABLE", "client explicitly reports no specialization system for this profession"
            else
                profession.specializationState, profession.specializationEvidence = "UNKNOWN", supportState
                incomplete = true
            end
        end
        data.professions[#data.professions + 1] = profession
    end
    table.sort(data.professions, function(a,b) return a.baseSkillLineID < b.baseSkillLineID end)
    return data, { completeness = incomplete and "partial" or "complete", reason = incomplete and "One or more specialization trees/nodes/currencies were unavailable" or nil }
end

local function professionRecipeContext()
    local api = C_TradeSkillUI
    if not api or type(api.GetChildProfessionInfo) ~= "function" or type(api.GetBaseProfessionInfo) ~= "function" then
        return nil, "active profession context APIs unavailable"
    end
    local childState, child = safeCall(api.GetChildProfessionInfo)
    local baseState, base = safeCall(api.GetBaseProfessionInfo)
    if childState ~= "OBSERVED_VALUE" or type(child) ~= "table" or baseState ~= "OBSERVED_VALUE" or type(base) ~= "table" then
        return nil, "active profession context is not ready"
    end
    local skillLineID = validNumber(child.professionID, true)
    local baseSkillLineID = validNumber(base.professionID, true)
    local parentID = validNumber(child.parentProfessionID, true)
    if not skillLineID or not baseSkillLineID or not parentID or parentID ~= baseSkillLineID then
        return nil, "active profession identity is ambiguous"
    end
    return {
        baseSkillLineID = baseSkillLineID,
        baseProfessionName = validString(base.professionName),
        parentProfessionID = parentID,
        skillLineID = skillLineID,
        professionID = skillLineID,
        professionName = validString(child.professionName),
        expansionName = validString(child.expansionName),
        skill = validNumber(child.skillLevel),
        maxSkill = validNumber(child.maxSkillLevel),
    }
end

local function recipeBoolean(value)
    if issecretvalue and issecretvalue(value) then return nil end
    if type(value) == "boolean" then return value end
    return nil
end

S.collectors.professionRecipes = function()
    local api = C_TradeSkillUI
    if not api or type(api.GetAllRecipeIDs) ~= "function" or type(api.GetRecipeInfo) ~= "function" then
        return nil, { reason = "Profession recipe APIs unavailable", retry = false }
    end
    local context, contextError = professionRecipeContext()
    if not context then return nil, { reason = contextError, retry = true, stale = true } end

    -- GetAllRecipeIDs is only meaningful for the currently initialized context.
    -- A cold empty result is unavailable coverage, never an observed zero.
    local idsState, ids = safeCall(api.GetAllRecipeIDs)
    if idsState ~= "OBSERVED_VALUE" or type(ids) ~= "table" then
        return nil, { reason = "Recipe enumeration " .. idsState, retry = idsState == "NIL_RESULT", stale = true }
    end
    local recipeIDs, seen = {}, {}
    for _, rawID in ipairs(ids) do
        local id = validNumber(rawID, true)
        if id and not seen[id] then seen[id] = true; recipeIDs[#recipeIDs + 1] = id end
    end
    table.sort(recipeIDs)
    if #recipeIDs == 0 then
        return nil, { reason = "Recipe enumeration empty; profession context not established", retry = true, stale = true }
    end

    local observedAt = S.Now()
    local recipes, unknown, learnedTrue, learnedFalse = {}, 0, 0, 0
    for _, recipeID in ipairs(recipeIDs) do
        local infoState, info = safeCall(api.GetRecipeInfo, recipeID)
        local learned
        if type(info) == "table" then learned = recipeBoolean(info.learned) end
        local learnedState = learned == true and "OBSERVED_TRUE" or learned == false and "OBSERVED_FALSE" or "UNKNOWN"
        if learnedState == "UNKNOWN" then unknown = unknown + 1 end
        if learnedState == "OBSERVED_TRUE" then learnedTrue = learnedTrue + 1 end
        if learnedState == "OBSERVED_FALSE" then learnedFalse = learnedFalse + 1 end
        local associationState, associated = safeCall(api.IsRecipeInSkillLine, recipeID, context.skillLineID)
        local skillLineIDs = {}
        if associationState == "OBSERVED_VALUE" and type(associated) == "boolean" and associated then
            skillLineIDs[1] = context.skillLineID
        end
        recipes[#recipes + 1] = {
            recipeID = recipeID,
            learned = learned,
            learnedState = learnedState,
            recipeInfoResult = infoState,
            skillLineIDs = skillLineIDs,
            skillLineAssociationState = associationState == "OBSERVED_VALUE" and type(associated) == "boolean" and "OBSERVED" or "UNKNOWN",
            skillLineAssociationResult = associationState,
        }
    end
    context.observedAt = observedAt
    context.sessionObservedAt = S.sessionStartedAt
    context.client = clientIdentity()
    context.evidence = "OBSERVED"
    context.recipes = recipes
    local coverage = { state = "PARTIAL", enumeration = "OBSERVED", candidateCompleteness = "UNKNOWN",
        returnedRecipeCount = #recipeIDs, learnedTrueCount = learnedTrue, learnedFalseCount = learnedFalse,
        explicitLearnedCount = #recipeIDs - unknown, unknownLearnedCount = unknown,
        filteredEnumerationUsed = false }
    context.coverage = S.Copy(coverage)
    local data = {
        formatVersion = 1,
        ownerScope = "CHARACTER",
        observedAt = observedAt,
        client = clientIdentity(),
        enumerationSource = "C_TradeSkillUI.GetAllRecipeIDs",
        coverage = coverage,
        professions = { context },
    }
    return data, { completeness = "partial", reason = "Observed initialized profession recipe state; global candidate catalogue completeness is unknown" }
end

local function factionRecord(id)
    local result, row = safeCall(C_Reputation and C_Reputation.GetFactionDataByID, id)
    if result ~= "OBSERVED_VALUE" or type(row) ~= "table" then return result end
    local fields = { "factionID", "parentFactionID", "name", "description", "reaction", "currentStanding", "currentReactionThreshold", "nextReactionThreshold",
        "atWarWith" , "canToggleAtWar", "isHeader", "isHeaderExpanded", "isChild", "isCollapsed", "isAccountWide", "isMajorFaction", "hasBonusRepGain", "canSetInactive" }
    local out = { evidence = "OBSERVED" }
    for _, k in ipairs(fields) do
        local v = row[k]
        if type(v) == "number" and validNumber(v) ~= nil or type(v) == "boolean" or type(v) == "string" and validString(v) then out[k] = v end
    end
    local scopeState, accountWide = safeCall(C_Reputation.IsAccountWideReputation, id)
    out.scopeEvidence = scopeState
    if scopeState == "OBSERVED_VALUE" and type(accountWide) == "boolean" then out.ownerScope = accountWide and "ACCOUNT_WARBAND" or "CHARACTER" end
    return "OBSERVED_VALUE", out
end

S.collectors.reputation = function()
    local api = C_Reputation
    if not api or type(api.GetFactionDataByID) ~= "function" then return nil, { reason = "Direct faction lookup API unavailable" } end
    local data = { formatVersion = 1, observedAt = S.Now(), ownerScope = "CHARACTER", client = clientIdentity(),
        coverage = { completeness = "partial", source = "bounded-direct-id-scan", rangeMin = 1, rangeMax = 4000,
            globalCatalogueVerified = false, candidatesQueried = 4000, recordsReturned = 0, nilLookups = 0, lookupFailures = 0 },
        factions = {}, majorFactions = {} }
    for id = 1, 4000 do
        local result, row = factionRecord(id)
        if result == "OBSERVED_VALUE" then data.coverage.recordsReturned = data.coverage.recordsReturned + 1; data.factions[#data.factions + 1] = row
        elseif result == "NIL_RESULT" then data.coverage.nilLookups = data.coverage.nilLookups + 1
        elseif result == "API_ERROR" or result == "API_MISSING" then data.coverage.lookupFailures = data.coverage.lookupFailures + 1 end
    end
    local majorsState, majorIDs = safeCall(C_MajorFactions and C_MajorFactions.GetMajorFactionIDs)
    if majorsState ~= "OBSERVED_VALUE" or type(majorIDs) ~= "table" then return data, { completeness = "partial", reason = "Major Faction enumeration " .. majorsState } end
    data.coverage.majorFactionEnumeration = "observed"
    for _, id in ipairs(majorIDs) do
        id = validNumber(id, true)
        if id then
            local result, major = safeCall(C_MajorFactions.GetMajorFactionData, id)
            local renownState, renown = safeCall(C_MajorFactions.GetMajorFactionRenownInfo, id)
            if result == "OBSERVED_VALUE" and type(major) == "table" then
                local entry = { majorFactionID = id, evidence = "OBSERVED", conventionalFactionID = validNumber(major.factionID, true),
                    expansionID = validNumber(major.expansionID), name = validString(major.name), isUnlocked = validBoolean(major.isUnlocked),
                    ownerScope = "UNKNOWN", maxLevel = validNumber(major.maxLevel), renownEvidence = renownState }
                for _, faction in ipairs(data.factions) do
                    if entry.conventionalFactionID and faction.factionID == entry.conventionalFactionID and faction.ownerScope then
                        entry.ownerScope = faction.ownerScope; break
                    end
                end
                if renownState == "OBSERVED_VALUE" and type(renown) == "table" then
                    entry.renown = { level = validNumber(renown.renownLevel), threshold = validNumber(renown.renownLevelThreshold),
                        earned = validNumber(renown.renownReputationEarned), evidence = "OBSERVED" }
                end
                data.majorFactions[#data.majorFactions + 1] = entry
            end
        end
    end
    for _, row in ipairs(data.factions) do
        local id = validNumber(row.factionID, true)
        if id then
            if C_GossipInfo and type(C_GossipInfo.GetFriendshipReputation) == "function" then
                local fState, friendship = safeCall(C_GossipInfo.GetFriendshipReputation, id)
                if fState == "OBSERVED_VALUE" and type(friendship) == "table" and validNumber(friendship.friendshipFactionID, true) then
                    row.friendshipState = "OBSERVED"; row.friendship = { evidence = "OBSERVED", data = friendship }
                elseif fState == "OBSERVED_VALUE" and type(friendship) == "table" and friendship.friendshipFactionID == 0 then
                    row.friendshipState = "NO_SUBSTANTIVE_RECORD"
                else row.friendshipState = "UNKNOWN"; row.friendshipResult = fState end
            else row.friendshipState = "UNKNOWN"; row.friendshipResult = "API_MISSING" end
            if api.IsFactionParagon then
                local pState, isParagon = safeCall(api.IsFactionParagon, id)
                if pState == "OBSERVED_VALUE" and type(isParagon) == "boolean" then row.paragonState = isParagon and "OBSERVED_TRUE" or "OBSERVED_FALSE"
                else row.paragonState = "UNKNOWN"; row.paragonPredicateResult = pState end
                if row.paragonState == "OBSERVED_TRUE" and api.GetFactionParagonInfo then
                    local dState, current, threshold, questID, pending, tooLow, stored = safeCall(api.GetFactionParagonInfo, id)
                    if dState == "OBSERVED_VALUE" then row.paragon = { evidence = "OBSERVED", current = validNumber(current), threshold = validNumber(threshold), rewardQuestID = validNumber(questID), pendingReward = validBoolean(pending), tooLowLevel = validBoolean(tooLow), stored = validNumber(stored) }
                    else row.paragonEvidence = dState end
                end
            else row.paragonState = "UNKNOWN"; row.paragonPredicateResult = "API_MISSING" end
        end
    end
    return data, { completeness = "partial",
        reason = "Bounded range is not a verified global catalogue; overall Retail coverage remains partial" }
end
