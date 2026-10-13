-- Forever 1.60.1 read-only talent observation.
-- This module is loaded only by GearExport-Forever.toc. It reads the legacy talent APIs when the
-- Forever client exposes them and records exactly what they return; it never spends or changes points.
local _, addon = ...
local S, F, C = addon.Sync, addon.Forever, WoWSyncCompat
if not S or not C or not C.IsForever or not C.IsForever() then return end

local MAX_TABS, MAX_TALENTS, MAX_TEXT = 10, 100, 256

local function public(value)
    return not (type(issecretvalue) == "function" and issecretvalue(value))
end
local function integer(value, minimum)
    return public(value) and type(value) == "number" and value == value and value ~= math.huge
        and value ~= -math.huge and value % 1 == 0 and value >= (minimum or 0)
end
local function clean(value)
    if not public(value) or type(value) ~= "string" or value == "" then return nil end
    return #value > MAX_TEXT and value:sub(1, MAX_TEXT) or value
end

-- Names only: which talent-related functions this client exposes. Nothing found here is called.
local MAX_PROBE = 60
local function talentApiInventory()
    local globals, namespaces = {}, {}
    for name, value in pairs(_G) do
        if #globals < MAX_PROBE and type(name) == "string" and type(value) == "function" and name:find("Talent") then globals[#globals + 1] = name end
        if type(name) == "string" and name:match("^C_") and type(value) == "table" and #namespaces < MAX_PROBE then
            for member, fn in pairs(value) do
                if #namespaces < MAX_PROBE and type(member) == "string" and type(fn) == "function"
                    and (member:find("Talent") or member:find("Trait") or name:find("Talent") or name:find("Trait") or name:find("Spec")) then
                    namespaces[#namespaces + 1] = name .. "." .. member
                end
            end
        end
    end
    table.sort(globals); table.sort(namespaces)
    return { globals = globals, namespaces = namespaces, truncated = (#globals >= MAX_PROBE or #namespaces >= MAX_PROBE) or nil }
end

-- Forever 1.60.1 exposes talents through the Retail trait system (C_ClassTalents + C_Traits), seen in
-- the API inventory on 2026-10-13. Only getters are called; nothing here purchases, refunds, commits,
-- loads or switches anything.
local MAX_NODES, MAX_TREES = 600, 12
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, ...)
    if ok and public(result) then return result end
    return nil
end
local function spellName(spellID)
    if not integer(spellID, 1) then return nil end
    local name = type(C_Spell) == "table" and clean(call(C_Spell.GetSpellName, spellID)) or nil
    if not name and type(GetSpellInfo) == "function" then
        local ok, legacy = pcall(GetSpellInfo, spellID)
        name = ok and clean(legacy) or nil
    end
    return name
end
local function number(value)
    return public(value) and type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function collectTraits()
    if type(C_ClassTalents) ~= "table" or type(C_Traits) ~= "table"
        or type(C_ClassTalents.GetActiveConfigID) ~= "function" or type(C_Traits.GetConfigInfo) ~= "function"
        or type(C_Traits.GetTreeNodes) ~= "function" or type(C_Traits.GetNodeInfo) ~= "function" then
        return nil
    end
    local configID = call(C_ClassTalents.GetActiveConfigID)
    if not integer(configID, 1) then
        return nil, { completeness = "unknown", reason = "No active talent configuration yet (talents may still be loading)", stale = true }
    end
    local config = call(C_Traits.GetConfigInfo, configID)
    local treeIDs = type(config) == "table" and type(config.treeIDs) == "table" and config.treeIDs or nil
    if not treeIDs or #treeIDs == 0 or #treeIDs > MAX_TREES then
        return nil, { completeness = "unknown", reason = "Talent configuration has no readable trees", stale = true }
    end
    local data = { formatVersion = 2, source = "C_ClassTalents/C_Traits", configID = configID, trees = {}, currencies = {} }
    local specIndex = call(GetSpecialization)
    if integer(specIndex, 1) and type(GetSpecializationInfo) == "function" then
        local ok, specID, specName = pcall(GetSpecializationInfo, specIndex)
        if ok and integer(specID, 1) then data.specialization = { index = specIndex, id = specID, name = clean(specName) } end
    end
    local partial, nodeCount, groups, order = false, 0, {}, {}
    for _, treeID in ipairs(treeIDs) do
        if integer(treeID, 1) then
            local currencies = call(C_Traits.GetTreeCurrencyInfo, configID, treeID, false)
            if type(currencies) == "table" then
                for _, currency in ipairs(currencies) do
                    if type(currency) == "table" then
                        local row = { treeID = treeID }
                        if integer(currency.traitCurrencyID, 0) then row.traitCurrencyID = currency.traitCurrencyID end
                        if integer(currency.quantity, 0) then row.quantity = currency.quantity end
                        if integer(currency.maxQuantity, 0) then row.maxQuantity = currency.maxQuantity end
                        if integer(currency.spent, 0) then row.spent = currency.spent end
                        data.currencies[#data.currencies + 1] = row
                    end
                end
            end
            local nodes = call(C_Traits.GetTreeNodes, treeID)
            if type(nodes) ~= "table" then
                partial = true
            else
                for _, nodeID in ipairs(nodes) do
                    nodeCount = nodeCount + 1
                    if nodeCount > MAX_NODES then partial = true; break end
                    local node = call(C_Traits.GetNodeInfo, configID, nodeID)
                    if type(node) ~= "table" then
                        partial = true
                    elseif node.isVisible ~= false then
                        local subTree = integer(node.subTreeID, 1) and node.subTreeID or nil
                        local key = subTree and ("sub:" .. subTree) or ("tree:" .. treeID)
                        local group = groups[key]
                        if not group then
                            local name
                            if subTree then
                                local info = call(C_Traits.GetSubTreeInfo, configID, subTree)
                                name = type(info) == "table" and clean(info.name) or nil
                            end
                            group = { treeID = treeID, subTreeID = subTree, name = name or ("Talent tree " .. treeID),
                                nameSource = name and "OBSERVED" or "DERIVED", pointsSpent = 0, talents = {}, evidence = "OBSERVED" }
                            groups[key] = group; order[#order + 1] = key
                        end
                        local entryID = type(node.activeEntry) == "table" and node.activeEntry.entryID
                            or (type(node.entryIDs) == "table" and node.entryIDs[1]) or nil
                        local name, spellID
                        if integer(entryID, 1) then
                            local entry = call(C_Traits.GetEntryInfo, configID, entryID)
                            local definitionID = type(entry) == "table" and entry.definitionID or nil
                            local definition = integer(definitionID, 1) and call(C_Traits.GetDefinitionInfo, definitionID) or nil
                            if type(definition) == "table" then
                                spellID = integer(definition.spellID, 1) and definition.spellID or nil
                                name = clean(definition.overrideName) or spellName(spellID)
                            end
                        end
                        local talent = { nodeID = integer(nodeID, 1) and nodeID or nil, name = name, spellID = spellID, evidence = "OBSERVED" }
                        if integer(node.currentRank, 0) then talent.currentRank = node.currentRank else partial = true end
                        if integer(node.maxRanks, 0) then talent.maxRank = node.maxRanks else partial = true end
                        if integer(node.ranksPurchased, 0) then talent.ranksPurchased = node.ranksPurchased end
                        if number(node.posX) then talent.posX = node.posX end
                        if number(node.posY) then talent.posY = node.posY end
                        -- Availability as the client reports it now; the requirement details come from conditions and edges.
                        if public(node.isAvailable) and type(node.isAvailable) == "boolean" then talent.isAvailable = node.isAvailable end
                        if public(node.canPurchaseRank) and type(node.canPurchaseRank) == "boolean" then talent.canPurchaseRank = node.canPurchaseRank end
                        if public(node.meetsEdgeRequirements) and type(node.meetsEdgeRequirements) == "boolean" then talent.meetsEdgeRequirements = node.meetsEdgeRequirements end
                        if type(node.visibleEdges) == "table" then
                            local unlocks = {}
                            for _, edge in ipairs(node.visibleEdges) do
                                if type(edge) == "table" and integer(edge.targetNode, 1) and #unlocks < 8 then unlocks[#unlocks + 1] = edge.targetNode end
                            end
                            if #unlocks > 0 then talent.unlocksNodeIDs = unlocks end
                        end
                        if type(node.conditionIDs) == "table" and type(C_Traits.GetConditionInfo) == "function" then
                            local conditions = {}
                            for _, conditionID in ipairs(node.conditionIDs) do
                                local condition = integer(conditionID, 1) and #conditions < 4 and call(C_Traits.GetConditionInfo, configID, conditionID) or nil
                                if type(condition) == "table" then
                                    local row = { conditionID = conditionID }
                                    for _, field in ipairs({ "isMet", "isGate", "isAlwaysMet", "isSufficient" }) do
                                        if public(condition[field]) and type(condition[field]) == "boolean" then row[field] = condition[field] end
                                    end
                                    for _, field in ipairs({ "spentAmountRequired", "traitCurrencyID", "playerLevel", "requiredLevel", "questID", "ranksGranted" }) do
                                        if integer(condition[field], 0) then row[field] = condition[field] end
                                    end
                                    conditions[#conditions + 1] = row
                                end
                            end
                            if #conditions > 0 then talent.conditions = conditions end
                        end
                        if not name then partial = true end
                        group.pointsSpent = group.pointsSpent + (talent.ranksPurchased or talent.currentRank or 0)
                        group.talents[#group.talents + 1] = talent
                    end
                end
            end
        end
    end
    for _, key in ipairs(order) do data.trees[#data.trees + 1] = groups[key] end
    -- Unspent points: the remaining quantity when exactly one talent currency is reported.
    if #data.currencies == 1 and data.currencies[1].quantity then data.unspentPoints = data.currencies[1].quantity end
    local hasUnspent = call(C_ClassTalents.HasUnspentTalentPoints)
    if type(hasUnspent) == "boolean" then data.hasUnspentTalentPoints = hasUnspent end
    local unspent = call(GetNumUnspentTalents)
    if integer(unspent, 0) then data.unspentTalentsGlobal = unspent; data.unspentPoints = data.unspentPoints or unspent end
    return data, { completeness = partial and "partial" or "complete", reason = partial and "One or more talent fields were unavailable" or nil }
end

S.collectors.talents = function()
    if not C.IsForever() then return nil, { completeness = "unknown", reason = "Forever talent collector is version isolated" } end
    if type(GetNumTalentTabs) ~= "function" or type(GetTalentTabInfo) ~= "function"
        or type(GetNumTalents) ~= "function" or type(GetTalentInfo) ~= "function" then
        local traits, traitMeta = collectTraits()
        if traits or traitMeta then
            if traits then
                traits.observedAt = S.Now()
                traits.clientProfile = "Forever:" .. tostring(F and F.runtimeVersion) .. ":" .. tostring(F and F.runtimeBuild) .. ":" .. tostring(F and F.runtimeInterface)
            end
            return traits, traitMeta
        end
        -- Record which talent API this client does expose, so the next collector reads the right one.
        local ok, inventory = pcall(talentApiInventory)
        return {
            formatVersion = 1, state = "LEGACY_API_UNAVAILABLE", observedAt = S.Now(),
            clientProfile = "Forever:" .. tostring(F and F.runtimeVersion) .. ":" .. tostring(F and F.runtimeBuild) .. ":" .. tostring(F and F.runtimeInterface),
            apiInventory = ok and inventory or nil, trees = {},
        }, { completeness = "unknown", reason = "Legacy talent APIs unavailable on this Forever client; API names inventoried" }
    end
    local ok, tabCount = pcall(GetNumTalentTabs)
    if not ok or not integer(tabCount, 0) or tabCount > MAX_TABS then
        return nil, { completeness = "unknown", reason = "Talent tree count unavailable or outside bound", stale = true }
    end
    local trees, partial, unspent = {}, false, nil
    for tab = 1, tabCount do
        local tabOK, name, _, pointsSpent = pcall(GetTalentTabInfo, tab)
        name = tabOK and clean(name) or nil
        if not name then
            partial = true
        else
            local tree = { tab = tab, name = name, talents = {}, evidence = "OBSERVED" }
            if integer(pointsSpent, 0) then tree.pointsSpent = pointsSpent else partial = true end
            local countOK, talentCount = pcall(GetNumTalents, tab)
            if not countOK or not integer(talentCount, 0) or talentCount > MAX_TALENTS then
                tree.talentCoverage = "UNKNOWN"; partial = true
            else
                tree.talentCoverage = "OBSERVED"
                for index = 1, talentCount do
                    local talentOK, talentName, _, tier, column, currentRank, maxRank = pcall(GetTalentInfo, tab, index)
                    talentName = talentOK and clean(talentName) or nil
                    if not talentName then
                        partial = true
                    else
                        local talent = { index = index, name = talentName, evidence = "OBSERVED" }
                        if integer(tier, 1) then talent.tier = tier end
                        if integer(column, 1) then talent.column = column end
                        if integer(currentRank, 0) then talent.currentRank = currentRank else partial = true end
                        if integer(maxRank, 0) then talent.maxRank = maxRank else partial = true end
                        tree.talents[#tree.talents + 1] = talent
                    end
                end
            end
            trees[#trees + 1] = tree
        end
    end
    if type(UnitCharacterPoints) == "function" then
        local pointsOK, points = pcall(UnitCharacterPoints, "player")
        if pointsOK and integer(points, 0) then unspent = points end
    end
    return {
        formatVersion = 1,
        clientProfile = "Forever:" .. tostring(F and F.runtimeVersion) .. ":" .. tostring(F and F.runtimeBuild) .. ":" .. tostring(F and F.runtimeInterface),
        source = "legacy talent APIs",
        observedAt = S.Now(),
        coverage = "VISIBLE_CLASS_TALENT_TREES",
        trees = trees,
        unspentPoints = unspent,
    }, { completeness = partial and "partial" or "complete", reason = partial and "One or more talent fields were unavailable" or nil }
end
