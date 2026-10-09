-- Expose only the existing collectors carried forward from the documented 70245 contracts.
-- The other Forever modules remain available for their older package history,
-- but must not run under this build without a separate live audit.
local _, addon = ...
local S, F = addon.Sync, addon.Forever
local CAPTURE_PROFILE = "Forever:1.60.1:70291:16001"
local equipmentCollector = S.collectors.equipment

local function publicName(value)
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if not ok or secret then return nil, false end
    end
    if type(value) ~= "string" or value == "" then return nil, true end
    return value, true
end

local function captureNameEvidence(firstName, realm)
    local safeFirstName = publicName(firstName)
    local safeRealm = publicName(realm)
    local calls = {}
    local candidates = {}
    local function record(apiName, fn)
        if type(fn) ~= "function" then
            calls[apiName] = { state = "API_MISSING" }
            return
        end
        local values
        local function pack(...) return { n = select("#", ...), ... } end
        local ok, result = pcall(function() return pack(fn("player")) end)
        if not ok then
            calls[apiName] = { state = "API_ERROR", error = tostring(result) }
            return
        end
        local returns = {}
        for i = 1, result.n do
            local value = result[i]
            local safe, isPublic = publicName(value)
            returns[i] = { index = i, type = isPublic and type(value) or "RESTRICTED", state = isPublic and value == nil and "NIL" or safe and "OBSERVED" or "UNAVAILABLE", value = safe }
        end
        calls[apiName] = { state = result.n > 0 and "OBSERVED" or "ZERO_RETURNS", returnCount = result.n, returns = returns }

        local first = publicName(result[1])
        local second = publicName(result[2])
        if safeFirstName and first == safeFirstName and apiName == "UnitName" and second and second ~= safeFirstName and second ~= safeRealm then
            candidates[#candidates + 1] = { value = second, source = "UnitName[2]" }
        elseif safeFirstName and first == safeFirstName and apiName == "GetUnitName" and first:sub(1, #safeFirstName + 1) == safeFirstName .. " " then
            local suffix = first:sub(#safeFirstName + 2)
            if suffix ~= "" and suffix ~= safeRealm then candidates[#candidates + 1] = { value = suffix, source = "GetUnitName suffix" } end
        elseif safeFirstName and first == safeFirstName and (apiName == "UnitFullName" or apiName == "UnitNameUnmodified")
            and second and second ~= safeFirstName and second ~= safeRealm then
            candidates[#candidates + 1] = { value = second, source = apiName .. "[2]" }
        end
    end

    record("UnitName", UnitName)
    record("GetUnitName", GetUnitName)
    record("UnitFullName", UnitFullName)
    record("UnitNameUnmodified", UnitNameUnmodified)
    local values, selected, sources, conflict = {}, nil, {}, false
    for _, candidate in ipairs(candidates) do
        local entry = values[candidate.value]
        if not entry then entry = { count = 0, sources = {} }; values[candidate.value] = entry end
        if not entry.sources[candidate.source] then
            entry.sources[candidate.source] = true
            entry.count = entry.count + 1
            entry.sourcesList = entry.sourcesList or {}
            entry.sourcesList[#entry.sourcesList + 1] = candidate.source
        end
    end
    local distinct = 0
    for value, entry in pairs(values) do
        distinct = distinct + 1
        if entry.count >= 2 then selected, sources = value, entry.sourcesList end
    end
    conflict = distinct > 1 or (distinct == 1 and selected == nil)
    if conflict or distinct > 1 then selected, sources = nil, nil end
    return selected, sources and table.concat(sources, "+") or nil, { state = conflict and "CONFLICTING_OR_UNCORROBORATED_CANDIDATES" or selected and "CORROBORATED" or "UNKNOWN",
        candidates = candidates, calls = calls, interpretation = "API semantics require live verification on Forever 1.60.1 build 70291" }
end

function addon.PrepareCaptureProfile(record)
    if record.captureProfile == CAPTURE_PROFILE then return end
    local priorSections = type(record.sections) == "table" and record.sections or nil
    local priorItems = type(record.itemMetadata) == "table" and record.itemMetadata or nil
    local priorVisits = type(record.visits) == "table" and record.visits or nil
    local priorExport = type(record.latestExport) == "table" and record.latestExport or nil
    if priorSections and next(priorSections) or priorItems and next(priorItems)
        or priorVisits and next(priorVisits) or priorExport then
        record.archivedCaptures = type(record.archivedCaptures) == "table" and record.archivedCaptures or {}
        record.archivedCaptures[#record.archivedCaptures + 1] = {
            profile = record.captureProfile or "UNVERSIONED",
            sections = priorSections,
            itemMetadata = priorItems,
            visits = priorVisits,
            latestExport = priorExport,
        }
    end
    -- Data captured by another client build must not appear as current 70291
    -- evidence. Keep it archived and start a fresh active observation record.
    record.sections, record.itemMetadata, record.visits = {}, {}, {}
    record.latestExport = nil
    record.captureProfile = CAPTURE_PROFILE
end

S.collectors = {
    character = function()
        local issues = {}
        local firstName = F.Read("Name", UnitName, 1, "string", issues, "player")
        local realm = F.Read("Realm", GetRealmName, 1, "string", issues)
        local surname, surnameSource, nameApiEvidence = captureNameEvidence(firstName, realm)
        local data = {
            name = firstName,
            surname = surname,
            surnameSource = surnameSource,
            nameApiEvidence = nameApiEvidence,
            realm = realm,
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
            reason = "Forever 70291 capture limited to fields supported by the carried-forward 70245 contract"
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

-- This section is isolated to the exact Forever 70291 package. The older
-- Forever trainer tuple adapter is intentionally not activated here.
S.order[#S.order + 1] = "forever70291Evidence"
-- Keep WOWSYNC v1 text parse-compatible with the currently deployed Dashboard.
-- The version-specific raw section is persisted alongside the export and is
-- consumed by the separate Forever parser integration handoff.
S.structuredOnly.forever70291Evidence = true
