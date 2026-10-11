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

local function positive(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then return false end
    return type(value) == "number" and value == value and value > 0 and value < math.huge
        and value % 1 == 0
end

local function nonnegative(value)
    return positive(value) or value == 0
end

local function publicString(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then return nil end
    return type(value) == "string" and value ~= "" and value or nil
end

local function safe(fn, ...)
    if type(fn) ~= "function" then return "API_MISSING" end
    local values = pack(pcall(fn, ...))
    if not values[1] then return "API_ERROR" end
    if values[2] == nil then return "NIL_RESULT" end
    return "OBSERVED_VALUE", unpackValues(values, 2, values.n)
end

local function denseIDs(value)
    if type(value) ~= "table" then return nil end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return nil end
        count = count + 1
    end
    local ids, seen = {}, {}
    for index = 1, count do
        local id = value[index]
        if not positive(id) or seen[id] then return nil end
        seen[id] = true
        ids[#ids + 1] = id
    end
    return ids
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

local function recipeRow(api, recipeID)
    local issues = {}
    local lineState, skillLineID, professionName, parentSkillLineID = safe(api.GetTradeSkillLineForRecipe, recipeID)
    if lineState ~= "OBSERVED_VALUE" or not positive(skillLineID) or not publicString(professionName) or not positive(parentSkillLineID) then
        return nil, "recipe profession association unavailable"
    end

    local knownState, learned = safe(C_SpellBook and C_SpellBook.IsSpellKnown, recipeID)
    if knownState ~= "OBSERVED_VALUE" or type(learned) ~= "boolean" then learned = nil end
    local infoState, recipeInfo = safe(api.GetRecipeInfo, recipeID)
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
                if type(equipLocation) == "string" and not (type(issecretvalue) == "function" and issecretvalue(equipLocation)) then itemInfo.equipLocation = equipLocation end
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
    if type(schematic) ~= "table" and infoName then row.name = infoName end
    if infoState == "OBSERVED_VALUE" and type(recipeInfo) == "table" then
        if nonnegative(recipeInfo.relativeDifficulty) then row.relativeDifficulty = recipeInfo.relativeDifficulty end
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
    if not S.professionRecipeOpen then return nil, { reason = "Open the character's Forever profession panel before /wowsync; no recipe panel is currently observed", retry = false, stale = true } end
    if type(api.IsTradeSkillLinked) ~= "function" then return nil, { reason = "Cannot verify that the open profession panel belongs to this character", retry = false, stale = true } end
    local linkedState, linked = safe(api.IsTradeSkillLinked)
    if linkedState ~= "OBSERVED_VALUE" or type(linked) ~= "boolean" or linked then
        return nil, { reason = "The profession panel is linked or its character source is unknown", retry = false, stale = true }
    end
    for _, name in ipairs({ "GetAllRecipeIDs", "GetTradeSkillLineForRecipe", "GetRecipeSchematic" }) do
        if type(api[name]) ~= "function" then return nil, { reason = "Forever recipe API unavailable: " .. name, retry = false, stale = true } end
    end
    local idsState, rawIDs = safe(api.GetAllRecipeIDs)
    local ids = idsState == "OBSERVED_VALUE" and denseIDs(rawIDs) or nil
    if not ids or #ids == 0 then
        return nil, { reason = "Forever recipe enumeration is empty or malformed; an uninitialized panel is not an empty known-recipe list", retry = true, stale = true }
    end
    local learnedByLine = learnedProfessions()
    if not learnedByLine then return nil, { reason = "Learned profession identity has not hydrated", retry = true, stale = true } end

    local rowsBySkillLine, incomplete = {}, false
    for _, recipeID in ipairs(ids) do
        local association, reason = recipeRow(api, recipeID)
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
            if association.recipe.learnedState == "UNKNOWN" or association.recipe.schematicState == "UNKNOWN" then incomplete = true end
        end
    end
    local professions = {}
    for _, row in pairs(rowsBySkillLine) do
        table.sort(row.recipes, function(a, b) return a.recipeID < b.recipeID end)
        -- This is the raw candidate count returned by GetAllRecipeIDs. Some
        -- candidates can remain unassociated and therefore have no recipe row.
        row.coverage.returnedRecipeCount = #ids
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
            returnedRecipeCount = #ids, learnedTrueCount = trueCount, learnedFalseCount = falseCount, unknownLearnedCount = unknownCount },
        professions = professions,
    }, { completeness = "partial",
        reason = incomplete and "Recipe identity was observed, but one or more learned/output/reagent API results are unavailable or incomplete" or "Profession-panel recipe enumeration is a candidate list, not an exhaustive recipe catalogue" }
end
