-- Synthetic contract fixtures only; never evidence from a live client.
return function(S, check, equal)
    check(S.collectors.forever70245Evidence ~= nil, "70245 raw evidence collector enabled")
    check(not S.collectors.trainer, "unvalidated older trainer collector remains disabled")
    local found = false
    for _, key in ipairs(S.order) do if key == "forever70245Evidence" then found = true end end
    check(found, "70245 evidence included in normal export refresh")
    check(S.structuredOnly.forever70245Evidence, "new evidence stays out of strict WOWSYNC v1 text for parser compatibility")

    local oldSkill, oldFrame = C_SkillInfo, ClassTrainerFrame
    local oldCount, oldInfo, oldCost = GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceCost
    local oldSkillReq, oldAbilityReq, oldAbilityCount = GetTrainerServiceSkillReq, GetTrainerServiceAbilityReq, GetTrainerServiceNumAbilityReq
    local oldServiceType, oldLearnable = GetTrainerServiceType, IsTrainerServiceLearnable
    local calls, infoCalls, abilityCalls, countApiCalls = 0, 0, 0, 0
    C_SkillInfo = {
        GetNumSkillLines = function() return 3 end,
        GetSkillLineInfo = function(index)
            calls = calls + 1
            if index == 1 then return { isHeader = true, name = "Weapon Skills", skillID = 6, rank = 0, maxRank = 0 } end
            return { isHeader = false, name = "Axes", skillID = 44 + index, skillLineCategoryID = 6,
                rank = 20 + index, maxRank = 40 }
        end,
    }
    ClassTrainerFrame = { IsShown = function() return false end }
    GetNumTrainerServices = function() countApiCalls = countApiCalls + 1; return 2 end
    GetTrainerServiceInfo = function(index)
        infoCalls = infoCalls + 1
        return "Service " .. index, "unavailable", 1234 + index, 10, "Rank 1", ""
    end
    GetTrainerServiceCost = function(index) return index * 100 end
    GetTrainerServiceSkillReq = function() return nil, 0, true end
    GetTrainerServiceAbilityReq = function(service, requirement)
        abilityCalls = abilityCalls + 1
        if service == 1 and requirement == 1 then return "|cffff0000Prerequisite|r", true end
        return nil, false
    end
    GetTrainerServiceNumAbilityReq = function() error("unvalidated count API must not be called") end
    GetTrainerServiceType, IsTrainerServiceLearnable = nil, nil

    local closed, closedMeta = S.collectors.forever70245Evidence()
    equal(closed.trainer.state, "NOT_OBSERVED_WINDOW_CLOSED", "closed trainer is explicit unknown")
    equal(countApiCalls, 0, "closed trainer invokes no service APIs")
    equal(closed.skillLineCountValue, 3, "skill count captured")
    equal(calls, 3, "each skill index called once")
    equal(closed.skillLines[2].name, "Axes", "raw skill name retained")
    equal(closed.skillLines[2].skillID, 46, "skill id retained separately for duplicate names")
    equal(closed.skillLines[2].index, 2, "skill index retained")
    equal(closed.skillLines[2].rank, 22, "raw rank retained")
    equal(closed.skillLines[2].maxRank, 40, "raw maximum rank retained")
    equal(closed.skillLines[1].isHeader, true, "header flag retained")
    equal(closed.skillLines[3].name, "Axes", "duplicate display name retained")
    check(closed.skillLines[2].skillID ~= closed.skillLines[3].skillID,
        "duplicate names retain distinct skill IDs")
    check(closed.skillLines[2].returnShape.count == 1 and closed.skillLines[2].returnShape.types[1] == "table",
        "skill return shape retained")
    equal(closed.skillLines[2].provenance, "IN_GAME_RUNTIME_CALL", "skill provenance retained")

    C_SkillInfo = {}
    local missingSkill = S.collectors.forever70245Evidence()
    equal(missingSkill.skillLineCount.state, "API_MISSING", "missing count API explicit")
    equal(missingSkill.skillLineCoverage, "UNKNOWN_COUNT", "missing count does not create an empty-complete skill list")
    C_SkillInfo = { GetNumSkillLines = function() error("synthetic count failure") end }
    local failedCount = S.collectors.forever70245Evidence()
    equal(failedCount.skillLineCount.state, "API_ERROR", "throwing count API captured as error")
    equal(failedCount.skillLineCoverage, "UNKNOWN_COUNT", "throwing count remains unknown")
    C_SkillInfo = { GetNumSkillLines = function() return 2 end,
        GetSkillLineInfo = function(index) if index == 1 then return { name = "Known", skillID = 1 } end error("synthetic row failure") end }
    local partialSkills = S.collectors.forever70245Evidence()
    equal(partialSkills.skillLines[2].state, "API_ERROR", "indexed API error remains row error")
    equal(partialSkills.skillLineCoverage, "PARTIAL_INDEXED_ROWS", "partial row cannot claim complete coverage")
    C_SkillInfo.GetSkillLineInfo = function(index) if index == 1 then return { name = "Known", skillID = 1 } end return nil end
    local nilSkill = S.collectors.forever70245Evidence()
    equal(nilSkill.skillLines[2].state, "NIL_RESULT", "nil indexed result remains explicit")

    C_SkillInfo = {
        GetNumSkillLines = function() return 3 end,
        GetSkillLineInfo = function(index)
            if index == 1 then return { isHeader = true, name = "Weapon Skills", skillID = 6, rank = 0, maxRank = 0 } end
            return { isHeader = false, name = "Axes", skillID = 44 + index, skillLineCategoryID = 6,
                rank = 20 + index, maxRank = 40 }
        end,
    }
    ClassTrainerFrame.IsShown = function() return true end
    GetNumTrainerServices = function() error("synthetic trainer count failure") end
    local failedTrainerCount = S.collectors.forever70245Evidence().trainer
    equal(failedTrainerCount.state, "PARTIAL_INVALID_SERVICE_COUNT", "throwing trainer count remains partial")
    equal(failedTrainerCount.attempted.serviceCountResult.state, "API_ERROR", "trainer count error retained")
    GetNumTrainerServices = function() countApiCalls = countApiCalls + 1; ClassTrainerFrame.shown = false; return 2 end
    ClassTrainerFrame.IsShown = function(self) return self.shown ~= false end
    local closedMidCapture = S.collectors.forever70245Evidence().trainer
    equal(closedMidCapture.state, "PARTIAL_WINDOW_CLOSED", "closing trainer during capture is explicit partial")
    equal(infoCalls, 0, "closed window prevents service calls")
    ClassTrainerFrame.shown = true
    ClassTrainerFrame.IsShown = function() return true end
    GetNumTrainerServices = function() countApiCalls = countApiCalls + 1; return 2 end
    local open = S.collectors.forever70245Evidence()
    local trainer = open.trainer.lastObserved
    equal(trainer.state, "OBSERVED_OPEN_WINDOW", "trainer captured only in open context")
    equal(trainer.serviceCount, 2, "service count captured")
    equal(#trainer.services, 2, "service indices captured")
    equal(trainer.services[1].index, 1, "service index retained")
    equal(trainer.services[1].calls.info.returnCount, 6, "exact trainer tuple return count retained")
    equal(trainer.services[1].calls.info.returns[2].observation.value, "unavailable",
        "status text retained raw without interpretation")
    equal(trainer.services[1].calls.cost.returns[1].observation.value, 100, "raw cost retained")
    equal(trainer.services[1].calls.skillRequirement.returns[1].observation.state, "NIL",
        "nil requirement remains nil")
    equal(trainer.services[1].calls.skillRequirement.returnCount, 3, "nil-containing tuple shape retained")
    equal(#trainer.services[1].calls.abilityRequirements, 2, "ability requirement and nil terminator retained")
    equal(trainer.services[1].calls.abilityRequirements[1].returns[1].observation.value,
        "|cffff0000Prerequisite|r", "raw ability requirement retained")
    equal(trainer.services[1].calls.abilityRequirements[2].returns[1].observation.state,
        "NIL", "ability terminator recorded explicitly")
    equal(infoCalls, 2, "one info call per service")
    equal(abilityCalls, 3, "bounded ability requirement calls stop at nil")
    equal(countApiCalls, 2, "trainer count called only for observed open contexts")
    equal(trainer.apiAvailability.GetTrainerServiceType, "API_MISSING", "missing API explicit")
    equal(trainer.apiAvailability.IsTrainerServiceLearnable, "API_MISSING", "missing learnability API explicit")
    check(trainer.apiAvailability.GetTrainerServiceNumAbilityReq:find("NOT_CALLED", 1, true),
        "unvalidated service requirement count API not used")
    equal(closedMeta.completeness, "partial", "trainer closed capture remains partial")

    GetNumTrainerServices = function() return 1 end
    GetTrainerServiceInfo = function() error("synthetic service info failure") end
    GetTrainerServiceCost = function() return nil end
    local failedService = S.collectors.forever70245Evidence().trainer.lastObserved.services[1]
    equal(failedService.calls.info.state, "API_ERROR", "trainer info error captured")
    equal(failedService.calls.cost.state, "OBSERVED_VALUE", "nil cost call keeps its return tuple")
    equal(failedService.calls.cost.returns[1].observation.state, "NIL", "nil cost is not zero")

    GetTrainerServiceInfo = function(index) return "Synthetic " .. index, "raw-status", 123, 10, "Rank", "" end
    GetTrainerServiceCost = function() return 0 end
    GetTrainerServiceAbilityReq = function() return "Requirement", true end
    local limited = S.collectors.forever70245Evidence().trainer.lastObserved.services[1]
    equal(#limited.calls.abilityRequirements, 20, "requirement probing is bounded")
    equal(limited.requirementsTruncated, true, "safety limit is explicitly partial")

    local snapshot = S.GetSnapshot()
    snapshot.sections.forever70245Evidence = { data = open, completeness = "partial", observedAt = 123 }
    local export = S.Render(snapshot)
    check(not export:find("[FOREVER 70245 EVIDENCE]", 1, true), "legacy v1 export omits new raw section")
    check(export:find("[END]", 1, true), "legacy v1 export remains well formed")
    local rawSection = S.RenderSection("forever70245Evidence", snapshot)
    check(rawSection:find("skillLine\t2\t46\t6\tAxes\t22\t40\tfalse", 1, true),
        "structured evidence renderer retains skill index/id/name/rank/max/header: " .. (rawSection:match("skillLine\t2[^\n]*") or "no index-2 row"))
    check(rawSection:find("unavailable", 1, true), "structured evidence retains raw status text")
    check(rawSection:find("|cffff0000Prerequisite|r", 1, true), "raw rendering preserves exact color escape text")
    check(rawSection:find("trainer.1.abilityRequirement.argument\t2\t2", 1, true),
        "rendered requirement call retains service and requirement indices")
    check(rawSection:find("Raw runtime observations only", 1, true), "structured evidence disclaims unvalidated interpretation")

    C_SkillInfo, ClassTrainerFrame = oldSkill, oldFrame
    GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceCost = oldCount, oldInfo, oldCost
    GetTrainerServiceSkillReq, GetTrainerServiceAbilityReq, GetTrainerServiceNumAbilityReq = oldSkillReq, oldAbilityReq, oldAbilityCount
    GetTrainerServiceType, IsTrainerServiceLearnable = oldServiceType, oldLearnable
    return true
end
