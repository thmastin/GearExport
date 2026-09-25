-- Forever build 70009 profession readiness adapter.
--
-- C_TradeSkillUI exposes an all-profession enumeration before its skill values
-- hydrate. Its pre-hydration 0/0 records cannot establish that a profession is
-- learned at zero skill. The Forever skills UI itself uses the legacy
-- GetProfessions/GetProfessionInfo tuple, which identifies learned indices and
-- reports their current/max skill independently of that trade-skill cache.
local _, addon = ...
local S, F = addon.Sync, addon.Forever

local function Public(value)
    return not (type(issecretvalue) == "function" and issecretvalue(value))
end

local function ValidNumber(value)
    return Public(value) and type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge and value >= 0 and value % 1 == 0
end

local function ProfessionIndices()
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then
        return nil, "Forever learned-profession APIs unavailable"
    end
    local result = { pcall(GetProfessions) }
    if not result[1] then return nil, "Forever learned-profession indices unavailable" end
    local indices, seen = {}, {}
    for position = 1, 5 do
        local index = result[position + 1]
        if index ~= nil then
            if not ValidNumber(index) or index <= 0 or seen[index] then
                return nil, "Forever learned-profession indices changed"
            end
            seen[index] = true
            indices[#indices + 1] = index
        end
    end
    return indices
end

local function ReadProfession(index)
    local result = { pcall(GetProfessionInfo, index) }
    if not result[1] then return nil, "Forever learned profession details unavailable" end
    -- name, texture, rank, maxRank, numSpells, spellOffset, skillLine, ...
    local name, rank, maxRank, skillLine = result[2], result[4], result[5], result[8]
    if not Public(name) or type(name) ~= "string" or name == "" then
        return nil, "Forever learned profession name unavailable"
    end
    if not ValidNumber(rank) or not ValidNumber(maxRank) or maxRank <= 0 or rank > maxRank then
        return nil, "Forever learned profession skill values unavailable"
    end
    if skillLine ~= nil and (not ValidNumber(skillLine) or skillLine <= 0) then
        return nil, "Forever learned profession identity changed"
    end
    return { name = name, rank = rank, maxRank = maxRank, skillLineID = skillLine }
end

S.collectors.professions = function()
    local indices, reason = ProfessionIndices()
    if not indices then return nil, { reason = reason, retry = true, stale = true } end
    local entries = {}
    for _, index in ipairs(indices) do
        local entry, detail = ReadProfession(index)
        if not entry then return nil, { reason = detail, retry = true, stale = true } end
        entries[#entries + 1] = entry
    end
    table.sort(entries, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return (a.skillLineID or 0) < (b.skillLineID or 0)
    end)
    return { entries = entries,
        coverage = "Forever learned profession indices and current/max skill from GetProfessions/GetProfessionInfo; C_TradeSkillUI pre-hydration values are not used" },
        { completeness = "complete" }
end
