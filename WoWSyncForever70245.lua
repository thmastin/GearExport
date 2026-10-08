-- Expose only collectors whose input contracts were observed on 70245.
-- The other Forever modules remain available for their older package history,
-- but must not run under this build without a separate live audit.
local _, addon = ...
local S, F = addon.Sync, addon.Forever
local CAPTURE_PROFILE = "Forever:1.60.1:70245:16001"
local equipmentCollector = S.collectors.equipment

function addon.PrepareCaptureProfile(record)
    if record.captureProfile == CAPTURE_PROFILE then return end
    local priorSections = type(record.sections) == "table" and record.sections or nil
    local priorItems = type(record.itemMetadata) == "table" and record.itemMetadata or nil
    local priorVisits = type(record.visits) == "table" and record.visits or nil
    if priorSections and next(priorSections) or priorItems and next(priorItems) or priorVisits and next(priorVisits) then
        record.archivedCaptures = type(record.archivedCaptures) == "table" and record.archivedCaptures or {}
        record.archivedCaptures[#record.archivedCaptures + 1] = {
            profile = record.captureProfile or "UNVERSIONED",
            sections = priorSections,
            itemMetadata = priorItems,
            visits = priorVisits,
        }
    end
    -- Data captured by another client build must not appear as current 70245
    -- evidence. Keep it archived and start a fresh active observation record.
    record.sections, record.itemMetadata, record.visits = {}, {}, {}
    record.captureProfile = CAPTURE_PROFILE
end

S.collectors = {
    character = function()
        local issues = {}
        local data = {
            name = F.Read("Name", UnitName, 1, "string", issues, "player"),
            realm = F.Read("Realm", GetRealmName, 1, "string", issues),
            class = F.Read("Class", UnitClass, 2, "string", issues, "player"),
            race = F.Read("Race", UnitRace, 1, "string", issues, "player"),
            level = F.Number("Level", UnitLevel, issues, "player"),
            clientVersion = F.Read("ClientVersion", GetBuildInfo, 1, "string", issues),
            clientBuild = F.Read("ClientBuild", GetBuildInfo, 2, "string", issues),
            interface = F.Read("Interface", GetBuildInfo, 4, "number", issues),
            clientFamily = "Forever",
        }
        table.sort(issues)
        return data, { completeness = "partial",
            reason = "Forever 70245 capture limited to runtime-observed character and build fields"
                .. (#issues > 0 and ("; " .. table.concat(issues, "; ")) or "") }
    end,
    equipment = function()
        local data, meta = equipmentCollector()
        if not data then
            meta = type(meta) == "table" and meta or {}
            meta.stale = true
        end
        return data, meta
    end,
    bags = S.collectors.bags,
}
