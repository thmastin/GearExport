-- Structured Forever trainer capture uses the corroborated service tuple.
return function(S, check, equal, advance)
    local names = { "ClassTrainerFrame", "TrainerFrame", "ClassTrainerFrameTitleText", "TrainerFrameTitleText",
        "GetNumTrainerServices", "GetTrainerServiceInfo", "GetTrainerServiceCost", "GetTrainerServiceLevelReq",
        "GetTrainerServiceSkillReq", "IsTradeskillTrainer", "UnitClass", "GetServerTime" }
    local old = {}; for _, name in ipairs(names) do old[name] = _G[name] end
    local open = true
    ClassTrainerFrame = { IsShown = function() return open end }
    ClassTrainerFrameTitleText = { GetText = function() return "Gretta Finespindle" end }
    GetNumTrainerServices = function() return 4 end
    GetTrainerServiceInfo = function(i)
        if i == 1 then return "Leatherworking", "header", 136241, 0, "", "Leatherworking" end
        if i == 2 then return "Camp Tent", "available", 134250, 0, "Tier 1", "Camping" end
        if i == 3 then return "Embossed Leather Gloves", "known", 135608, 20, "Apprentice", "Leatherworking" end
        return "Odd Service", "client-new-status", 135999, 30, "Tier X", "Camping"
    end
    GetTrainerServiceCost = function(i) return i == 3 and 150 or 0 end
    GetTrainerServiceLevelReq = function(i) return i == 3 and 18 or nil end
    GetTrainerServiceSkillReq = function() return "Leatherworking", 100, true end
    IsTradeskillTrainer = function() return true end
    UnitClass = function() return "Druid", "DRUID" end
    GetServerTime = function() return 1730937600 end
    local captured, meta = S.collectors.trainer()
    equal(captured.category, "Gretta Finespindle", "visit keyed by trainer name")
    equal(captured.snapshot.name, "Gretta Finespindle", "trainer name captured")
    equal(captured.snapshot.type, "profession", "profession trainer typed")
    equal(captured.snapshot.professionName, "Leatherworking", "profession name captured")
    equal(captured.snapshot.capturedAt, 1730937600, "trainer observation timestamp captured")
    equal(#captured.snapshot.services, 3, "header skipped and all service rows retained")
    equal(captured.snapshot.services[1].name, "Camp Tent", "Forever six-value tuple name captured")
    equal(captured.snapshot.services[1].status, "available", "status read from tuple position two")
    equal(captured.snapshot.services[1].icon, 134250, "icon read from tuple position three")
    equal(captured.snapshot.services[1].requiredLevel, 0, "numeric tuple level is fallback when level API is unavailable")
    equal(captured.snapshot.services[1].rank, "Tier 1", "rank read from tuple position five")
    equal(captured.snapshot.services[1].category, "Camping", "category read from tuple position six")
    equal(captured.snapshot.services[2].name, "Embossed Leather Gloves", "Leatherworking service captured")
    equal(captured.snapshot.services[2].status, "used", "known status maps to used")
    equal(captured.snapshot.services[2].rawStatus, "known", "source status retained")
    equal(captured.snapshot.services[2].rank, "Apprentice", "Leatherworking rank captured")
    equal(captured.snapshot.services[2].costCopper, 150, "Leatherworking service cost captured in copper")
    equal(captured.snapshot.services[2].requiredLevel, 18, "numeric required-level API result takes precedence")
    equal(captured.snapshot.services[2].requiredSkill.name, "Leatherworking", "required skill captured")
    equal(captured.snapshot.services[2].requiredSkill.rank, 100, "required skill rank captured")
    equal(captured.snapshot.services[3].status, "unknown", "unrecognized status row retained as unknown")
    equal(captured.snapshot.services[3].rawStatus, "client-new-status", "unrecognized raw status preserved")
    equal(captured.snapshot.droppedRowCount, 0, "no parseable service row counted as dropped")
    check(meta.completeness == "complete", "structured trainer visit complete")

    S.CommitTrainer(captured.category, captured.snapshot, meta)
    equal(S.record.sections.trainer.data.snapshots["Gretta Finespindle"].services[2].costCopper,
        150, "latest trainer visit saved under trainer name")
    ClassTrainerFrameTitleText.GetText = function() return "Ironforge Druid Trainer" end
    IsTradeskillTrainer = function() return false end
    GetNumTrainerServices = function() return 1 end
    GetTrainerServiceInfo = function() return "Bear Form", "available", 135276, 10, "Rank 1", "Druid" end
    GetTrainerServiceCost = function() return 100 end
    GetTrainerServiceSkillReq = function() return nil end
    local classVisit = S.collectors.trainer()
    equal(classVisit.snapshot.type, "class", "class trainer typed")
    equal(classVisit.snapshot.className, "Druid", "class name captured")

    GetNumTrainerServices = function() return 2 end
    GetTrainerServiceInfo = function() return nil, nil end
    local unparseable, partialMeta = S.collectors.trainer()
    equal(#unparseable.snapshot.services, 0, "all invalid rows yield no fabricated service")
    equal(unparseable.snapshot.droppedRowCount, 2, "all invalid rows counted as dropped")
    equal(partialMeta.completeness, "partial", "nonzero service count with no parseable rows is partial")
    check(partialMeta.reason and partialMeta.reason ~= "", "unparseable service list includes a reason")

    S.trainerOpen = false
    for key in pairs(S.dirty) do S.dirty[key] = nil end
    S.RequestSync()
    check(S.trainerOpen, "refresh notices trainer window still open")
    check(S.dirty.trainer ~= nil, "refresh schedules trainer recapture")
    open = false
    for key in pairs(S.dirty) do S.dirty[key] = nil end
    S.trainerOpen = false
    for _, name in ipairs(names) do _G[name] = old[name] end
end
