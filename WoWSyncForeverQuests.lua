-- Forever 1.60.1 read-only quest observation.
-- This module is loaded only by GearExport-Forever.toc.
local _, addon = ...
local S, F, C = addon.Sync, addon.Forever, WoWSyncCompat

local MAX_LOG_ROWS = 120
local MAX_QUESTS = 100
local MAX_OBJECTIVES = 32
local MAX_COMPLETED_IDS = 500
local MAX_TEXT = 256

local function public(value)
    return not (type(issecretvalue) == "function" and issecretvalue(value))
end

local function issue(issues, text)
    if #issues < 100 then issues[#issues + 1] = text end
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return false, nil, "unavailable" end
    local result = { pcall(fn, ...) }
    if not result[1] then return false, nil, "failed" end
    return true, result[2], nil, result[3], result[4]
end

local function finiteInteger(value, minimum)
    return public(value) and type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge and value % 1 == 0
        and value >= (minimum or 0)
end

local function cleanText(value)
    if not public(value) or type(value) ~= "string" then return nil end
    if #value > MAX_TEXT then return value:sub(1, MAX_TEXT), true end
    return value
end

local function readBoolean(api, method, id, issues)
    local ok, value = safeCall(api[method], id)
    if not ok or not public(value) or type(value) ~= "boolean" then
        issue(issues, method .. " unknown")
        return nil
    end
    return value
end

local function objectiveRows(api, questID, issues)
    local ok, rows = safeCall(api.GetQuestObjectives, questID)
    if not ok or not public(rows) or type(rows) ~= "table" then
        issue(issues, "quest " .. questID .. " objectives unavailable")
        return nil, "UNKNOWN"
    end

    local output, partial, total, inspectedKeys = {}, false, 0, 0
    for key, row in pairs(rows) do
        inspectedKeys = inspectedKeys + 1
        if inspectedKeys > MAX_OBJECTIVES then partial = true; break end
        if not public(key) or not finiteInteger(key, 1) then partial = true
        elseif key > total then total = key end
    end
    if total > MAX_OBJECTIVES then partial = true end
    -- Numeric objective keys are emitted in the API's order. A returned empty
    -- table is observed zero objectives; sparse/malformed tables stay partial.
    for index = 1, math.min(total, MAX_OBJECTIVES) do
        local row = rows[index]
        if not public(row) or type(row) ~= "table" then
            partial = true
        else
            local text, clipped = cleanText(row.text)
            if clipped then partial = true end
            local objectiveType, typeClipped = cleanText(row.type)
            if typeClipped then partial = true end
            local entry = { index = index }
            if text then entry.text = text else partial = true end
            if objectiveType then entry.type = objectiveType end
            if public(row.objectiveType) and (type(row.objectiveType) == "number" or type(row.objectiveType) == "string") then entry.objectiveType = row.objectiveType end
            if public(row.finished) and type(row.finished) == "boolean" then entry.finished = row.finished else entry.finishedState = "UNKNOWN"; partial = true end
            if finiteInteger(row.numFulfilled, 0) then entry.numFulfilled = row.numFulfilled else entry.numFulfilledState = "UNKNOWN"; partial = true end
            if finiteInteger(row.numRequired, 0) then entry.numRequired = row.numRequired else entry.numRequiredState = "UNKNOWN"; partial = true end
            output[#output + 1] = entry
        end
    end
    return output, partial and "PARTIAL" or "OBSERVED", total
end

local function collectQuest(api, info, issues)
    local questID = info.questID
    local title, clipped = cleanText(info.title)
    if clipped then issue(issues, "quest " .. questID .. " title truncated") end
    if not title and type(api.GetTitleForQuestID) == "function" then
        local ok, fallback = safeCall(api.GetTitleForQuestID, questID)
        if ok then title, clipped = cleanText(fallback) end
        if clipped then issue(issues, "quest " .. questID .. " title truncated") end
    end
    if not title then issue(issues, "quest " .. questID .. " title unknown") end

    local quest = {
        questID = questID,
        evidence = "OBSERVED",
        titleState = title and "OBSERVED" or "UNKNOWN",
        objectiveState = "UNKNOWN",
        completionState = "UNKNOWN",
        turnInReadinessState = "UNKNOWN",
    }
    if title then quest.title = title end
    for _, key in ipairs({ "level", "difficultyLevel", "suggestedGroup", "frequency", "campaignID" }) do
        local value = info[key]
        if public(value) and finiteInteger(value, 0) then quest[key] = value end
    end
    for _, key in ipairs({ "isTask", "isBounty", "isStory", "isScaling", "isOnMap", "hasLocalPOI", "isHidden", "isAutoComplete", "startEvent" }) do
        local value = info[key]
        if public(value) and type(value) == "boolean" then quest[key] = value end
    end

    local objectives, objectiveState = objectiveRows(api, questID, issues)
    if objectives then quest.objectives, quest.objectiveState = objectives, objectiveState end
    local complete = readBoolean(api, "IsComplete", questID, issues)
    if complete ~= nil then quest.isComplete, quest.completionState = complete, "OBSERVED" end

    -- The Forever generated declaration returns nullable boolean. Never infer
    -- readiness from IsComplete or objective progress.
    if type(api.ReadyForTurnIn) == "function" then
        local ok, ready = safeCall(api.ReadyForTurnIn, questID)
        if ok and public(ready) and type(ready) == "boolean" then
            quest.readyForTurnIn, quest.turnInReadinessState = ready, "OBSERVED"
        else
            issue(issues, "ReadyForTurnIn unknown for quest " .. questID)
        end
    else
        issue(issues, "ReadyForTurnIn unavailable")
    end

    if type(api.GetQuestWatchType) == "function" then
        local ok, watchType = safeCall(api.GetQuestWatchType, questID)
        if ok and public(watchType) and (type(watchType) == "number" or type(watchType) == "string") then
            quest.watchType = watchType
            quest.watchState = "OBSERVED"
        else quest.watchState = "UNKNOWN" end
    else quest.watchState = "UNKNOWN" end

    if type(api.GetNextWaypoint) == "function" then
        local result = { pcall(api.GetNextWaypoint, questID) }
        if result[1] and public(result[2]) and finiteInteger(result[2], 0)
            and public(result[3]) and type(result[3]) == "number"
            and public(result[4]) and type(result[4]) == "number" then
            quest.waypoint = { mapID = result[2], x = result[3], y = result[4], state = "OBSERVED" }
        else quest.waypointState = "UNKNOWN" end
    else quest.waypointState = "UNKNOWN" end
    if type(api.GetNextWaypointText) == "function" then
        local ok, text = safeCall(api.GetNextWaypointText, questID)
        if ok then quest.waypointText = cleanText(text) end
    end
    return quest
end

local function collectCompleted(api, issues)
    if type(api.GetAllCompletedQuestIDs) ~= "function" then
        issue(issues, "completed quest history unavailable")
        return { state = "UNKNOWN", questIDs = {} }
    end
    local ok, rows = safeCall(api.GetAllCompletedQuestIDs)
    if not ok or not public(rows) or type(rows) ~= "table" then
        issue(issues, "completed quest history unknown")
        return { state = "UNKNOWN", questIDs = {} }
    end
    local ids, seen, partial = {}, {}, false
    local count = #rows
    if count > MAX_COMPLETED_IDS then partial = true end
    for index = 1, math.min(count, MAX_COMPLETED_IDS) do
        local id = rows[index]
        if not public(id) or not finiteInteger(id, 1) then partial = true
        elseif not seen[id] then seen[id] = true; ids[#ids + 1] = id
        else partial = true end
    end
    table.sort(ids)
    local quests = {}
    for _, id in ipairs(ids) do
        local entry = { questID = id, titleState = "UNKNOWN" }
        if type(api.GetTitleForQuestID) == "function" then
            local titleOK, title = safeCall(api.GetTitleForQuestID, id)
            if titleOK then
                local cleaned, clipped = cleanText(title)
                if cleaned then entry.title, entry.titleState = cleaned, "OBSERVED" end
                if clipped then partial = true; issue(issues, "completed quest title truncated") end
            end
        end
        quests[#quests + 1] = entry
    end
    return { state = partial and "PARTIAL" or "OBSERVED", questIDs = ids, quests = quests, returnedCount = #ids, truncated = partial or nil }
end

S.collectors.quests = function()
    local issues, api = {}, type(C_QuestLog) == "table" and C_QuestLog or nil
    if not C.IsForever() then return nil, { completeness = "unknown", reason = "Forever quest collector is version isolated" } end
    if not api then return nil, { completeness = "unknown", reason = "C_QuestLog unavailable", stale = true } end

    -- Some Forever builds expose both counts from the same call. Call once and
    -- retain both return values, treating missing/malformed values as unknown.
    local countOK, shownCount, totalCount
    local result = { pcall(api.GetNumQuestLogEntries) }
    countOK, shownCount, totalCount = result[1], result[2], result[3]
    if not countOK or not finiteInteger(shownCount, 0) or not finiteInteger(totalCount, 0) then
        issue(issues, "quest log counts unavailable")
        return nil, { completeness = "unknown", reason = table.concat(issues, "; "), stale = true }
    end
    if shownCount > MAX_LOG_ROWS then issue(issues, "quest log row limit reached") end
    local entries, seenIDs, scannedRows, partial = {}, {}, math.min(shownCount, MAX_LOG_ROWS), shownCount > MAX_LOG_ROWS
    for index = 1, scannedRows do
        local infoOK, info = safeCall(api.GetInfo, index)
        if not infoOK or not public(info) or type(info) ~= "table" then
            partial = true; issue(issues, "quest row " .. index .. " unavailable")
        elseif public(info.isHeader) and info.isHeader == true then
            -- Header rows are structural, not quests.
        elseif public(info.questID) and finiteInteger(info.questID, 1) then
            if #entries < MAX_QUESTS then
                local quest = collectQuest(api, info, issues)
                quest.logIndex = index
                if seenIDs[quest.questID] then partial = true; issue(issues, "duplicate active quest ID")
                else seenIDs[quest.questID] = true; entries[#entries + 1] = quest end
                if quest.objectiveState ~= "OBSERVED" or quest.completionState ~= "OBSERVED" or quest.turnInReadinessState ~= "OBSERVED" then partial = true end
                if quest.titleState ~= "OBSERVED" then partial = true end
            else partial = true; issue(issues, "active quest limit reached") end
        else
            partial = true; issue(issues, "quest row " .. index .. " missing quest ID")
        end
    end
    if totalCount > MAX_QUESTS then partial = true; issue(issues, "active quest count exceeds bound") end
    if #entries ~= totalCount and shownCount <= MAX_LOG_ROWS then
        -- Header rows are excluded by the client quest count. A mismatch may
        -- also indicate collapsed/hidden rows; never call coverage complete.
        partial = true; issue(issues, "scanned quest count differs from client count")
    end
    table.sort(entries, function(a, b) return a.questID < b.questID end)
    local completed = collectCompleted(api, issues)
    if completed.state ~= "OBSERVED" then partial = true end
    if #issues > 0 then partial = true end
    table.sort(issues)
    local observedAt = S.Now()
    local data = {
        formatVersion = 1,
        clientProfile = "Forever:1.60.1:" .. tostring(F.build) .. ":16001",
        clientFamily = "Forever",
        source = "C_QuestLog",
        observedAt = observedAt,
        activeState = "OBSERVED",
        activeCompleteness = partial and "partial" or "complete",
        activeCounts = { visibleEntries = shownCount, quests = totalCount, scannedRows = scannedRows, returnedQuests = #entries },
        active = entries,
        completedHistory = completed,
        capabilities = {
            getInfo = type(api.GetInfo) == "function",
            getObjectives = type(api.GetQuestObjectives) == "function",
            isComplete = type(api.IsComplete) == "function",
            readyForTurnIn = type(api.ReadyForTurnIn) == "function",
            completedHistory = type(api.GetAllCompletedQuestIDs) == "function",
            tracking = type(api.GetQuestWatchType) == "function",
            waypoint = type(api.GetNextWaypoint) == "function",
        },
        issues = issues,
    }
    return data, { completeness = partial and "partial" or "complete", reason = #issues > 0 and table.concat(issues, "; ") or nil }
end
