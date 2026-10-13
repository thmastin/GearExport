-- Forever 1.60.1 read-only reputation observation.
-- Loaded only by GearExport-Forever.toc. Reads the faction list the client already shows (Retail-style
-- C_Reputation first, legacy GetFactionInfo as fallback) and emits the same row shape as the Classic
-- collector. It never expands or collapses headers, toggles at-war, or changes the watched faction.
local _, addon = ...
local S, F, C = addon.Sync, addon.Forever, WoWSyncCompat
if not S or not C or not C.IsForever or not C.IsForever() then return end

local MAX_FACTIONS, MAX_TEXT = 500, 256

local function public(value)
    return not (type(issecretvalue) == "function" and issecretvalue(value))
end
local function integer(value, minimum)
    return public(value) and type(value) == "number" and value == value and value ~= math.huge
        and value ~= -math.huge and value % 1 == 0 and value >= (minimum or 0)
end
local function number(value)
    return public(value) and type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end
local function clean(value)
    if not public(value) or type(value) ~= "string" or value == "" then return nil end
    return #value > MAX_TEXT and value:sub(1, MAX_TEXT) or value
end
local function profile()
    return "Forever:" .. tostring(F and F.runtimeVersion) .. ":" .. tostring(F and F.runtimeBuild) .. ":" .. tostring(F and F.runtimeInterface)
end

-- One normalized row reader per API family: name, factionID, standing, bar, flags.
local function modernRow(index)
    local ok, row = pcall(C_Reputation.GetFactionDataByIndex, index)
    if not ok or type(row) ~= "table" then return nil end
    return { name = row.name, factionID = row.factionID, standing = row.reaction, barMin = row.currentReactionThreshold,
        barMax = row.nextReactionThreshold, barValue = row.currentStanding, atWar = row.atWarWith, canToggle = row.canToggleAtWar,
        isHeader = row.isHeader, collapsed = row.isCollapsed, hasRep = row.isHeaderWithRep, watched = row.isWatched, isChild = row.isChild }
end
local function legacyRow(index)
    local ok, name, _, standing, barMin, barMax, barValue, atWar, canToggle, isHeader, collapsed, hasRep, watched, isChild, factionID = pcall(GetFactionInfo, index)
    if not ok then return nil end
    return { name = name, factionID = factionID, standing = standing, barMin = barMin, barMax = barMax, barValue = barValue,
        atWar = atWar, canToggle = canToggle, isHeader = isHeader, collapsed = collapsed, hasRep = hasRep, watched = watched, isChild = isChild }
end

S.collectors.reputation = function()
    if not C.IsForever() then return nil, { completeness = "unknown", reason = "Forever reputation collector is version isolated" } end
    local count, read, source
    if type(C_Reputation) == "table" and type(C_Reputation.GetNumFactions) == "function" and type(C_Reputation.GetFactionDataByIndex) == "function" then
        local ok, value = pcall(C_Reputation.GetNumFactions)
        if ok then count, read, source = value, modernRow, "C_Reputation.GetFactionDataByIndex" end
    end
    if not read and type(GetNumFactions) == "function" and type(GetFactionInfo) == "function" then
        local ok, value = pcall(GetNumFactions)
        if ok then count, read, source = value, legacyRow, "GetFactionInfo" end
    end
    if not read then return nil, { completeness = "unknown", reason = "Reputation list APIs unavailable on this Forever client", stale = true } end
    if not integer(count, 0) then return nil, { completeness = "unknown", reason = "Faction row count unavailable", stale = true } end
    if count > MAX_FACTIONS then return nil, { completeness = "unknown", reason = "Faction row bound exceeded", stale = true } end
    local client, rows, partial, parents = profile(), {}, false, {}
    for index = 1, count do
        local row = read(index)
        local name = row and clean(row.name)
        if not name then
            partial = true
        elseif row.isHeader == true then
            parents[row.isChild == true and "child" or "parent"] = name
            if row.isChild ~= true then parents.child = nil end
            if row.collapsed == true then partial = true end
            if row.hasRep == true then
                if integer(row.factionID, 1) then
                    rows[#rows + 1] = { factionID = row.factionID, name = name, isHeaderReputation = true, evidence = "OBSERVED", ownerScope = "CHARACTER",
                        standingID = integer(row.standing, 0) and row.standing or nil, barMin = number(row.barMin) and row.barMin or nil,
                        barMax = number(row.barMax) and row.barMax or nil, barValue = number(row.barValue) and row.barValue or nil }
                else partial = true end
            end
        else
            local out = { name = name, evidence = "OBSERVED", ownerScope = "CHARACTER", visibleIndex = index }
            if integer(row.factionID, 1) then out.factionID = row.factionID else partial = true end
            if integer(row.standing, 0) then out.standingID = row.standing end
            if number(row.barMin) then out.barMin = row.barMin end
            if number(row.barMax) then out.barMax = row.barMax end
            if number(row.barValue) then out.barValue = row.barValue end
            if public(row.atWar) and type(row.atWar) == "boolean" then out.atWar = row.atWar end
            if public(row.canToggle) and type(row.canToggle) == "boolean" then out.canToggleAtWar = row.canToggle end
            if public(row.watched) and type(row.watched) == "boolean" then out.isWatched = row.watched end
            out.parentCategory = parents.child or parents.parent
            out.factionKey = "forever:" .. tostring(out.factionID or ((out.parentCategory or "") .. ":" .. name))
            rows[#rows + 1] = out
        end
    end
    return { formatVersion = 1, clientProfile = client, source = source, observedAt = S.Now(), ownerScope = "CHARACTER",
        coverage = "VISIBLE_REPUTATION_ROWS_ONLY", factions = rows, majorFactions = {} },
        { completeness = "partial", reason = partial and "Faction rows may be collapsed or missing stable IDs" or "Only faction rows visible in the current reputation list are covered" }
end
