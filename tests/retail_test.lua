-- Retail 12.1.0-shaped APIs: removed Classic globals intentionally absent.
local passed, actions = 0, 0
local function check(value, message) assert(value, message); passed = passed + 1 end
local function equal(a, b, message) check(a == b, message .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local function action() actions = actions + 1; error("Gameplay action invoked") end
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
Enum = { BagIndex = { Backpack = 0, ReagentBag = 5 }, BankType = { Character = 0, Account = 2 },
    SpellBookSpellBank = { Player = 0, Pet = 1 }, SpellBookItemType = { Spell = 1, FutureSpell = 2, Flyout = 3, PetAction = 4 } }
local itemRef = "item:240001:7440:213743:0:0:0:0:0:90:0:0:16:4:10354:10299:6652:12030:2:28:2462:38:8"
local link = "|cffa335ee|H" .. itemRef .. "|h[Crafted Sample]|h|r"
local pending, bankView, requests = false, true, 0
C_Item = {
    GetItemInfo = function(ref)
        check(ref ~= nil, "item reference supplied")
        if pending then return nil end
        return "Crafted Sample", link, 4, 200, 80, "Armor", "Plate", 1, "INVTYPE_HEAD", 1, 4321
    end,
    GetDetailedItemLevelInfo = function(ref) equal(ref, link, "instance link for level"); return pending and nil or 289 end,
    GetItemStats = function() if not pending then return { ITEM_MOD_HASTE_RATING_SHORT = 42, ITEM_MOD_MASTERY_RATING_SHORT = 31 } end end,
    RequestLoadItemDataByID = function(id) equal(id, 240001, "metadata request ID"); requests = requests + 1 end,
    GetItemCount = function() return 2 end,
}
C_TooltipInfo = { GetInventoryItem = function() if not pending then return { lines = { { leftText = "Crafted Sample" } } } end end }
C_Bank = {
    CanViewBank = function(kind) equal(kind, Enum.BankType.Character, "only character bank read"); return bankView end,
    FetchPurchasedBankTabIDs = function(kind) equal(kind, Enum.BankType.Character, "purchased character IDs"); return { 6, 8 } end,
    FetchNumPurchasedBankTabs = function() return 2 end,
    AutoDepositItemsIntoBank = action, PurchaseBankTab = action, DepositMoney = action,
}
C_Container = {
    GetContainerNumSlots = function(bag) check(bag >= 0 and bag <= 8, "no Classic/account bank IDs"); return bag == 0 and 16 or bag == 5 and 36 or bag == 6 and 98 or bag == 8 and 98 or 0 end,
    GetContainerItemInfo = function(bag, slot)
        if (bag == 0 or bag == 5 or bag == 6) and slot == 1 then
            return { itemID = 240001, hyperlink = link, stackCount = 2, isLocked = false, isBound = true }
        end
    end,
    ContainerIDToInventoryID = function(bag) check(bag >= 1 and bag <= 5, "only equipped bags mapped"); return 19 + bag end,
    PickupContainerItem = action, UseContainerItem = action, SplitContainerItem = action,
}
function C_Container.GetContainerNumFreeSlots(bag)
    return C_Container.GetContainerNumSlots(bag) - ((bag == 0 or bag == 5 or bag == 6) and 1 or 0), bag == 5 and 2048 or 0
end
function GetInventoryItemLink(_, slot) if slot == 1 then return link end end
function GetInventoryItemID(_, slot) if slot == 1 then return 240001 end end
function GetInventoryItemTexture(_, slot) if slot == 1 then return 1 end end
local spells = {
    { name = "Class spell", spellID = 1001, itemType = 1, subName = "Not a rank" },
    { name = "Passive", spellID = 1002, itemType = 1, isPassive = true },
    { name = "Future", spellID = 9999, itemType = 2 },
    { name = "Off spec", spellID = 9998, itemType = 1, isOffSpec = true },
    { name = "Flyout", actionID = 50, itemType = 3 },
    { name = "Class spell", spellID = 1001, itemType = 1 },
    { name = "Racial", spellID = 1004, itemType = 1 },
}
C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { name = "General and class", itemIndexOffset = 0, numSpellBookItems = #spells } end,
    GetSpellBookItemInfo = function(index, bank) equal(bank, 0, "player spellbook only"); return spells[index] end,
}
function GetFlyoutInfo() return "Flyout", "", 2, true end
function GetFlyoutSlotInfo(_, slot) return 1003, nil, slot == 1, "Known flyout" end
function GetProfessions() return nil, 2, nil, 4, 5 end
function GetProfessionInfo(index)
    return index == 2 and "Alchemy" or index == 4 and "Fishing" or "Cooking", 1, 45, 100, 0, 0, 2800 + index, 0, 0, 0, "Midnight"
end
C_TradeSkillUI = { GetProfessionInfoBySkillLineID = function() return { expansionName = "Midnight" } end, CraftRecipe = action }
local trainerCategory = "Alchemy"
function GetTrainerServiceInfo() return "Recipe", "available", 12345, 80 end
function GetTrainerServiceCost() return 5500 end
function GetTrainerServiceSkillLine() return trainerCategory end
assert(loadfile("WoWSyncCompat.lua"))("GearExport", {})
local C = WoWSyncCompat
local bags, bank = C.GetBankRanges()
equal(#bags, 6, "Retail bag range includes reagent bag")
equal(bags[6], 5, "reagent ID")
equal(bank[2], 8, "use actual purchased IDs, not guessed contiguous range")
bankView = false; _, bank = C.GetBankRanges(); equal(bank, nil, "unviewable bank unknown"); bankView = true
equal(C.GetContainerBagIdentity(6), nil, "bank tab is not an equipped bag")
equal(C.GetContainerInfo(5, 1).stackCount, 2, "modern container table")
check(C.GetBankCoverage():find("ACCOUNT/Warband", 1, true), "account coverage explicit")
equal(C.GetPurchasedBankSlots(), 2, "purchased tabs")
equal(C.GetItemLevel(link, 200), 289, "instance item level")
check(C.IsItemDataReady(240001), "modern item readiness")
pending = true; check(not C.IsItemDataReady(240001), "async item not ready")
C.RequestItemData(240001); equal(requests, 1, "read request only"); pending = false
local stats, ready = C.GetEquipmentStats(link, 1)
check(ready and #stats == 2, "modern equipment metadata")
local tabs = C.EnumerateSpellbook()
equal(#tabs[1].entries, 5, "future/offspec excluded; known flyout/racial included")
equal(tabs[1].entries[1].rank, nil, "Retail subName never rank")
local professions = C.GetProfessionState()
equal(#professions.entries, 3, "sparse primary and secondary professions")
equal(professions.entries[1].tier, "Midnight", "profession tier")
local service = C.GetTrainerService(1)
equal(service.status, "available", "Retail trainer tuple")
equal(service.requiredLevel, 80, "Retail trainer level from tuple")
equal(service.rank, nil, "no Retail trainer rank")
equal(C.TrainerCategory({ trainer = {}, services = { service } }), "PROF_ALCHEMY", "profession category from API")
equal(C.TrainerCategory({ trainer = {}, services = {} }), "UNKNOWN", "empty trainer unknown")
equal(actions, 0, "no actions")
print("PASS: " .. passed .. " Retail assertions; 0 gameplay actions")
