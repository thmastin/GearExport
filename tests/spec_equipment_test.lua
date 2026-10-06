return function(S, check, equal, advance, event)
  local oldSpecAPI, oldClass, oldLink, oldRetail = C_SpecializationInfo, UnitClass, GetInventoryItemLink, WoWSyncCompat.IsRetail
  local oldItemInfo = C_Item.GetItemInfo
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

  -- Process/refresh path: evidence is linked to the equipment section committed
  -- by this scan, then omitted by the next unrelated export.
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
  local snapshot = S.GetSnapshot()
  check(snapshot.specEquipmentObservation ~= nil, "snapshot carries just-completed co-observation")
  local linked = snapshot.specEquipmentObservation.equipmentObservation
  equal(linked.capture, S.record.sections.equipment.capture, "link uses equipment capture identity")
  equal(linked.revision, S.record.sections.equipment.revision, "link uses equipment section revision")
  equal(linked.observedAt, S.record.sections.equipment.observedAt, "link uses equipment section observedAt")
  local withoutEvidence = S.Copy(snapshot)
  withoutEvidence.specEquipmentObservation = nil
  equal(S.Render(snapshot), S.Render(withoutEvidence), "structured co-observation leaves WOWSYNC v1 text unchanged")
  advance(0.1)
  check(S.record.latestExport.specEquipmentObservation ~= nil, "SavedVariables latestExport has structured sidecar")
  equal(S.record.latestExport.specEquipmentObservation.equipmentObservation.capture,
    S.record.sections.equipment.capture, "saved evidence points to rendered equipment observation")
  event("PLAYER_MONEY")
  advance(0.5)
  equal(S.record.latestExport.specEquipmentObservation, nil, "unrelated later export does not carry prior co-observation")

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
  C_Item.GetItemInfo = oldItemInfo

  C_SpecializationInfo, UnitClass, GetInventoryItemLink = oldSpecAPI, oldClass, oldLink
  WoWSyncCompat.IsRetail = oldRetail
end
