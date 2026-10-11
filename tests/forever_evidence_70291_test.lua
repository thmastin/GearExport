-- Synthetic contract fixtures only; never evidence from a live client.
return function(S, check, equal)
    check(S.collectors.forever70291Evidence ~= nil, "70291 raw evidence collector enabled")
    local parsedTrainer, trainerReason = S.collectors.trainer()
    equal(parsedTrainer, nil, "unverified trainer tuple adapter stays disabled")
    check(trainerReason.reason:find("semantics remain UNKNOWN", 1, true) ~= nil, "trainer module fails closed while raw evidence collector remains enabled")
    local found = false
    for _, key in ipairs(S.order) do if key == "forever70291Evidence" then found = true end end
    check(found, "70291 evidence included in normal export refresh")
    check(S.structuredOnly.forever70291Evidence, "new evidence stays out of strict WOWSYNC v1 text for parser compatibility")

    local oldSkill, oldFrame, oldItemAPI, oldSpecializationInfo, oldPlayerInfo = C_SkillInfo, ClassTrainerFrame, C_Item, C_SpecializationInfo, C_PlayerInfo
    local oldTrainerFrame, oldTrainerStep = TrainerFrame, ClassTrainerFrameSkillStep
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
    local exactArmor = "item:123:4:5"
    local exactVariant = "item:123:4:5:6"
    local oldEquipment, oldBags = S.record.sections.equipment, S.record.sections.bags
    S.record.sections.equipment = { completeness = "complete", observedAt = GetServerTime(), data = { slots = { [16] = { itemID = 123, itemString = exactArmor } } } }
    S.record.sections.bags = { completeness = "complete", observedAt = GetServerTime(), data = { containers = { { id = 0, slots = {
        [1] = { itemID = 123, itemString = exactArmor, count = 1 },
        [2] = { itemID = 123, itemString = exactVariant, count = 2 },
    } } } } }
    local instantCalls, equippableCalls, deltaCalls = {}, {}, {}
    C_Item = {
        GetItemInfoInstant = function(reference)
            instantCalls[#instantCalls + 1] = reference
            return 123, "Armor", "Leather", "INVTYPE_CHEST", 999, 4, 2
        end,
        GetItemInfo = function(reference)
            check(reference == exactArmor or reference == exactVariant, "full item-info API receives an exact observed variant")
            return "Synthetic Armor", reference, 2, 3, 1, "Armor", "Leather", 1, "INVTYPE_CHEST", 0, 0, 4, 2, 1
        end,
        GetItemStats = function(reference)
            check(reference == exactArmor or reference == exactVariant, "item-stats API receives an exact observed variant")
            return { ITEM_MOD_STAMINA_SHORT = 5, ITEM_MOD_ARMOR = 10 }
        end,
        GetItemSpecInfo = function(reference)
            check(reference == exactArmor or reference == exactVariant, "item specialization API receives the exact observed variant")
            return { 71, 72 }
        end,
        GetItemStatDelta = function(candidate, equipped)
            deltaCalls[#deltaCalls + 1] = { candidate, equipped }
            return { ITEM_MOD_ARMOR = 1 }
        end,
        IsEquippableItem = function(reference)
            equippableCalls[#equippableCalls + 1] = reference
            return true
        end,
        IsItemBindToAccount = function(reference) check(reference == exactArmor or reference == exactVariant, "account-binding API receives exact item string"); return false end,
        IsItemBindToAccountUntilEquip = function(reference) check(reference == exactArmor or reference == exactVariant, "account-bound-until-equip API receives exact item string"); return false end,
    }
    local canUseIDs = {}
    C_PlayerInfo = { CanUseItem = function(itemID) canUseIDs[#canUseIDs + 1] = itemID; return itemID == 123 end }
    C_SpecializationInfo = {
        GetSpecialization = function() return 1 end,
        GetSpecializationInfo = function(index)
            equal(index, 1, "active specialization details use the observed active index")
            return 71, "Synthetic Arms", "", 0, 0
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

    local closed, closedMeta = S.collectors.forever70291Evidence()
    equal(closed.trainer.state, "NOT_OBSERVED_WINDOW_CLOSED", "closed trainer is explicit unknown")
    equal(countApiCalls, 0, "closed trainer invokes no service APIs")
    equal(calls, 3, "each skill index called once per capture")
    equal(#closed.itemFacts.items, 2, "item facts are captured per exact itemString variant")
    equal(instantCalls[1], exactArmor, "item metadata API receives an exact observed itemString")
    equal(equippableCalls[2], exactVariant, "equippability API receives each exact variant")
    equal(canUseIDs[1], 123, "CanUseItem receives observed base item ID")
    equal(closed.itemFacts.items[1].playerCanUseItem.api, "C_PlayerInfo.CanUseItem", "player use API is separately labeled")
    equal(closed.itemFacts.items[1].playerCanUseItem.input.scope, "CURRENT_PLAYER_ONLY", "player-scoped API cannot be generalized to other characters")
    equal(closed.itemFacts.items[1].playerCanUseItem.returns[1].observation.value, true, "player CanUseItem result remains raw")
    equal(closed.itemFacts.items[1].bindingEvidence.semanticInterpretation, "UNKNOWN_UNVALIDATED", "binding semantics stay gated pending Forever capture")
    equal(closed.itemFacts.items[1].bindingEvidence.isItemBindToAccount.returns[1].observation.value, false, "account binding raw result retained")
    equal(closed.itemFacts.items[1].bindingEvidence.itemInfoBindType.observation.value, 1, "GetItemInfo bindType position retained raw")
    equal(closed.itemFacts.items[1].itemInfoInstant.returns[4].observation.value, "INVTYPE_CHEST",
        "raw inventory-type evidence is retained without an eligibility claim")
    equal(closed.itemFacts.items[1].isEquippableItem.returns[1].observation.value, true,
        "item-level equippability result is raw evidence only")
    equal(closed.itemFacts.items[1].itemInfo.api, "C_Item.GetItemInfo", "full item-info call name retained")
    equal(closed.itemFacts.items[1].itemInfo.returns[5].observation.value, 1,
        "full item-info return tuple retained without semantic interpretation")
    equal(closed.itemFacts.items[1].itemStats.table.state, "OBSERVED_TABLE", "item stats table captured as evidence")
    equal(closed.itemFacts.items[1].itemStats.table.entries[1].key, "ITEM_MOD_ARMOR", "item stat keys retained deterministically")
    equal(closed.itemFacts.items[1].itemSpecInfo.table.entries[1].observation.value, 71, "item specialization IDs retained as raw table entries")
    equal(closed.specialization.activeIndex.returns[1].observation.value, 1, "active specialization index retained raw")
    equal(closed.specialization.activeInfo.returns[1].observation.value, 71, "active specialization detail tuple retained raw")
    equal(#closed.itemFacts.statDeltaComparisons.comparisons, 1, "unique carried variant is compared with observed equipment")
    equal(deltaCalls[1][1], exactVariant, "stat delta preserves candidate exact variant as first input")
    equal(deltaCalls[1][2], exactArmor, "stat delta preserves equipped exact variant as second input")
    equal(closed.itemFacts.statDeltaComparisons.comparisons[1].table.entries[1].key, "ITEM_MOD_ARMOR", "stat delta table remains raw")
    equal(closed.itemFacts.statDeltaComparisons.comparisons[1].input.candidateItemString, exactVariant, "stat delta pair labels ordered exact links")
    equal(closed.itemFacts.statDeltaComparisons.reason:find("not interpreted") ~= nil, true, "stat delta does not become an upgrade conclusion")
    equal(closed.itemFacts.completeness, "complete", "all item metadata API samples are present")
    S.record.sections.bags.completeness = "partial"
    local partialSource = S.collectors.forever70291Evidence().itemFacts
    equal(partialSource.completeness, "partial", "partial inventory source cannot be upgraded by fresh item API samples")
    S.record.sections.bags.completeness = "complete"
    S.record.sections.bags.observedAt = 1
    local oldSource = S.collectors.forever70291Evidence().itemFacts
    equal(oldSource.completeness, "partial", "old inventory source cannot be upgraded by fresh item API samples")
    S.record.sections.bags.observedAt = GetServerTime()
    ClassTrainerFrame, TrainerFrame, ClassTrainerFrameSkillStep = nil, nil, nil
    local unavailable = S.collectors.forever70291Evidence()
    equal(unavailable.trainer.state, "NOT_OBSERVED_FRAME_UNAVAILABLE", "missing trainer UI frame is explicit not-observed")
    equal(countApiCalls, 0, "unavailable trainer frame invokes no service APIs")
    ClassTrainerFrame = { IsShown = function() return false end }
    equal(closed.skillLineCountValue, 3, "skill count captured")
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
    local missingSkill = S.collectors.forever70291Evidence()
    equal(missingSkill.skillLineCount.state, "API_MISSING", "missing count API explicit")
    equal(missingSkill.skillLineCoverage, "UNKNOWN_COUNT", "missing count does not create an empty-complete skill list")
    C_Item = {}
    C_PlayerInfo = {}
    C_SpecializationInfo = {}
    local missingItemAPIs = S.collectors.forever70291Evidence().itemFacts
    equal(missingItemAPIs.completeness, "partial", "missing item APIs cannot become complete metadata")
    equal(missingItemAPIs.items[1].itemInfoInstant.state, "API_MISSING", "missing item API remains explicit")
    equal(missingItemAPIs.items[1].itemSpecInfo.state, "API_MISSING", "missing item specialization API remains explicit")
    equal(missingItemAPIs.items[1].playerCanUseItem.state, "API_MISSING", "missing player use API remains explicit")
    equal(missingItemAPIs.items[1].bindingEvidence.isItemBindToAccount.state, "API_MISSING", "missing account binding API remains explicit")
    equal(missingItemAPIs.statDeltaComparisons.state, "API_MISSING", "missing stat delta API remains explicit")
    C_Item = { GetItemStatDelta = function() error("synthetic delta failure") end }
    local failedDelta = S.collectors.forever70291Evidence().itemFacts.statDeltaComparisons
    equal(failedDelta.comparisons[1].state, "API_ERROR", "stat delta API errors remain explicit raw evidence")
    equal(failedDelta.completeness, "partial", "stat delta API error keeps pair coverage partial")
    C_Item = { GetItemStatDelta = function() return nil end }
    local nilDelta = S.collectors.forever70291Evidence().itemFacts.statDeltaComparisons
    equal(nilDelta.comparisons[1].table.state, "NIL", "nil delta result shape remains explicit")
    equal(nilDelta.completeness, "partial", "unknown nil delta shape cannot be marked complete")
    C_Item = {
        GetItemInfoInstant = function() return 999, "Armor", "Leather", "INVTYPE_CHEST" end,
        IsEquippableItem = function() return nil end,
        GetItemInfo = function() error("uncached item data") end,
        GetItemStats = function() return nil end,
    }
    local malformedItem = S.collectors.forever70291Evidence().itemFacts
    equal(malformedItem.completeness, "partial", "mismatched identity and nil item verdict stay partial")
    C_SkillInfo = { GetNumSkillLines = function() error("synthetic count failure") end }
    local failedCount = S.collectors.forever70291Evidence()
    equal(failedCount.skillLineCount.state, "API_ERROR", "throwing count API captured as error")
    equal(failedCount.skillLineCoverage, "UNKNOWN_COUNT", "throwing count remains unknown")
    C_SkillInfo = { GetNumSkillLines = function() return 2 end,
        GetSkillLineInfo = function(index) if index == 1 then return { name = "Known", skillID = 1 } end error("synthetic row failure") end }
    local partialSkills = S.collectors.forever70291Evidence()
    equal(partialSkills.skillLines[2].state, "API_ERROR", "indexed API error remains row error")
    equal(partialSkills.skillLineCoverage, "PARTIAL_INDEXED_ROWS", "partial row cannot claim complete coverage")
    C_SkillInfo.GetSkillLineInfo = function(index) if index == 1 then return { name = "Known", skillID = 1 } end return nil end
    local nilSkill = S.collectors.forever70291Evidence()
    equal(nilSkill.skillLines[2].state, "NIL_RESULT", "nil indexed result remains explicit")
    C_SpecializationInfo = { GetSpecialization = function() return nil end }
    local absentSpec = S.collectors.forever70291Evidence().specialization
    equal(absentSpec.activeInfo.state, "UNKNOWN", "nil active specialization does not produce an active specialization result")

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
    local failedTrainerCount = S.collectors.forever70291Evidence().trainer
    equal(failedTrainerCount.state, "PARTIAL_INVALID_SERVICE_COUNT", "throwing trainer count remains partial")
    equal(failedTrainerCount.attempted.serviceCountResult.state, "API_ERROR", "trainer count error retained")
    GetNumTrainerServices = function() countApiCalls = countApiCalls + 1; ClassTrainerFrame.shown = false; return 2 end
    ClassTrainerFrame.IsShown = function(self) return self.shown ~= false end
    local closedMidCapture = S.collectors.forever70291Evidence().trainer
    equal(closedMidCapture.state, "PARTIAL_WINDOW_CLOSED", "closing trainer during capture is explicit partial")
    equal(infoCalls, 0, "closed window prevents service calls")
    ClassTrainerFrame.shown = true
    ClassTrainerFrame.IsShown = function() return true end
    GetNumTrainerServices = function() countApiCalls = countApiCalls + 1; return 2 end
    local open = S.collectors.forever70291Evidence()
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
    local failedService = S.collectors.forever70291Evidence().trainer.lastObserved.services[1]
    equal(failedService.calls.info.state, "API_ERROR", "trainer info error captured")
    equal(failedService.calls.cost.state, "OBSERVED_VALUE", "nil cost call keeps its return tuple")
    equal(failedService.calls.cost.returns[1].observation.state, "NIL", "nil cost is not zero")

    GetTrainerServiceInfo = function(index) return "Synthetic " .. index, "raw-status", 123, 10, "Rank", "" end
    GetTrainerServiceCost = function() return 0 end
    GetTrainerServiceAbilityReq = function() return "Requirement", true end
    local limited = S.collectors.forever70291Evidence().trainer.lastObserved.services[1]
    equal(#limited.calls.abilityRequirements, 20, "requirement probing is bounded")
    equal(limited.requirementsTruncated, true, "safety limit is explicitly partial")

    S.record.sections.equipment, S.record.sections.bags = oldEquipment, oldBags
    local snapshot = S.GetSnapshot()
    snapshot.sections.forever70291Evidence = { data = open, completeness = "partial", observedAt = 123 }
    local export = S.Render(snapshot)
    check(not export:find("[FOREVER 70291 EVIDENCE]", 1, true), "legacy v1 export omits new raw section")
    check(export:find("[END]", 1, true), "legacy v1 export remains well formed")
    local rawSection = S.RenderSection("forever70291Evidence", snapshot)
    check(rawSection:find("skillLine\t2\t46\t6\tAxes\t22\t40\tfalse", 1, true),
        "structured evidence renderer retains skill index/id/name/rank/max/header: " .. (rawSection:match("skillLine\t2[^\n]*") or "no index-2 row"))
    check(rawSection:find("unavailable", 1, true), "structured evidence retains raw status text")
    check(rawSection:find("|cffff0000Prerequisite|r", 1, true), "raw rendering preserves exact color escape text")
    check(rawSection:find("trainer.1.abilityRequirement.argument\t2\t2", 1, true),
        "rendered requirement call retains service and requirement indices")
    check(rawSection:find("itemFact\t123\t" .. exactArmor .. "\tOBSERVED_VALUE\tOBSERVED_VALUE", 1, true),
        "rendered raw item evidence preserves exact item variant and API states")
    check(rawSection:find("INVTYPE_CHEST", 1, true), "rendered item tuple remains available for audit")
    check(rawSection:find("Raw runtime observations only", 1, true), "structured evidence disclaims unvalidated interpretation")

    S.record.sections.equipment, S.record.sections.bags = oldEquipment, oldBags
    C_Item = oldItemAPI
    C_PlayerInfo = oldPlayerInfo
    C_SpecializationInfo = oldSpecializationInfo
    C_SkillInfo, ClassTrainerFrame = oldSkill, oldFrame
    TrainerFrame, ClassTrainerFrameSkillStep = oldTrainerFrame, oldTrainerStep
    GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceCost = oldCount, oldInfo, oldCost
    GetTrainerServiceSkillReq, GetTrainerServiceAbilityReq, GetTrainerServiceNumAbilityReq = oldSkillReq, oldAbilityReq, oldAbilityCount
    GetTrainerServiceType, IsTrainerServiceLearnable = oldServiceType, oldLearnable
    return true
end
