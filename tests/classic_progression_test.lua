return function(S, check, equal, event, advance)
    local names = { "GetNumQuestLogEntries", "GetQuestLogTitle", "GetNumQuestLeaderBoards", "GetQuestLogLeaderBoard",
        "GetQuestsCompleted", "GetNumFactions", "GetFactionInfo", "GetNumTalentTabs", "GetTalentTabInfo", "GetNumTalents", "GetTalentInfo" }
    local saved = {}
    for _, name in ipairs(names) do saved[name] = _G[name] end
    local quests = {
        { "Quests", nil, nil, true, false },
        { "Find the Scout", 8, 0, false, false, nil, 0, 101 },
        { "Report Back", 8, 0, false, false, true, 0, 202 },
    }
    local rows = { { "Scout rescued: 1/1", "monster", true }, { "Return safely", "event", false } }
    GetNumQuestLogEntries = function() return 3, 2 end
    GetQuestLogTitle = function(index)
        local row = quests[index]
        if row then return row[1], row[2], row[3], row[4], row[5], row[6], row[7], row[8] end
    end
    GetNumQuestLeaderBoards = function(index) return index == 2 and 2 or 0 end
    GetQuestLogLeaderBoard = function(objective, index)
        local row = rows[objective]
        if row then return row[1], row[2], row[3] end
    end
    GetQuestsCompleted = function() return { [9] = true, [12] = true } end
    GetNumFactions = function() return 2 end
    GetFactionInfo = function(index)
        if index == 1 then return "Classic Factions", "", 0, 0, 0, 0, false, false, true, true, false, false, false end
        return "Ironforge", "Alliance", 5, 3000, 6000, 4200, false, false, false, false, true, true, true, 47
    end
    GetNumTalentTabs = function() return 1 end
    GetTalentTabInfo = function() return "Arms", "icon", 3 end
    GetNumTalents = function() return 1 end
    GetTalentInfo = function() return "Improved Heroic Strike", "icon", 1, 1, 2, 3 end

    check(S.collectors.quests and S.collectors.reputation and S.collectors.talents, "Classic progression collectors registered")
    local data, meta = S.collectors.quests()
    equal(meta.completeness, "complete", "fully returned active quest and history observation can be complete")
    equal(#data.active, 2, "active quests enumerated excluding headers")
    equal(data.active[1].questID, 101, "quest ID captured")
    equal(data.active[1].isComplete, false, "legacy nil completion flag means observed in-progress")
    equal(data.active[1].objectives[1].finished, true, "objective completion explicit")
    equal(data.active[1].objectives[2].finished, false, "objective incompletion explicit")
    equal(data.active[2].isComplete, true, "boolean completion state preserved")
    equal(data.active[2].turnInReadinessState, "UNKNOWN", "turn-in readiness is not inferred from completion")
    equal(data.completedHistory.state, "OBSERVED", "API returned completed-ID set identified as observed")
    equal(data.completedHistory.returnedCount, 2, "completed history count describes API return only")
    check(data.capabilities.turnInReadiness == false, "unsupported turn-in readiness capability explicit")

    local oldAt = S.Now()
    S.Commit("quests", data, meta)
    rows[1] = { "Scout rescued: 1/1", "monster" }
    local missingFinished, missingFinishedMeta = S.collectors.quests()
    S.Commit("quests", missingFinished, missingFinishedMeta)
    local partialFinishedRow
    for _, row in ipairs(S.record.sections.quests.data.active) do if row.questID == 101 then partialFinishedRow = row end end
    equal(partialFinishedRow.objectives[1].finished, true, "previous objective result survives same-index response with missing flag")
    equal(partialFinishedRow.objectives[1].finishedState, "LAST_SEEN", "inherited objective result has field-level last-seen state")
    rows[1] = { "Scout rescued: 1/1", "monster", true }
    local savedObjectivesCount = GetNumQuestLeaderBoards
    GetNumQuestLeaderBoards = nil
    local withoutObjectiveAPI, withoutObjectiveMeta = S.collectors.quests()
    S.Commit("quests", withoutObjectiveAPI, withoutObjectiveMeta)
    local partialRow
    for _, row in ipairs(S.record.sections.quests.data.active) do if row.questID == 101 then partialRow = row end end
    equal(partialRow.evidence, "OBSERVED", "current quest identity remains observed in a partial refresh")
    equal(partialRow.objectiveState, "PARTIAL", "missing objective API marks retained objective data partial")
    equal(partialRow.objectives[1].evidence, "LAST_SEEN", "prior objective details survive partial refresh as last-seen")
    GetNumQuestLeaderBoards = savedObjectivesCount
    quests = { { "Quests", nil, nil, true, false }, { "Report Back", 8, 0, false, false, true, 0, 202 } }
    GetNumQuestLogEntries = function() return 2, 1 end
    GetNumQuestLeaderBoards = function() return 1 end
    GetQuestLogLeaderBoard = function() return "Return safely", "event", true end
    GetQuestsCompleted = function() return { [9] = true, [13] = true } end
    local nextData, nextMeta = S.collectors.quests()
    S.record.sections.quests.data.completedHistory.quests = {
        { questID = 9, titleState = "UNKNOWN", evidence = "OBSERVED" },
    }
    S.Commit("quests", nextData, nextMeta)
    local stored = S.record.sections.quests.data
    local priorActive
    for _, row in ipairs(stored.active) do if row.questID == 101 then priorActive = row end end
    equal(priorActive.evidence, "LAST_SEEN", "disappeared active quest remains last-seen, not completed")
    equal(priorActive.isComplete, false, "disappearance does not rewrite observed completion")
    equal(stored.activeCompleteness, "partial", "merged current and last-seen quest rows are explicitly partial")
    equal(stored.completedHistory.state, "PARTIAL", "historical IDs omitted by newer return are not treated as current-complete")
    local historyEvidence = {}
    for _, row in ipairs(stored.completedHistory.quests) do historyEvidence[row.questID] = row.evidence end
    equal(historyEvidence[9], "OBSERVED", "returned completed-history ID is refreshed")
    equal(historyEvidence[12], "LAST_SEEN", "omitted historical ID retained as last-seen")
    check(stored.observedAt >= oldAt, "quest observation timestamp advances")

    local reputation, repMeta = S.collectors.reputation()
    equal(repMeta.completeness, "partial", "visible reputation list does not claim full account coverage")
    equal(reputation.factions[1].factionID, 47, "provided faction ID preserved")
    equal(reputation.factions[1].barValue, 4200, "observed faction bar value captured")
    equal(reputation.factions[1].ownerScope, "CHARACTER", "legacy reputation ownership is character-scoped")
    equal(reputation.factions[1].factionKey:match("^legacy:"), "legacy:", "missing stable faction identity uses namespaced display key")

    local talents, talentMeta = S.collectors.talents()
    equal(talentMeta.completeness, "complete", "available talent tree rows captured")
    equal(talents.trees[1].pointsSpent, 3, "tab points spent captured")
    equal(talents.trees[1].talents[1].currentRank, 2, "current talent rank captured")
    equal(talents.trees[1].talents[1].maxRank, 3, "maximum talent rank captured")
    equal(talents.trees[1].classFile, nil, "unverified tab return is not mislabeled as class file")

    local savedCompleted, savedObjective, savedLog = GetQuestsCompleted, GetQuestLogLeaderBoard, GetQuestLogTitle
    GetQuestsCompleted, GetQuestLogLeaderBoard, GetQuestLogTitle = nil, nil, nil
    local unavailable, unavailableMeta = S.collectors.quests()
    equal(unavailableMeta.completeness, "unknown", "missing quest APIs preserve unknown")
    equal(unavailable, nil, "unsupported quest collection does not become an empty log")
    GetQuestsCompleted, GetQuestLogLeaderBoard, GetQuestLogTitle = savedCompleted, savedObjective, savedLog

    local savedBuild = GetBuildInfo
    GetBuildInfo = function() return "Forever 1.60.1", "", "", 16001 end
    equal(S.collectors.quests(), nil, "Forever interface cannot use Classic quest adapter")
    GetBuildInfo = savedBuild
    for _, name in ipairs(names) do _G[name] = saved[name] end
end
