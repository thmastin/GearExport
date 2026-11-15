-- Structured Forever trainer capture uses the corroborated service tuple.
return function(S, check, equal, advance)
    local names = { "ClassTrainerFrame", "TrainerFrame", "ClassTrainerFrameTitleText", "TrainerFrameTitleText",
        "GetNumTrainerServices", "GetTrainerServiceInfo", "GetTrainerServiceCost", "GetTrainerServiceLevelReq",
        "GetTrainerServiceSkillReq", "IsTradeskillTrainer", "UnitClass", "GetServerTime" }
    local old = {}; for _, name in ipairs(names) do old[name] = _G[name] end
    local open = true
    ClassTrainerFrame = { IsShown = function() return open end }
    ClassTrainerFrameTitleText = { GetText = function() return "Gretta Finespindle" end }
    GetNumTrainerServices = function() return 3 end
    GetTrainerServiceInfo = function(i)
        if i == 1 then return "Leatherworking", "", "header", true end
        if i == 2 then return "Embossed Leather Gloves", "", "available", false end
        return "Cured Light Hide", "", "used", false
    end
    GetTrainerServiceCost = function(i) return i == 2 and 150 or 50 end
    GetTrainerServiceLevelReq = function() return 10 end
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
    equal(#captured.snapshot.services, 2, "header rows skipped")
    equal(captured.snapshot.services[1].name, "Embossed Leather Gloves", "first service captured")
    equal(captured.snapshot.services[1].costCopper, 150, "service cost captured in copper")
    equal(captured.snapshot.services[1].status, "available", "available status captured")
    equal(captured.snapshot.services[1].requiredSkill.name, "Leatherworking", "required skill captured")
    equal(captured.snapshot.services[1].requiredSkill.rank, 100, "required skill rank captured")
    equal(captured.snapshot.services[2].status, "used", "used status captured")
    check(meta.completeness == "complete", "structured trainer visit complete")

    S.CommitTrainer(captured.category, captured.snapshot, meta)
    equal(S.record.sections.trainer.data.snapshots["Gretta Finespindle"].services[2].costCopper,
        50, "latest trainer visit saved under trainer name")
    ClassTrainerFrameTitleText.GetText = function() return "Ironforge Druid Trainer" end
    IsTradeskillTrainer = function() return false end
    GetNumTrainerServices = function() return 1 end
    GetTrainerServiceInfo = function() return "Bear Form", "", "available", false end
    GetTrainerServiceCost = function() return 100 end
    GetTrainerServiceSkillReq = function() return nil end
    local classVisit = S.collectors.trainer()
    equal(classVisit.snapshot.type, "class", "class trainer typed")
    equal(classVisit.snapshot.className, "Druid", "class name captured")

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
