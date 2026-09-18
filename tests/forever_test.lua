-- Phase 1 intentionally supplies no bank/item/trainer/spell/profession APIs.
local passed, actions, requests, seconds = 0, 0, 0, 0
local function check(value, message) assert(value, message); passed = passed + 1 end
local function equal(a, b, message) check(a == b, message .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local function widget(name)
    local w = { scripts = {}, events = {}, shown = false }
    setmetatable(w, { __index = function(_, key)
        if key == "SetScript" then return function(self, event, fn) self.scripts[event] = fn end end
        if key == "RegisterEvent" then return function(self, event) self.events[event] = true end end
        if key == "IsShown" then return function(self) return self.shown end end
        if key == "Show" then return function(self) self.shown = true end end
        if key == "Hide" then return function(self) self.shown = false end end
        if key == "CreateTexture" or key == "CreateFontString" then return function() return widget() end end
        if key == "GetNumLines" then return function() return 1 end end
        return function() end
    end })
    if name then _G[name] = w end
    return w
end
function CreateFrame(_, name) return widget(name) end
UIParent, UISpecialFrames, SlashCmdList = widget(), {}, {}
function GetTime() return seconds end
function GetServerTime() return 1789670000 + math.floor(seconds) end
local version, build, interface = "1.60.1", "69913", 8675309 -- Synthetic interface, not client evidence.
function GetBuildInfo() return version, build, "test", interface end
local target = "Forever"
C_AddOns = { GetAddOnMetadata = function(name, field)
    equal(name, "GearExport", "loading identity retained")
    equal(field, "X-WoWSync-Target", "explicit target routing")
    return target
end }
function UnitGUID() return "Player-Forever-Test" end
function UnitName() return "Hallo" end
function GetRealmName() return "Test Realm" end
function UnitClass() return "Warrior", "WARRIOR" end
function UnitLevel() return 10 end
function UnitFactionGroup() return "Horde" end
function GetMoney() return 12345 end
function UnitXP() return 413 end
function UnitXPMax() return 72820 end
function GetRealZoneText() return "Test Zone" end
function GetSubZoneText() return "Test Subzone" end
C_Map = { GetBestMapForUnit = function() return 1 end,
    GetPlayerMapPosition = function() return { GetXY = function() return 0.125, 0.75 end } end }
function RequestTimePlayed() requests = requests + 1 end
local function action() actions = actions + 1; error("Unexpected gameplay call") end
BuyTrainerService, UseContainerItem, PickupContainerItem = action, action, action
local addon = {}
for _, file in ipairs({ "WoWSyncCompat.lua", "WoWSyncForever.lua", "WoWSyncCore.lua",
    "WoWSyncForeverCollectors.lua", "WoWSyncRender.lua", "WoWSyncUI.lua" }) do
    assert(loadfile(file))("GearExport", addon)
end
local S, C = addon.Sync, WoWSyncCompat
local function advance(duration)
    for _ = 1, math.ceil(duration / 0.1) do
        seconds = seconds + 0.1
        if S.eventFrame.scripts.OnUpdate then S.eventFrame.scripts.OnUpdate() end
    end
end
check(C.IsForever(), "explicit Forever package and verified version/build")
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
check(not C.IsRetail(), "Forever is not routed as Retail even with a shared project ID")
target = "Retail"; check(not C.IsForever(), "wrong package rejected"); target = "Forever"
for _, other in ipairs({ "1.15.9", "2.5.6", "12.1.0" }) do
    version = other; check(not C.IsForever(), "other clients rejected")
end
version = "1.60.1"
for _, other in ipairs({ "69893", "69914", "different" }) do
    build = other
    check(not S.Initialize(), "non-current build fails closed: " .. other)
    equal(WoWSyncDB, nil, "wrong client does not create database")
    equal(S.error, "The installed WoWSync build is not verified for the running Forever client.",
        "rejection describes verification rather than a package phase")
end
build = "69913"
local realGUID = UnitGUID
UnitGUID = nil; check(not S.Initialize(), "missing GUID cannot fabricate character")
UnitGUID = function() error("Unavailable") end; check(not S.Initialize(), "throwing GUID handled")
UnitGUID = realGUID
S.eventFrame.scripts.OnEvent(S.eventFrame, "PLAYER_LOGIN")
advance(1)
equal(S.record.identity.name, "Hallo", "identity captured")
local data = S.record.sections.character.data
equal(data.name, "Hallo", "name")
equal(data.realm, "Test Realm", "realm")
equal(data.class, "WARRIOR", "class")
equal(data.level, 10, "level")
equal(data.faction, "Horde", "faction")
equal(data.moneyCopper, 12345, "raw copper")
equal(data.xp, 413, "raw XP")
equal(data.xpMax, 72820, "raw max XP")
equal(data.clientFamily, "Forever", "Forever never mislabeled Retail")
equal(data.interface, interface, "interface comes from API, not version arithmetic")
equal(S.record.sections.location.data.x, 12.5, "map X")
equal(S.record.sections.location.data.y, 75, "map Y")
equal(requests, 0, "unverified playtime request never sent")
for _, event in ipairs({ "TIME_PLAYED_MSG", "BANKFRAME_OPENED", "TRAINER_SHOW", "BAG_UPDATE", "SPELLS_CHANGED" }) do
    check(not S.eventFrame.events[event], "deferred event not registered: " .. event)
end
local output
check(S.Export(function(text) output = text end), "export accepted")
advance(1)
check(output and output:find("WOWSYNC v1", 1, true), "shared canonical export")
check(output:find("PlayedSeconds: ?\nLevelPlayedSeconds: ?", 1, true), "deferred playtime unknown")
check(output:find("XP: 413/72820", 1, true), "XP ratio")
check(output:find("[BANK]\nState: UNKNOWN", 1, true), "bank not observed")
check(output:find("Not implemented in Forever Phase 1", 1, true), "deferred sections explained")
local frozen = S.GetSnapshot()
local frozenText = S.Render(frozen)
advance(1); equal(S.Render(frozen), frozenText, "deterministic without clock reads")
assert(loadfile("tests/forever_equipment_test.lua"))()(S, check, equal, advance)
assert(loadfile("tests/forever_snapshot_test.lua"))()(S, equal)
for _, key in ipairs({ "UnitName", "GetRealmName", "UnitClass", "UnitLevel", "UnitFactionGroup", "GetMoney", "UnitXP", "UnitXPMax" }) do
    _G[key] = function() error("API changed") end
end
S.RequestSync(); advance(1)
local unknown = S.RenderSection("character", S.GetSnapshot())
for _, field in ipairs({ "Name", "Realm", "Class", "Level", "Faction", "MoneyCopper" }) do
    check(unknown:find(field .. ": ?", 1, true), "failed field unknown: " .. field)
end
check(unknown:find("XP: ?/?", 1, true), "unavailable XP explicit")
check(unknown:find("MoneyCopper failed", 1, true), "diagnostic reason retained")
GetMoney, UnitXP, UnitXPMax, UnitLevel = function() return 0 end, function() return 0 end, function() return 100 end, function() return 1 end
S.RequestSync(); advance(1)
equal(S.record.sections.character.data.moneyCopper, 0, "known zero money")
equal(S.record.sections.character.data.xp, 0, "known zero XP")
local secret = {}
issecretvalue = function(value) return value == secret end
GetMoney = function() return secret end
UnitLevel = function() return "10" end
UnitXP = function() return -1 end
UnitXPMax = nil
C_Map, GetRealZoneText, GetSubZoneText = nil, nil, nil
S.RequestSync(); advance(1)
equal(S.record.sections.character.data.moneyCopper, nil, "restricted value unknown")
equal(S.record.sections.character.data.level, nil, "changed type unknown")
equal(S.record.sections.character.data.xp, nil, "negative XP rejected")
equal(S.record.sections.character.data.xpMax, nil, "missing XP API unknown")
equal(S.record.sections.location.data.zone, nil, "absent location unknown")
equal(S.record.sections.location.completeness, "partial", "location diagnostics")
equal(SLASH_WOWSYNC1, "/wowsync", "command preserved")
check(not SlashCmdList.GEAREXPORT and not SlashCmdList.BANKCLEANUP, "no legacy/action commands loaded")
equal(actions, 0, "no gameplay actions")
equal(requests, 0, "no unvalidated requests")
print("PASS: " .. passed .. " Forever assertions; 0 gameplay actions")
