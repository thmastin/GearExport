-- Forever 1.60.1 profession recipe observation.
-- This is an explicit, read-only scan of the player's open profession panel.
-- It never opens UI, changes recipe filters, or crafts. GetAllRecipeIDs may
-- include unlearned candidates, so learned state is independently checked via
-- C_SpellBook.IsSpellKnown(recipe spell ID); unavailable/contradictory answers
-- remain UNKNOWN. The API surface is version scoped by the Forever TOC.
local _, addon = ...
local S, F = addon.Sync, addon.Forever
local unpackValues = unpack or table.unpack
local function pack(...) return { n = select("#", ...), ... } end
local MAX_OUTPUT_ITEM_SAMPLES, MAX_OUTPUT_LOAD_REQUESTS, MAX_REQUIREMENTS = 128, 32, 32
local MAX_RECIPE_REQUIREMENT_CALLS = 128

local function isPublic(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret ~= true
end

local function positive(value)
    if not isPublic(value) then return false end
    return type(value) == "number" and value == value and value > 0 and value < math.huge
        and value % 1 == 0
end

local function nonnegative(value)
    return isPublic(value) and type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge and value >= 0 and value % 1 == 0
end

local function publicString(value)
    if not isPublic(value) then return nil end
    return type(value) == "string" and value ~= "" and value or nil
end

local function observed(value)
    if value == nil then return { state = "NIL" } end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if not ok or secret then return { state = "RESTRICTED", type = type(value) } end
    end
    local kind = type(value)
    if kind == "string" or kind == "number" or kind == "boolean" then
        return { state = "OBSERVED", type = kind, value = value }
    end
    return { state = "UNSUPPORTED_VALUE_TYPE", type = kind }
end

local function rawCall(fn, ...)
    if type(fn) ~= "function" then return { state = "API_MISSING", provenance = "IN_GAME_RUNTIME_CALL" } end
    local values = pack(pcall(fn, ...))
    if not values[1] then
        local message = type(values[2]) == "string" and values[2] or ("error value type: " .. type(values[2]))
        return { state = "API_ERROR", error = message:gsub("[%c]", " "):sub(1, 180), provenance = "IN_GAME_RUNTIME_CALL" }
    end
    local returns, hasValue = {}, false
    for index = 2, values.n do
        if values[index] ~= nil then hasValue = true end
        local value = observed(values[index])
        returns[#returns + 1] = { index = index - 1, observation = value }
    end
    return { state = hasValue and "OBSERVED_VALUE" or values.n > 1 and "NIL_RESULT" or "ZERO_RETURNS",
        returnCount = values.n - 1, returns = returns, _rawReturns = values, provenance = "IN_GAME_RUNTIME_CALL" }
end

local function rawTable(value, maxRows)
    if value == nil then return { state = "NIL" } end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if not ok or secret then return { state = "RESTRICTED", type = type(value) } end
    end
    if type(value) ~= "table" then return { state = "UNSUPPORTED_VALUE_TYPE", type = type(value) } end
    local keys = {}
    local ok = pcall(function()
        for key in pairs(value) do
            if type(key) == "string" or type(key) == "number" then keys[#keys + 1] = key end
        end
    end)
    if not ok then return { state = "API_ERROR", type = "table" } end
    table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
    local entries = {}
    for index = 1, math.min(#keys, maxRows) do
        local key = keys[index]
        local readOK, item = pcall(function() return value[key] end)
        entries[#entries + 1] = { key = tostring(key), value = readOK and observed(item) or { state = "API_ERROR" } }
    end
    return { state = "OBSERVED_TABLE", entryCount = #keys, complete = #keys <= maxRows, entries = entries }
end

local function itemOutputEvidence(itemID, itemAPI)
    local now = S.Now()
    local minimalItem = "item:" .. tostring(itemID)
    local evidence = { itemID = itemID, observedAt = now, provenance = "IN_GAME_RUNTIME_CALL",
        itemReference = minimalItem, itemReferenceKind = "MINIMAL_ID_REFERENCE_NO_VARIANT",
        identityState = "OBSERVED_ITEM_ID_NO_INSTANCE_VARIANT" }
    evidence.itemInfoInstant = rawCall(itemAPI.GetItemInfoInstant, itemID)
    evidence.itemInfoInstant.api, evidence.itemInfoInstant.input = "C_Item.GetItemInfoInstant", { itemID = itemID }
    local instant = evidence.itemInfoInstant.returns or {}
    local fields = { "returnedItemID", "itemType", "itemSubType", "equipLocation", "icon", "classID", "subclassID" }
    for index, name in ipairs(fields) do
        local row = instant[index]
        evidence[name .. "Observation"] = row and row.observation or { state = "UNKNOWN" }
        if row and row.observation.state == "OBSERVED" then evidence[name] = row.observation.value end
    end
    if evidence.returnedItemID ~= nil and evidence.returnedItemID ~= itemID then evidence.identityState = "ITEM_ID_MISMATCH" end

    evidence.itemInfo = rawCall(itemAPI.GetItemInfo, itemID)
    evidence.itemInfo.api, evidence.itemInfo.input = "C_Item.GetItemInfo", { itemID = itemID }
    local info = evidence.itemInfo.returns or {}
    local infoFields = { "name", "apiReturnedItemLink", "quality", "itemLevel", "requiredLevel", "itemType", "itemSubType",
        "maxStackCount", "equipLocation", "icon", "sellPrice", "classID", "subclassID", "bindType" }
    for index, name in ipairs(infoFields) do
        local row = info[index]
        evidence[name .. "Observation"] = row and row.observation or { state = "UNKNOWN" }
        if row and row.observation.state == "OBSERVED" then evidence[name] = row.observation.value end
    end
    evidence.nameSource = evidence.name and "C_Item.GetItemInfo" or nil

    evidence.itemStats = rawCall(itemAPI.GetItemStats, minimalItem)
    evidence.itemStats.api, evidence.itemStats.input = "C_Item.GetItemStats",
        { itemID = itemID, itemReference = minimalItem, referenceKind = "MINIMAL_ID_REFERENCE_NO_VARIANT" }
    local statReturn = evidence.itemStats.returns and evidence.itemStats.returns[1]
    local statRaw = evidence.itemStats._rawReturns and evidence.itemStats._rawReturns[2]
    if evidence.itemStats.state == "API_MISSING" then evidence.itemStats.table = { state = "API_MISSING" }
    elseif evidence.itemStats.state == "API_ERROR" then evidence.itemStats.table = { state = "API_ERROR" }
    elseif statReturn and statReturn.observation.state == "NIL" then evidence.itemStats.table = { state = "NIL" }
    elseif statReturn and statReturn.observation.type == "table" then evidence.itemStats.table = rawTable(statRaw, MAX_OUTPUT_ITEM_SAMPLES)
    else evidence.itemStats.table = { state = evidence.itemStats.state == "ZERO_RETURNS" and "ZERO_RETURNS" or "UNKNOWN" } end

    evidence.isEquippableItem = rawCall(itemAPI.IsEquippableItem, itemID)
    evidence.isEquippableItem.api, evidence.isEquippableItem.input = "C_Item.IsEquippableItem", { itemID = itemID, scope = "CURRENT_PLAYER_API_RESULT" }
    local playerInfo = type(C_PlayerInfo) == "table" and C_PlayerInfo or {}
    evidence.canUseItem = rawCall(playerInfo.CanUseItem, itemID)
    evidence.canUseItem.api, evidence.canUseItem.input = "C_PlayerInfo.CanUseItem", { itemID = itemID, scope = "CURRENT_PLAYER_ONLY" }
    evidence.eligibilityInterpretation = "RAW_PLAYER_SCOPED_SIGNALS_ONLY_NOT_FULL_EQUIP_ELIGIBILITY"

    local infoName = info[1] and info[1].observation
    local statsAvailable = evidence.itemStats.table and evidence.itemStats.table.state == "OBSERVED_TABLE"
    if evidence.identityState == "ITEM_ID_MISMATCH" then
        evidence.cacheState = "API_ID_MISMATCH"
    elseif infoName and infoName.state == "OBSERVED" and statsAvailable then
        evidence.cacheState = "CACHED_METADATA_AND_STATS_RETURNED"
    else
        local prior = S.foreverRecipeItemLoadResults and S.foreverRecipeItemLoadResults[itemID]
        if prior then
            evidence.cacheState, evidence.loadResult = prior.state, S.Copy(prior)
            if prior.state == "LOAD_SUCCEEDED" then evidence.cacheState = "LOAD_SUCCEEDED_BUT_METADATA_OR_STATS_NIL" end
        else evidence.cacheState = "CACHE_STATE_UNKNOWN" end
        local requests = S.foreverRecipeItemRequests or {}
        S.foreverRecipeItemRequests = requests
        S.foreverRecipeItemRequestCount = S.foreverRecipeItemRequestCount or 0
        if not requests[itemID] and S.foreverRecipeItemRequestCount < MAX_OUTPUT_LOAD_REQUESTS
            and type(itemAPI.RequestLoadItemDataByID) == "function" then
            S.foreverRecipeItemRequestCount = S.foreverRecipeItemRequestCount + 1
            evidence.loadRequestResult = rawCall(itemAPI.RequestLoadItemDataByID, itemID)
            evidence.loadRequestResult.api = "C_Item.RequestLoadItemDataByID"
            evidence.loadRequestResult.input = { itemID = itemID }
            requests[itemID] = evidence.loadRequestResult.state == "API_ERROR" and "API_ERROR" or true
            local requestReturn = evidence.loadRequestResult.returns and evidence.loadRequestResult.returns[1]
            if evidence.loadRequestResult.state == "API_ERROR" then
                evidence.loadRequestState, evidence.cacheState = "API_ERROR", "CACHE_REQUEST_ERROR"
            elseif requestReturn and requestReturn.observation.state == "OBSERVED"
                and requestReturn.observation.type == "boolean" and requestReturn.observation.value == false then
                evidence.loadRequestState, evidence.cacheState = "API_RETURNED_FALSE", "CACHE_REQUEST_REJECTED"
            else
                evidence.loadRequestState, evidence.cacheState = "REQUEST_CALL_SUCCEEDED_AWAITING_EVENT", "CACHE_PENDING"
            end
        elseif requests[itemID] then
            evidence.loadRequestState = requests[itemID] == "API_ERROR" and "PREVIOUS_REQUEST_API_ERROR" or "ALREADY_REQUESTED_THIS_SESSION"
            if evidence.cacheState == "CACHE_STATE_UNKNOWN" then
                evidence.cacheState = requests[itemID] == "API_ERROR" and "CACHE_REQUEST_ERROR" or "CACHE_PENDING"
            end
        elseif type(itemAPI.RequestLoadItemDataByID) ~= "function" then
            evidence.loadRequestState = "API_MISSING"
            if evidence.cacheState == "CACHE_STATE_UNKNOWN" then evidence.cacheState = "CACHE_REQUEST_UNAVAILABLE" end
        else
            evidence.loadRequestState = "REQUEST_BOUND_REACHED"
            if evidence.cacheState == "CACHE_STATE_UNKNOWN" then evidence.cacheState = "CACHE_PENDING_UNREQUESTED" end
        end
    end
    evidence.itemInfoInstant._rawReturns, evidence.itemInfo._rawReturns = nil, nil
    evidence.itemStats._rawReturns, evidence.isEquippableItem._rawReturns = nil, nil
    evidence.canUseItem._rawReturns = nil
    if evidence.loadRequestResult then evidence.loadRequestResult._rawReturns = nil end
    return evidence
end

local function recipeRequirements(api, recipeID)
    local result = rawCall(api.GetRecipeRequirements, recipeID)
    result.api, result.input = "C_TradeSkillUI.GetRecipeRequirements", { recipeID = recipeID }
    result.observedAt = S.Now()
    if result.state ~= "OBSERVED_VALUE" then result._rawReturns = nil; return result end
    local raw = result._rawReturns and result._rawReturns[2]
    if raw == nil then result.state, result._rawReturns = "NIL_RESULT", nil; return result end
    if not isPublic(raw) or type(raw) ~= "table" then
        result.state, result._rawReturns = isPublic(raw) and "UNSUPPORTED_RETURN_SHAPE" or "RESTRICTED", nil
        return result
    end
    do
        local keys, requirements, partial = {}, {}, false
        local scanOK = pcall(function()
            for key in pairs(raw) do
                if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then error("invalid requirement key") end
                keys[#keys + 1] = key
            end
        end)
        if not scanOK then result.state, result._rawReturns = "MALFORMED_RETURN_SHAPE", nil; return result end
        for _, key in ipairs(keys) do
            if not isPublic(key) then result.state, result._rawReturns = "RESTRICTED", nil; return result end
        end
        table.sort(keys)
        if #keys > MAX_REQUIREMENTS then result.truncated = true end
        for index = 1, math.min(#keys, MAX_REQUIREMENTS) do
            local rowOK, row = pcall(function() return raw[keys[index]] end)
            if not rowOK or not isPublic(row) or type(row) ~= "table" then
                partial = true; requirements[index] = { state = not rowOK and "API_ERROR" or "MALFORMED_ROW" }
            else
                local fieldsOK, name, met, kind = pcall(function() return row.name, row.met, row.type end)
                local captured = { provenance = "C_TradeSkillUI.GetRecipeRequirements" }
                if not fieldsOK then
                    partial = true; captured.nameState, captured.metState, captured.typeState = "API_ERROR", "API_ERROR", "API_ERROR"
                    requirements[index] = captured
                else
                    local safeName = isPublic(name) and type(name) == "string" and publicString(name) or nil
                    if safeName then captured.name, captured.nameState = safeName, "OBSERVED"
                    else captured.nameState = "UNKNOWN"; partial = true end
                    if isPublic(met) and type(met) == "boolean" then captured.met, captured.metState = met, "OBSERVED"
                    else captured.metState = "UNKNOWN"; partial = true end
                    if isPublic(kind) and (type(kind) == "number" or type(kind) == "string") then captured.requirementType, captured.typeState = kind, "OBSERVED"
                    else captured.typeState = "UNKNOWN"; partial = true end
                    requirements[index] = captured
                end
            end
        end
        result.requirements = requirements
        result.state = (result.truncated or partial) and "PARTIAL" or "OBSERVED_TABLE"
        result.returnedCount = #keys
    end
    result._rawReturns = nil
    return result
end

local function safe(fn, ...)
    if type(fn) ~= "function" then return "API_MISSING" end
    local values = pack(pcall(fn, ...))
    if not values[1] then
        local message = type(values[2]) == "string" and values[2] or ("error value type: " .. type(values[2]))
        message = message:gsub("[%c]", " "):sub(1, 180)
        return "API_ERROR", nil, message
    end
    if values[2] == nil then return "NIL_RESULT" end
    return "OBSERVED_VALUE", unpackValues(values, 2, values.n)
end

local function numericRecipeIDs(value)
    if type(value) ~= "table" then return nil end
    local keyedIDs, seen, returnedCount, duplicateCount = {}, {}, 0, 0
    for key, id in pairs(value) do
        -- The version-matched API contract says this is a number array and
        -- its example iterates with pairs. Accept sparse positive-integer
        -- array keys, but never treat dictionary keys or boolean set values
        -- as recipe IDs. This handles holes without guessing a new shape.
        if not positive(key) or not positive(id) then return nil end
        returnedCount = returnedCount + 1
        if returnedCount > 10000 then return nil end
        if seen[id] then
            duplicateCount = duplicateCount + 1
        else
            seen[id] = true
            keyedIDs[#keyedIDs + 1] = { key = key, id = id }
        end
    end
    table.sort(keyedIDs, function(left, right) return left.key < right.key end)
    local ids = {}
    for _, pair in ipairs(keyedIDs) do ids[#ids + 1] = pair.id end
    return ids, returnedCount, duplicateCount
end

local function recipeEnumerationFailure(state, value, apiError)
    if state == "API_ERROR" then
        return "C_TradeSkillUI.GetAllRecipeIDs raised an API error: " .. (apiError or "error detail unavailable")
    end
    if state == "NIL_RESULT" then return "C_TradeSkillUI.GetAllRecipeIDs returned nil; recipe availability remains UNKNOWN" end
    if state ~= "OBSERVED_VALUE" then
        return "C_TradeSkillUI.GetAllRecipeIDs result was not observed (" .. tostring(state) .. ")"
    end
    if type(value) ~= "table" then
        return "C_TradeSkillUI.GetAllRecipeIDs returned " .. type(value) .. ", expected a recipe ID array"
    end

    local keyCount, numberKeys, otherKeyTypes = 0, 0, {}
    for key in pairs(value) do
        keyCount = keyCount + 1
        if type(key) == "number" then numberKeys = numberKeys + 1
        else otherKeyTypes[type(key)] = true end
    end
    if keyCount == 0 then
        return "C_TradeSkillUI.GetAllRecipeIDs returned an empty table (0 candidates); whether the panel is still hydrating is UNKNOWN"
    end
    local keyTypes = {}
    for keyType in pairs(otherKeyTypes) do keyTypes[#keyTypes + 1] = keyType end
    table.sort(keyTypes)
    return "C_TradeSkillUI.GetAllRecipeIDs returned a malformed array (keys=" .. keyCount .. ", numericKeys=" .. numberKeys
        .. (#keyTypes > 0 and ", otherKeyTypes=" .. table.concat(keyTypes, ",") or "") .. "); candidate completeness remains UNKNOWN"
end

local function learnedProfessions()
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return nil end
    local result = { pcall(GetProfessions) }
    if not result[1] then return nil end
    local bySkillLine = {}
    for position = 1, 5 do
        local index = result[position + 1]
        if index ~= nil then
            if not positive(index) then return nil end
            local info = { pcall(GetProfessionInfo, index) }
            if not info[1] then return nil end
            -- Forever's verified Skills panel tuple: name, texture, rank,
            -- maxRank, spells, offset, skillLineID.
            local name, rank, maxRank, skillLineID = publicString(info[2]), info[4], info[5], info[8]
            if not name or not nonnegative(rank) or not positive(maxRank) or rank > maxRank or not positive(skillLineID) then return nil end
            if bySkillLine[skillLineID] then return nil end
            bySkillLine[skillLineID] = { name = name, skill = rank, maxSkill = maxRank }
        end
    end
    return bySkillLine
end

local function captureReagents(schematic)
    local slots = schematic.reagentSlotSchematics
    if type(slots) ~= "table" then return nil end
    local count = 0
    for key in pairs(slots) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return nil end
        count = count + 1
    end
    local output = {}
    for index = 1, count do
        local slot = slots[index]
        if type(slot) ~= "table" or not nonnegative(slot.quantityRequired) or type(slot.reagents) ~= "table" then return nil end
        local required = slot.required
        if required ~= nil and type(required) ~= "boolean" then return nil end
        if slot.slotInfo ~= nil and type(slot.slotInfo) ~= "table" then return nil end
        local requiredSkillRank = type(slot.slotInfo) == "table" and slot.slotInfo.requiredSkillRank or nil
        if requiredSkillRank ~= nil and not nonnegative(requiredSkillRank) then return nil end
        local reagentCount = 0
        for key in pairs(slot.reagents) do
            if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return nil end
            reagentCount = reagentCount + 1
        end
        local choices = {}
        for choiceIndex = 1, reagentCount do
            local reagent = slot.reagents[choiceIndex]
            if type(reagent) ~= "table" then return nil end
            local itemID, currencyID = reagent.itemID, reagent.currencyID
            if itemID ~= nil and not positive(itemID) or currencyID ~= nil and not positive(currencyID)
                or itemID == nil and currencyID == nil then return nil end
            local choice = {}
            if itemID ~= nil then choice.itemID = itemID end
            if currencyID ~= nil then choice.currencyID = currencyID end
            choices[#choices + 1] = choice
        end
        if required ~= false and slot.quantityRequired > 0 and #choices == 0 then return nil end
        local captured = {
            slotIndex = index,
            quantityRequired = slot.quantityRequired,
        }
        if required ~= nil then captured.required = required end
        if requiredSkillRank ~= nil then captured.requiredSkillRank = requiredSkillRank end
        if nonnegative(slot.reagentType) then captured.reagentType = slot.reagentType end
        captured.reagents = choices
        output[#output + 1] = captured
    end
    return output
end

local function recipeRow(api, recipeID, outputEvidenceContext)
    local issues = {}
    local lineState, skillLineID, professionName, parentSkillLineID = safe(api.GetTradeSkillLineForRecipe, recipeID)
    if lineState ~= "OBSERVED_VALUE" or not positive(skillLineID) or not publicString(professionName) or not positive(parentSkillLineID) then
        return nil, "recipe profession association unavailable"
    end

    local knownState, learned = safe(C_SpellBook and C_SpellBook.IsSpellKnown, recipeID)
    if knownState ~= "OBSERVED_VALUE" or type(learned) ~= "boolean" then learned = nil end
    local infoState, recipeInfo = safe(api.GetRecipeInfo, recipeID)
    if type(recipeInfo) == "table" and recipeInfo.recipeID ~= nil
        and (not positive(recipeInfo.recipeID) or recipeInfo.recipeID ~= recipeID) then
        return nil, "recipe info identity mismatch"
    end
    local infoLearned = type(recipeInfo) == "table" and recipeInfo.learned or nil
    if type(infoLearned) ~= "boolean" then infoLearned = nil end
    if learned ~= nil and infoLearned ~= nil and learned ~= infoLearned then learned = nil end

    -- GetRecipeInfo is optional on some Forever builds. Preserve only fields
    -- whose exact primitive types are known; these API values are useful
    -- progression evidence, but maxTrivialLevel is not a minimum skill
    -- requirement and relativeDifficulty is not translated into a rank.
    local infoName = type(recipeInfo) == "table" and publicString(recipeInfo.name) or nil

    local schematicState, schematic = safe(api.GetRecipeSchematic, recipeID, false)
    local row = {
        recipeID = recipeID,
        learned = learned,
        learnedState = learned == true and "OBSERVED_TRUE" or learned == false and "OBSERVED_FALSE" or "UNKNOWN",
        recipeInfoResult = infoState,
        spellKnownResult = knownState,
        skillLineID = skillLineID,
        skillLineAssociationState = "OBSERVED",
        skillLineIDs = { skillLineID },
        schematicState = schematicState == "OBSERVED_VALUE" and "OBSERVED" or "UNKNOWN",
        evidence = "OBSERVED",
    }
    if type(schematic) == "table" then
        local schematicID = schematic.recipeID
        if schematicID ~= nil and schematicID ~= recipeID then return nil, "recipe schematic identity mismatch" end
        row.name = publicString(schematic.name) or infoName
        row.outputItemID = positive(schematic.outputItemID) and schematic.outputItemID or nil
        row.outputItemInfo = { state = "UNKNOWN", source = "C_Item.GetItemInfoInstant" }
        if row.outputItemID and type(C_Item) == "table" then
            local itemState, itemID, itemType, itemSubType, equipLocation, _, classID, subclassID = safe(C_Item.GetItemInfoInstant, row.outputItemID)
            if itemState == "OBSERVED_VALUE" and itemID == row.outputItemID then
                local itemInfo = { state = "OBSERVED", source = "C_Item.GetItemInfoInstant", itemID = itemID }
                if publicString(itemType) then itemInfo.itemType = itemType end
                if publicString(itemSubType) then itemInfo.itemSubType = itemSubType end
                if publicString(equipLocation) then itemInfo.equipLocation = equipLocation end
                if positive(classID) then itemInfo.classID = classID end
                if nonnegative(subclassID) then itemInfo.subclassID = subclassID end
                row.outputItemInfo = itemInfo
            end
        end
        if nonnegative(schematic.quantityMin) then row.outputQuantityMin = schematic.quantityMin end
        if nonnegative(schematic.quantityMax) then row.outputQuantityMax = schematic.quantityMax end
        if row.outputQuantityMin and row.outputQuantityMax and row.outputQuantityMin > row.outputQuantityMax then
            return nil, "recipe output quantities conflict"
        end
        local reagents = captureReagents(schematic)
        if reagents and row.name then row.reagentSlots = reagents else row.schematicState = "UNKNOWN" end
    end
    if row.learnedState == "OBSERVED_TRUE" then
        if outputEvidenceContext.requirementCallCount < MAX_RECIPE_REQUIREMENT_CALLS then
            outputEvidenceContext.requirementCallCount = outputEvidenceContext.requirementCallCount + 1
            row.requirements = recipeRequirements(api, recipeID)
        else
            row.requirements = { state = "NOT_SAMPLED_BOUND", api = "C_TradeSkillUI.GetRecipeRequirements",
                input = { recipeID = recipeID }, provenance = "UNKNOWN" }
        end
        if row.requirements.state ~= "OBSERVED_TABLE" and row.requirements.state ~= "PARTIAL" then
            issues[#issues + 1] = "Recipe requirements unavailable for recipe " .. recipeID
        end
        if row.outputItemID then
            local itemAPI = type(C_Item) == "table" and C_Item or {}
            local existing = outputEvidenceContext.byItemID[row.outputItemID]
            if existing then
                row.outputItemEvidence = S.Copy(existing)
                row.outputItemEvidence.sourceRecipeID = recipeID
                row.outputItemEvidenceState = "OBSERVED"
            elseif outputEvidenceContext.count < MAX_OUTPUT_ITEM_SAMPLES then
                local captured = itemOutputEvidence(row.outputItemID, itemAPI)
                outputEvidenceContext.byItemID[row.outputItemID] = captured
                outputEvidenceContext.count = outputEvidenceContext.count + 1
                row.outputItemEvidence = S.Copy(captured)
                row.outputItemEvidence.sourceRecipeID = recipeID
                row.outputItemEvidenceState = "OBSERVED"
            else
                row.outputItemEvidenceState = "NOT_SAMPLED_BOUND"
                issues[#issues + 1] = "Learned recipe output item evidence sample bound reached"
            end
        else
            row.outputItemEvidenceState = "UNKNOWN"
            issues[#issues + 1] = "Learned recipe output item ID unavailable for recipe " .. recipeID
        end
    end
    if type(schematic) ~= "table" and infoName then row.name = infoName end
    if infoState == "OBSERVED_VALUE" and type(recipeInfo) == "table" then
        if type(recipeInfo.relativeDifficulty) == "number" and recipeInfo.relativeDifficulty == math.floor(recipeInfo.relativeDifficulty)
            and recipeInfo.relativeDifficulty >= 0 and recipeInfo.relativeDifficulty <= 3 then
            row.relativeDifficulty = recipeInfo.relativeDifficulty
        end
        if nonnegative(recipeInfo.maxTrivialLevel) then row.maxTrivialLevel = recipeInfo.maxTrivialLevel end
        if nonnegative(recipeInfo.numSkillUps) then row.numSkillUps = recipeInfo.numSkillUps end
        if type(recipeInfo.canSkillUp) == "boolean" then row.canSkillUp = recipeInfo.canSkillUp end
        row.recipeProgressionInfoState = "OBSERVED"
    else
        row.recipeProgressionInfoState = "UNKNOWN"
    end
    return { baseSkillLineID = parentSkillLineID, skillLineID = skillLineID,
        parentProfessionID = parentSkillLineID, professionName = professionName, recipe = row }
end

S.collectors.professionRecipes = function()
    local api = type(C_TradeSkillUI) == "table" and C_TradeSkillUI or {}
    if S.professionRecipeMode == "CRAFT" then return nil, { reason = "Craft window APIs are not supported; recipe capture is UNKNOWN", retry = false, stale = true } end
    if not S.professionRecipeOpen then return nil, { reason = "Open the character's Forever profession panel before /wowsync; no recipe panel is currently observed", retry = false, stale = true } end
    if type(api.IsTradeSkillLinked) ~= "function" then return nil, { reason = "Cannot verify that the open profession panel belongs to this character", retry = false, stale = true } end
    local linkedState, linked = safe(api.IsTradeSkillLinked)
    if linkedState ~= "OBSERVED_VALUE" or type(linked) ~= "boolean" or linked then
        return nil, { reason = "The profession panel is linked or its character source is unknown", retry = false, stale = true }
    end
    for _, name in ipairs({ "GetAllRecipeIDs", "GetTradeSkillLineForRecipe", "GetRecipeSchematic" }) do
        if type(api[name]) ~= "function" then return nil, { reason = "Forever recipe API unavailable: " .. name, retry = false, stale = true } end
    end
    local idsState, rawIDs, enumerationError = safe(api.GetAllRecipeIDs)
    local ids, rawRecipeIDCount, duplicateRecipeIDCount
    if idsState == "OBSERVED_VALUE" then ids, rawRecipeIDCount, duplicateRecipeIDCount = numericRecipeIDs(rawIDs) end
    if not ids or #ids == 0 then
        return nil, { reason = recipeEnumerationFailure(idsState, rawIDs, enumerationError), retry = true, stale = true }
    end
    local learnedByLine = learnedProfessions()
    if not learnedByLine then return nil, { reason = "Learned profession identity has not hydrated", retry = true, stale = true } end

    local rowsBySkillLine, incomplete = {}, false
    local outputEvidenceContext = { byItemID = {}, count = 0, requirementCallCount = 0 }
    for _, recipeID in ipairs(ids) do
        local association, reason = recipeRow(api, recipeID, outputEvidenceContext)
        if not association then
            incomplete = true
        else
            local owner = learnedByLine[association.parentProfessionID]
            if not owner then
                return nil, { reason = "Open profession recipe list does not match a learned profession on this character", retry = false, stale = true }
            end
            if association.professionName ~= owner.name then
                return nil, { reason = "Profession API names disagree; recipe source remains UNKNOWN", retry = false, stale = true }
            end
            if rowsBySkillLine[association.skillLineID] then
                local row = rowsBySkillLine[association.skillLineID]
                if row.baseSkillLineID ~= association.baseSkillLineID or row.professionName ~= association.professionName then
                    return nil, { reason = "Mixed profession identities in one recipe panel", retry = false, stale = true }
                end
                row.recipes[#row.recipes + 1] = association.recipe
            else
                local owner = learnedByLine[association.parentProfessionID]
                rowsBySkillLine[association.skillLineID] = {
                    baseSkillLineID = association.baseSkillLineID,
                    skillLineID = association.skillLineID,
                    parentProfessionID = association.parentProfessionID,
                    professionName = association.professionName,
                    name = owner.name,
                    skill = owner.skill,
                    maxSkill = owner.maxSkill,
                    recipes = { association.recipe },
                    coverage = { state = "PARTIAL", enumeration = "OBSERVED", candidateCompleteness = "UNKNOWN",
                        filteredEnumerationUsed = false },
                }
            end
            if association.recipe.learnedState == "UNKNOWN" or association.recipe.schematicState == "UNKNOWN"
                or association.recipe.requirements and association.recipe.requirements.state ~= "OBSERVED_TABLE"
                    and association.recipe.requirements.state ~= "PARTIAL"
                or association.recipe.outputItemEvidenceState == "UNKNOWN"
                or association.recipe.outputItemEvidenceState == "NOT_SAMPLED_BOUND" then incomplete = true end
        end
    end
    local professions = {}
    for _, row in pairs(rowsBySkillLine) do
        table.sort(row.recipes, function(a, b) return a.recipeID < b.recipeID end)
        -- This is the raw candidate count returned by GetAllRecipeIDs. Some
        -- candidates can remain unassociated and therefore have no recipe row.
        row.coverage.returnedRecipeCount = rawRecipeIDCount
        row.coverage.uniqueCandidateCount = #ids
        row.coverage.duplicateRecipeIDCount = duplicateRecipeIDCount
        professions[#professions + 1] = row
    end
    table.sort(professions, function(a, b) return a.skillLineID < b.skillLineID end)
    if #professions ~= 1 then return nil, { reason = "Recipe panel did not resolve to exactly one profession", retry = false, stale = true } end
    local trueCount, falseCount, unknownCount = 0, 0, 0
    for _, recipe in ipairs(professions[1].recipes) do
        if recipe.learnedState == "OBSERVED_TRUE" then trueCount = trueCount + 1
        elseif recipe.learnedState == "OBSERVED_FALSE" then falseCount = falseCount + 1
        else unknownCount = unknownCount + 1 end
    end
    professions[1].coverage.learnedTrueCount = trueCount
    professions[1].coverage.learnedFalseCount = falseCount
    professions[1].coverage.unknownLearnedCount = unknownCount

    local now = S.Now()
    local buildIssues = {}
    local version = F.Read("Forever version", GetBuildInfo, 1, "string", buildIssues)
    local build = F.Read("Forever build", GetBuildInfo, 2, "string", buildIssues)
    local interface = F.Read("Forever interface", GetBuildInfo, 4, "number", buildIssues)
    local buildNumber = build and tonumber(build) or nil
    local interfaceNumber = interface and positive(interface) and interface or nil
    if not version or not buildNumber or not interfaceNumber then
        return nil, { reason = "Forever client version/build/interface identity is incomplete", retry = false, stale = true }
    end
    return {
        formatVersion = 1, observedAt = now, ownerScope = "CHARACTER",
        client = { clientFamily = "Forever", clientVersion = version, clientBuild = buildNumber, interface = interfaceNumber },
        coverage = { state = "PARTIAL", candidateCompleteness = "UNKNOWN", filteredEnumerationUsed = false,
            returnedRecipeCount = rawRecipeIDCount, uniqueCandidateCount = #ids,
            duplicateRecipeIDCount = duplicateRecipeIDCount,
            learnedTrueCount = trueCount, learnedFalseCount = falseCount, unknownLearnedCount = unknownCount },
        professions = professions,
    }, { completeness = "partial",
        reason = incomplete and "Recipe identity was observed, but one or more learned/output/reagent API results are unavailable or incomplete" or "Profession-panel recipe enumeration is a candidate list, not an exhaustive recipe catalogue" }
end
