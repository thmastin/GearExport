-- Read-only legacy profession-list observer for Classic Era and TBC.
-- The collector never opens, expands, filters, or crafts from a profession UI.
local _, addon = ...
local S, C = addon.Sync, WoWSyncCompat
if not S or not C or C.IsRetail() or (C.IsForever and C.IsForever()) then return end

local MAX_ROWS, MAX_RECIPES, MAX_REAGENTS = 500, 400, 32

local function integer(value, minimum)
    return type(value) == "number" and value == value and value ~= math.huge
        and value ~= -math.huge and value % 1 == 0 and value >= (minimum or 0)
end

local function itemPayload(link)
    if type(link) ~= "string" or #link > 512 then return nil end
    -- Keep the complete client-provided payload opaque. Parse only the base ID
    -- needed to validate identity; do not normalize away suffixes or variants.
    local payload = link:match("^|c%x%x%x%x%x%x%x%x|H(item:[^|]+)|h%[[^%]]*%]|h|r$")
        or link:match("^|H(item:[^|]+)|h%[[^%]]*%]|h$")
    if not payload then return nil end
    local id = tonumber(payload:match("^item:(%d+):") or payload:match("^item:(%d+)$"))
    if not integer(id, 1) then return nil end
    return payload, id
end

local function enchantPayload(link)
    if type(link) ~= "string" or #link > 512 then return nil end
    local id = link:match("^|c%x%x%x%x%x%x%x%x|Henchant:(%d+)|h%[[^%]]*%]|h|r$")
        or link:match("^|Henchant:(%d+)|h%[[^%]]*%]|h$")
    id = tonumber(id)
    if not integer(id, 1) then return nil end
    return "enchant:" .. tostring(id), id
end

local function profile()
    if type(GetBuildInfo) ~= "function" then return nil end
    local ok, _, _, _, interface = pcall(GetBuildInfo)
    if not ok then return nil end
    if not integer(interface, 1) then return nil end
    return "Classic:" .. tostring(WOW_PROJECT_ID or "project-unknown") .. ":" .. tostring(interface)
end

local function linkedTradeSkill()
    if type(IsTradeSkillLinked) ~= "function" then return nil, "Trade-skill ownership API unavailable" end
    local ok, linked = pcall(IsTradeSkillLinked)
    if not ok then return nil, "Trade-skill ownership is unknown" end
    -- Legacy Era/TBC returns 1 for linked lists and nil for the local player's
    -- own list; boolean values are accepted for compatible client variants.
    if linked == 1 or linked == true then return nil, "Linked trade-skill list is not this character's learned list" end
    if linked ~= nil and linked ~= false then return nil, "Trade-skill ownership is unknown" end
    if type(GetTradeSkillLine) ~= "function" or type(GetNumTradeSkills) ~= "function"
        or type(GetTradeSkillInfo) ~= "function" or type(GetTradeSkillItemLink) ~= "function" then
        return nil, "Legacy trade-skill APIs unavailable"
    end
    local okLine, name, rank, maxRank = pcall(GetTradeSkillLine)
    if not okLine or type(name) ~= "string" or name == "" or name == "UNKNOWN"
        or not integer(rank, 0) or not integer(maxRank, 0) then
        return nil, "Open trade-skill identity or skill values unavailable"
    end
    local okCount, count = pcall(GetNumTradeSkills)
    if not okCount or not integer(count, 0) then return nil, "Trade-skill row count unavailable" end
    return { name = name, rank = rank, maxRank = maxRank, count = count }
end

local function readReagents(index, recipe, issues)
    if type(GetTradeSkillNumReagents) ~= "function" then
        recipe.reagentState = "UNKNOWN"
        issues[#issues + 1] = "reagent list API unavailable"
        return
    end
    local ok, count = pcall(GetTradeSkillNumReagents, index)
    if not ok or not integer(count, 0) then
        recipe.reagentState = "UNKNOWN"
        issues[#issues + 1] = "reagent count unavailable"
        return
    end
    if count > MAX_REAGENTS then
        recipe.reagentState = "PARTIAL"
        issues[#issues + 1] = "reagent bound reached"
    else recipe.reagentState = "OBSERVED" end
    recipe.reagents = {}
    for reagentIndex = 1, math.min(count, MAX_REAGENTS) do
        local row = { index = reagentIndex }
        if type(GetTradeSkillReagentInfo) == "function" then
            local infoOK, name, _, required, carried = pcall(GetTradeSkillReagentInfo, index, reagentIndex)
            if infoOK and type(name) == "string" and name ~= "" then row.name = name end
            if infoOK and integer(required, 0) then row.required = required end
            if infoOK and integer(carried, 0) then
                row.carriedByClient = carried
                row.carriedEvidence = "OBSERVED"
                row.carriedScope = "CURRENT_CHARACTER_BAGS_AS_REPORTED_BY_CLIENT"
            end
        end
        if type(GetTradeSkillReagentItemLink) == "function" then
            local linkOK, link = pcall(GetTradeSkillReagentItemLink, index, reagentIndex)
            if linkOK and type(link) == "string" then
                local payload, itemID = itemPayload(link)
                if payload then row.itemID, row.itemString, row.itemLink = itemID, payload, link end
            end
        end
        if not row.itemID or row.required == nil then
            recipe.reagentState = "PARTIAL"
            issues[#issues + 1] = "reagent identity or required quantity unavailable"
        end
        recipe.reagents[#recipe.reagents + 1] = row
    end
end

local function collectTradeSkill()
    local line, reason = linkedTradeSkill()
    if not line then return nil, reason end
    if line.count > MAX_ROWS then return nil, "Trade-skill row limit exceeded" end
    local profileID = profile()
    if not profileID then return nil, "Classic client profile unavailable" end
    local profession = {
        name = line.name, rank = line.rank, maxRank = line.maxRank,
        professionKey = profileID .. ":profession:" .. line.name,
        recipes = {}, rowCount = line.count,
        coverage = "Visible rows from the player-owned legacy trade-skill window; current filters and collapsed categories may omit learned recipes",
    }
    local issues, keyCounts, pending = {}, {}, {}
    for index = 1, line.count do
        local ok, name, kind, available = pcall(GetTradeSkillInfo, index)
        if not ok or type(name) ~= "string" then
            issues[#issues + 1] = "trade-skill row " .. index .. " unavailable"
        elseif name ~= "" and kind ~= "header" and kind ~= "subheader" then
            local recipe = { name = name, observedRow = index, learnedState = "OBSERVED_TRUE",
                evidence = "OBSERVED", sourceAPI = "GetTradeSkillInfo" }
            if type(kind) == "string" then recipe.difficulty = kind end
            if integer(available, 0) then
                recipe.currentlyCraftableCount = available
                recipe.currentlyCraftableEvidence = "OBSERVED"
                recipe.currentlyCraftableScope = "CLIENT_REPORT_FOR_CURRENT_BAGS_AND_UI_STATE"
            end
            local itemOK, outputLink = pcall(GetTradeSkillItemLink, index)
            if itemOK and type(outputLink) == "string" then
                local payload, itemID = itemPayload(outputLink)
                if payload then
                    recipe.outputItemID, recipe.outputItemString, recipe.outputItemLink = itemID, payload, outputLink
                    local key = profession.professionKey .. ":recipe:" .. name .. ":" .. payload
                    keyCounts[key] = (keyCounts[key] or 0) + 1
                    recipe._candidateKey = key
                else
                    recipe.outputItemState = "UNKNOWN"
                    issues[#issues + 1] = "output link did not contain a valid exact item payload"
                end
            else
                recipe.outputItemState = "UNKNOWN"
                issues[#issues + 1] = "output item link unavailable"
            end
            readReagents(index, recipe, issues)
            if type(GetTradeSkillNumMade) == "function" then
                local madeOK, minimum, maximum = pcall(GetTradeSkillNumMade, index)
                if madeOK and integer(minimum, 1) and integer(maximum, minimum) then
                    recipe.outputQuantity = { minimum = minimum, maximum = maximum, evidence = "OBSERVED" }
                end
            end
            if type(GetTradeSkillRecipeLink) == "function" then
                local recipeOK, link = pcall(GetTradeSkillRecipeLink, index)
                if recipeOK and type(link) == "string" and #link <= 512 then recipe.recipeLink = link end
            end
            if #profession.recipes < MAX_RECIPES then
                profession.recipes[#profession.recipes + 1] = recipe
            else issues[#issues + 1] = "recipe result limit reached" end
        end
    end
    -- Only output-link/name pairs unique in this observed list are safe keys for
    -- cross-refresh history. Duplicate products remain OBSERVED this capture,
    -- but are not falsely merged as a single recipe identity.
    for _, recipe in ipairs(profession.recipes) do
        local key = recipe._candidateKey
        recipe._candidateKey = nil
        if key and keyCounts[key] == 1 then recipe.recipeKey = key
        else
            recipe.identityState = "UNKNOWN"
            if key then issues[#issues + 1] = "duplicate output/name prevents stable recipe identity" end
        end
    end
    table.sort(profession.recipes, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return (a.outputItemID or 0) < (b.outputItemID or 0)
    end)
    if #profession.recipes == 0 then return nil, "No recipe rows could be established from the currently open profession window" end
    local observedAt = S.Now()
    profession.observedAt = observedAt
    profession.source = "legacy trade-skill list API"
    profession.clientProfile = profileID
    return {
        formatVersion = 1, clientProfile = profileID, source = "GetTradeSkillInfo/GetTradeSkillItemLink",
        observedAt = observedAt, coverage = "PARTIAL_VISIBLE_LIST", professions = { profession },
        issues = issues,
    }, { completeness = "partial", source = "client", reason = "The open list reflects current filters and expanded categories; it does not prove the full learned-recipe catalogue" }
end

-- The older Craft UI is a separate API surface (notably used by enchanting).
-- Visible rows do not by themselves prove that a recipe is learned, so these
-- records retain UNKNOWN learned state even when item/reagent details are read.
local function collectCraft()
    if type(GetCraftDisplaySkillLine) ~= "function" or type(GetNumCrafts) ~= "function"
        or type(GetCraftInfo) ~= "function" or type(GetCraftItemLink) ~= "function" then
        return nil, "Legacy Craft APIs unavailable"
    end
    local lineOK, name, rank, maxRank = pcall(GetCraftDisplaySkillLine)
    if not lineOK or type(name) ~= "string" or name == "" or not integer(rank, 0) or not integer(maxRank, 0) then
        return nil, "Craft window profession identity unavailable"
    end
    local countOK, count = pcall(GetNumCrafts)
    if not countOK or not integer(count, 0) or count > MAX_ROWS then return nil, "Craft row count unavailable or outside bound" end
    local profileID = profile()
    if not profileID then return nil, "Classic client profile unavailable" end
    local profession = { name = name, rank = rank, maxRank = maxRank,
        professionKey = profileID .. ":craft-profession:" .. name,
        sourceAPI = "GetCraftInfo", rowCount = count, recipes = {},
        coverage = "Visible rows from the legacy Craft window; learned state is not exposed and coverage may be trainer/UI-limited" }
    local issues, keyCounts = {}, {}
    for index = 1, count do
        local ok, craftName, subName, kind, available, _, trainingPointCost, requiredLevel = pcall(GetCraftInfo, index)
        if not ok or type(craftName) ~= "string" then
            issues[#issues + 1] = "craft row " .. index .. " unavailable"
        elseif craftName ~= "" and kind ~= "header" then
            local recipe = { name = craftName, observedRow = index, evidence = "OBSERVED",
                learnedState = "UNKNOWN", learnedReason = "Legacy Craft API does not establish recipe learned state",
                rowSource = "GetCraftInfo", craftType = kind }
            if type(subName) == "string" and subName ~= "" then recipe.subName = subName end
            if integer(available, 0) then
                recipe.clientAvailableCount = available
                recipe.clientAvailableEvidence = "OBSERVED"
                recipe.clientAvailableScope = "CLIENT_REPORT_FOR_CURRENT_CRAFT_WINDOW_CONTEXT"
            end
            if integer(trainingPointCost, 0) then recipe.trainerPointCost = trainingPointCost end
            if integer(requiredLevel, 0) then recipe.trainerRequiredLevel = requiredLevel end
            local itemOK, outputLink = pcall(GetCraftItemLink, index)
            if itemOK and type(outputLink) == "string" then
                local payload, itemID = itemPayload(outputLink)
                if payload then
                    recipe.outputKind = "ITEM"
                    recipe.outputItemID, recipe.outputItemString, recipe.outputItemLink = itemID, payload, outputLink
                    local key = profession.professionKey .. ":recipe:" .. craftName .. ":" .. payload
                    keyCounts[key] = (keyCounts[key] or 0) + 1
                    recipe._candidateKey = key
                else
                    local enchantString, enchantID = enchantPayload(outputLink)
                    if enchantString then
                        -- Enchanting Craft links identify an enchant, not a
                        -- physical output item. Keep the typed identity opaque.
                        recipe.outputKind = "ENCHANTMENT"
                        recipe.enchantID, recipe.enchantString = enchantID, enchantString
                        recipe.craftLink = outputLink
                        local key = profession.professionKey .. ":enchant:" .. enchantString
                        keyCounts[key] = (keyCounts[key] or 0) + 1
                        recipe._candidateKey = key
                    else
                        recipe.outputItemState = "UNKNOWN"
                        recipe.craftLinkState = "UNKNOWN"
                    end
                end
            else recipe.outputItemState = "UNKNOWN" end
            if type(GetCraftNumReagents) == "function" then
                local reagentOK, reagentCount = pcall(GetCraftNumReagents, index)
                if reagentOK and integer(reagentCount, 0) and reagentCount <= MAX_REAGENTS then
                    recipe.reagents, recipe.reagentState = {}, "OBSERVED"
                    for reagentIndex = 1, reagentCount do
                        local reagent = { index = reagentIndex }
                        if type(GetCraftReagentInfo) == "function" then
                            local infoOK, reagentName, _, required, carried = pcall(GetCraftReagentInfo, index, reagentIndex)
                            if infoOK and type(reagentName) == "string" and reagentName ~= "" then reagent.name = reagentName end
                            if infoOK and integer(required, 0) then reagent.required = required end
                            if infoOK and integer(carried, 0) then
                                reagent.carriedByClient = carried
                                reagent.carriedEvidence = "OBSERVED"
                                reagent.carriedScope = "CURRENT_CHARACTER_BAGS_AS_REPORTED_BY_CLIENT"
                            end
                        end
                        if type(GetCraftReagentItemLink) == "function" then
                            local linkOK, link = pcall(GetCraftReagentItemLink, index, reagentIndex)
                            if linkOK and type(link) == "string" then
                                local payload, itemID = itemPayload(link)
                                if payload then reagent.itemID, reagent.itemString, reagent.itemLink = itemID, payload, link end
                            end
                        end
                        if not reagent.itemID or reagent.required == nil then recipe.reagentState = "PARTIAL" end
                        recipe.reagents[#recipe.reagents + 1] = reagent
                    end
                elseif reagentOK and integer(reagentCount, 0) then
                    recipe.reagentState = "PARTIAL"
                    issues[#issues + 1] = "craft reagent bound reached"
                else recipe.reagentState = "UNKNOWN" end
            else recipe.reagentState = "UNKNOWN" end
            profession.recipes[#profession.recipes + 1] = recipe
        end
    end
    for _, recipe in ipairs(profession.recipes) do
        if recipe._candidateKey and keyCounts[recipe._candidateKey] == 1 then recipe.recipeKey = recipe._candidateKey end
        recipe._candidateKey = nil
    end
    return { formatVersion = 1, clientProfile = profileID, observedAt = S.Now(),
        source = "legacy Craft APIs", professions = { profession },
        issues = issues }, { completeness = "partial", source = "client",
        reason = "Craft window rows do not prove learned status and may reflect trainer/UI context" }
end

S.collectors.professionRecipes = function()
    if not S.professionRecipeOpen then return nil, { completeness = "unknown", reason = "Profession window not observed open", stale = true } end
    local collector = S.professionRecipeWindowType == "CRAFT" and collectCraft or collectTradeSkill
    local ok, data, meta = pcall(collector)
    if not ok then return nil, { completeness = "unknown", reason = "Legacy profession API call failed", stale = true } end
    if not data then return nil, { completeness = "unknown", reason = meta, stale = true } end
    return data, meta
end
