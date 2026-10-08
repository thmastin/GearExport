-- Raw, read-only skill-line and trainer observations for Forever 1.60.1.70291.
local _, addon = ...
local S, F = addon.Sync, addon.Forever
local MAX_TRAINER_SERVICES, MAX_ABILITY_REQUIREMENTS = 200, 20
local unpackValues = unpack or table.unpack

local function public(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret ~= true
end

local function safeText(value)
    local ok, text = pcall(tostring, value)
    return ok and text or "<unprintable>"
end

local function apiStatus(fn)
    return type(fn) == "function" and "API_PRESENT" or "API_MISSING"
end

local function rawValue(value)
    if value == nil then return { state = "NIL", type = "nil" } end
    local kind = type(value)
    if not public(value) then return { state = "RESTRICTED", type = kind } end
    if kind == "string" or kind == "number" or kind == "boolean" then
        return { state = "OBSERVED", type = kind, value = value }
    end
    return { state = "UNSUPPORTED_VALUE_TYPE", type = kind }
end

local function call(fn, args)
    if type(fn) ~= "function" then return { state = "API_MISSING", provenance = "IN_GAME_RUNTIME_CALL" } end
    local function packed(...) return { n = select("#", ...), ... } end
    local ok, result = pcall(function() return packed(fn(unpackValues(args, 1, args.n or #args))) end)
    if not ok then
        return { state = "API_ERROR", error = safeText(result), provenance = "IN_GAME_RUNTIME_CALL" }
    end
    local returns = {}
    for i = 1, result.n do returns[i] = { index = i, observation = rawValue(result[i]) } end
    return { state = result.n > 0 and "OBSERVED_VALUE" or "ZERO_RETURNS",
        returnCount = result.n, returns = returns, _rawReturns = result,
        observedAt = S.Now(), provenance = "IN_GAME_RUNTIME_CALL" }
end

local function readSkillLines(data, issues)
    local api = type(C_SkillInfo) == "table" and C_SkillInfo or {}
    local countRow = call(api.GetNumSkillLines, { n = 0 })
    countRow.api, countRow.input = "C_SkillInfo.GetNumSkillLines", {}
    data.skillLineCount = countRow
    data.skillLineApiAvailability = {
        ["C_SkillInfo.GetNumSkillLines"] = apiStatus(api.GetNumSkillLines),
        ["C_SkillInfo.GetSkillLineInfo"] = apiStatus(api.GetSkillLineInfo),
    }
    local countObs = countRow.returns and countRow.returns[1] and countRow.returns[1].observation
    local count = countObs and countObs.state == "OBSERVED" and countObs.type == "number" and countObs.value
    if type(count) ~= "number" or count < 0 or count % 1 ~= 0 or count > 300 then
        issues[#issues + 1] = "Skill line count unavailable or outside safe bound"
        data.skillLines = {}
        data.skillLineCoverage = "UNKNOWN_COUNT"
        return
    end
    data.skillLineCountValue = count
    data.skillLines = {}
    local rowsOK = true
    for index = 1, count do
        local observed = call(api.GetSkillLineInfo, { n = 1, index })
        observed.api, observed.input = "C_SkillInfo.GetSkillLineInfo", { index = index }
        observed.returnShape = { count = observed.returnCount or 0, types = {} }
        local ret = observed.returns and observed.returns[1]
        if ret then observed.returnShape.types[1] = ret.observation.type end
        local row = { index = index, state = observed.state, api = observed.api,
            input = observed.input, returnCount = observed.returnCount,
            returnShape = observed.returnShape, returns = observed.returns,
            error = observed.error, provenance = observed.provenance }
        local result = observed._rawReturns and observed._rawReturns[1]
        if type(result) == "table" and public(result) then
            local fields, keys = {}, {}
            for key in pairs(result) do keys[#keys + 1] = key end
            table.sort(keys, function(a, b)
                local left, right = safeText(a), safeText(b)
                if left == right then return type(a) < type(b) end
                return left < right
            end)
            for _, key in ipairs(keys) do
                local fieldName = safeText(key)
                local valueOK, value = pcall(function() return result[key] end)
                fields[#fields + 1] = { key = fieldName, keyType = type(key),
                    observation = valueOK and rawValue(value) or { state = "API_ERROR", type = "unknown" } }
                if fieldName == "skillID" or fieldName == "skillLineCategoryID" or fieldName == "rank"
                    or fieldName == "maxRank" or fieldName == "isHeader" or fieldName == "name" then
                    local v = valueOK and rawValue(value)
                    if v and v.state == "OBSERVED" then row[fieldName] = v.value end
                end
            end
            row.rawFields = fields
        else
            rowsOK = false
            issues[#issues + 1] = "Skill line " .. index .. " result unavailable"
            if observed.state == "API_ERROR" then row.state, row.error = "API_ERROR", observed.error
            elseif observed.state == "API_MISSING" then row.state = "API_MISSING"
            elseif ret and ret.observation.state == "NIL" then row.state = "NIL_RESULT"
            else row.state = "RESTRICTED_OR_UNSUPPORTED_RESULT" end
        end
        data.skillLines[#data.skillLines + 1] = row
    end
    data.skillLineCoverage = rowsOK and "OBSERVED_INDEXED_ROWS" or "PARTIAL_INDEXED_ROWS"
end

local function trainerFrame()
    local sawFrame, visibilityError = false, false
    for _, name in ipairs({ "ClassTrainerFrame", "TrainerFrame", "ClassTrainerFrameSkillStep" }) do
        local frame = _G[name]
        if frame and type(frame.IsShown) == "function" then
            sawFrame = true
            local ok, shown = pcall(frame.IsShown, frame)
            if ok and shown == true then return name, "OBSERVED_OPEN" end
            if not ok or type(shown) ~= "boolean" then visibilityError = true end
        end
    end
    if visibilityError then return nil, "UNKNOWN_FRAME_VISIBILITY" end
    if sawFrame then return nil, "NOT_OBSERVED_WINDOW_CLOSED" end
    return nil, "NOT_OBSERVED_FRAME_UNAVAILABLE"
end

local function observeTrainer(previous, issues)
    local frameName, frameState = trainerFrame()
    if not frameName then
        return { state = frameState, provenance = "IN_GAME_RUNTIME_CONTEXT",
            lastObserved = previous and previous.lastObserved or nil }
    end
    local observation = { state = "OBSERVED_OPEN_WINDOW", frame = frameName,
        capturedAt = S.Now(), provenance = "IN_GAME_RUNTIME_CALL", serviceCount = nil,
        apiAvailability = {}, services = {} }
    local function record(apiName, fn, args, context)
        local result = call(fn, args)
        local arguments = {}
        for i = 1, args.n or #args do arguments[i] = args[i] end
        result.api, result.input, result.context = apiName,
            { argumentCount = args.n or #args, arguments = arguments }, context
        return result
    end
    local count = record("GetNumTrainerServices", GetNumTrainerServices, { n = 0 }, { frame = frameName })
    observation.serviceCountResult = count
    local countObs = count.returns and count.returns[1] and count.returns[1].observation
    local total = countObs and countObs.state == "OBSERVED" and countObs.type == "number" and countObs.value
    if type(total) ~= "number" or total < 0 or total % 1 ~= 0 or total > MAX_TRAINER_SERVICES then
        observation.state, observation.coverage = "PARTIAL_INVALID_SERVICE_COUNT", "UNKNOWN_SERVICE_COUNT"
        issues[#issues + 1] = "Trainer service count unavailable or outside safe bound"
        observation.apiAvailability.GetNumTrainerServices = apiStatus(GetNumTrainerServices)
        return { state = observation.state, lastObserved = previous and previous.lastObserved or nil,
            attempted = observation, provenance = "IN_GAME_RUNTIME_CONTEXT" }
    end
    observation.serviceCount = total
    observation.coverage = "OBSERVED_SERVICE_INDEXES"
    observation.requirementCoverage = "RAW_INDEXED_CALLS; NO TOTAL-REQUIREMENT SEMANTICS ASSUMED"
    issues[#issues + 1] = "Trainer requirement observation is raw and partial; total prerequisite semantics are unvalidated"
    observation.apiAvailability = {
        GetTrainerServiceInfo = apiStatus(GetTrainerServiceInfo),
        GetTrainerServiceCost = apiStatus(GetTrainerServiceCost),
        GetTrainerServiceSkillReq = apiStatus(GetTrainerServiceSkillReq),
        GetTrainerServiceAbilityReq = apiStatus(GetTrainerServiceAbilityReq),
        GetTrainerServiceNumAbilityReq = apiStatus(GetTrainerServiceNumAbilityReq)
            .. "; NOT_CALLED_SEMANTICS_UNVALIDATED",
        GetTrainerServiceType = apiStatus(GetTrainerServiceType),
        IsTrainerServiceLearnable = apiStatus(IsTrainerServiceLearnable),
    }
    local rowsComplete = true
    for serviceIndex = 1, total do
        if trainerFrame() ~= frameName then
            observation.state, observation.coverage = "PARTIAL_WINDOW_CLOSED", "TRAINER_WINDOW_CLOSED_DURING_CAPTURE"
            rowsComplete = false
            issues[#issues + 1] = "Trainer window closed during service enumeration"
            break
        end
        local context = { frame = frameName, serviceIndex = serviceIndex,
            note = "Raw observation only; no purchase or learning action" }
        local service = { index = serviceIndex, provenance = "IN_GAME_RUNTIME_CALL", calls = {} }
        service.calls.info = record("GetTrainerServiceInfo", GetTrainerServiceInfo,
            { n = 1, serviceIndex }, context)
        service.calls.cost = record("GetTrainerServiceCost", GetTrainerServiceCost,
            { n = 1, serviceIndex }, context)
        service.calls.skillRequirement = record("GetTrainerServiceSkillReq", GetTrainerServiceSkillReq,
            { n = 1, serviceIndex }, context)
        if service.calls.info.state == "API_MISSING" or service.calls.info.state == "API_ERROR"
            or service.calls.cost.state == "API_MISSING" or service.calls.cost.state == "API_ERROR" then
            rowsComplete = false
            issues[#issues + 1] = "Trainer service " .. serviceIndex .. " info or cost unavailable"
        end
        if service.calls.skillRequirement.state == "API_MISSING" or service.calls.skillRequirement.state == "API_ERROR" then
            rowsComplete = false
            issues[#issues + 1] = "Trainer skill requirement call unavailable for " .. serviceIndex
        end
        service.calls.abilityRequirements = {}
        for requirementIndex = 1, MAX_ABILITY_REQUIREMENTS do
            if trainerFrame() ~= frameName then
                observation.state, observation.coverage = "PARTIAL_WINDOW_CLOSED", "TRAINER_WINDOW_CLOSED_DURING_CAPTURE"
                rowsComplete = false
                issues[#issues + 1] = "Trainer window closed during requirement enumeration"
                break
            end
            local requirement = record("GetTrainerServiceAbilityReq", GetTrainerServiceAbilityReq,
                { n = 2, serviceIndex, requirementIndex }, { frame = frameName,
                    serviceIndex = serviceIndex, requirementIndex = requirementIndex })
            service.calls.abilityRequirements[#service.calls.abilityRequirements + 1] = requirement
            local first = requirement.returns and requirement.returns[1] and requirement.returns[1].observation
            if requirement.state == "API_MISSING" or requirement.state == "API_ERROR"
                then rowsComplete = false; issues[#issues + 1] = "Trainer ability requirement call unavailable for " .. serviceIndex; break end
            if first and first.state == "NIL" then break end
            if requirementIndex == MAX_ABILITY_REQUIREMENTS then
                service.requirementsTruncated = true
                rowsComplete = false
                issues[#issues + 1] = "Trainer service " .. serviceIndex .. " requirement probe reached safe limit"
            end
        end
        observation.services[#observation.services + 1] = service
    end
    if not rowsComplete and observation.state == "OBSERVED_OPEN_WINDOW" then
        observation.coverage = "PARTIAL_SERVICE_ROWS"
    end
    return { state = observation.state, lastObserved = observation,
        provenance = "IN_GAME_RUNTIME_CONTEXT" }
end

S.collectors.forever70291Evidence = function()
    local issues = {}
    local data = { client = { family = "Forever", version = F.version, build = F.build,
        interface = F.interface }, capturedAt = S.Now(), provenance = "IN_GAME_RUNTIME_CALL",
        clientBuildInfo = call(GetBuildInfo, { n = 0 }), unknowns = {
            transferability = "UNKNOWN_UNVALIDATED",
            generalEquipability = "UNKNOWN_UNVALIDATED",
            professionEquipRestrictions = "UNKNOWN_UNVALIDATED",
            bindingSemantics = "UNKNOWN_UNVALIDATED",
            effectiveEquipmentStats = "UNKNOWN_UNVALIDATED",
            talentBuildInterpretation = "UNKNOWN_UNVALIDATED",
            weaponReadiness = "UNKNOWN_UNVALIDATED",
        } }
    readSkillLines(data, issues)
    local oldSection = S.record and S.record.sections and S.record.sections.forever70291Evidence
    local priorTrainer = oldSection and oldSection.data and oldSection.data.trainer
    data.trainer = observeTrainer(priorTrainer, issues)
    if data.trainer.state ~= "OBSERVED_OPEN_WINDOW" then
        issues[#issues + 1] = "Trainer service observations not refreshed; no supported trainer window was observed open"
    end
    table.sort(issues)
    return data, { completeness = #issues == 0 and "complete" or "partial",
        reason = #issues > 0 and table.concat(issues, "; ") or nil,
        source = "Forever 70291 read-only runtime evidence; API tuple contracts carried forward from 70245 pending live comparison" }
end

-- Collector refreshes on API change events and trainer-window events. It does
-- not open UI or invoke trainer service interaction functions.
local eventFrame = CreateFrame("Frame")
for _, event in ipairs({ "SKILL_LINES_CHANGED", "TRAINER_SHOW", "TRAINER_UPDATE",
    "TRAINER_DESCRIPTION_UPDATE", "TRAINER_SERVICE_INFO_NAME_UPDATE", "TRAINER_CLOSED" }) do
    eventFrame:RegisterEvent(event)
end
eventFrame:SetScript("OnEvent", function(_, event)
    if F and WoWSyncCompat and WoWSyncCompat.IsForever() and S.collectors.forever70291Evidence then
        S.Mark("forever70291Evidence")
    end
end)
