-- Read-only Era/TBC progression observations using their legacy client APIs.
-- This module is absent from Retail and Forever packages.
local _, addon = ...
local S, C = addon.Sync, WoWSyncCompat
if not S or not C or C.IsRetail() or (C.IsForever and C.IsForever()) then return end

local MAX_QUEST_ROWS, MAX_QUESTS, MAX_OBJECTIVES, MAX_COMPLETED, MAX_FACTIONS, MAX_TABS, MAX_TALENTS = 250, 200, 32, 5000, 500, 10, 100
local function integer(value, minimum)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
        and value % 1 == 0 and value >= (minimum or 0)
end
local function clean(value, limit)
    if type(value) ~= "string" or value == "" then return nil end
    return #value > (limit or 256) and value:sub(1, limit or 256) or value
end
local function profile()
    if type(GetBuildInfo) ~= "function" then return nil end
    local ok, version, _, _, interface = pcall(GetBuildInfo)
    if not ok or type(version) ~= "string" or (interface ~= 11509 and interface ~= 20506) then return nil end
    return "Classic:" .. tostring(WOW_PROJECT_ID or "project-unknown") .. ":" .. tostring(interface)
end

S.collectors.quests = function()
    local client = profile()
    if not client or type(GetNumQuestLogEntries) ~= "function" or type(GetQuestLogTitle) ~= "function" then
        return nil, { completeness = "unknown", reason = "Legacy quest-log APIs unavailable", stale = true }
    end
    local ok, visibleRows, questCount = pcall(GetNumQuestLogEntries)
    if not ok or not integer(visibleRows, 0) then return nil, { completeness = "unknown", reason = "Quest-log count unavailable", stale = true } end
    local partial, issues, active, seen, scanCount = visibleRows > MAX_QUEST_ROWS, {}, {}, {}, math.min(visibleRows, MAX_QUEST_ROWS)
    local objectivesAPI = type(GetNumQuestLeaderBoards) == "function" and type(GetQuestLogLeaderBoard) == "function"
    for index = 1, scanCount do
        local rowOK, title, level, group, header, collapsed, complete, frequency, questID = pcall(GetQuestLogTitle, index)
        if not rowOK then
            partial = true; issues[#issues + 1] = "quest row API failed"
        elseif header then
            if collapsed then partial = true end
        elseif title ~= nil then
            if not integer(questID, 1) or type(title) ~= "string" or title == "" then
                partial = true; issues[#issues + 1] = "active quest identity incomplete"
            elseif seen[questID] then
                partial = true; issues[#issues + 1] = "duplicate quest ID"
            elseif #active >= MAX_QUESTS then
                partial = true; issues[#issues + 1] = "active quest bound reached"
            else
                seen[questID] = true
                local quest = { questID = questID, title = clean(title), evidence = "OBSERVED",
                    sourceAPI = "GetQuestLogTitle", objectiveState = "UNKNOWN",
                    completionState = "UNKNOWN", turnInReadinessState = "UNKNOWN" }
                if integer(level, 0) then quest.level = level end
                if integer(group, 0) then quest.suggestedGroup = group end
                if integer(frequency, 0) then quest.frequency = frequency end
                if type(complete) == "boolean" then
                    quest.completionState = "OBSERVED"
                    quest.isComplete = complete
                elseif complete == 1 or complete == 0 or complete == -1 then
                    quest.completionState = "OBSERVED"
                    quest.isComplete = complete == 1
                    if complete == -1 then quest.isFailed = true end
                elseif complete == nil then
                    -- The legacy GetQuestLogTitle contract returns nil for the
                    -- ordinary in-progress case, 1 for complete, and -1 failed.
                    quest.completionState = "OBSERVED"
                    quest.isComplete = false
                end
                if objectivesAPI then
                    local countOK, objectiveCount = pcall(GetNumQuestLeaderBoards, index)
                    if countOK and integer(objectiveCount, 0) then
                        quest.objectives, quest.objectiveState = {}, objectiveCount > MAX_OBJECTIVES and "PARTIAL" or "OBSERVED"
                        if objectiveCount > MAX_OBJECTIVES then partial = true end
                        for objectiveIndex = 1, math.min(objectiveCount, MAX_OBJECTIVES) do
                            local objectiveOK, text, kind, finished = pcall(GetQuestLogLeaderBoard, objectiveIndex, index)
                            if not objectiveOK or type(text) ~= "string" or text == "" then
                                quest.objectiveState = "PARTIAL"; partial = true
                            else
                                local objective = { index = objectiveIndex, text = clean(text), evidence = "OBSERVED" }
                                if type(kind) == "string" then objective.type = clean(kind) end
                                if type(finished) == "boolean" then objective.finished = finished else objective.finishedState = "UNKNOWN"; quest.objectiveState = "PARTIAL"; partial = true end
                                quest.objectives[#quest.objectives + 1] = objective
                            end
                        end
                    else partial = true end
                end
                if quest.completionState == "UNKNOWN" or quest.objectiveState == "UNKNOWN" then partial = true end
                active[#active + 1] = quest
            end
        end
    end
    table.sort(active, function(a,b) return a.questID < b.questID end)
    if integer(questCount, 0) and #active ~= questCount then partial = true end
    local completed = { state = "UNKNOWN", questIDs = {}, quests = {},
        coverage = "CLIENT_RETURNED_IDS; DAILY_RESULTS_MAY_RESET; API_DOCUMENTS_ACCOUNT_WIDE_PET_BATTLE_EXCEPTIONS" }
    if type(GetQuestsCompleted) == "function" then
        local historyOK, history = pcall(GetQuestsCompleted)
        if historyOK and type(history) == "table" then
            local ids, malformed = {}, false
            for id, isComplete in pairs(history) do
                if integer(id, 1) and isComplete == true then
                    ids[#ids + 1] = id
                    if #ids > MAX_COMPLETED then malformed = true; break end
                else malformed = true end
            end
            table.sort(ids)
            completed = { state = malformed and "PARTIAL" or "OBSERVED", questIDs = ids, quests = {}, returnedCount = #ids,
                coverage = "CLIENT_RETURNED_IDS; DAILY_RESULTS_MAY_RESET; API_DOCUMENTS_ACCOUNT_WIDE_PET_BATTLE_EXCEPTIONS" }
            for _, id in ipairs(ids) do completed.quests[#completed.quests + 1] = { questID = id, titleState = "UNKNOWN" } end
            if malformed then partial = true end
        else partial = true; issues[#issues + 1] = "completed history query failed" end
    else partial = true; issues[#issues + 1] = "completed history API unavailable" end
    if completed.state ~= "OBSERVED" then partial = true end
    return { formatVersion = 1, clientProfile = client, clientFamily = "Classic",
        source = "legacy quest log APIs", observedAt = S.Now(), activeState = "OBSERVED",
        activeCompleteness = partial and "partial" or "complete", activeCounts = {
            visibleEntries = visibleRows, quests = questCount, scannedRows = scanCount, returnedQuests = #active },
        active = active, completedHistory = completed,
        capabilities = { activeQuestLog = true, objectives = objectivesAPI, completedHistory = type(GetQuestsCompleted) == "function", turnInReadiness = false },
        issues = issues }, { completeness = partial and "partial" or "complete",
        reason = partial and "Quest-log rows, collapsed sections, objectives, or completed history were incomplete" or nil }
end

S.collectors.reputation = function()
    local client = profile()
    if not client or type(GetNumFactions) ~= "function" or type(GetFactionInfo) ~= "function" then
        return nil, { completeness = "unknown", reason = "Legacy reputation APIs unavailable", stale = true }
    end
    local ok, count = pcall(GetNumFactions)
    if not ok or not integer(count, 0) then return nil, { completeness = "unknown", reason = "Faction row count unavailable", stale = true } end
    if count > MAX_FACTIONS then return nil, { completeness = "unknown", reason = "Faction row bound exceeded", stale = true } end
    local rows, partial, parents = {}, false, {}
    for index = 1, count do
        local rowOK, name, _, standing, barMin, barMax, barValue, atWar, canToggle, isHeader, collapsed, hasRep, watched, isChild, factionID = pcall(GetFactionInfo, index)
        if not rowOK or type(name) ~= "string" or name == "" then
            partial = true
        elseif isHeader then
            parents[isChild and "child" or "parent"] = name
            if collapsed then partial = true end
            if hasRep then
                -- Header-owned reputation is represented explicitly; it is not
                -- an ordinary faction row and retains its client API identity.
                if integer(factionID, 1) then rows[#rows + 1] = { factionID = factionID, name = name, isHeaderReputation = true, evidence = "OBSERVED", ownerScope = "CHARACTER" } else partial = true end
            end
        else
            local row = { name = clean(name), evidence = "OBSERVED", ownerScope = "CHARACTER", visibleIndex = index }
            if integer(factionID, 1) then row.factionID = factionID else partial = true end
            if integer(standing, 0) then row.standingID = standing end
            if type(barMin) == "number" then row.barMin = barMin end
            if type(barMax) == "number" then row.barMax = barMax end
            if type(barValue) == "number" then row.barValue = barValue end
            if type(atWar) == "boolean" then row.atWar = atWar end
            if type(canToggle) == "boolean" then row.canToggleAtWar = canToggle end
            if type(watched) == "boolean" then row.isWatched = watched end
            row.parentCategory = parents.child or parents.parent
            row.factionKey = "legacy:" .. client .. ":" .. tostring(row.parentCategory or "") .. ":" .. row.name
            rows[#rows + 1] = row
        end
    end
    return { formatVersion = 1, clientProfile = client, source = "GetFactionInfo",
        observedAt = S.Now(), ownerScope = "CHARACTER", coverage = "VISIBLE_REPUTATION_ROWS_ONLY",
        factions = rows, majorFactions = {}, }, { completeness = "partial",
        reason = partial and "Faction rows may be collapsed or missing stable IDs" or "Only faction rows visible in the current reputation list are covered" }
end

S.collectors.talents = function()
    local client = profile()
    if not client or type(GetNumTalentTabs) ~= "function" or type(GetTalentTabInfo) ~= "function"
        or type(GetNumTalents) ~= "function" or type(GetTalentInfo) ~= "function" then
        return nil, { completeness = "unknown", reason = "Legacy talent APIs unavailable", stale = true }
    end
    local ok, tabCount = pcall(GetNumTalentTabs)
    if not ok or not integer(tabCount, 0) or tabCount > MAX_TABS then return nil, { completeness = "unknown", reason = "Talent tree count unavailable or outside bound", stale = true } end
    local trees, partial = {}, false
    for tab = 1, tabCount do
        local tabOK, name, _, pointsSpent = pcall(GetTalentTabInfo, tab)
        if not tabOK or type(name) ~= "string" then
            partial = true
        else
            local tree = { tab = tab, name = clean(name), talents = {}, evidence = "OBSERVED" }
            if integer(pointsSpent, 0) then tree.pointsSpent = pointsSpent else partial = true end
            local countOK, talentCount = pcall(GetNumTalents, tab)
            if not countOK or not integer(talentCount, 0) or talentCount > MAX_TALENTS then
                tree.talentCoverage = "UNKNOWN"; partial = true
            else
                tree.talentCoverage = "OBSERVED"
                for index = 1, talentCount do
                    local talentOK, talentName, _, tier, column, currentRank, maxRank = pcall(GetTalentInfo, tab, index)
                    if not talentOK or type(talentName) ~= "string" then partial = true
                    else
                        local talent = { index = index, name = clean(talentName), evidence = "OBSERVED" }
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
    return { formatVersion = 1, clientProfile = client, source = "legacy talent APIs",
        observedAt = S.Now(), coverage = "VISIBLE_CLASS_TALENT_TREES", trees = trees },
        { completeness = partial and "partial" or "complete", reason = partial and "One or more talent fields were unavailable" or nil }
end
