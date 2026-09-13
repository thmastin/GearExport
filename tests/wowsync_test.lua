-- Run from GearExport: fengari tests/wowsync_test.lua [path/to/v2.1/GearExport.lua]
-- Headless API fixtures verify state and output, not in-client event timing/taint.
local passed = 0
local function check(value, message)
    assert(value, message)
    passed = passed + 1
end
local function equal(a, b, message) check(a == b, message .. "\nexpected: " .. tostring(b) .. "\nactual: " .. tostring(a)) end
local frames, seconds, epoch = {}, 0, 1789000000
local guid, money, known, trainerReady, trainerMode = "Player-1-A", 12345, false, true, "profession"
local itemPending, cursor, locked, collapsed = false, false, false, false
local movingCalls, itemReads, trainerReads = 0, 0, 0
local itemLink = "|cff00ff00|Hitem:100:0:0:0:0:0:1:0|h[Sample]|h|r"
local variantLink = "|cff00ff00|Hitem:100:0:0:0:0:0:2:0|h[Sample]|h|r"
local bagItems = { [0] = { [1] = { id = 100, count = 3, link = itemLink } },
    [-1] = { [1] = { id = 100, count = 5, link = itemLink } } }
local function widget(name)
    local w = { shown = true, scripts = {}, events = {}, text = "", enabled = true, name = name }
    setmetatable(w, { __index = function(_, key)
        if key == "GetPoint" then return function() return "CENTER", nil, "CENTER", 0, 0 end end
        if key == "GetNumLines" then return function() return 1 end end
        if key == "NumLines" then return function() return 2 end end
        if key == "GetText" then return function(self) return self.text end end
        if key == "SetText" then return function(self, text) self.text = text; if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end end end
        if key == "SetScript" then return function(self, event, fn) self.scripts[event] = fn end end
        if key == "RegisterEvent" then return function(self, event) self.events[event] = true end end
        if key == "Show" then return function(self) self.shown = true end end
        if key == "Hide" then return function(self) self.shown = false end end
        if key == "IsShown" or key == "IsVisible" then return function(self) return self.shown end end
        if key == "Enable" then return function(self) self.enabled = true end end
        if key == "Disable" then return function(self) self.enabled = false end end
        if key == "CreateTexture" or key == "CreateFontString" then return function() return widget() end end
        return function() end
    end })
    if name then _G[name] = w end
    frames[#frames + 1] = w
    return w
end
function CreateFrame(_, name) return widget(name) end
UIParent = widget("UIParent")
BankFrame = widget("BankFrame"); BankFrame:Hide()
ClassTrainerFrame = widget("ClassTrainerFrame")
UISpecialFrames, SlashCmdList = {}, {}
ChatFontNormal, GameFontNormal = {}, {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
BOOKTYPE_SPELL, NUM_BAG_SLOTS, NUM_BANKBAGSLOTS, BANK_CONTAINER, NUM_BANKGENERIC_SLOTS = "spell", 4, 7, -1, 28
function GetTime() return seconds end
function GetServerTime() return epoch + math.floor(seconds) end
function time() return GetServerTime() end
function date() return "2026-09-10 12:00:00" end
function UnitGUID(unit) return unit == "player" and guid or "Creature-0-0-0-0-123-0" end
function UnitName(unit) return unit == "player" and (guid == "Player-1-A" and "Torahn" or "Alt") or "Trainer" end
function GetRealmName() return "Dreamscythe" end
function UnitClass() return "Shaman", "SHAMAN" end
function UnitLevel() return 35 end
function UnitFactionGroup() return "Horde" end
function UnitXP() return 10 end
function UnitXPMax() return 100 end
function GetBuildInfo() return "2.5.5", "68101", "", 20506 end
function GetMoney() return money end
function GetRealZoneText() return "Thunder Bluff" end
function GetSubZoneText() return "" end
function GetCursorInfo() if cursor then return "item", 100 end end
function GetItemInfo(reference)
    itemReads = itemReads + 1
    if itemPending then return nil end
    return "Sample", type(reference) == "string" and reference or itemLink, 2, 30, 25, "Armor", "Mail", 20, "INVTYPE_HEAD", 1, 12, 4, 3, 2
end
function GetInventoryItemLink(_, slot) if slot == 1 then return itemLink end end
function GetInventoryItemID(_, slot) if slot == 1 then return 100 end end
function GetInventoryItemTexture(_, slot) if slot == 1 then return 1 end end
function GetItemStats() return { ITEM_MOD_STRENGTH_SHORT = 3 } end
function GetItemCount() return 3 end
function GetNumBankSlots() return 0 end
function GetNumSkillLines() return 2 end
function GetSkillLineInfo(index)
    if index == 1 then return "Professions", true, not collapsed end
    if not collapsed then return "Mining", false, true, 100, 0, 0, 150, true end
end
function GetNumSpellTabs() return 1 end
function GetSpellTabInfo() return "General", 1, 0, known and 2 or 1 end
function GetSpellBookItemName(index) return index == 1 and "Mining" or "New spell", "Rank 1" end
function GetSpellBookItemInfo(index) return "SPELL", 200 + index end
function GetSpellLink(index) return "|Hspell:" .. (200 + index) .. "|h[Spell]|h" end
function IsTradeskillTrainer() return trainerMode == "profession" end
function IsTalentTrainer() return trainerMode == "class" end
function GetNumTrainerServices() trainerReads = trainerReads + 1; return trainerReady and 2 or 0 end
function GetTrainerServiceInfo(index)
    if index == 1 then return "Header", "", "header", true end
    return "New spell", "Rank 1", known and "used" or "available"
end
function GetTrainerServiceCost() return 100 end
function GetTrainerServiceLevelReq() return 30 end
function GetTrainerServiceSkillReq()
    if trainerMode == "profession" then return "Mining", 75, true end
    if trainerMode == "weapon" then return "Swords", 1, true end
end
function GetTrainerServiceNumAbilityReq() return 1 end
function GetTrainerServiceAbilityReq() return "Mining", true end
function GetTrainerServiceTypeFilter(status) return status ~= "used" end
local function action() movingCalls = movingCalls + 1; error("Automatic gameplay action invoked") end
BuyTrainerService, EquipItemByName, CastSpellByName, SendMail, BuyMerchantItem, UseContainerItem = action, action, action, action, action, action
C_Container = {}
function C_Container.GetContainerNumSlots(bag) return bag == -1 and 28 or bag == 0 and 16 or 0 end
function C_Container.GetContainerNumFreeSlots(bag)
    local occupied = 0
    for _ in pairs(bagItems[bag] or {}) do occupied = occupied + 1 end
    return C_Container.GetContainerNumSlots(bag) - occupied, 0
end
function C_Container.ContainerIDToInventoryID(bag) assert(bag > 0); return 19 + bag end
function C_Container.GetContainerItemInfo(bag, slot)
    local item = bagItems[bag] and bagItems[bag][slot]
    if not item then return nil end
    return { hyperlink = item.link, itemID = item.id, stackCount = item.count, isLocked = locked, isBound = item.bound or false }
end
function C_Container.GetContainerItemLink(bag, slot)
    local item = bagItems[bag] and bagItems[bag][slot]
    return item and item.link
end
C_Container.UseContainerItem, C_Container.SplitContainerItem, C_Container.PickupContainerItem = action, action, action
GetContainerNumSlots, GetContainerNumFreeSlots = C_Container.GetContainerNumSlots, C_Container.GetContainerNumFreeSlots
function GetContainerItemInfo(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info then return 1, info.stackCount, info.isLocked, 2, false, false, info.hyperlink end
end
GetContainerItemLink = C_Container.GetContainerItemLink
local function load(path, addon) assert(loadfile(path))("GearExport", addon) end
local function outputs()
    local result = {}
    for _, command in ipairs({ "GEAREXPORT", "GEARITEMEXPORT", "GEARINVENTORYEXPORT", "GEARTRAINEREXPORT" }) do
        SlashCmdList[command](command == "GEARITEMEXPORT" and "100" or "")
        result[command] = GearExportDB.latestExport
    end
    return result
end
local function legacyMatrix()
    local result = {}
    for _, mode in ipairs({ "plain", "bank", "tsm", "tsm_bank", "uncached" }) do
        if mode == "bank" or mode == "tsm_bank" then BankFrame:Show() else BankFrame:Hide() end
        itemPending = mode == "uncached"
        TSM_API = mode:find("tsm", 1, true) and {
            ToItemString = function() return "i:100" end,
            GetCustomPriceValue = function(source)
                if source == "Destroy" then error("source unavailable") end
                return source == "DBRegionSaleRate" and 0.25 or 200
            end,
            GetBankQuantity = function() return 5 end,
            GetMailQuantity = function() return 2 end,
            GetAuctionQuantity = function() return 1 end,
        } or nil
        for key, text in pairs(outputs()) do result[mode .. ":" .. key] = text end
    end
    BankFrame:Hide(); TSM_API = nil; itemPending = false
    outputs()
    return result
end
local baseline
if arg[1] then
    load(arg[1], {})
    baseline = legacyMatrix()
end
load("WoWSyncCompat.lua", {})
local addon = {}
load("GearExport.lua", addon)
local current = legacyMatrix()
if baseline then
    for key, text in pairs(baseline) do equal(current[key], text, "v2.1 legacy report unchanged: " .. key) end
end
local oldLatest = GearExportDB.latestExport
SlashCmdList.GEAREXPORT("help")
equal(GearExportDB.latestExport, oldLatest, "help does not overwrite exports")
load("BankCleanup.lua", addon)
for _, file in ipairs({ "WoWSyncCore.lua", "WoWSyncCollectors.lua", "WoWSyncRender.lua", "WoWSyncUI.lua" }) do load(file, addon) end
local S = addon.Sync
local function event(name, arg)
    S.eventFrame.scripts.OnEvent(S.eventFrame, name, arg)
end
local function advance(duration)
    for _ = 1, math.ceil(duration / 0.1) do
        seconds = seconds + 0.1
        if S.eventFrame.scripts.OnUpdate then S.eventFrame.scripts.OnUpdate() end
    end
end
event("ADDON_LOADED", "GearExport")
event("PLAYER_LOGIN")
advance(1)
check(S.record.sections.bags.data.containers[1].slots[1].count == 3, "login captures bags")
check(not S.record.sections.bank, "login does not fabricate bank")
check(not S.record.sections.trainer, "login does not fabricate trainer")
equal(S.record.sections.equipment.data.slots[1].stats[1].value, 3, "shared equipment stats")
equal(S.record.sections.professions.data.entries[1].name, "Mining", "shared professions")
check(not WoWSyncButton:IsShown(), "launcher defaults hidden")
SlashCmdList.WOWSYNC("button")
check(WoWSyncButton:IsShown() and WoWSyncDB.settings.showButton, "optional launcher toggles")
local observed = S.record.sections.bags.observedAt
local revision = S.record.sections.bags.revision
local changed = S.record.sections.bags.changedAt
for _ = 1, 100 do event("BAG_UPDATE", 0) end
equal(S.record.sections.bags.observedAt, observed, "events do not scan immediately")
advance(1)
equal(S.record.sections.bags.revision, revision, "unchanged scan retains revision")
equal(S.record.sections.bags.changedAt, changed, "unchanged scan retains change timestamp")
check(S.record.sections.bags.observedAt > observed, "unchanged successful scan refreshes observation")
local reads = itemReads
advance(5)
equal(itemReads, reads, "no idle polling")
check(S.eventFrame.scripts.OnUpdate == nil, "scheduler sleeps when clean")
bagItems[0][1].count = 7
event("BAG_UPDATE", 0); advance(1)
equal(S.record.sections.bags.data.containers[1].slots[1].count, 7, "bag changes replace current state")
equal(S.record.sections.bags.revision, revision + 1, "changed content increments revision")
BankFrame:Show(); event("BANKFRAME_OPENED"); advance(1)
equal(S.record.sections.bank.data.containers[1].slots[1].count, 5, "bank open captures bank")
local bankObserved = S.record.sections.bank.observedAt
local bankReads = itemReads
BankFrame:Hide(); event("BANKFRAME_CLOSED"); bagItems[-1] = {}; advance(1)
equal(S.record.sections.bank.data.containers[1].slots[1].count, 5, "bank close retains snapshot")
equal(S.record.sections.bank.observedAt, bankObserved, "bank close does not fake freshness")
local snapshot = S.GetSnapshot()
local text = S.Render(snapshot)
equal(S.Render(snapshot), text, "deterministic rendering")
check(text:find("LAST_SEEN", 1, true), "cached bank explicitly labeled")
check(text:find("WOWSYNC v1", 1, true) and text:sub(-5) == "[END]", "export framing")
check(text:find("[KNOWN SPELLS]", 1, true), "full export includes known spells")
local section = S.RenderSection("bags", snapshot)
check(text:find(section, 1, true), "independent renderer matches full section")
local focused = S.Render(snapshot, { "bags", "bank" })
check(not focused:find("[EQUIPMENT]", 1, true), "focused rendering uses same schema")
local liveCount = S.record.sections.bags.data.containers[1].slots[1].count
snapshot.sections.bags.data.containers[1].slots[1].count = 999
equal(S.record.sections.bags.data.containers[1].slots[1].count, liveCount, "API returns copies")

bagItems[0][2] = { id = 100, count = 2, link = itemLink }
bagItems[0][3] = { id = 100, count = 4, link = variantLink }
event("BAG_UPDATE"); advance(1)
section = S.RenderSection("bags", S.GetSnapshot())
check(section:find("Sample\t9\t", 1, true), "same variant stacks aggregate only in render")
check(section:find("Sample\t4\t", 1, true), "different suffix stays separate")
equal(S.record.sections.bags.data.containers[1].slots[2].count, 2, "physical stacks preserved")
locked = true
observed = S.record.sections.bags.observedAt
bagItems[0][1].count = 1
event("ITEM_LOCK_CHANGED"); advance(4)
equal(S.record.sections.bags.observedAt, observed, "locked scan does not refresh old data")
check(S.record.sections.bags.lastAttemptError:find("movement"), "lock failure annotated")
check(S.eventFrame.scripts.OnUpdate == nil, "retry budget bounded")
locked = false; event("ITEM_LOCK_CHANGED"); advance(1)
equal(S.record.sections.bags.data.containers[1].slots[1].count, 1, "unlock reconciles")
check(not S.record.sections.bags.lastAttemptError, "successful capture clears failure")
itemPending = true; event("BAG_UPDATE"); advance(3)
equal(S.record.sections.bags.completeness, "partial", "uncached metadata explicit")
equal(S.record.sections.bags.data.containers[1].slots[1].itemID, 100, "uncached item retains ID")
itemPending = false; event("GET_ITEM_INFO_RECEIVED", 100); advance(1)
equal(S.record.sections.bags.completeness, "complete", "metadata arrival enriches")
collapsed = true; event("SKILL_LINES_CHANGED"); advance(1)
equal(S.record.sections.professions.completeness, "partial", "collapsed skills not declared complete")
collapsed = false; event("SKILL_LINES_CHANGED"); advance(1)

trainerReady = false; event("TRAINER_SHOW"); advance(0.5)
equal(S.record.sections.trainer.completeness, "partial", "empty early trainer not complete")
trainerReady = true; event("TRAINER_UPDATE"); advance(1)
local professionTrainer = S.record.sections.trainer.data.snapshots.PROF_MINING
equal(#professionTrainer.services, 1, "trainer updates capture services")
equal(professionTrainer.services[1].skillRequirement.rank, 75, "skill requirement retained")
check(not professionTrainer.services[1].spellID, "trainer index never masquerades as spell ID")
equal(S.record.sections.trainer.completeness, "partial", "filtered trainer coverage explicit")
known = true; event("SPELLS_CHANGED"); event("TRAINER_UPDATE"); advance(1)
equal(#S.record.sections.spells.data.entries, 2, "learning refreshes known spellbook")
equal(S.record.sections.trainer.data.snapshots.PROF_MINING.services[1].status, "used", "learning refreshes trainer status")
event("TRAINER_UPDATE"); event("TRAINER_CLOSED")
trainerReads = 0; advance(3)
equal(trainerReads, 0, "closed trainer cancels delayed scans")
check(S.record.visits.trainers.PROF_MINING.unreconciled, "closing pending trainer flags uncertainty")

-- Distinct trainer categories retain independent snapshots and visits.
trainerMode, trainerReady = "weapon", true; event("TRAINER_SHOW"); event("TRAINER_UPDATE"); advance(1)
check(S.record.sections.trainer.data.snapshots.PROF_MINING ~= nil, "weapon visit retains profession snapshot")
check(S.record.sections.trainer.data.snapshots.WEAPON ~= nil, "weapon trainer stored separately")
event("TRAINER_CLOSED")
trainerMode = "class"; event("TRAINER_SHOW"); event("TRAINER_UPDATE"); advance(1)
check(S.record.sections.trainer.data.snapshots.CLASS ~= nil, "class trainer stored separately")
check(S.record.sections.trainer.data.snapshots.WEAPON ~= nil, "class visit retains weapon snapshot")
event("TRAINER_CLOSED")
local professionObserved = S.record.sections.trainer.data.snapshots.PROF_MINING.observedAt
money = 54321; trainerMode = "class"; event("TRAINER_SHOW"); event("TRAINER_UPDATE"); advance(1)
equal(S.record.sections.trainer.data.snapshots.CLASS.moneyAtVisit, 54321, "revisit updates class snapshot")
equal(S.record.sections.trainer.data.snapshots.PROF_MINING.observedAt, professionObserved,
    "revisit does not update profession snapshot")
event("TRAINER_CLOSED")
local trainerText = S.RenderSection("trainer", S.GetSnapshot())
check(trainerText:find("[PROF_MINING]", 1, true) and trainerText:find("[WEAPON]", 1, true)
    and trainerText:find("[CLASS]", 1, true), "multi-trainer export has deterministic category blocks")
check(trainerText:find("LAST_SEEN", 1, true), "closed trainer categories retain stale state")
local trainerTextAgain = S.RenderSection("trainer", S.GetSnapshot())
equal(trainerTextAgain, trainerText, "multi-trainer rendering is deterministic")
trainerMode, trainerReady = "weapon", false; event("TRAINER_SHOW"); advance(1)
check(S.record.sections.trainer.data.snapshots.UNKNOWN ~= nil,
    "empty ambiguous trainer is preserved as UNKNOWN")
check(S.record.sections.trainer.data.snapshots.CLASS ~= nil,
    "empty ambiguous trainer does not erase CLASS")
event("TRAINER_CLOSED"); trainerReady = true

local callbackText
check(S.Export(function(result) callbackText = result end), "export request accepted")
advance(4)
check(callbackText and callbackText:find("[END]", 1, true), "sync generates consolidated export")
equal(GearExportDB.latestExport, oldLatest, "sync does not overwrite legacy latestExport")
equal(S.record.latestExport.text, callbackText, "single latest consolidated export saved")
local frozen = callbackText
money = 999; event("PLAYER_MONEY"); advance(1)
equal(S.record.latestExport.text, frozen, "background events do not rewrite displayed export")
local oldRecord = S.record
guid = "Player-1-B"; S.record = nil; event("PLAYER_LOGIN"); advance(1)
check(S.record ~= oldRecord, "characters isolated by GUID")
check(not S.record.sections.bank, "alt does not inherit bank")
equal(WoWSyncDB.characters["Player-1-A"], oldRecord, "previous character remains available")
equal(movingCalls, 0, "no gameplay action APIs called")

-- Render without access to any live data APIs.
snapshot = S.GetSnapshot()
local oldTime, oldMoney = GetServerTime, GetMoney
GetServerTime, GetMoney = action, action
check(S.Render(snapshot):find("[END]", 1, true), "renderer independent of client APIs")
GetServerTime, GetMoney = oldTime, oldMoney

-- Failure handling and compatibility branches.
local containerAPI = C_Container
local legacyInfo, legacyLink = GetContainerItemInfo, GetContainerItemLink
local legacyFree = GetContainerNumFreeSlots
C_Container = nil
GetContainerNumFreeSlots = function(bag)
    local occupied = 0
    for _ in pairs(bagItems[bag] or {}) do occupied = occupied + 1 end
    return containerAPI.GetContainerNumSlots(bag) - occupied, 0
end
GetContainerItemInfo = function(bag, slot)
    local info = containerAPI.GetContainerItemInfo(bag, slot)
    if info then return 1, info.stackCount, info.isLocked, 2, false, false, info.hyperlink end
end
GetContainerItemLink = containerAPI.GetContainerItemLink
event("BAG_UPDATE"); advance(1)
check(not S.record.sections.bags.lastAttemptError, "legacy fallback scan succeeds")
equal(S.record.sections.bags.data.containers[1].slots[1].count, 1, "legacy tuple container API supported")
check(S.record.sections.bags.data.containers[1].slots[1].bound == nil, "unknown legacy binding is not false")
C_Container, GetContainerItemInfo, GetContainerItemLink = containerAPI, legacyInfo, legacyLink
GetContainerNumFreeSlots = legacyFree
local getInfo = GetItemInfo
observed = S.record.sections.bags.observedAt
GetItemInfo = function() error("fixture cache error") end
event("BAG_UPDATE"); advance(3)
equal(S.record.sections.bags.observedAt, observed, "collector exception preserves snapshot freshness")
check(S.record.sections.bags.lastAttemptError:find("Collector error", 1, true), "collector exception reported")
GetItemInfo = getInfo; event("BAG_UPDATE"); advance(1)
local slotInfo = C_Container.GetContainerItemInfo
C_Container.GetContainerItemInfo = function() return nil end
observed = S.record.sections.bags.observedAt
event("BAG_UPDATE"); advance(3)
equal(S.record.sections.bags.observedAt, observed, "inconsistent free/occupied slots do not publish empty inventory")
C_Container.GetContainerItemInfo = slotInfo; event("BAG_UPDATE"); advance(1)
local inventoryLink = GetInventoryItemLink
GetInventoryItemLink = function(unit, slot) if slot == 20 then return itemLink end; return inventoryLink(unit, slot) end
event("BAG_UPDATE"); advance(3)
check(S.record.sections.bags.lastAttemptError:find("capacity pending", 1, true), "equipped bag with zero capacity is not considered empty")
GetInventoryItemLink = inventoryLink; event("BAG_UPDATE"); advance(1)
cursor = true; event("BAG_UPDATE"); advance(3)
check(S.record.sections.bags.lastAttemptError:find("movement", 1, true), "cursor movement defers capture")
cursor = false; event("BAG_UPDATE"); advance(1)

-- A tooltip-derived random stat must override incomplete GetItemStats values.
ITEM_MOD_STRENGTH_SHORT = "Strength"
GearExportStatScanTooltipTextLeft2 = { GetText = function() return "+7 Strength" end }
event("PLAYER_EQUIPMENT_CHANGED", 1); advance(1)
equal(S.record.sections.equipment.data.slots[1].stats[1].value, 7, "resolved tooltip overrides base item stats")
local tooltipLines = GearExportStatScanTooltip.NumLines
GearExportStatScanTooltip.NumLines = function() return 0 end
event("PLAYER_EQUIPMENT_CHANGED", 1); advance(3)
equal(S.record.sections.equipment.completeness, "partial", "unready tooltip does not claim complete stats")
GearExportStatScanTooltip.NumLines = tooltipLines; event("GET_ITEM_INFO_RECEIVED", 100); advance(1)
equal(S.record.sections.equipment.completeness, "complete", "tooltip metadata retry completes")

-- Tooltip cleanup must not turn a successful scan into a false partial result.
local tooltip = GearExportStatScanTooltip
local priorHide, priorSet = tooltip.Hide, tooltip.SetInventoryItem
tooltip.Hide = function(self) self.fixtureLines = 0 end
tooltip.SetInventoryItem = function(self) self.fixtureLines = 2 end
tooltip.NumLines = function(self) return self.fixtureLines or 0 end
event("PLAYER_EQUIPMENT_CHANGED", 1); advance(1)
equal(S.record.sections.equipment.completeness, "complete", "readiness measured before tooltip cleanup")
equal(S.record.sections.equipment.data.slots[1].stats[1].value, 7, "tooltip cleanup does not change interpreted stats")
tooltip.Hide, tooltip.SetInventoryItem, tooltip.NumLines = priorHide, priorSet, tooltipLines

local registered = {
    SLASH_GEAREXPORT1 = "/gearexport", SLASH_GEAREXPORT2 = "/gearx",
    SLASH_GEARITEMEXPORT1 = "/itemx", SLASH_GEARHELP1 = "/gearhelp",
    SLASH_GEARINVENTORYEXPORT1 = "/bagsx", SLASH_GEARTRAINEREXPORT1 = "/trainerx",
    SLASH_GEARBANKCLEANUP1 = "/bankx", SLASH_WOWSYNC1 = "/wowsync",
}
for key, command in pairs(registered) do equal(_G[key], command, "slash registration preserved: " .. command) end
check(type(SlashCmdList.GEARBANKCLEANUP) == "function" and type(SlashCmdList.GEARHELP) == "function", "bank/help handlers remain available")

-- Default export remains current-character only even with another character saved.
local altSnapshot = S.GetSnapshot()
local altText = S.Render(altSnapshot)
check(altText:find("Name: Alt", 1, true) and not altText:find("Name: Torahn", 1, true), "default export excludes other character snapshots")
for _, key in ipairs(S.order) do
    check(altText:find(S.RenderSection(key, altSnapshot), 1, true), "independent section matches canonical export: " .. key)
end

-- Bounded export even while events continue to arrive.
local exported, count = nil, 0
S.Export(function(result) exported = result; count = count + 1 end)
for _ = 1, 40 do event("BAG_UPDATE"); advance(0.1) end
check(exported ~= nil, "continuous events cannot starve export completion")
equal(count, 1, "export callback runs once")
advance(1)
SlashCmdList.WOWSYNC("export"); WoWSyncExportFrame:Hide(); advance(4)
check(not WoWSyncExportFrame:IsShown(), "async export does not reopen dismissed UI")
check(not S.exportRequest, "UI export completes without reload")

snapshot = S.GetSnapshot()
snapshot.sections.character.data.name = "Name\twith\ncontrols\\"
local escaped = S.RenderSection("character", snapshot)
check(escaped:find("Name\\twith\\ncontrols\\\\", 1, true), "text cannot inject rows or sections")
local big = S.Copy(snapshot)
big.sections.spells.data.entries = {}
for index = 1, 1500 do big.sections.spells.data.entries[index] = { spellID = index, name = "Spell " .. index, rank = "Rank 1" } end
local largeText = S.Render(big)
check(#largeText > 32768 and largeText:find("Spell 1500", 1, true) and largeText:sub(-5) == "[END]", "large exports render completely")
equal(S.Render(big), largeText, "large export deterministic")

local function serializable(value, seen)
    if type(value) ~= "table" then return type(value) == "string" or type(value) == "number" or type(value) == "boolean" end
    if seen[value] then return false end
    seen[value] = true
    for key, child in pairs(value) do
        if not serializable(key, {}) or not serializable(child, seen) then return false end
    end
    seen[value] = nil
    return true
end
check(serializable(WoWSyncDB, {}), "SavedVariables contain only acyclic serializable values")
check(not S.record.history and not S.record.events, "no event-history log retained")
equal(movingCalls, 0, "all edge cases remain observation only")
local db = WoWSyncDB
WoWSyncDB = { schemaVersion = 999, characters = { sentinel = true } }; S.record = nil
check(not S.Initialize(), "future schema fails closed")
check(WoWSyncDB.characters.sentinel, "future database not overwritten")
WoWSyncDB = db

-- Legacy single-trainer data migrates without being discarded or guessed.
local legacyDB = { schemaVersion = 1, characters = { [guid] = {
    identity = { guid = guid, name = "Legacy", realm = "Dreamscythe" }, sections = {
        trainer = { data = { name = "Unknown Trainer", services = {} }, completeness = "partial" },
    }, visits = { trainer = { openedAt = 17, name = "Unknown Trainer", session = 1 } },
} } }
WoWSyncDB, S.record = legacyDB, nil
check(S.Initialize(), "legacy trainer database initializes")
check(S.record.sections.trainer.data.snapshots.UNKNOWN.name == "Unknown Trainer",
    "legacy trainer snapshot preserved under UNKNOWN")
check(S.record.visits.trainers.UNKNOWN.openedAt == 17, "legacy trainer visit preserved")
WoWSyncDB, S.record = db, nil
check(S.Initialize(), "current database restored after migration test")

-- Classic Era-shaped compatibility fixture: the General spellbook tab is second,
-- and item data arrives through ITEM_DATA_LOAD_RESULT.
local classicTabs, classicSkills = false, false
local originalBuild, originalTabs, originalTabInfo, originalSkillCount, originalSkillInfo =
    GetBuildInfo, GetNumSpellTabs, GetSpellTabInfo, GetNumSkillLines, GetSkillLineInfo
GetBuildInfo = function() return "1.15.9", "69547", "", 11509 end
GetNumSpellTabs = function() return classicTabs and 2 or originalTabs() end
GetSpellTabInfo = function(tab)
    if not classicTabs then return originalTabInfo(tab) end
    if tab == 1 then return "Combat", 1, 0, 1 end
    return "General", 1, 1, 1
end
GetNumSkillLines = function() return classicSkills and 3 or originalSkillCount() end
GetSkillLineInfo = function(index)
    if not classicSkills then return originalSkillInfo(index) end
    if index == 1 then return "Professions", true, true end
    if index == 2 then return "Mining", false, true, 100, 0, 0, 150, true end
    return "First Aid", false, true, 75, 0, 0, 150, false
end
GetSpellBookItemName = function(index)
    if classicTabs then return index == 1 and "Combat spell" or "First Aid", "Rank 1" end
    return index == 1 and "Mining" or "New spell", "Rank 1"
end
GetSpellBookItemInfo = function(index) return "SPELL", 300 + index end
GetSpellLink = function(index) return "|Hspell:" .. (300 + index) .. "|h[Spell]|h" end
classicTabs, classicSkills = true, true
event("SPELLS_CHANGED"); event("PLAYER_LEVEL_UP"); advance(1)
check(S.record.sections.character.data.interface == 11509, "Classic interface metadata captured")
check(S.record.sections.professions.data.entries[1].name == "First Aid", "profession evidence works when General is tab 2")
check(S.record.sections.spells.data.entries[1].spellID == 301, "Classic spell IDs remain stable")
itemPending = true; event("BAG_UPDATE"); advance(2)
check(S.record.sections.bags.completeness == "partial", "Classic delayed item metadata is partial")
itemPending = false; event("ITEM_DATA_LOAD_RESULT", 100, true); advance(1)
check(S.record.sections.bags.completeness == "complete", "Classic item data event refreshes snapshot")
local oldMap = C_Map; C_Map = nil; event("ZONE_CHANGED"); advance(1)
check(S.record.sections.location.data.zone == "Thunder Bluff", "Classic optional map APIs fall back safely")
C_Map = oldMap
GetBuildInfo, GetNumSpellTabs, GetSpellTabInfo, GetNumSkillLines, GetSkillLineInfo =
    originalBuild, originalTabs, originalTabInfo, originalSkillCount, originalSkillInfo
print("PASS: " .. passed .. " assertions; " .. movingCalls .. " gameplay actions")
