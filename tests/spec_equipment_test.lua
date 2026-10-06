return function(S, check, equal, advance, event)
  local oldSpecAPI, oldClass, oldLink, oldRetail = C_SpecializationInfo, UnitClass, GetInventoryItemLink, WoWSyncCompat.IsRetail
  local oldItemInfo = C_Item.GetItemInfo
  local originalEquipmentSection = S.Copy(S.record.sections.equipment)
  local originalLatestExport = S.Copy(S.record.latestExport)
  local activeIDs, activeRead, rosterRows, ready, trace = {}, 0, {}, true, {}

  UnitClass = function() return "Shaman", "SHAMAN", 7 end
  WoWSyncCompat.IsRetail = function() return true end
  local function installAPI()
    activeRead = 0
    C_SpecializationInfo = {
      IsInitialized = function() trace[#trace + 1] = "ready"; return ready end,
      GetNumSpecializationsForClassID = function(classID)
        equal(classID, 7, "class ID used to enumerate roster")
        trace[#trace + 1] = "roster-count"
        return #rosterRows
      end,
      GetSpecialization = function()
        activeRead = activeRead + 1
        trace[#trace + 1] = "active-index-" .. activeRead
        return activeRead, activeIDs[activeRead] and 1 or nil
      end,
      GetSpecializationInfo = function(index, _, _, _, _, _, classID)
        if classID then
          trace[#trace + 1] = "roster-info-" .. index
          local row = rosterRows[index]
          if not row then return nil end
          return row.specID, row.name, nil, nil, row.role, row.primaryStat, nil, nil, nil, row.isUnlocked
        end
        trace[#trace + 1] = "active-info-" .. activeRead
        local specID = activeIDs[activeRead]
        if not specID then return nil end
        return specID, "Active " .. specID, nil, nil, "DAMAGER", 2, 0, nil, 0, nil
      end,
    }
  end
  local function configure(ids, isReady, rows)
    activeIDs, ready, rosterRows = ids, isReady, rows
    trace, activeRead = {}, 0
    installAPI()
  end
  GetInventoryItemLink = function(unit, slot)
    if slot == 1 and not trace.equipmentMarked then
      trace.equipmentMarked = true
      trace[#trace + 1] = "equipment-scan"
    end
    return oldLink(unit, slot)
  end
  local function collect()
    trace, activeRead = {}, 0
    local data, meta = S.collectors.equipment()
    check(data and data.slots, "equipment remains available with spec evidence"); return data, meta
  end

  configure({ 253, 253 }, true, {
    { specID = 253, name = "Beast Mastery", role = "DAMAGER", primaryStat = 2, isUnlocked = true },
    { specID = 254, name = "Marksmanship", role = "DAMAGER", primaryStat = 2 },
    { specID = 255, name = "Survival", role = "DAMAGER", primaryStat = 2, isUnlocked = false },
  })
  local data, meta = collect()
  local observation = meta.specEquipmentObservation
  equal(observation.stability, "STABLE", "matching known active spec brackets are stable")
  equal(observation.activeSpecBefore.specID, 253, "before specID captured")
  equal(observation.activeSpecAfter.specID, 253, "after specID captured")
  equal(observation.roster.state, "OBSERVED", "initialized roster observed")
  equal(#observation.roster.specializations, 3, "full roster enumerated")
  equal(observation.roster.specializations[2].specID, 254, "specID retained independently")
  equal(observation.roster.specializations[2].index, 2, "specialization index retained as provenance")
  equal(observation.roster.specializations[2].isUnlocked, nil, "nil isUnlocked stays absent")
  equal(observation.roster.specializations[3].isUnlocked, false, "explicit false is preserved")
  equal(observation.roster.specializations[1].primaryStat, 2, "primary stat preserved")
  equal(S.record.sections.combatSpecialization.data.activeSpec.specID, 263,
    "existing generic combat sidecar remains separate")
  equal(observation.activeSpecBefore.specID, 253,
    "co-observation uses this equipment call, not generic carried combat state")
  equal(data.slots[1].itemID, 240001, "equipment item record unchanged")
  local lastEquip, afterRead
  for i, step in ipairs(trace) do
    if step == "equipment-scan" then lastEquip = i end
    if step == "active-index-2" then afterRead = i end
  end
  check(trace[1] == "ready" and trace[2] == "roster-count" and trace[3] == "roster-info-1",
    "readiness and roster precede active-spec bracket")
  check(lastEquip and afterRead and lastEquip < afterRead, "after-spec read follows completed equipment scan")
  equal(observation.atomicity, "NOT_CLAIMED", "stable bracket does not claim atomicity")

  configure({ 253, 254 }, true, rosterRows)
  _, meta = collect()
  equal(meta.specEquipmentObservation.stability, "UNSTABLE", "different before/after spec is unstable")
  check(meta.specEquipmentObservation.stability ~= "STABLE", "spec change never represented as stable")

  configure({ 253, 253 }, false, rosterRows)
  data, meta = collect()
  equal(meta.specEquipmentObservation.stability, "NOT_READY", "uninitialized specialization is not ready")
  equal(meta.specEquipmentObservation.roster.state, "NOT_READY", "unready roster is not an observed empty list")
  equal(meta.specEquipmentObservation.roster.specializations, nil, "unready roster has no fabricated rows")
  check(data.slots[1], "equipment still collects when specialization API is not initialized")

  configure({ 253, nil }, true, rosterRows)
  _, meta = collect()
  equal(meta.specEquipmentObservation.stability, "UNKNOWN", "unknown after active spec is non-stable")
  configure({ nil, 253 }, true, rosterRows)
  _, meta = collect()
  equal(meta.specEquipmentObservation.stability, "UNKNOWN", "unknown before active spec is non-stable")

  configure({ 253, 253 }, true, {
    { specID = 253, name = "Beast Mastery", role = nil, primaryStat = nil, isUnlocked = nil },
  })
  _, meta = collect()
  local only = meta.specEquipmentObservation.roster.specializations[1]
  equal(only.specID, 253, "nil metadata does not erase stable specID")
  equal(only.role, nil, "nil role stays absent")
  equal(only.primaryStat, nil, "nil primary stat stays absent")
  equal(only.isUnlocked, nil, "nil unlock value stays absent")
  equal(meta.specEquipmentObservation.stability, "STABLE", "roster metadata absence does not fabricate false stability")

  configure({ 253, 253 }, true, rosterRows)
  local callsBefore = activeRead
  WoWSyncCompat.IsRetail = function() return false end
  data, meta = S.collectors.equipment()
  equal(meta.specEquipmentObservation, nil, "non-Retail equipment has no Retail specialization evidence")
  equal(activeRead, callsBefore, "non-Retail equipment does not call Retail spec APIs")
  equal(data.slots[1].itemID, 240001, "non-Retail equipment collection behavior remains")
  WoWSyncCompat.IsRetail = function() return true end

  -- The committed equipment envelope owns its co-observation. Every export
  -- refresh projects that same observation while its equipment envelope stays current.
  configure({ 253, 253 }, true, rosterRows)
  GetInventoryItemLink = function(unit, slot)
    if slot == 1 and not trace.equipmentMarked then
      trace.equipmentMarked = true
      trace[#trace + 1] = "equipment-scan"
    end
    return oldLink(unit, slot)
  end
  S.Mark("equipment", 0)
  S.Process(true)
  local equipmentEnvelope = S.record.sections.equipment
  check(equipmentEnvelope.specEquipmentObservation ~= nil, "equipment envelope owns co-observation")
  local envelopeObservation = equipmentEnvelope.specEquipmentObservation
  local linked = envelopeObservation.equipmentObservation
  equal(linked.capture, equipmentEnvelope.capture, "envelope link uses exact equipment capture")
  equal(linked.revision, equipmentEnvelope.revision, "envelope link uses exact equipment revision")
  equal(linked.observedAt, equipmentEnvelope.observedAt, "envelope link uses exact equipment observedAt")
  local snapshot = S.GetSnapshot()
  check(snapshot.specEquipmentObservation ~= nil, "snapshot projects envelope-owned co-observation")
  equal(snapshot.specEquipmentObservation.equipmentObservation.capture, equipmentEnvelope.capture,
    "snapshot projection links exact equipment capture")
  equal(snapshot.specEquipmentObservation.equipmentObservation.revision, equipmentEnvelope.revision,
    "snapshot projection links exact equipment revision")
  equal(snapshot.specEquipmentObservation.equipmentObservation.observedAt, equipmentEnvelope.observedAt,
    "snapshot projection links exact equipment observedAt")
  local withoutEvidence = S.Copy(snapshot)
  withoutEvidence.specEquipmentObservation = nil
  withoutEvidence.sections.equipment.specEquipmentObservation = nil
  equal(S.Render(snapshot), S.Render(withoutEvidence), "structured co-observation leaves WOWSYNC v1 text unchanged")
  advance(0.1)
  check(S.record.latestExport.specEquipmentObservation ~= nil, "SavedVariables latestExport has structured sidecar")
  equal(S.record.latestExport.specEquipmentObservation.equipmentObservation.capture,
    equipmentEnvelope.capture, "saved evidence projects the rendered equipment observation")
  local e1 = S.Copy(equipmentEnvelope)
  local firstGeneratedAt = S.record.latestExport.generatedAt
  local firstLink = S.Copy(equipmentEnvelope.specEquipmentObservation.equipmentObservation)
  WoWSyncCompat.IsRetail = function() return false end
  equal(S.GetSnapshot().specEquipmentObservation, nil, "non-Retail snapshot does not project Retail equipment evidence")
  WoWSyncCompat.IsRetail = function() return true end
  event("PLAYER_MONEY")
  advance(2)
  check(S.record.latestExport.generatedAt > firstGeneratedAt, "unrelated refresh advances generatedAt")
  equal(S.record.sections.equipment.observedAt, e1.observedAt, "unrelated refresh leaves equipment observedAt")
  equal(S.record.sections.equipment.capture, e1.capture, "unrelated refresh leaves equipment capture")
  equal(S.record.sections.equipment.revision, e1.revision, "unrelated refresh leaves equipment revision")
  check(S.record.latestExport.specEquipmentObservation ~= nil, "unrelated refresh retains linked observation projection")
  equal(S.record.latestExport.specEquipmentObservation.equipmentObservation.observedAt, firstLink.observedAt,
    "unrelated refresh retains linked observedAt")
  equal(S.record.latestExport.specEquipmentObservation.equipmentObservation.capture, firstLink.capture,
    "unrelated refresh retains linked capture")
  equal(S.record.latestExport.specEquipmentObservation.equipmentObservation.revision, firstLink.revision,
    "unrelated refresh retains linked revision")

  local beforeLogoutGeneratedAt = S.record.latestExport.generatedAt
  advance(1)
  event("PLAYER_LOGOUT")
  check(S.record.latestExport.generatedAt > beforeLogoutGeneratedAt, "logout refresh advances generatedAt")
  equal(S.record.sections.equipment.observedAt, e1.observedAt, "logout leaves equipment observedAt unchanged")
  equal(S.record.sections.equipment.capture, e1.capture, "logout leaves equipment capture unchanged")
  equal(S.record.sections.equipment.revision, e1.revision, "logout leaves equipment revision unchanged")
  check(S.record.latestExport.specEquipmentObservation ~= nil, "logout preserves observation projection")
  equal(S.record.latestExport.specEquipmentObservation.equipmentObservation.capture, e1.capture,
    "logout projection remains linked to committed equipment")

  -- A failed attempt updates attempt diagnostics but does not replace or clear
  -- the prior committed equipment envelope and its observation.
  local actualEquipmentCollector = S.collectors.equipment
  S.collectors.equipment = function() return nil, { reason = "synthetic failed scan", retry = true } end
  S.Mark("equipment", 0)
  S.Process(true)
  equal(S.record.sections.equipment.capture, e1.capture, "failed attempt retains committed equipment capture")
  equal(S.record.sections.equipment.observedAt, e1.observedAt, "failed attempt retains committed equipment observedAt")
  equal(S.record.sections.equipment.revision, e1.revision, "failed attempt retains committed equipment revision")
  check(S.record.sections.equipment.specEquipmentObservation ~= nil, "failed attempt retains envelope evidence")
  equal(S.record.sections.equipment.specEquipmentObservation.equipmentObservation.observedAt, e1.observedAt,
    "failed attempt retains evidence observedAt link")
  equal(S.record.sections.equipment.specEquipmentObservation.equipmentObservation.capture, e1.capture,
    "failed attempt keeps evidence linked to old equipment")
  equal(S.record.sections.equipment.specEquipmentObservation.equipmentObservation.revision, e1.revision,
    "failed attempt retains evidence revision link")
  advance(2)
  check(S.record.latestExport.specEquipmentObservation ~= nil, "refresh after failed attempt still projects committed evidence")
  S.collectors.equipment = actualEquipmentCollector

  -- A corrupt/mismatched persisted tuple is never repaired or projected.
  local validObservation = S.Copy(S.record.sections.equipment.specEquipmentObservation)
  for _, field in ipairs({ "observedAt", "revision" }) do
    local value = S.record.sections.equipment.specEquipmentObservation.equipmentObservation[field]
    S.record.sections.equipment.specEquipmentObservation.equipmentObservation[field] = value + 1000
    equal(S.GetSnapshot().specEquipmentObservation, nil, "mismatched " .. field .. " link is rejected")
    S.record.sections.equipment.specEquipmentObservation.equipmentObservation[field] = value
  end
  S.record.sections.equipment.specEquipmentObservation.equipmentObservation.capture = e1.capture + 1000
  equal(S.GetSnapshot().specEquipmentObservation, nil, "mismatched envelope link is rejected by snapshot")
  S.Mark("character", 0)
  S.Process(true)
  advance(2)
  equal(S.record.latestExport.specEquipmentObservation, nil, "mismatched envelope link is not projected to latestExport")
  S.record.sections.equipment.specEquipmentObservation = validObservation

  -- A successful newer equipment commit without specialization evidence must
  -- replace the envelope without inheriting E1's evidence.
  advance(1)
  S.collectors.equipment = function()
    return S.Copy(S.record.sections.equipment.data), { completeness = "complete" }
  end
  S.Mark("equipment", 0)
  S.Process(true)
  local e2 = S.record.sections.equipment
  check(e2.capture ~= e1.capture, "new equipment observation has a new capture")
  equal(e2.specEquipmentObservation, nil, "new equipment envelope without spec evidence does not inherit E1")
  equal(S.GetSnapshot().specEquipmentObservation, nil, "E2 snapshot has no inherited co-observation")
  advance(2)
  equal(S.record.latestExport.specEquipmentObservation, nil, "E2 latestExport does not associate E1 evidence")
  S.collectors.equipment = actualEquipmentCollector

  -- Leave a valid E1-style record available for the Retail suite's explicit
  -- reinitialization/persistence check, then let the runner restore its fixture.
  S.record.sections.equipment = e1
  S.Mark("character", 0)
  S.Process(true)
  advance(2)
  check(S.record.latestExport.specEquipmentObservation ~= nil, "restored committed envelope projects for persistence check")

  -- Each partial/retried scan must finish its own bracket. The test's existing
  -- item metadata stub becomes unavailable and forces the collector retry path.
  C_Item.GetItemInfo = function() return nil end
  configure({ 253, 253, 253, 253, 253, 253, 253, 253, 253, 253 }, true, rosterRows)
  local scanCount = 0
  GetInventoryItemLink = function(unit, slot)
    if slot == 1 then scanCount = scanCount + 1; trace[#trace + 1] = "equipment-scan-" .. scanCount end
    return oldLink(unit, slot)
  end
  event("PLAYER_EQUIPMENT_CHANGED")
  advance(2.8)
  check(scanCount > 1, "incomplete metadata caused full equipment retries")
  equal(activeRead, scanCount * 2, "every retry has a before and completion-time after spec read")
  equal(S.record.sections.equipment.specEquipmentObservation.equipmentObservation.capture,
    S.record.sections.equipment.capture, "latest retry evidence remains linked to its committed envelope")
  C_Item.GetItemInfo = oldItemInfo

  C_SpecializationInfo, UnitClass, GetInventoryItemLink = oldSpecAPI, oldClass, oldLink
  WoWSyncCompat.IsRetail = oldRetail
  return { equipment = originalEquipmentSection, latestExport = originalLatestExport }
end
