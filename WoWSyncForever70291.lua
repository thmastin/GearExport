-- Version-scoped observational collectors for the explicitly allowlisted
-- Forever builds.
local _, addon = ...
local S, F = addon.Sync, addon.Forever
local function captureProfile()
    return "Forever:" .. F.version .. ":" .. F.build .. ":" .. F.interface
end
local equipmentCollector = S.collectors.equipment
local locationCollector = S.collectors.location

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
        candidates = candidates, calls = calls,
        interpretation = "API semantics require live verification on Forever 1.60.1 build " .. tostring(F.build) }
end

function addon.PrepareCaptureProfile(record)
    local activeProfile = captureProfile()
    if record.captureProfile == activeProfile then return end
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
        if S.PruneArchives then S.PruneArchives(record) end
    end
    -- Data captured by another client build must not appear as current
    -- evidence. Keep it archived and start a fresh active observation record.
    record.sections, record.itemMetadata, record.visits = {}, {}, {}
    record.latestExport = nil
    record.captureProfile = activeProfile
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
            faction = F.Read("Faction", UnitFactionGroup, 1, "string", issues, "player"),
            moneyCopper = F.Number("MoneyCopper", GetMoney, issues),
            xp = F.Number("XP", UnitXP, issues, "player"),
            xpMax = F.Number("XPMax", UnitXPMax, issues, "player"),
            clientFamily = "Forever",
        }
        local played = S.played
        if played then
            if played.guid ~= UnitGUID("player") then
                issues[#issues + 1] = "Playtime response belongs to a different character"
            else
                data.playedSeconds, data.levelPlayedSeconds = played.total, played.levelSeconds
                if data.playedSeconds == nil then issues[#issues + 1] = "Total playtime unavailable" end
                if data.levelPlayedSeconds == nil then issues[#issues + 1] = "Level playtime unavailable" end
            end
        else
            issues[#issues + 1] = "Playtime response not observed"
        end
        table.sort(issues)
        return data, { completeness = "partial",
            reason = "Forever capture limited to fields enabled by the version-scoped collectors"
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
    location = locationCollector,
    bags = S.collectors.bags,
    trainer = function()
        local visible = false
        for _, frameName in ipairs({ "ClassTrainerFrame", "TrainerFrame" }) do
            local frame = _G[frameName]
            if frame and type(frame.IsShown) == "function" then
                local ok, shown = pcall(frame.IsShown, frame)
                if ok and shown == true then visible = true; break end
            end
        end
        if not visible then return nil, { reason = "Trainer window is not open" } end
        local count = type(GetNumTrainerServices) == "function" and GetNumTrainerServices() or nil
        if type(count) ~= "number" or count < 0 or count > 250 or count % 1 ~= 0 then return nil, { reason = "Trainer service count unavailable or invalid" } end
        local function frameText(names)
            for _, name in ipairs(names) do
                local widget = _G[name]
                if widget and type(widget.GetText) == "function" then
                    local called, value = pcall(widget.GetText, widget)
                    if called then value = publicName(value); if value then return value end end
                end
            end
        end
        local trainerName = frameText({ "ClassTrainerFrameTitleText", "TrainerFrameTitleText" })
        local profession = type(IsTradeskillTrainer) == "function" and IsTradeskillTrainer() == true
        local classTrainer = type(IsTalentTrainer) == "function" and IsTalentTrainer() == true
        if not profession and not classTrainer and type(IsTradeskillTrainer) ~= "function" then
            classTrainer = true
        end
        local trainerType, professionName, className = profession and "profession" or "class", nil, nil
        if profession then
            for i = 1, count do
                if type(GetTrainerServiceSkillReq) == "function" then
                    local skill = publicName(GetTrainerServiceSkillReq(i))
                    if skill then professionName = skill; break end
                end
            end
        else
            if type(UnitClass) == "function" then className = publicName(UnitClass("player")) end
        end
        trainerName = trainerName or professionName or className or (profession and "Profession Trainer" or "Class Trainer")
        local services, droppedRowCount = {}, 0
        for i = 1, count do
            local called, name, rawStatus, icon, levelReq, rank, category = pcall(GetTrainerServiceInfo, i)
            if not called then
                droppedRowCount = droppedRowCount + 1
            elseif rawStatus ~= "header" and rawStatus ~= "headerbutton" then
                name = publicName(name)
                if not name then
                    droppedRowCount = droppedRowCount + 1
                else
                    local status = rawStatus
                    if status == "known" then status = "used" end
                    if status ~= "available" and status ~= "used" and status ~= "unavailable" then status = "unknown" end
                    local cost = type(GetTrainerServiceCost) == "function" and GetTrainerServiceCost(i) or nil
                    local level = type(GetTrainerServiceLevelReq) == "function" and GetTrainerServiceLevelReq(i) or nil
                    local skill, skillRank
                    if type(GetTrainerServiceSkillReq) == "function" then skill, skillRank = GetTrainerServiceSkillReq(i) end
                    skill = publicName(skill)
                    services[#services + 1] = { name = name, rank = publicName(rank), status = status,
                        rawStatus = type(rawStatus) == "string" and rawStatus or nil,
                        icon = type(icon) == "number" and icon or nil,
                        category = publicName(category),
                        costCopper = type(cost) == "number" and cost >= 0 and cost or nil,
                        requiredLevel = type(levelReq) == "number" and levelReq or type(level) == "number" and level or nil,
                        requiredSkill = skill and { name = skill, rank = type(skillRank) == "number" and skillRank or nil } or nil }
                end
            end
        end
        local emptyReportedList = count > 0 and #services == 0
        local incomplete = droppedRowCount > 0 or emptyReportedList
        local reason
        if emptyReportedList then reason = "Trainer reported services but no service rows could be parsed"
        elseif droppedRowCount > 0 then reason = tostring(droppedRowCount) .. " trainer service row(s) could not be parsed" end
        local at = type(GetServerTime) == "function" and GetServerTime() or S.Now()
        local moneyAtVisitIssues = {}
        local moneyAtVisit = F.Number("Trainer money at visit", GetMoney, moneyAtVisitIssues)
        return { category = trainerName, snapshot = { capturedAt = at, name = trainerName, type = trainerType,
            professionName = professionName, className = className, moneyAtVisit = moneyAtVisit,
            filters = { available = nil, unavailable = nil, used = nil }, services = services, droppedRowCount = droppedRowCount } },
            { completeness = incomplete and "partial" or "complete", reason = reason, source = "Forever trainer service API" }
    end,
}

S.collectors.equipmentSets = function()
    local function markUnknown()
        local sections = S.record and S.record.sections or {}
        local function mark(item) if type(item) == "table" then item.equipmentSetsState = "UNKNOWN" end end
        local equipment = sections.equipment and sections.equipment.data
        for _, item in pairs(equipment and equipment.slots or {}) do mark(item) end
        for _, key in ipairs({ "bags", "bank" }) do
            local data = sections[key] and sections[key].data
            for _, container in ipairs(data and data.containers or {}) do
                for _, item in pairs(container.slots or {}) do mark(item) end
            end
        end
    end
    local api = type(C_EquipmentSet) == "table" and C_EquipmentSet or nil
    if not api or type(api.GetEquipmentSetIDs) ~= "function"
        or type(api.GetEquipmentSetInfo) ~= "function" or type(api.GetItemLocations) ~= "function" then
        markUnknown()
        return { state = "UNKNOWN", reason = "Equipment Manager APIs unavailable" }, { completeness = "partial" }
    end
    local okIDs, ids = pcall(api.GetEquipmentSetIDs)
    if not okIDs or type(ids) ~= "table" then
        markUnknown()
        return { state = "UNKNOWN", reason = "Equipment set IDs unavailable" }, { completeness = "partial" }
    end
    local itemAPI = type(C_Item) == "table" and C_Item or {}
    if type(itemAPI.GetItemID) ~= "function" or type(itemAPI.GetItemLink) ~= "function" then
        markUnknown()
        return { state = "UNKNOWN", reason = "Item location identity/link APIs unavailable" }, { completeness = "partial" }
    end
    local sets, namesByItemString = {}, {}
    for _, setID in ipairs(ids) do
        local okInfo, name, icon, returnedID, equipped = pcall(api.GetEquipmentSetInfo, setID)
        local okLocations, locations = pcall(api.GetItemLocations, setID)
        if not okInfo or type(name) ~= "string" or not okLocations or type(locations) ~= "table" then
            markUnknown()
            return { state = "UNKNOWN", reason = "Equipment set details unavailable" }, { completeness = "partial" }
        end
        local rows = {}
        for _, location in ipairs(locations) do
            local okItem, itemID = pcall(itemAPI.GetItemID, location)
            if okItem and type(itemID) == "number" and itemID > 0 then
                local okLink, link = pcall(itemAPI.GetItemLink, location)
                local itemString = okLink and type(link) == "string" and link:match("(item:[^|]+)") or nil
                local linkID = itemString and tonumber(itemString:match("^item:(%d+)"))
                if linkID == itemID then
                    rows[#rows + 1] = { itemID = itemID, itemString = itemString }
                    namesByItemString[itemString] = namesByItemString[itemString] or {}
                    namesByItemString[itemString][name] = true
                else
                    rows[#rows + 1] = { itemID = itemID }
                end
            end
        end
        table.sort(rows, function(a, b) return a.itemID < b.itemID end)
        local isEquipped
        if type(equipped) == "boolean" then isEquipped = equipped end
        sets[#sets + 1] = { setID = setID, name = name, icon = icon,
            isEquipped = isEquipped, itemLocations = rows }
    end
    local function attach(item)
        if type(item) ~= "table" then return end
        local names = item.itemString and namesByItemString[item.itemString]
        if not item.itemString then item.equipmentSetsState = "UNKNOWN"; return end
        item.equipmentSets = {}
        if names then for name in pairs(names) do item.equipmentSets[#item.equipmentSets + 1] = name end end
        table.sort(item.equipmentSets)
        item.equipmentSetsState = "OBSERVED"
    end
    local function annotate()
        local record = S.record
        local sections = record and record.sections
        if not sections then return end
        local equipment = sections.equipment and sections.equipment.data
        for _, item in pairs(equipment and equipment.slots or {}) do attach(item) end
        for _, key in ipairs({ "bags", "bank" }) do
            local data = sections[key] and sections[key].data
            for _, container in ipairs(data and data.containers or {}) do
                for _, item in pairs(container.slots or {}) do attach(item) end
            end
        end
    end
    table.sort(sets, function(a, b) return a.setID < b.setID end)
    annotate()
    return { state = "OBSERVED", sets = sets }, { completeness = "complete" }
end

-- Raw diagnostic evidence is opt-in and excluded from ordinary exports.
-- Keep WOWSYNC v1 text parse-compatible with the currently deployed Dashboard.
-- The version-specific raw section is persisted alongside the export and is
-- consumed by the separate Forever parser integration handoff.
S.structuredOnly.forever70291Evidence = true
S.EnableForeverEvidenceDebug = function(enabled)
    enabled = enabled == true
    if not S.settings then S.settings = {} end
    S.settings.debugForever70291Evidence = enabled
    local function include(list)
        for i = #list, 1, -1 do if list[i] == "forever70291Evidence" then table.remove(list, i) end end
        if enabled then list[#list + 1] = "forever70291Evidence" end
    end
    include(S.order); include(S.captureOrder)
    if not enabled then
        S.dirty.forever70291Evidence = nil
        if S.record and S.record.sections then S.record.sections.forever70291Evidence = nil end
    end
    if enabled then S.Mark("forever70291Evidence") end
end
