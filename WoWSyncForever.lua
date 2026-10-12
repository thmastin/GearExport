-- Loaded only by the Forever package. No legacy exporter or gameplay modules.
local ADDON_NAME, addon = ...
local C = WoWSyncCompat
-- Builds in this table have direct compatibility evidence. It is deliberately
-- not an addon-load allowlist: Forever updates frequently, and each collector
-- guards its own API/return contract. A new build must not disable every
-- otherwise-working observation merely because its build number changed.
local F = { family = "Forever", knownProfiles = {
    ["1.60.1:70291:16001"] = true, ["1.60.1:70338:16001"] = true,
} }
addon.Forever = F
-- Forever uses the stable inventory slot IDs. Keep IDs in the export; these
-- labels are presentation only and are checked against Blizzard's Forever UI
-- slot constants rather than inferred from an item's class.
addon.Readers = { SlotNames = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest",
    [6] = "Waist", [7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands",
    [11] = "Finger 1", [12] = "Finger 2", [13] = "Trinket 1", [14] = "Trinket 2",
    [15] = "Back", [16] = "Main Hand", [17] = "Off Hand", [18] = "Ranged", [19] = "Tabard",
} }
-- This package selects its own adapters even if Blizzard reuses a project ID.
function C.IsRetail() return false end

function C.IsSupportedForeverBuild(build, interface, version)
    version = version or F.runtimeVersion
    return F.knownProfiles[tostring(version) .. ":" .. tostring(build) .. ":" .. tostring(interface)] == true
end

local function IsForeverProject(projectID, camelotID, interface)
    -- Prefer the named client constant. The numeric fallback is based on the
    -- captured 1.60.1 build 70338 project ID (18), and constrained to the
    -- Forever interface family. The addon TOC target is independently checked.
    if type(camelotID) == "number" then return projectID == camelotID end
    return projectID == 18 and type(interface) == "number" and interface >= 16000 and interface < 20000
end

F.IsForeverProject = IsForeverProject

local function IsForeverVersion(version)
    if type(version) ~= "string" then return false end
    local major, minor, patch = version:match("^(%d+)%.(%d+)%.(%d+)$")
    major, minor, patch = tonumber(major), tonumber(minor), tonumber(patch)
    -- Forever 1.60+ is its own client line. This excludes Classic 1.15 and
    -- TBC 2.x while allowing routine Forever 1.6x version updates.
    return major == 1 and minor ~= nil and minor >= 60 and minor < 100 and patch ~= nil
end
F.IsForeverVersion = IsForeverVersion

local function Public(value)
    return not (type(issecretvalue) == "function" and issecretvalue(value))
end

-- Read-only calls are isolated: absent, throwing, restricted or differently
-- typed returns are unknown, never zero or a fabricated identity.
function F.Read(label, fn, index, expected, issues, ...)
    if type(fn) ~= "function" then issues[#issues + 1] = label .. " unavailable"; return nil end
    local result = { pcall(fn, ...) }
    if not result[1] then issues[#issues + 1] = label .. " failed"; return nil end
    local value = result[(index or 1) + 1]
    if not Public(value) or type(value) ~= expected
        or expected == "string" and value == ""
        or expected == "number" and (value ~= value or value == math.huge or value == -math.huge) then
        issues[#issues + 1] = label .. " unknown"
        return nil
    end
    return value
end

function F.Number(label, fn, issues, ...)
    local value = F.Read(label, fn, 1, "number", issues, ...)
    if value and (value < 0 or value % 1 ~= 0) then
        issues[#issues + 1] = label .. " invalid"
        return nil
    end
    return value
end

function C.IsForever()
    local issues = {}
    local version = F.Read("version", GetBuildInfo, 1, "string", issues)
    local build = F.Read("build", GetBuildInfo, 2, "string", issues)
    local interface = F.Read("interface", GetBuildInfo, 4, "number", issues)
    local projectID = type(WOW_PROJECT_ID) == "number" and WOW_PROJECT_ID or nil
    local camelotID = type(WOW_PROJECT_CAMELOT) == "number" and WOW_PROJECT_CAMELOT or nil
    local metadata = type(C_AddOns) == "table" and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local target = F.Read("target", metadata, 1, "string", issues, ADDON_NAME, "X-WoWSync-Target")
    local isProject = IsForeverProject(projectID, camelotID, interface)
    local recognized = target == "Forever" and isProject and IsForeverVersion(version)
        and type(build) == "string" and build:match("^%d+$") ~= nil
        and interface ~= nil and interface >= 16000 and interface < 20000
    if recognized then
        -- Scope evidence and freshness to the exact running runtime, including
        -- unverified update builds. Build identity is not API compatibility.
        F.runtimeVersion, F.runtimeBuild, F.runtimeInterface = version, build, interface
        F.version, F.build, F.interface = version, build, interface
        F.compatibilityVerified = C.IsSupportedForeverBuild(build, interface, version)
        F.compatibilityState = F.compatibilityVerified and "VERIFIED_PROFILE" or "UNVERIFIED_BUILD"
        F.compatibilityReason = F.compatibilityVerified and nil
            or "Forever project identified; this client build has not been compatibility-tested. Each observation remains API-guarded."
        local evidence = WOW_PROJECT_CAMELOT and "WOW_PROJECT_ID_EQUALS_WOW_PROJECT_CAMELOT"
            or "WOW_PROJECT_ID_18_AND_INTERFACE_16000_19999"
        if addon.Sync then addon.Sync.runtimeCompatibility = {
            state = F.compatibilityState, version = version, build = build, interface = interface,
            reason = F.compatibilityReason, projectEvidence = evidence,
        } end
    end
    return recognized
end

function addon.ReadIdentity()
    if not C.IsForever() then
        if addon.Sync then addon.Sync.error = "Forever client identity is not established; export was not initialized." end
        return nil
    end
    local issues = {}
    local guid = F.Read("GUID", UnitGUID, 1, "string", issues, "player")
    local name = F.Read("Name", UnitName, 1, "string", issues, "player")
    local realm = F.Read("Realm", GetRealmName, 1, "string", issues)
    if not guid and addon.Sync then addon.Sync.error = "Character GUID unavailable; snapshot cannot be safely assigned." end
    return guid, name, realm
end

-- Forever retains the documented asynchronous request/event contract.  Nothing
-- is estimated while a response is outstanding or if either value is absent.
function C.RequestPlayed()
    -- The exact Forever 1.60.1 API contract is asynchronous. Core waits for
    -- TIME_PLAYED_MSG and leaves both values unknown if it never arrives.
    if type(RequestTimePlayed) ~= "function" then return false end
    local ok = pcall(RequestTimePlayed)
    return ok
end

function C.IsBankViewable()
    local api = type(C_Bank) == "table" and C_Bank or {}
    local bankType = type(Enum) == "table" and Enum.BankType and Enum.BankType.Character
    if type(api.CanViewBank) ~= "function" or type(bankType) ~= "number" then return false end
    local ok, viewable = pcall(api.CanViewBank, bankType)
    return ok and Public(viewable) and type(viewable) == "boolean" and viewable
end

addon.SyncEvents = {
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT",
    "PLAYER_MONEY", "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE",
    "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
    "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED",
    "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT",
    "BAG_UPDATE", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED",
    "SKILL_LINES_CHANGED", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE",
    "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_LIST_UPDATE", "NEW_RECIPE_LEARNED",
    "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "SPELL_TEXT_UPDATE",
    "QUEST_ACCEPTED", "QUEST_AUTOCOMPLETE", "QUEST_COMPLETE", "QUEST_DATA_LOAD_RESULT",
    "QUEST_LOG_CRITERIA_UPDATE", "QUEST_LOG_UPDATE", "QUEST_REMOVED", "QUEST_TURNED_IN",
    "QUEST_WATCH_LIST_CHANGED", "QUEST_WATCH_UPDATE",
    "TIME_PLAYED_MSG",
    "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "BANK_TABS_CHANGED",
    "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_DESCRIPTION_UPDATE", "TRAINER_SERVICE_INFO_NAME_UPDATE", "TRAINER_CLOSED",
}
