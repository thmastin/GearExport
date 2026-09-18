local _, addon = ...
local S, F = addon.Sync, addon.Forever

local function Meta(issues)
    table.sort(issues)
    return { completeness = #issues > 0 and "partial" or "complete",
        reason = #issues > 0 and table.concat(issues, "; ") or nil }
end

S.collectors.character = function()
    local issues = { "Playtime unverified on Forever; capture deferred" }
    local data = {
        name = F.Read("Name", UnitName, 1, "string", issues, "player"),
        realm = F.Read("Realm", GetRealmName, 1, "string", issues),
        class = F.Read("Class", UnitClass, 2, "string", issues, "player"),
        level = F.Number("Level", UnitLevel, issues, "player"),
        faction = F.Read("Faction", UnitFactionGroup, 1, "string", issues, "player"),
        moneyCopper = F.Number("MoneyCopper", GetMoney, issues),
        xp = F.Number("XP", UnitXP, issues, "player"),
        xpMax = F.Number("XPMax", UnitXPMax, issues, "player"),
        clientVersion = F.Read("ClientVersion", GetBuildInfo, 1, "string", issues),
        clientBuild = F.Read("ClientBuild", GetBuildInfo, 2, "string", issues),
        interface = F.Read("Interface", GetBuildInfo, 4, "number", issues),
        clientFamily = "Forever",
    }
    return data, Meta(issues)
end

S.collectors.location = function()
    local issues = {}
    local data = { zone = F.Read("Zone", GetRealZoneText, 1, "string", issues),
        subzone = F.Read("Subzone", GetSubZoneText, 1, "string", issues) }
    data.mapID = F.Number("MapID", type(C_Map) == "table" and C_Map.GetBestMapForUnit, issues, "player")
    if data.mapID then
        -- Protect the complete vector access, including field lookup and GetXY.
        local function Coordinates()
            local position = C_Map.GetPlayerMapPosition(data.mapID, "player")
            return position:GetXY()
        end
        local x = F.Read("PositionX", Coordinates, 1, "number", issues)
        local y = F.Read("PositionY", Coordinates, 2, "number", issues)
        if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
            data.x, data.y = math.floor(x * 10000 + 0.5) / 100, math.floor(y * 10000 + 0.5) / 100
        else issues[#issues + 1] = "Position unknown" end
    end
    return data, Meta(issues)
end

-- Preserve canonical section order, but never read deferred subsystems.
for _, key in ipairs({ "equipment", "bags", "professions", "spells" }) do
    S.collectors[key] = function() return nil, { reason = "Not implemented in Forever Phase 1" } end
end
