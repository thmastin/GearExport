-- Retail 12.1.0-shaped APIs: removed Classic globals intentionally absent.
local passed, actions = 0, 0
local function check(value, message) assert(value, message); passed = passed + 1 end
local function equal(a, b, message) check(a == b, message .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local function action() actions = actions + 1; error("Gameplay action invoked") end
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
Enum = { BagIndex = { Backpack = 0, ReagentBag = 5 }, BankType = { Character = 0, Account = 2 },
    SpellBookSpellBank = { Player = 0, Pet = 1 }, SpellBookItemType = { Spell = 1, FutureSpell = 2, Flyout = 4, PetAction = 3 },
    TooltipDataLineType = { ItemBinding = 20 }, TooltipDataItemBinding = { Soulbound = 3, BnetAccount = 2, BindToAccountUntilEquipped = 10 } }
local itemRef = "item:240001:7440:213743:0:0:0:0:0:90:0:0:16:4:10354:10299:6652:12030:2:28:2462:38:8"
local link = "|cffa335ee|H" .. itemRef .. "|h[Crafted Sample]|h|r"
local pending, bankView, requests, locationsValid = false, true, 0, true
local expectedLocation
ItemLocation = {
    CreateFromBagAndSlot = function(self, bagID, slotIndex)
        equal(self, ItemLocation, "bag ItemLocation constructor receiver")
        check(type(bagID) == "number", "bag constructor receives bag ID in argument 2")
        check(type(slotIndex) == "number", "bag constructor receives slot index in argument 3")
        if expectedLocation then
            equal(bagID, expectedLocation.bagID, "exact bag ID constructor argument")
            equal(slotIndex, expectedLocation.slot, "exact bag slot constructor argument")
        end
        return { valid = locationsValid, kind = "bag", bagID = bagID, slot = slotIndex }
    end,
    CreateFromEquipmentSlot = function(self, equipmentSlotIndex)
        equal(self, ItemLocation, "equipment ItemLocation constructor receiver")
        check(type(equipmentSlotIndex) == "number", "equipment slot is constructor argument 2")
        if expectedLocation then equal(equipmentSlotIndex, expectedLocation.slot, "exact equipment slot constructor argument") end
        return { valid = locationsValid, kind = "equipment", slot = equipmentSlotIndex }
    end,
}
check(not pcall(ItemLocation.CreateFromBagAndSlot, 0, 1), "bag ItemLocation mock rejects missing receiver")
check(not pcall(ItemLocation.CreateFromEquipmentSlot, 1), "equipment ItemLocation mock rejects missing receiver")
local function requireValidLocation(loc)
    assert(type(loc) == "table" and loc.valid == true and loc.kind, "C_Item location API requires a valid ItemLocation")
end
local baseEquipLocation = "INVTYPE_HEAD"
C_Item = {
    GetItemInfo = function(ref)
        check(ref ~= nil, "item reference supplied")
        if pending then return nil end
        return "Crafted Sample", link, 4, 200, 80, "Armor", "Plate", 1, baseEquipLocation, 1, 4321, 4, 4, 8, 10, nil, false
    end,
    GetItemID = function(loc) requireValidLocation(loc); return 240001 end,
    DoesItemExist = function(loc) requireValidLocation(loc); return true end,
    GetItemLink = function(loc) requireValidLocation(loc); return link end,
    GetDetailedItemLevelInfo = function(ref) equal(ref, link, "instance link for level"); if not pending then return 289 end end,
    GetItemGUID = function(loc) requireValidLocation(loc); return loc.kind .. "-" .. tostring(loc.bagID or "") .. "-" .. loc.slot end,
    GetItemInventoryType = function(loc) requireValidLocation(loc); if not pending then return "INVTYPE_HEAD" end end,
    GetCurrentItemLevel = function(loc) requireValidLocation(loc); if not pending then return loc.kind == "equipment" and 289 or 276 end end,
    IsBound = function(loc) requireValidLocation(loc); return false end,
    IsBoundToAccountUntilEquip = function(loc) requireValidLocation(loc); return false end,
    IsItemBindToAccount = function() return true end,
    IsItemBindToAccountUntilEquip = function() return false end,
    IsItemDataCached = function(loc) requireValidLocation(loc); return not pending end,
    RequestLoadItemData = function(loc) requireValidLocation(loc); requests = requests + 1 end,
    IsEquippableItem = function() return not pending end,
    GetItemStats = function() if not pending then return { ITEM_MOD_HASTE_RATING_SHORT = 42, ITEM_MOD_MASTERY_RATING_SHORT = 31 } end end,
    RequestLoadItemDataByID = function(id) equal(id, 240001, "metadata request ID"); requests = requests + 1 end,
    GetItemCount = function() return 2 end,
}
C_TooltipInfo = {
    GetInventoryItem = function()
        if pending then return nil end
        return { lines = { { type = Enum.TooltipDataLineType.ItemBinding,
            args = { { field = "bindingType", intVal = Enum.TooltipDataItemBinding.Soulbound } } } } }
    end,
    GetBagItem = function()
        if pending then return nil end
        return { lines = { { type = Enum.TooltipDataLineType.ItemBinding,
            args = { { field = "bindingType", intVal = Enum.TooltipDataItemBinding.BnetAccount } } } } }
    end,
}
C_PlayerInfo = { CanUseItem = function(id) equal(id, 240001, "current character query uses base ID"); return true end }
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
    { name = "Flyout", actionID = 50, itemType = 4 },
    { name = "Class spell", spellID = 1001, itemType = 1 },
    { name = "Racial", spellID = 1004, itemType = 1 },
}
C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { name = "General and class", itemIndexOffset = 0, numSpellBookItems = #spells } end,
    GetSpellBookItemInfo = function(index, bank)
        equal(bank, 0, "player spellbook only")
        if index == 101 then return { name = "Alchemy", spellID = 1005, itemType = 1 } end
        return spells[index]
    end,
}
function GetFlyoutInfo() return "Flyout", "", 2, true end
function GetFlyoutSlotInfo(_, slot) return 1003, nil, slot == 1, "Known flyout" end
function GetProfessions() return nil, 2, nil, 4, 5 end
function GetProfessionInfo(index)
    return index == 2 and "Alchemy" or index == 4 and "Fishing" or "Cooking", 1, 45, 100,
        index == 2 and 1 or 0, 100, 2800 + index, 0, 0, 0, "Midnight"
end
C_TradeSkillUI = { GetProfessionInfoBySkillLineID = function() return { expansionName = "Midnight" } end, CraftRecipe = action }
local trainerCategory = "Alchemy"
function GetTrainerServiceInfo() return "Recipe", "available", 12345, 80 end
function GetTrainerServiceCost() return 5500, true end
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

-- Load the complete selected package, with a UI fixture and no Classic API shims.
local frames, seconds, playerGUID = {}, 0, "Player-Retail-A"
local function widget(name)
    local w = { shown = true, scripts = {}, events = {}, text = "", name = name }
    setmetatable(w, { __index = function(_, key)
        if key == "GetPoint" then return function() return "CENTER", nil, "CENTER", 0, 0 end end
        if key == "GetNumLines" or key == "NumLines" then return function() return 1 end end
        if key == "GetText" then return function(self) return self.text end end
        if key == "SetText" then return function(self, text) self.text = text; if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end end end
        if key == "SetScript" then return function(self, event, fn) self.scripts[event] = fn end end
        if key == "RegisterEvent" then return function(self, event)
            if event == "PLAYERBANKBAGSLOTS_CHANGED" then error("removed event") end
            self.events[event] = true
        end end
        if key == "Show" then return function(self) self.shown = true end end
        if key == "Hide" then return function(self) self.shown = false end end
        if key == "IsShown" or key == "IsVisible" then return function(self) return self.shown end end
        if key == "CreateTexture" or key == "CreateFontString" then return function() return widget() end end
        return function() end
    end })
    frames[#frames + 1] = w
    if name then _G[name] = w end
    return w
end
function CreateFrame(_, name) return widget(name) end
UIParent = widget("UIParent")
BankFrame = widget("BankFrame"); BankFrame:Hide()
ClassTrainerFrame = widget("ClassTrainerFrame")
UISpecialFrames, SlashCmdList = {}, {}
ChatFontNormal, GameFontNormal = {}, {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function GetTime() return seconds end
function GetServerTime() return 1789300000 + math.floor(seconds) end
function time() return GetServerTime() end
function date() return "2026-09-13" end
function UnitGUID(unit) return unit == "player" and playerGUID or "Creature-Trainer" end
function UnitName(unit) return unit == "player" and "RetailTester" or "Uninformative NPC Name" end
function GetRealmName() return "Test Realm" end
function UnitClass() return "Mage", "MAGE" end
function UnitLevel() return 90 end
function UnitFactionGroup() return "Alliance" end
function UnitXP() return 0 end
function UnitXPMax() return 0 end
function GetBuildInfo() return "12.1.0", "69814", "", 120100 end
function GetMoney() return 123456789 end
function GetRealZoneText() return "Silvermoon" end
function GetSubZoneText() return "Bazaar" end
function GetCursorInfo() return nil end
C_Map = { GetBestMapForUnit = function() return 2393 end,
    GetPlayerMapPosition = function() return { GetXY = function() return 0.125, 0.75 end } end }
local serviceCount = 1
function GetNumTrainerServices() return serviceCount end
function IsTradeskillTrainer() return trainerCategory ~= nil end
function GetTrainerServiceTypeFilter() return true end
function GetTrainerServiceSkillReq() return trainerCategory, 1, true end
function GetTrainerServiceNumAbilityReq() return 0 end
BuyTrainerService, BuyMerchantItem, SendMail, EquipItemByName, CastSpellByName = action, action, action, action, action
local addon = {}
for _, file in ipairs({ "GearExport.lua", "WoWSyncCore.lua", "WoWSyncCollectors.lua", "WoWSyncRender.lua", "WoWSyncUI.lua" }) do
    assert(loadfile(file))("GearExport", addon)
end
local S = addon.Sync
local function event(name, arg) S.eventFrame.scripts.OnEvent(S.eventFrame, name, arg) end
local function advance(duration)
    for _ = 1, math.ceil(duration / 0.1) do
        seconds = seconds + 0.1
        if S.eventFrame.scripts.OnUpdate then S.eventFrame.scripts.OnUpdate() end
    end
end
event("ADDON_LOADED", "GearExport"); event("PLAYER_LOGIN"); advance(1)
check(S.unsupportedEvents.PLAYERBANKBAGSLOTS_CHANGED, "removed event tolerated")
check(S.optionalEvents.BANK_TABS_CHANGED, "Retail bank tab event registered")
equal(S.record.sections.character.data.clientFamily, "Retail", "Retail identity")
equal(S.record.sections.character.data.interface, 120100, "Retail interface")
equal(S.record.sections.character.data.moneyCopper, 123456789, "gold remains copper")
equal(S.record.sections.location.data.x, 12.5, "map normalized")
equal(#S.record.sections.bags.data.containers, 6, "canonical bags include reagent")
equal(S.record.sections.bags.data.containers[6].storage, "REAGENT_BAG", "reagent category")
equal(S.record.sections.equipment.data.slots[1].itemString, itemRef, "all modern item modifiers preserved")
equal(S.record.sections.equipment.data.slots[1].itemLevel, 289, "instance level in snapshot")
check(S.record.gearCandidates and S.record.gearCandidates.contractVersion == 1, "Retail candidate sidecar persisted")
local bagCandidate, equippedCandidate
for _, candidate in ipairs(S.record.gearCandidates.candidates) do
    if candidate.observedLocation.type == "CONTAINER_SLOT" and candidate.observedLocation.containerID == 0 then bagCandidate = candidate end
    if candidate.observedLocation.type == "EQUIPMENT_SLOT" then equippedCandidate = candidate end
end
check(bagCandidate and equippedCandidate, "bag and equipment candidates observed")
equal(bagCandidate.candidateState, "EQUIPPABLE", "known equippable candidate retained")
equal(bagCandidate.itemString.value, itemRef, "variant string kept intact")
equal(bagCandidate.itemGUID.state, "KNOWN", "location GUID captured")
equal(bagCandidate.currentItemLevel.value, 276, "candidate level read from instance location")
equal(equippedCandidate.currentItemLevel.value, 289, "same base ID can have distinct instance level")
equal(bagCandidate.itemID.value, equippedCandidate.itemID.value, "two candidate instances may share a base item ID")
check(bagCandidate.observedLocation.type ~= equippedCandidate.observedLocation.type,
    "same-base candidates retain distinct observed locations")
equal(bagCandidate.isBound.value, false, "known false bound evidence preserved")
equal(bagCandidate.itemBindToAccount.value, true, "item-info account binding predicate retained raw")
equal(bagCandidate.tooltipBindingType.value, Enum.TooltipDataItemBinding.BnetAccount, "typed tooltip binding captured")
equal(bagCandidate.currentCharacterCanUse.value, true, "current-character evidence captured")
check(bagCandidate.accountCanUse == nil and bagCandidate.transferableToAlt == nil
    and bagCandidate.recommendedUpgrade == nil and bagCandidate.demand == nil
    and bagCandidate.surplus == nil and bagCandidate.disposition == nil, "no derived gear/economic policy fields")
local function rawCandidate() return C.GetGearCandidate("bag", 0, 1, 240001, link) end
local function rawEquipmentCandidate() return C.GetGearCandidate("equipment", nil, 1, 240001, link) end
local debugCandidate, _, debugObservation = C.GetGearCandidate("bag", 0, 1, 240001, link)
check(debugCandidate ~= nil and debugObservation.tooltipDataExists and debugObservation.itemBindingLineExists,
    "temporary tooltip diagnostic reports an ItemBinding line")
check(#debugObservation.lineFields > 0 and #debugObservation.argsShape == 1,
    "temporary tooltip diagnostic exposes bounded primitive line and args fields")
local savedAPIs = {
    itemID = C_Item.GetItemID, exists = C_Item.DoesItemExist, itemLink = C_Item.GetItemLink, guid = C_Item.GetItemGUID,
    invType = C_Item.GetItemInventoryType, currentLevel = C_Item.GetCurrentItemLevel,
    isBound = C_Item.IsBound, boundUntil = C_Item.IsBoundToAccountUntilEquip,
    info = C_Item.GetItemInfo, equippable = C_Item.IsEquippableItem,
    bindAccount = C_Item.IsItemBindToAccount, bindUntil = C_Item.IsItemBindToAccountUntilEquip,
    cached = C_Item.IsItemDataCached, canUse = C_PlayerInfo.CanUseItem,
    bagTooltip = C_TooltipInfo.GetBagItem,
}
local candidate = rawCandidate()
equal(candidate.observedLocation.type, "CONTAINER_SLOT", "bag ItemLocation represented as observation location")
expectedLocation = { bagID = 0, slot = 1 }
candidate = rawCandidate()
expectedLocation = nil
equal(candidate.itemGUID.value, "bag-0-1", "bag constructor preserves exact location arguments")
expectedLocation = { slot = 1 }
candidate = rawEquipmentCandidate()
expectedLocation = nil
equal(candidate.itemGUID.value, "equipment--1", "equipment constructor preserves exact slot argument")
C_Item.GetCurrentItemLevel = function() return 312 end
candidate = rawCandidate(); equal(candidate.currentItemLevel.value, 312, "same base item accepts a distinct instance level")
C_Item.GetCurrentItemLevel = function() return nil end
candidate = rawCandidate(); equal(candidate.currentItemLevel.state, "UNKNOWN", "missing location level remains unknown")
C_Item.GetCurrentItemLevel = function() error("location unavailable") end
candidate = rawCandidate(); equal(candidate.currentItemLevel.state, "UNKNOWN", "instance API error remains unknown")
local secretLevel = {}
issecretvalue = function(value) return value == secretLevel end
C_Item.GetCurrentItemLevel = function() return secretLevel end
candidate = rawCandidate(); equal(candidate.currentItemLevel.state, "UNKNOWN", "secret-like instance level remains unknown")
issecretvalue = nil
C_Item.GetCurrentItemLevel = savedAPIs.currentLevel
C_Item.GetItemInventoryType = function() return nil end
candidate = rawCandidate(); equal(candidate.equipType.state, "UNKNOWN", "missing equip type remains unknown")
C_Item.GetItemInventoryType = savedAPIs.invType
C_Item.GetItemInfo = function() return "x", link, 4, 200, 0, "Armor", "Plate", 1, "INVTYPE_HEAD", 1, 1, 4, 4 end
candidate = rawCandidate(); equal(candidate.requiredLevel.value, 0, "explicit required-level zero stays known")
C_Item.GetItemInfo = function() return "x", link, 4, 200, nil, "Armor", "Plate", 1, "INVTYPE_HEAD", 1, 1, 4, 4 end
candidate = rawCandidate(); equal(candidate.requiredLevel.state, "UNKNOWN", "missing required level remains unknown")
C_Item.IsBound = function() return true end
C_Item.IsBoundToAccountUntilEquip = function() return true end
candidate = rawCandidate(); equal(candidate.isBound.value, true, "bound true preserved"); equal(candidate.boundToAccountUntilEquip.value, true, "Warbound-until-equipped predicate preserved")
C_Item.IsBoundToAccountUntilEquip = function() return false end
candidate = rawCandidate(); equal(candidate.boundToAccountUntilEquip.value, false, "specific binding-state false preserved independently")
C_Item.GetItemGUID = function() return nil end
candidate = rawCandidate(); equal(candidate.itemGUID.state, "UNKNOWN", "absent GUID stays unknown")
C_Item.GetItemGUID = savedAPIs.guid
local variantLink = link:gsub("240001:7440", "240001:7441")
C_Item.GetItemLink = function() return link end
candidate = C.GetGearCandidate("bag", 0, 1, 240001, variantLink)
equal(candidate.candidateState, "UNKNOWN", "same-base replacement variant invalidates location evidence")
equal(candidate.currentItemLevel.state, "UNKNOWN", "same-base replacement receives no instance level")
C_Item.GetItemLink = function() return variantLink end
candidate = C.GetGearCandidate("bag", 0, 1, 240001, variantLink)
equal(candidate.itemString.value, variantLink:match("(item:[^|]+)"), "distinct full item string retained for same base ID")
equal(candidate.itemID.value, 240001, "variant remains associated with same base ID")
C_Item.GetItemLink = savedAPIs.itemLink
C_TooltipInfo.GetBagItem = function() return { lines = { { leftText = "Warbound" } } } end
candidate = rawCandidate(); equal(candidate.tooltipBindingType.state, "UNKNOWN", "localized tooltip text is never parsed")
C_TooltipInfo.GetBagItem = nil
candidate = rawCandidate(); equal(candidate.tooltipBindingType.state, "UNKNOWN", "unavailable tooltip API remains unknown")
C_TooltipInfo.GetBagItem = savedAPIs.bagTooltip
C_TooltipInfo.GetBagItem = function() return { lines = { { type = Enum.TooltipDataLineType.ItemBinding,
    args = { { field = "bindingType", intVal = 999 } } } } } end
candidate = rawCandidate(); equal(candidate.tooltipBindingType.state, "UNKNOWN", "unknown typed tooltip enum stays unknown")
equal(candidate.tooltipBindingType.rawValue, 999, "unknown typed tooltip enum raw value retained")
C_TooltipInfo.GetBagItem = function() return { lines = { { type = Enum.TooltipDataLineType.ItemBinding,
    args = { { field = "bindingType", intVal = Enum.TooltipDataItemBinding.BindToAccountUntilEquipped } } } } } end
candidate = rawCandidate(); equal(candidate.tooltipBindingType.value,
    Enum.TooltipDataItemBinding.BindToAccountUntilEquipped, "typed account-until-equipped enum captured")
C_TooltipInfo.GetBagItem = function() return { lines = { { type = Enum.TooltipDataLineType.ItemBinding,
    bonding = Enum.TooltipDataItemBinding.Soulbound, leftText = "localized display text" } } } end
candidate, _, debugObservation = C.GetGearCandidate("bag", 0, 1, 240001, link)
equal(candidate.tooltipBindingType.state, "UNKNOWN", "diagnostic bonding field does not change production binding semantics")
local bondingFound, displayTextFound = false, false
for _, field in ipairs(debugObservation.lineFields) do
    if field.key == "bonding" and field.value == Enum.TooltipDataItemBinding.Soulbound then bondingFound = true end
    if field.key == "leftText" then displayTextFound = true end
end
check(bondingFound and not displayTextFound, "diagnostic exposes bonding and omits localized display text")
C_TooltipInfo.GetBagItem = function() return nil end
candidate, _, debugObservation = C.GetGearCandidate("bag", 0, 1, 240001, link)
check(not debugObservation.tooltipDataExists and not debugObservation.itemBindingLineExists,
    "missing tooltip data is represented safely")
C_TooltipInfo.GetBagItem = function() error("tooltip API unavailable") end
candidate, _, debugObservation = C.GetGearCandidate("bag", 0, 1, 240001, link)
check(not debugObservation.tooltipDataExists and not debugObservation.itemBindingLineExists,
    "tooltip API error is represented safely")
C_TooltipInfo.GetBagItem = function()
    local line = { type = Enum.TooltipDataLineType.ItemBinding }
    setmetatable(line, { __index = function() error("unexpected tooltip payload") end })
    return { lines = { line } }
end
candidate, _, debugObservation = C.GetGearCandidate("bag", 0, 1, 240001, link)
check(debugObservation.unexpectedPayload and candidate.tooltipBindingType.state == "UNKNOWN",
    "unexpected tooltip payload remains safe and unknown")
C_TooltipInfo.GetBagItem = function() return { lines = { { leftText = "localized only" } } } end
candidate, _, debugObservation = C.GetGearCandidate("bag", 0, 1, 240001, link)
check(debugObservation.tooltipDataExists and not debugObservation.itemBindingLineExists,
    "missing ItemBinding line is represented safely")
C_TooltipInfo.GetBagItem = function()
    local line = { type = Enum.TooltipDataLineType.ItemBinding, args = {} }
    for index = 1, 30 do line["field" .. index] = index end
    for index = 1, 12 do line.args[index] = { field = "key" .. index, intVal = index } end
    return { lines = { line } }
end
candidate, _, debugObservation = C.GetGearCandidate("bag", 0, 1, 240001, link)
check(#debugObservation.lineFields == 24 and debugObservation.lineFieldsTruncated
    and #debugObservation.argsShape == 8
    and debugObservation.argsTruncated, "diagnostic primitive keys and args have fixed bounds")
C_TooltipInfo.GetBagItem = savedAPIs.bagTooltip
C_PlayerInfo.CanUseItem = function() return false end
candidate = rawCandidate(); equal(candidate.currentCharacterCanUse.value, false, "current-character false is preserved")
C_PlayerInfo.CanUseItem = function() error("unavailable") end
candidate = rawCandidate(); equal(candidate.currentCharacterCanUse.state, "UNKNOWN", "current-character API error stays unknown")
C_Item.GetItemID = function() return 100 end
candidate = rawCandidate(); equal(candidate.candidateState, "UNKNOWN", "replaced location cannot assert candidate identity")
equal(candidate.itemGUID.state, "UNKNOWN", "replaced location cannot attach a GUID")
C_Item.IsEquippableItem = function() return false end
C_Item.GetItemID = savedAPIs.itemID
local nonEquippable, state = rawCandidate(); equal(nonEquippable, nil, "known non-equippable omitted"); equal(state, "not-equippable", "non-equippable result explicit internally")
locationsValid = false
baseEquipLocation = "INVTYPE_NON_EQUIP_IGNORE"
candidate, state = rawCandidate()
equal(candidate, nil, "invalid location plus definitive non-equippable item is omitted")
equal(state, "not-equippable", "invalid location does not mask definitive non-equippable evidence")
C_Item.IsEquippableItem = function() return nil end
candidate, state = rawCandidate()
equal(candidate.candidateState, "UNKNOWN", "invalid location plus unresolved classification is retained")
equal(candidate.itemGUID.state, "UNKNOWN", "invalid location cannot attach instance GUID")
locationsValid = true
baseEquipLocation = "INVTYPE_HEAD"
C_Item.IsEquippableItem = function() return true end
C_Item.IsItemDataCached = function() return false end
C_Item.IsEquippableItem = function() return false end
candidate, state = rawCandidate(); equal(candidate.candidateState, "UNKNOWN", "uncached item not dropped as non-equippable")
check(requests > 1, "location-scoped async loading requested")
for key, value in pairs(savedAPIs) do
    if key == "itemID" then C_Item.GetItemID = value
    elseif key == "exists" then C_Item.DoesItemExist = value
    elseif key == "itemLink" then C_Item.GetItemLink = value
    elseif key == "guid" then C_Item.GetItemGUID = value
    elseif key == "invType" then C_Item.GetItemInventoryType = value
    elseif key == "currentLevel" then C_Item.GetCurrentItemLevel = value
    elseif key == "isBound" then C_Item.IsBound = value
    elseif key == "boundUntil" then C_Item.IsBoundToAccountUntilEquip = value
    elseif key == "info" then C_Item.GetItemInfo = value
    elseif key == "equippable" then C_Item.IsEquippableItem = value
    elseif key == "bindAccount" then C_Item.IsItemBindToAccount = value
    elseif key == "bindUntil" then C_Item.IsItemBindToAccountUntilEquip = value
    elseif key == "cached" then C_Item.IsItemDataCached = value
    elseif key == "canUse" then C_PlayerInfo.CanUseItem = value
    elseif key == "bagTooltip" then C_TooltipInfo.GetBagItem = value end
end
local retailProject = WOW_PROJECT_ID
WOW_PROJECT_ID = 2
equal(C.CollectGearCandidates(), nil, "candidate collector is Retail-only")
equal(S.GetSnapshot().gearCandidates, nil, "Retail sidecar is not exposed for another client family")
WOW_PROJECT_ID = retailProject
equal(#S.record.sections.spells.data.entries, 5, "deduplicated learned spells including profession abilities")
equal(S.record.sections.spells.data.entries[5].spellID, 1005, "profession spell outside class tab ranges")
equal(#S.record.sections.professions.data.entries, 3, "canonical professions")
equal(S.record.sections.bank, nil, "closed bank not fabricated")
local frozen = S.GetSnapshot()
local rendered = S.Render(frozen)
check(rendered:find("WOWSYNC v1", 1, true) == 1 and rendered:find("[END]", 1, true), "same canonical envelope")
equal(S.Render(frozen), rendered, "deterministic rendering")
for _, key in ipairs(S.order) do check(rendered:find(S.RenderSection(key, frozen), 1, true), "shared section renderer " .. key) end
check(rendered:find("ClientFamily: Retail", 1, true), "Retail metadata rendered")
check(rendered:find(itemRef, 1, true), "full itemRef rendered")
check(rendered:find("[GEAR CANDIDATES]", 1, true), "candidate sidecar rendered additively")
check(rendered:find("[DEBUG TOOLTIP ITEM BINDING]", 1, true), "temporary typed-tooltip diagnostic is rendered")
check(rendered:find("Temporary diagnostic; display text omitted", 1, true), "diagnostic scope is explicit")
check(rendered:find("field=bindingType,intVal=", 1, true), "structured args fields are visible in diagnostic export")
check(not rendered:find("localized display text", 1, true), "diagnostic export excludes localized tooltip text")
check(#(S.record.gearCandidates.tooltipBindingDiagnostics or {}) <= 3,
    "at most one tooltip diagnostic observation per source")
check(not S.Render(frozen, { "bags", "bank" }):find("[GEAR CANDIDATES]", 1, true), "focused legacy section rendering excludes sidecar")
check(S.Render(frozen, { "gearCandidates" }):find("[GEAR CANDIDATES]", 1, true), "focused sidecar selection is supported")
check(not rendered:find("transferableToAlt", 1, true) and not rendered:find("accountCanUse", 1, true)
    and not rendered:find("recommendedUpgrade", 1, true) and not rendered:find("surplus", 1, true), "renderer has no derived policy outputs")
check(not rendered:find("Not a rank", 1, true), "no manufactured rank")
local goodGearCandidates = S.record.gearCandidates
local originalRanges = C.GetBankRanges
C.GetBankRanges = function() return nil, nil end
event("BAG_UPDATE_DELAYED"); advance(3)
equal(S.record.gearCandidates.observedAt, goodGearCandidates.observedAt, "failed candidate refresh retains prior observation")
equal(#S.record.gearCandidates.candidates, #goodGearCandidates.candidates, "failed candidate refresh retains prior rows")
C.GetBankRanges = originalRanges
event("BAG_UPDATE_DELAYED"); advance(1)
BankFrame:Show(); event("BANKFRAME_OPENED"); advance(1)
equal(#S.record.sections.bank.data.containers, 2, "character purchased tabs only")
local bankCandidateSeen = false
for _, candidate in ipairs(S.record.gearCandidates.candidates) do
    if candidate.observedLocation.type == "BANK_SLOT" then bankCandidateSeen = true end
end
check(bankCandidateSeen, "viewable Character Bank candidates included")
check(S.Render(S.GetSnapshot()):find("ACCOUNT/Warband API-supported but deferred", 1, true), "explicit account limitation")
local bankObserved = S.record.sections.bank.observedAt
bankView = false; event("BANK_TABS_CHANGED"); advance(3)
equal(S.record.sections.bank.observedAt, bankObserved, "unviewable bank preserves last seen data")
local bankCandidateLastSeen = false
for _, candidate in ipairs(S.record.gearCandidates.candidates) do
    if candidate.observedLocation.type == "BANK_SLOT" and candidate.observationState == "LAST_SEEN" then bankCandidateLastSeen = true end
end
check(bankCandidateLastSeen, "inaccessible bank candidate retained as last-seen")
check(S.record.sections.bank.lastAttemptError, "unviewable refresh reported")
check(S.RenderSection("bank", S.GetSnapshot()):find("LAST_SEEN", 1, true), "unviewable open bank is last seen")
event("BANKFRAME_CLOSED"); BankFrame:Hide()
check(S.RenderSection("bank", S.GetSnapshot()):find("LAST_SEEN", 1, true), "closed bank stale label")
bankView = true
pending = true; event("PLAYER_EQUIPMENT_CHANGED"); advance(3)
equal(S.record.sections.equipment.completeness, "partial", "delayed modern equipment partial")
equal(S.record.sections.equipment.data.slots[1].itemString, itemRef, "identity survives metadata delay")
check(requests > 1, "metadata loading requested")
local pendingCandidate
for _, candidate in ipairs(S.record.gearCandidates.candidates) do
    if candidate.observedLocation.type == "EQUIPMENT_SLOT" then pendingCandidate = candidate end
end
check(pendingCandidate and pendingCandidate.candidateState == "UNKNOWN", "uncached equippability remains an unknown candidate")
equal(pendingCandidate.currentItemLevel.state, "UNKNOWN", "pending instance level remains unknown")
check(S.Render(S.GetSnapshot()):find("UNKNOWN", 1, true), "unknown evidence round-trips through snapshot/render")
check(S.dirty.gearCandidates == nil, "candidate asynchronous retries exhaust within bounded scheduler")
pending = false; event("ITEM_DATA_LOAD_RESULT", 240001); advance(1)
equal(S.record.sections.equipment.completeness, "complete", "metadata event repairs equipment")
check(S.record.gearCandidates.completeness == "complete", "candidate retry resolves after item data event")
event("TRAINER_SHOW"); advance(1)
equal(S.record.sections.trainer.data.snapshots.PROF_ALCHEMY.services[1].requiredLevel, 80, "canonical Retail trainer tuple")
event("TRAINER_CLOSED"); trainerCategory = "Blacksmithing"; event("TRAINER_SHOW"); advance(1); event("TRAINER_CLOSED")
trainerCategory = nil; serviceCount = 0; event("TRAINER_SHOW"); advance(3); event("TRAINER_CLOSED")
local snapshots = S.record.sections.trainer.data.snapshots
check(snapshots.PROF_ALCHEMY and snapshots.PROF_BLACKSMITHING and snapshots.UNKNOWN, "multi-category persistence")
equal(#snapshots.UNKNOWN.services, 0, "no invented trainer rows")
equal(snapshots.UNKNOWN.completeness, "partial", "empty trainer honest partial")
local oldRecord = S.record
playerGUID = "Player-Retail-B"; S.record = nil; S.Initialize(); S.RequestSync(); advance(1)
check(S.record ~= oldRecord and not S.record.sections.trainer, "character separation")
equal(WoWSyncDB.characters["Player-Retail-A"], oldRecord, "previous character retained")
C_Map = nil; S.Mark("location"); advance(1)
equal(S.record.sections.location.data.mapID, nil, "missing optional map")
equal(S.record.sections.location.data.zone, "Silvermoon", "zone survives absent map")
SlashCmdList.WOWSYNC(""); advance(4)
check(S.record.latestExport.text:find("WOWSYNC v1", 1, true) == 1, "UI copyable canonical export")
local stable = S.record.latestExport.text
event("PLAYER_MONEY"); advance(1)
equal(S.record.latestExport.text, stable, "copy text stable after background refresh")
for _, command in ipairs({ "GEAREXPORT", "GEARITEMEXPORT", "GEARINVENTORYEXPORT", "GEARTRAINEREXPORT" }) do
    SlashCmdList[command](command == "GEARITEMEXPORT" and "240001" or "")
    check(GearExportDB.latestExport, "Retail legacy command " .. command)
end
SlashCmdList.GEARINVENTORYEXPORT("")
check(GearExportDB.latestExport:find("Free bag slots: 50 / 52", 1, true), "legacy Retail summary includes reagent bag capacity")
-- Movement, readiness, omitted APIs, and storage edge cases.
local originalInfo = C_Container.GetContainerItemInfo
C_Container.GetContainerItemInfo = function(bag, slot)
    local info = originalInfo(bag, slot)
    if info then info.isLocked = true end
    return info
end
local bagObserved = S.record.sections.bags.observedAt
event("ITEM_LOCK_CHANGED"); advance(3)
equal(S.record.sections.bags.observedAt, bagObserved, "locked inventory preserves observation")
check(S.record.sections.bags.lastAttemptError:find("movement", 1, true), "lock reason")
C_Container.GetContainerItemInfo = originalInfo
event("BAG_UPDATE_DELAYED"); advance(1)
check(S.record.sections.bags.observedAt > bagObserved, "settled movement captured")
C_Container.GetContainerItemInfo = function(bag, slot)
    local info = originalInfo(bag, slot)
    if info then info.hyperlink = nil end
    return info
end
event("BAG_UPDATE"); advance(3)
equal(S.record.sections.bags.completeness, "partial", "missing instance link partial")
equal(S.record.sections.bags.data.containers[1].slots[1].itemString, nil, "generic cached link never replaces instance identity")
C_Container.GetContainerItemInfo = originalInfo
event("BAG_UPDATE"); advance(1)
local originalFree = C_Container.GetContainerNumFreeSlots
C_Container.GetContainerNumFreeSlots = function() return 0, 0 end
bagObserved = S.record.sections.bags.observedAt
event("BAG_UPDATE"); advance(3)
equal(S.record.sections.bags.observedAt, bagObserved, "free/occupied mismatch does not overwrite")
C_Container.GetContainerNumFreeSlots = originalFree
event("BAG_UPDATE"); advance(1)
BankFrame:Show(); event("BANKFRAME_OPENED"); advance(1)
local tabObserved = S.record.sections.bank.observedAt
local originalSlots = C_Container.GetContainerNumSlots
C_Container.GetContainerNumSlots = function(bag) if bag == 6 then return 0 end; return originalSlots(bag) end
event("BANK_TABS_CHANGED"); advance(3)
equal(S.record.sections.bank.observedAt, tabObserved, "zero purchased-tab capacity is pending")
C_Container.GetContainerNumSlots = originalSlots
local originalPurchased = C_Bank.FetchNumPurchasedBankTabs
C_Bank.FetchNumPurchasedBankTabs = function() return 3 end
event("BANK_TABS_CHANGED"); advance(3)
equal(S.record.sections.bank.observedAt, tabObserved, "purchased count mismatch preserves bank")
C_Bank.FetchNumPurchasedBankTabs = originalPurchased
event("BANK_TABS_CHANGED"); advance(1)
event("BANKFRAME_CLOSED"); BankFrame:Hide()
local originalCursor = GetCursorInfo
GetCursorInfo = function() return "item", 240001 end
bagObserved = S.record.sections.bags.observedAt
event("ITEM_LOCK_CHANGED"); advance(3)
equal(S.record.sections.bags.observedAt, bagObserved, "cursor movement is not captured as settled")
GetCursorInfo = originalCursor
event("BAG_UPDATE_DELAYED"); advance(1)
local originalProfessions = GetProfessions
GetProfessions = function() return nil, nil, nil, nil, nil end
event("SKILL_LINES_CHANGED"); advance(1)
equal(#S.record.sections.professions.data.entries, 0, "no tracked professions has empty declared coverage")
GetProfessions = originalProfessions
local originalProfessionInfo = GetProfessionInfo
GetProfessionInfo = function() return nil end
event("TRADE_SKILL_LIST_UPDATE"); advance(3)
equal(S.record.sections.professions.completeness, "partial", "missing profession fields are partial")
GetProfessionInfo = originalProfessionInfo
event("TRADE_SKILL_DATA_SOURCE_CHANGED"); advance(1)
equal(#S.record.sections.professions.data.entries, 3, "profession refresh event")
spells[1].spellID = 0
event("SPELL_TEXT_UPDATE"); advance(3)
equal(S.record.sections.spells.completeness, "partial", "invalid spell identity partial")
for _, entry in ipairs(S.record.sections.spells.data.entries) do check(entry.spellID ~= 0, "never export invalid spell ID") end
spells[1].spellID = 1001
event("PLAYER_SPECIALIZATION_CHANGED", "player"); advance(1)
equal(S.record.sections.spells.completeness, "complete", "spec event refresh")
local originalSpellAPI = C_SpellBook
C_SpellBook = nil
local spellsObserved = S.record.sections.spells.observedAt
event("SPELLS_CHANGED"); advance(3)
equal(S.record.sections.spells.observedAt, spellsObserved, "missing spell API preserves snapshot")
C_SpellBook = originalSpellAPI
event("SPELLS_CHANGED"); advance(1)
local originalStats = C_Item.GetItemStats
local secret = {}
issecretvalue = function(value) return value == secret end
C_Item.GetItemStats = function() return { ITEM_MOD_HASTE_RATING_SHORT = secret } end
event("PLAYER_EQUIPMENT_CHANGED"); advance(3)
equal(S.record.sections.equipment.completeness, "partial", "restricted stat remains partial")
equal(#S.record.sections.equipment.data.slots[1].stats, 0, "restricted stat not exposed")
C_Item.GetItemStats = originalStats; issecretvalue = nil
event("PLAYER_EQUIPMENT_CHANGED"); advance(1)
local oldRender = S.Render(S.GetSnapshot())
local renderClock = GetServerTime
GetServerTime = function() error("renderer queried clock") end
local snapshot = { schemaVersion = 1, generatedAt = 42, sections = S.Copy(S.record.sections), visits = S.Copy(S.record.visits), access = {} }
equal(S.Render(snapshot), S.Render(snapshot), "frozen rendering never reads clock")
GetServerTime = renderClock
check(oldRender:find("[PROFESSIONS]", 1, true), "schema sections retained")
-- Reinitialize with the same SavedVariables as /reload would.
assert(loadfile("tests/played_test.lua"))()(S, check, equal, advance, addon)
assert(loadfile("tests/retail_played_test.lua"))()(S, check, equal, advance)
local savedDB = WoWSyncDB
local reloaded = {}
for _, file in ipairs({ "GearExport.lua", "WoWSyncCore.lua", "WoWSyncCollectors.lua", "WoWSyncRender.lua" }) do
    assert(loadfile(file))("GearExport", reloaded)
end
reloaded.Sync.Initialize()
equal(WoWSyncDB, savedDB, "reload preserves database")
check(WoWSyncDB.characters["Player-Retail-A"].sections.trainer.data.snapshots.PROF_ALCHEMY, "trainer persistence across reload")
check(not SlashCmdList.BANKCLEANUP, "Retail does not load BankCleanup")
equal(actions, 0, "no actions")
print("PASS: " .. passed .. " Retail assertions; 0 gameplay actions")
