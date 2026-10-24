local passed = 0
local function check(value, message)
    assert(value, message)
    passed = passed + 1
end
local function equal(actual, expected, message)
    check(actual == expected, message .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
end

WOW_PROJECT_ID, WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC = 2, 1, 2
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_WRATH_CLASSIC = 5, 11
WOW_PROJECT_CATACLYSM_CLASSIC, WOW_PROJECT_MISTS_CLASSIC = 14, 19
local guid = "Player-ClassicEra-123"
local trees = { { "Arms", 31 }, { "Fury", 0 }, { "Protection", 0 } }
function GetBuildInfo() return "1.15.9", "60100", "", 11509 end
function UnitClass() return "Warrior", "WARRIOR" end
function UnitName() return "Tester" end
function GetRealmName() return "Test Realm" end
function UnitLevel() return 60 end
function UnitFactionGroup() return "Alliance" end
function GetMoney() return 0 end
function UnitGUID(unit) return unit == "player" and guid end
function GetNumTalentTabs() return #trees end
function GetTalentTabInfo(index) return trees[index][1], nil, trees[index][2] end

local addon = { Sync = { collectors = {} }, Readers = { SlotNames = {} } }
local function load(path) assert(loadfile(path))("GearExport", addon) end
load("WoWSyncCompat.lua")
load("WoWSyncTalentTabs.lua")
load("WoWSyncCollectors.lua")
load("WoWSyncRender.lua")
local C, S = WoWSyncCompat, addon.Sync
check(C.IsClassicEra(), "Era project identity is identified")

local function snapshot()
    local data = assert(S.collectors.character())
    return { sections = { character = { data = data, completeness = "complete", observedAt = 1 } } }
end
local output = S.RenderSection("character", snapshot())
check(output:find("GUID: Player%-ClassicEra%-123") ~= nil, "GUID uses GUID parser field")
check(output:find("TalentStatus: OBSERVED", 1, true) ~= nil, "talents are observed")
check(output:find("talentTree\tname\tpointsSpent", 1, true) ~= nil, "talent tree parser columns are explicit")
check(output:find("talentTree\tArms\t31", 1, true) ~= nil, "tree name and points are emitted")
check(output:find("talentTree\tFury\t0", 1, true) ~= nil, "zero point tree is observed")

-- Exact Classic Era 1.15.9 / 70003 live tuples supplied for the regression.
trees = { { "Affliction", 1 } }
GetTalentTabInfo = function()
    return 302, "Affliction", "", 136145, 1, "WarlockCurses", 0, true
end
local liveData = S.collectors.character()
equal(liveData.talents.status, "OBSERVED", "modern live tab tuple is recognized")
equal(liveData.talents.trees[1].tabID, 302, "modern tuple tabID is retained")
equal(liveData.talents.trees[1].name, "Affliction", "modern tuple name is retained")
equal(liveData.talents.trees[1].pointsSpent, 1, "modern tuple points are read from slot five")
GetTalentTabInfo = function() return "Affliction", nil, 1 end
liveData = S.collectors.character()
equal(liveData.talents.status, "OBSERVED", "legacy tab tuple remains recognized")
equal(liveData.talents.trees[1].tabID, nil, "legacy tuple has no fabricated tabID")
GetTalentTabInfo = function() return true, "Affliction", nil, nil, 1 end
liveData = S.collectors.character()
equal(liveData.talents.status, "UNKNOWN", "unknown tab tuple shape fails closed")
trees = { { "Arms", 31 }, { "Fury", 0 }, { "Protection", 0 } }
GetTalentTabInfo = function(index) return trees[index][1], nil, trees[index][2] end

GetBuildInfo = function() return "1.15.10", "60101", "", 11510 end
output = S.RenderSection("character", snapshot())
check(output:find("GUID: Player%-ClassicEra%-123") ~= nil
    and output:find("TalentStatus: OBSERVED", 1, true) ~= nil, "Era patch interface 11510 still emits GUID and talents")

UnitLevel = function() return 9 end
trees = { { "Arms", 0 }, { "Fury", 0 }, { "Protection", 0 } }
output = S.RenderSection("character", snapshot())
check(output:find("TalentStatus: OBSERVED", 1, true) ~= nil, "level under 10 remains observed")
check(output:find("talentTree\tArms\t0", 1, true) ~= nil, "level under 10 exports observed zero points")

GetTalentTabInfo = nil
output = S.RenderSection("character", snapshot())
check(output:find("TalentStatus: UNKNOWN", 1, true) ~= nil, "missing talent APIs are unknown")
check(not output:find("talentTree\tname", 1, true), "unknown talent tree data is not fabricated")

UnitGUID = nil
output = S.RenderSection("character", snapshot())
check(output:find("GUID: UNKNOWN", 1, true) ~= nil, "unavailable GUID is explicit")

-- TBC shares the collector and renderer files; for equivalent legacy data the
-- new Classic-only fields are absent, preserving its character bytes.
WOW_PROJECT_ID = WOW_PROJECT_BURNING_CRUSADE_CLASSIC
GetBuildInfo = function() return "2.5.5", "68101", "", 20506 end
UnitGUID = function() return "Player-TBC-123" end
GetNumTalentTabs = function() return 3 end
GetTalentTabInfo = function() return "Changed", nil, 44 end
output = S.RenderSection("character", snapshot())
check(not output:find("GUID:", 1, true) and not output:find("TalentStatus:", 1, true), "TBC text is unchanged")

WOW_PROJECT_ID = WOW_PROJECT_CLASSIC
WoWSyncCompat.IsForever = function() return true end
output = S.RenderSection("character", snapshot())
check(not output:find("GUID:", 1, true) and not output:find("TalentStatus:", 1, true), "Forever project identity is explicitly excluded")

WoWSyncCompat.IsForever = nil
WOW_PROJECT_ID = WOW_PROJECT_MAINLINE
output = S.RenderSection("character", snapshot())
check(not output:find("GUID:", 1, true) and not output:find("TalentStatus:", 1, true), "Retail project identity is explicitly excluded")

WOW_PROJECT_ID, WOW_PROJECT_CLASSIC = 2, nil
GetBuildInfo = function() return "1.15.10", "60101", "", 11510 end
output = S.RenderSection("character", snapshot())
check(not output:find("GUID:", 1, true) and not output:find("TalentStatus:", 1, true), "ambiguous missing project constants fail closed")
print("PASS: " .. passed .. " Classic Era identity/talent assertions")
