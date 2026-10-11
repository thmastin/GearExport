return function(S, check, equal, advance)
    local passed = 0
    local function c(value, message) check(value, "quest: " .. message); passed = passed + 1 end
    local function e(a, b, message) equal(a, b, "quest: " .. message); passed = passed + 1 end
    local addon = S.record and WoWSyncDB
    C_QuestLog = {
        GetNumQuestLogEntries = function() return 3, 2 end,
        GetInfo = function(index)
            if index == 1 then return { isHeader = true, title = "Eastern Kingdoms" } end
            if index == 2 then return { questID = 101, title = "A Test Quest", level = 5, isTask = false, isAutoComplete = false } end
            if index == 3 then return { questID = 102, title = "Ready Quest", level = 6, isStory = true } end
        end,
        GetQuestObjectives = function(id)
            if id == 101 then return {
                { text = "First objective", type = "item", finished = false, numFulfilled = 1, numRequired = 4 },
                { text = "Second objective", type = "monster", finished = false, numFulfilled = 0, numRequired = 2 },
            } end
            return {}
        end,
        IsComplete = function(id) return id == 102 end,
        ReadyForTurnIn = function(id) return id == 102 end,
        GetAllCompletedQuestIDs = function() return { 77, 76, 77 } end,
        GetTitleForQuestID = function(id) return "Completed " .. id end,
        GetQuestWatchType = function(id) return id == 101 and 1 or nil end,
        GetNextWaypoint = function(id) if id == 101 then return 12, 0.25, 0.75 end end,
        GetNextWaypointText = function(id) if id == 101 then return "Objective area" end end,
    }
    c(S.collectors.quests ~= nil, "Forever quest collector registered")
    c(S.structuredOnly.quests == true, "quest section is structured sidecar only")
    c(S.eventFrame.events.QUEST_LOG_UPDATE and S.eventFrame.events.QUEST_LOG_CRITERIA_UPDATE, "quest refresh events registered")
    local data, meta = S.collectors.quests()
    e(data.activeState, "OBSERVED", "active log observed")
    e(data.activeCompleteness, "partial", "duplicate history ID causes partial coverage")
    e(#data.active, 2, "header excluded and two active quests retained")
    e(data.active[1].questID, 101, "quest ID retained")
    e(data.active[1].objectives[1].numFulfilled, 1, "objective progress retained")
    e(data.active[1].objectives[1].text, "First objective", "client objective order is preserved")
    e(data.active[1].objectives[2].index, 2, "objective identity includes its observed array index")
    e(data.active[1].readyForTurnIn, false, "not-ready value remains explicit false")
    e(data.active[2].isComplete, true, "completion API result retained")
    e(data.active[2].readyForTurnIn, true, "turn-in readiness remains separate explicit value")
    e(data.active[2].objectiveState, "OBSERVED", "an actual empty objective table is observed")
    e(data.completedHistory.state, "PARTIAL", "duplicate completed history rows mark coverage partial")
    e(data.completedHistory.quests[1].questID, 76, "completed quest IDs are sorted and retain identity")
    e(data.completedHistory.quests[1].title, "Completed 76", "available completed-quest titles are captured")
    e(meta.completeness, "partial", "section completeness reflects partial history")

    C_QuestLog = {
        GetNumQuestLogEntries = function() return 1, 1 end,
        GetInfo = function() return { questID = 103, title = "Unknown Objective" } end,
        GetQuestObjectives = function() return nil end,
        IsComplete = function() return false end,
        ReadyForTurnIn = function() return nil end,
        GetAllCompletedQuestIDs = function() return {} end,
    }
    data, meta = S.collectors.quests()
    e(data.active[1].objectiveState, "UNKNOWN", "nil objectives are unknown, not empty")
    e(data.active[1].turnInReadinessState, "UNKNOWN", "nil readiness is unknown")
    e(data.activeCompleteness, "partial", "nil values reduce coverage completeness")

    C_QuestLog.GetAllCompletedQuestIDs = nil
    data, meta = S.collectors.quests()
    e(data.completedHistory.state, "UNKNOWN", "missing completed-history API remains unknown")

    C_QuestLog = {
        GetNumQuestLogEntries = function() return 1, 1 end,
        GetInfo = function() return { questID = 105, title = "Blank Objective" } end,
        GetQuestObjectives = function() return { { text = "", finished = false, numFulfilled = 0, numRequired = 1 } } end,
        IsComplete = function() return false end,
        GetAllCompletedQuestIDs = function() return {} end,
    }
    data = S.collectors.quests()
    e(data.active[1].objectiveState, "PARTIAL", "blank objective text is malformed, not complete evidence")
    e(data.active[1].objectives[1].text, nil, "empty objective text is not retained as a valid description")

    C_QuestLog.GetNumQuestLogEntries = function() return 0, 0 end
    C_QuestLog.GetAllCompletedQuestIDs = function() return {} end
    data, meta = S.collectors.quests()
    e(data.activeState, "OBSERVED", "valid empty log is observed")
    e(#data.active, 0, "valid empty log contains zero rows")
    e(data.activeCompleteness, "complete", "verified empty log can be complete")

    local manyObjectives = {}
    for index = 1, 34 do manyObjectives[index] = { text = "Objective " .. index, finished = false, numFulfilled = 0, numRequired = 1 } end
    C_QuestLog.GetNumQuestLogEntries = function() return 1, 1 end
    C_QuestLog.GetInfo = function() return { questID = 104, title = "Bounded quest" } end
    C_QuestLog.GetQuestObjectives = function() return manyObjectives end
    data, meta = S.collectors.quests()
    e(#data.active[1].objectives, 32, "objective output obeys the collection bound")
    e(data.active[1].objectiveState, "PARTIAL", "truncated objectives remain explicitly partial")
    e(data.active[1].objectives[2].index, 2, "objective ordering and source indices are preserved")

    C_QuestLog.GetNumQuestLogEntries = function() error("client API changed") end
    data, meta = S.collectors.quests()
    e(data, nil, "throwing count API does not fabricate an empty log")
    e(meta.stale, true, "a failed refresh preserves the prior successful section")

    C_QuestLog = {
        GetNumQuestLogEntries = function() return 0, 0 end,
        GetInfo = function() return nil end,
        GetQuestObjectives = function() return nil end,
        GetAllCompletedQuestIDs = function() return {} end,
    }
    local before = S.record.sections.quests and S.record.sections.quests.observedAt
    S.Mark("quests", 0); advance(0.3)
    c(S.record.sections.quests ~= nil, "collected section persists in per-character SavedVariables")
    c(S.GetSnapshot().sections.quests ~= nil, "quest section appears in structured snapshot")
    c(before == nil or S.record.sections.quests.observedAt >= before, "section timestamp is monotonic")
    e(S.record.sections.quests.data.clientFamily, "Forever", "stored section carries client version family")
    e(addon.schemaVersion, 1, "existing SavedVariables schema remains unchanged")
    return passed
end
