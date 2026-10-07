return function(S, check, equal, advance, event, addon)
    local oldAPI, oldClass, oldRetail = C_SpecializationInfo, UnitClass, WoWSyncCompat.IsRetail
    local oldEquipment = S.Copy(S.record.sections.equipment)
    local oldCandidates, oldLatest = S.Copy(S.record.gearCandidates), S.Copy(S.record.latestExport)
    local oldDirty, oldCapture = S.dirty, S.capture
    local oldLink = GetInventoryItemLink
    local oldItemInfo = C_Item.GetItemInfo
    local reads, roster, ready, ids, trace = 0, {}, true, { 253, 253 }, {}
    local function installAPI()
        reads = 0
        C_SpecializationInfo = {
            IsInitialized = function() trace[#trace + 1] = "ready"; return ready end,
            GetNumSpecializationsForClassID = function(classID)
                equal(classID, 3, "roster uses player class ID")
                return #roster
            end,
            GetSpecialization = function()
                reads = reads + 1; trace[#trace + 1] = "active-" .. reads
                return reads, ids[reads]
            end,
            GetSpecializationInfo = function(index, _, _, _, _, _, classID)
                if classID then
                    trace[#trace + 1] = "roster-" .. index
                    local row = roster[index]
                    if not row then return nil end
                    return row.id, row.name, nil, nil, row.role, row.primary, nil, nil, nil, row.unlocked
                end
                trace[#trace + 1] = "active-info-" .. index
                local id = ids[reads]
                return id, id and ("Spec " .. id), nil, nil, "DAMAGER", 2, nil, nil, nil, nil
            end,
        }
    end
    local function setup(isReady, specIDs, rows)
        ready, ids, roster, trace = isReady, specIDs, rows, {}
        installAPI()
    end
    UnitClass = function() return "Hunter", "HUNTER", 3 end
    WoWSyncCompat.IsRetail = function() return true end
    roster = {
        { id = 253, name = "Beast Mastery", role = "DAMAGER", primary = 2, unlocked = true },
        { id = 254, name = "Marksmanship", role = "DAMAGER", primary = 2 },
        { id = 255, name = "Survival", role = "DAMAGER", primary = 2, unlocked = false },
    }
    setup(true, { 253, 253 }, roster)
    GetInventoryItemLink = function(unit, slot)
        if slot == 1 and not trace.scan then trace.scan = true; trace[#trace + 1] = "equipment-scan" end
        return oldLink(unit, slot)
    end
    local data, meta = S.collectors.equipment()
    check(data and data.slots, "equipment scan succeeds with specialization evidence")
    local obs = meta.specEquipmentObservation
    equal(obs.stability, "STABLE", "ready matching specIDs are stable")
    equal(obs.activeSpecBefore.specID, 253, "specID preserved as identity")
    equal(obs.roster.specializations[2].specID, 254, "Hunter roster includes specID 254")
    equal(obs.roster.specializations[3].specID, 255, "Hunter roster includes specID 255")
    equal(obs.roster.specializations[2].index, 2, "index retained as provenance")
    equal(obs.roster.specializations[2].isUnlocked, nil, "nil metadata stays absent")
    equal(obs.roster.specializations[3].isUnlocked, false, "explicit false remains false")
    equal(obs.atomicity, "NOT_CLAIMED", "stable does not claim atomicity")
    local scanPos, afterPos
    local beforePos
    for i, value in ipairs(trace) do
        if value == "equipment-scan" then scanPos = i end
        if value == "active-1" then beforePos = i end
        if value == "active-2" then afterPos = i end
    end
    check(beforePos and scanPos and afterPos and beforePos < scanPos and scanPos < afterPos,
        "active spec bracket surrounds equipment scan")

    setup(true, { 253, 254 }, roster)
    _, meta = S.collectors.equipment()
    equal(meta.specEquipmentObservation.stability, "UNSTABLE", "different specIDs are unstable")
    setup(false, { 253, 253 }, roster)
    _, meta = S.collectors.equipment()
    equal(meta.specEquipmentObservation.stability, "NOT_READY", "explicit uninitialized state is NOT_READY")
    equal(meta.specEquipmentObservation.roster.specializations, nil, "not-ready roster is not fabricated empty")
    setup(true, { 253, nil }, roster)
    _, meta = S.collectors.equipment()
    equal(meta.specEquipmentObservation.stability, "UNKNOWN", "missing after specID is UNKNOWN")
    setup(nil, { 253, 253 }, roster)
    _, meta = S.collectors.equipment()
    equal(meta.specEquipmentObservation.stability, "UNKNOWN", "unknown readiness is not stable")
    C_SpecializationInfo.GetSpecializationInfo = function() error("spec API unavailable") end
    _, meta = S.collectors.equipment()
    equal(meta.specEquipmentObservation.stability, "UNKNOWN", "throwing spec API does not abort equipment")
    C_SpecializationInfo.GetSpecializationInfo = nil
    _, meta = S.collectors.equipment()
    equal(meta.specEquipmentObservation.stability, "UNKNOWN", "missing spec API is unknown")
    equal(data.slots[1].itemID, 240001, "equipment remains independent of spec API")

    -- Each direct equipment retry is a new scan and gets two fresh active reads.
    setup(true, { 253, 253, 254, 254 }, roster)
    local _, retryOne = S.collectors.equipment()
    local firstReads = reads
    local _, retryTwo = S.collectors.equipment()
    equal(firstReads, 2, "first equipment observation has a fresh bracket")
    equal(reads, 4, "second equipment retry has a new before/after bracket")
    equal(retryOne.specEquipmentObservation.activeSpecBefore.specID, 253, "first retry evidence independent")
    equal(retryTwo.specEquipmentObservation.activeSpecBefore.specID, 254, "second retry re-reads active spec")

    -- Exercise the actual bounded Process retry scheduler while item metadata
    -- is unresolved; every invocation must re-read both sides of the bracket.
    setup(true, { 253, 253, 254, 254, 255, 255, 255, 255, 255, 255 }, roster)
    local cachedItemInfo = C_Item.GetItemInfo
    C_Item.GetItemInfo = function() return nil end
    S.dirty = {}
    S.Mark("equipment", 0)
    advance(4)
    equal(reads, 10, "initial scan plus four actual equipment retries each bracketed")
    equal(S.record.sections.equipment.specEquipmentObservation.activeSpecBefore.specID, 255,
        "last retry records the spec active for its own scan")
    equal(S.record.sections.equipment.specEquipmentObservation.activeSpecAfter.specID, 255,
        "last retry records its own after spec")
    C_Item.GetItemInfo = cachedItemInfo

    -- A candidate-only capture cannot invoke the equipment/spec bracket.
    setup(true, { 253, 253 }, roster)
    local beforeCandidate = reads
    local candidateData, candidateMeta = S.collectors.gearCandidates()
    check(candidateData ~= nil or candidateMeta.retry, "candidate-only collector remains independent")
    equal(reads, beforeCandidate, "gear-candidate-only attempt does not read active spec")

    -- Commit equipment and evidence to one envelope; projection is from that envelope.
    S.dirty = {}
    S.record.sections.equipment = S.Copy(oldEquipment)
    S.record.gearCandidates = S.Copy(oldCandidates)
    S.record.latestExport = S.Copy(oldLatest)
    setup(true, { 253, 253 }, roster)
    S.Mark("equipment", 0)
    S.Process(true)
    local e1 = S.record.sections.equipment
    local s1 = e1.specEquipmentObservation
    check(s1 ~= nil, "committed equipment envelope owns sidecar")
    equal(s1.equipmentObservation.observedAt, e1.observedAt, "exact observedAt link")
    equal(s1.equipmentObservation.capture, e1.capture, "exact capture link")
    equal(s1.equipmentObservation.revision, e1.revision, "exact revision link")
    local snapshot = S.GetSnapshot()
    check(snapshot.specEquipmentObservation ~= nil, "Retail snapshot projects linked evidence")
    check(snapshot.gearCandidates ~= nil, "candidate evidence also survives snapshot")
    local noSpec = S.Copy(snapshot); noSpec.specEquipmentObservation = nil
    equal(S.Render(snapshot), S.Render(noSpec), "spec evidence is not rendered as text")
    check(S.Render(snapshot):find("[GEAR CANDIDATES]", 1, true) ~= nil, "candidate text remains rendered")

    -- Export uses same projection and keeps candidate text. Logout regenerates it.
    local callbackText
    S.Export(function(text) callbackText = text end)
    advance(4)
    check(callbackText and callbackText:find("[GEAR CANDIDATES]", 1, true), "normal export retains candidate output")
    check(S.record.latestExport.specEquipmentObservation ~= nil, "latestExport stores structured projection")
    check(not S.record.latestExport.text:find("SPEC EQUIPMENT", 1, true), "text has no spec-equipment section")
    local latest = S.record.latestExport
    local equipmentTuple = S.Copy(S.record.sections.equipment.specEquipmentObservation.equipmentObservation)
    advance(1)
    event("PLAYER_LOGOUT")
    check(S.record.latestExport.generatedAt > latest.generatedAt, "logout refreshes generatedAt")
    equal(S.record.sections.equipment.observedAt, equipmentTuple.observedAt, "logout keeps equipment observation")
    equal(S.record.sections.equipment.capture, equipmentTuple.capture, "logout keeps equipment capture")
    equal(S.record.sections.equipment.revision, equipmentTuple.revision, "logout keeps equipment revision")
    check(S.record.latestExport.specEquipmentObservation ~= nil, "logout retains projection")
    equal(S.record.latestExport.specEquipmentObservation.equipmentObservation.capture, equipmentTuple.capture,
        "logout projection points to same equipment envelope")
    check(S.record.latestExport.text:find("[GEAR CANDIDATES]", 1, true), "logout refresh retains candidate text")

    -- Exact tuple validation rejects mismatches and never repairs them.
    local valid = S.Copy(S.record.sections.equipment.specEquipmentObservation)
    local currentBeforeFailure = S.Copy(S.record.sections.equipment)
    for _, key in ipairs({ "observedAt", "capture", "revision" }) do
        local value = S.record.sections.equipment.specEquipmentObservation.equipmentObservation[key]
        S.record.sections.equipment.specEquipmentObservation.equipmentObservation[key] = value + 1
        equal(S.GetSnapshot().specEquipmentObservation, nil, "mismatched " .. key .. " is rejected")
        S.record.sections.equipment.specEquipmentObservation.equipmentObservation[key] = value
    end
    S.record.sections.equipment.specEquipmentObservation = valid

    -- Failed attempts retain current envelope; successful evidence-free scans replace it.
    local oldCollector = S.collectors.equipment
    S.collectors.equipment = function() return nil, { reason = "scan failed", retry = true } end
    S.Mark("equipment", 0); S.Process(true)
    equal(S.record.sections.equipment.specEquipmentObservation.equipmentObservation.capture, currentBeforeFailure.capture,
        "failed scan retains current evidence")
    event("PLAYER_LOGOUT")
    check(S.record.latestExport.specEquipmentObservation ~= nil, "refresh after failed attempt still projects current evidence")
    S.collectors.equipment = function() return S.Copy(e1.data), { completeness = "partial" } end
    S.Mark("equipment", 0); S.Process(true)
    local e2 = S.record.sections.equipment
    equal(e2.completeness, "partial", "partial observation semantics are retained")
    equal(e2.specEquipmentObservation, nil, "new evidence-free scan does not inherit old sidecar")
    equal(S.GetSnapshot().specEquipmentObservation, nil, "new envelope has no projected old evidence")
    S.collectors.equipment = oldCollector

    -- Evidence can describe a legitimately committed partial scan without
    -- changing the completeness label or declaring baseline authority.
    setup(true, { 253, 253 }, roster)
    local partialData, partialMeta = S.collectors.equipment()
    partialMeta.completeness = "partial"
    S.collectors.equipment = function() return partialData, partialMeta end
    S.Mark("equipment", 0); S.Process(true)
    check(S.record.sections.equipment.specEquipmentObservation ~= nil, "co-observation may attach to partial envelope")
    equal(S.record.sections.equipment.completeness, "partial", "sidecar does not promote partial completeness")
    S.collectors.equipment = oldCollector

    WoWSyncCompat.IsRetail = function() return false end
    equal(S.GetSnapshot().specEquipmentObservation, nil, "non-Retail snapshot does not project evidence")
    event("PLAYER_LOGOUT")
    equal(S.record.latestExport.specEquipmentObservation, nil, "non-Retail export refresh does not project Retail evidence")
    local retailSnapshot = S.GetSnapshot()
    WoWSyncCompat.IsRetail = function() return true end
    event("PLAYER_LOGOUT")
    S.record.sections.equipment = currentBeforeFailure
    local persistenceSnapshot = S.GetSnapshot()
    local persistenceObservation = persistenceSnapshot.specEquipmentObservation
    check(persistenceObservation ~= nil, "valid record available for persistence/reinitialization")
    local function plain(value, seen)
        local kind = type(value)
        if kind ~= "table" then return kind == "nil" or kind == "string" or kind == "number" or kind == "boolean" end
        if seen[value] then return false end
        seen[value] = true
        for key, child in pairs(value) do
            if type(key) ~= "string" and type(key) ~= "number" then return false end
            if not plain(child, seen) then return false end
        end
        seen[value] = nil
        return true
    end
    check(plain(persistenceObservation, {}), "sidecar contains plain SavedVariables-safe data")
    S.record.latestExport = { text = S.Render(persistenceSnapshot), generatedAt = persistenceSnapshot.generatedAt,
        specEquipmentObservation = S.Copy(persistenceObservation) }
    equal(retailSnapshot.specEquipmentObservation, nil, "non-Retail projection remains absent")
    WoWSyncCompat.IsRetail, C_SpecializationInfo, UnitClass = oldRetail, oldAPI, oldClass
    GetInventoryItemLink, C_Item.GetItemInfo = oldLink, oldItemInfo
    S.record.gearCandidates = oldCandidates
    S.dirty, S.capture = oldDirty, oldCapture
end
