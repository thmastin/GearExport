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
-- Synthetic environment values match the observed client version/build/interface;
-- the surrounding mocked APIs are test fixtures, not additional live evidence.
local version, build, interface = "1.60.1", "70245", 16001
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
function UnitRace() return "Dwarf", "Dwarf", 3 end
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
    "WoWSyncForeverCollectors.lua", "WoWSyncForever70245.lua", "WoWSyncForeverBags70245.lua",
    "WoWSyncRender.lua", "WoWSyncUI.lua" }) do
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
for _, other in ipairs({ "69893", "70009", "69914", "different" }) do
    build = other
    check(not S.Initialize(), "non-current build fails closed: " .. other)
    equal(WoWSyncDB, nil, "wrong client does not create database")
    equal(S.error, "The installed WoWSync build is not verified for the running Forever client.",
        "rejection describes verification rather than a package phase")
end
build = "70245"
interface = 16000; check(not C.IsForever(), "wrong interface rejected"); interface = 16001
local realGUID = UnitGUID
UnitGUID = nil; check(not S.Initialize(), "missing GUID cannot fabricate character")
UnitGUID = function() error("Unavailable") end; check(not S.Initialize(), "throwing GUID handled")
UnitGUID = realGUID
local legacySections = { professions = { data = { entries = { { name = "Stale profession" } } } },
    bank = { data = { containers = { { id = 6 } } } } }
local legacyItems = { [6948] = { bindType = 1 } }
local legacyVisits = { bank = { openedAt = 123 } }
local legacyExport = { text = "old 70009 WOWSYNC export", generatedAt = 123 }
WoWSyncDB = { schemaVersion = 1, settings = { preserve = true }, characters = {
    ["Player-Forever-Test"] = { captureProfile = "Forever:1.60.1:70009:16001",
        sections = legacySections, itemMetadata = legacyItems, visits = legacyVisits,
        latestExport = legacyExport },
} }
S.eventFrame.scripts.OnEvent(S.eventFrame, "PLAYER_LOGIN")
advance(1)
equal(S.record.identity.name, "Hallo", "identity captured")
equal(S.record.captureProfile, "Forever:1.60.1:70245:16001", "active saved-data profile is build scoped")
equal(S.record.sections.professions, nil, "legacy unsupported section is not current evidence")
equal(S.record.archivedCaptures[1].sections, legacySections, "legacy sections remain preserved in archive")
equal(S.record.archivedCaptures[1].itemMetadata, legacyItems, "legacy item metadata remains preserved")
equal(S.record.archivedCaptures[1].visits, legacyVisits, "legacy visits remain preserved")
equal(S.record.archivedCaptures[1].latestExport, legacyExport, "legacy export remains preserved in archive")
check(S.record.latestExport ~= legacyExport and S.record.latestExport.text ~= legacyExport.text,
    "legacy export is invalidated before a fresh build-scoped export")
equal(WoWSyncDB.settings.preserve, true, "existing global settings remain intact")
local data = S.record.sections.character.data
equal(data.name, "Hallo", "name")
equal(data.realm, "Test Realm", "realm")
equal(data.class, "WARRIOR", "class")
equal(data.level, 10, "level")
equal(data.race, "Dwarf", "race")
equal(data.faction, nil, "unprobed faction unknown")
equal(data.moneyCopper, nil, "unprobed money unknown")
equal(data.xp, nil, "unprobed XP unknown")
equal(data.xpMax, nil, "unprobed XP maximum unknown")
equal(data.clientFamily, "Forever", "Forever never mislabeled Retail")
equal(data.interface, interface, "interface comes from API, not version arithmetic")
equal(S.record.sections.location, nil, "unprobed location collector disabled")
equal(requests, 0, "unverified 70245 playtime request is not sent")
for _, event in ipairs({ "TIME_PLAYED_MSG", "BANKFRAME_OPENED", "TRAINER_SHOW" }) do check(S.eventFrame.events[event], "Forever event registered: " .. event) end
local output
check(S.Export(function(text) output = text end), "export accepted")
advance(0.2) -- unprobed playtime is not requested
check(output and output:find("WOWSYNC v1", 1, true), "shared canonical export")
check(output:find("PlayedSeconds: ?\nLevelPlayedSeconds: ?", 1, true), "deferred playtime unknown")
check(output:find("XP: ?/?", 1, true), "unprobed XP stays unknown")
check(output:find("[BANK]\nState: UNKNOWN", 1, true), "bank not observed")
check(output:find("capture limited to runtime-observed", 1, true), "unprobed fields remain explicitly limited")
local frozen = S.GetSnapshot()
local frozenText = S.Render(frozen)
advance(1); equal(S.Render(frozen), frozenText, "deterministic without clock reads")
assert(loadfile("tests/forever_equipment_test.lua"))()(S, check, equal, advance)
assert(S.collectors.bags and not S.collectors.bank and not S.collectors.trainer
    and not S.collectors.professions and not S.collectors.spells,
    "70245 exposes only live-observed Forever collectors")
assert(loadfile("tests/forever_bags_70245_test.lua"))()(S, check, equal)
for _, key in ipairs({ "UnitName", "GetRealmName", "UnitClass", "UnitRace", "UnitLevel" }) do
    _G[key] = function() error("API changed") end
end
S.RequestSync(); advance(1)
local unknown = S.RenderSection("character", S.GetSnapshot())
for _, field in ipairs({ "Name", "Realm", "Class", "Race", "Level" }) do
    check(unknown:find(field .. ": ?", 1, true), "failed field unknown: " .. field)
end
check(unknown:find("XP: ?/?", 1, true), "unavailable XP explicit")
check(unknown:find("capture limited to runtime-observed", 1, true), "scope diagnostic retained")
local secret = {}
issecretvalue = function(value) return value == secret end
UnitLevel = function() return "10" end
UnitRace = function() return secret end
C_Map, GetRealZoneText, GetSubZoneText = nil, nil, nil
S.RequestSync(); advance(1)
equal(S.record.sections.character.data.level, nil, "changed type unknown")
equal(S.record.sections.character.data.race, nil, "restricted race unknown")
equal(S.record.sections.location, nil, "location remains unobserved")
equal(SLASH_WOWSYNC1, "/wowsync", "command preserved")
check(not SlashCmdList.GEAREXPORT and not SlashCmdList.BANKCLEANUP, "no legacy/action commands loaded")
equal(actions, 0, "no gameplay actions")
equal(requests, 0, "unverified playtime contract performs no request")
check(not S.collectors.currencies and not C.ReadCurrencyList(), "Forever has no currency capture")
for _, key in ipairs(S.order) do check(key ~= "currencies", "Forever order excludes currencies") end
print("PASS: " .. passed .. " Forever assertions; 0 gameplay actions")
