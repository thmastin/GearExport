-- Synthetic bank API shapes only. Trainer tuple interpretation stays disabled pending live verification.
return function(S, check, equal, advance)
    local oldBank, oldEnum, oldContainer = C_Bank, Enum, C_Container
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
    local result, trainerMeta = S.collectors.trainer()
    equal(result, nil, "unverified trainer tuple is not parsed")
    check(trainerMeta.reason:find("semantics remain UNKNOWN", 1, true) ~= nil, "trainer reason preserves unknown API semantics")
    S.trainerOpen, S.bankOpen = false, false
end
