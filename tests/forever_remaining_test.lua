-- Synthetic API shapes only.  Real Forever bank/trainer tuple validation remains live work.
return function(S, check, equal, advance)
    local oldBank, oldEnum, oldContainer = C_Bank, Enum, C_Container
    local oldNum, oldInfo, oldCost, oldLevel, oldSkill, oldReqs, oldReq = GetNumTrainerServices,
        GetTrainerServiceInfo, GetTrainerServiceCost, GetTrainerServiceLevelReq, GetTrainerServiceSkillReq,
        GetTrainerServiceNumAbilityReq, GetTrainerServiceAbilityReq
    Enum = Enum or {}; Enum.BankType = { Character = 7 }
    C_Bank = { CanViewBank = function(kind) return kind == 7 end, FetchPurchasedBankTabIDs = function() return { 40, 44 } end }
    C_Container = { GetContainerNumSlots = function(id) return id == 40 and 2 or id == 44 and 1 end,
        GetContainerItemInfo = function(id, slot)
            if id == 40 and slot == 1 then return { itemID = 100, hyperlink = "|Hitem:100:0:0:0|h[x]|h", itemName = "One", stackCount = 3, isLocked = false, isBound = true } end
        end }
    S.bankOpen = true
    local bank, meta = S.collectors.bank()
    equal(#bank.containers, 2, "Forever bank uses returned character tab IDs")
    equal(bank.containers[1].id, 40, "no inferred negative bank container")
    equal(bank.containers[1].free, 1, "bank empty slot observed")
    equal(bank.containers[1].slots[1].count, 3, "bank item observed")
    equal(meta.completeness, "complete", "complete synthetic bank")
    C_Bank.CanViewBank = function() return false end
    equal(S.collectors.bank(), nil, "unviewable bank remains UNKNOWN")
    C_Bank.CanViewBank = function() return true end; C_Bank.FetchPurchasedBankTabIDs = function() return { 40, 40 } end
    equal(S.collectors.bank(), nil, "duplicate bank IDs rejected")
    C_Bank.FetchPurchasedBankTabIDs = function() return {} end
    bank, meta = S.collectors.bank(); equal(#bank.containers, 0, "observed empty bank is not UNKNOWN")
    C_Bank, Enum, C_Container = oldBank, oldEnum, oldContainer
    GetNumTrainerServices = function() return 1 end
    GetTrainerServiceInfo = function() return "Fireball", "available", 135812, 6 end
    GetTrainerServiceCost, GetTrainerServiceLevelReq = function() return 100 end, nil
    GetTrainerServiceSkillReq, GetTrainerServiceNumAbilityReq = function() return "Pyromancy", 50, false end, function() return 1 end
    GetTrainerServiceAbilityReq = function() return "Fireball", true end
    S.trainerOpen = true; S.currentTrainerVisit = { openedAt = 1, name = "Trainer", session = 1 }; S.record.visits.trainers = S.record.visits.trainers or {}
    local result, trainerMeta = S.collectors.trainer()
    equal(result.snapshot.services[1].name, "Fireball", "trainer ability observed")
    equal(result.snapshot.services[1].rank, nil, "modern trainer tuple exposes no rank")
    equal(result.snapshot.services[1].requiredLevel, 6, "modern tuple required level observed")
    equal(result.snapshot.services[1].skillRequirement.rank, 50, "trainer skill requirement observed")
    equal(result.snapshot.services[1].abilityRequirements[1].name, "Fireball", "trainer prerequisite observed")
    check(not result.snapshot.services[1].spellID, "trainer index never becomes spell ID")
    GetTrainerServiceInfo = function() return nil end
    equal(S.collectors.trainer(), nil, "malformed trainer tuple remains UNKNOWN")
    GetTrainerServiceInfo = function() return "Fireball", "available", {}, 6 end
    equal(S.collectors.trainer(), nil, "malformed modern texture remains UNKNOWN")
    GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceCost, GetTrainerServiceLevelReq, GetTrainerServiceSkillReq, GetTrainerServiceNumAbilityReq, GetTrainerServiceAbilityReq = oldNum, oldInfo, oldCost, oldLevel, oldSkill, oldReqs, oldReq
    S.trainerOpen, S.bankOpen = false, false
end
