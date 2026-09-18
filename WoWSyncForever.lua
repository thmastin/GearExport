-- Loaded only by the Forever package. No legacy exporter or gameplay modules.
local ADDON_NAME, addon = ...
local C = WoWSyncCompat
local F = { version = "1.60.1", build = "69893" }
addon.Forever = F
addon.Readers = { SlotNames = {} }
-- This package selects its own adapters even if Blizzard reuses a project ID.
function C.IsRetail() return false end

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
    local metadata = type(C_AddOns) == "table" and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local target = F.Read("target", metadata, 1, "string", issues, ADDON_NAME, "X-WoWSync-Target")
    return target == "Forever" and version == F.version and build == F.build
end

function addon.ReadIdentity()
    if not C.IsForever() then
        if addon.Sync then addon.Sync.error = "Forever Phase 1 package requires the verified Forever beta build." end
        return nil
    end
    local issues = {}
    local guid = F.Read("GUID", UnitGUID, 1, "string", issues, "player")
    local name = F.Read("Name", UnitName, 1, "string", issues, "player")
    local realm = F.Read("Realm", GetRealmName, 1, "string", issues)
    if not guid and addon.Sync then addon.Sync.error = "Character GUID unavailable; snapshot cannot be safely assigned." end
    return guid, name, realm
end

-- Executable symbols alone do not validate the server event payload. Phase 1
-- does not request playtime until a live Forever event trace has been checked.
function C.RequestPlayed() return false end

addon.SyncEvents = {
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT",
    "PLAYER_MONEY", "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE",
    "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
}
