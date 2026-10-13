-- Forever 1.60.1 read-only talent observation.
-- This module is loaded only by GearExport-Forever.toc. It reads the legacy talent APIs when the
-- Forever client exposes them and records exactly what they return; it never spends or changes points.
local _, addon = ...
local S, F, C = addon.Sync, addon.Forever, WoWSyncCompat
if not S or not C or not C.IsForever or not C.IsForever() then return end

local MAX_TABS, MAX_TALENTS, MAX_TEXT = 10, 100, 256

local function public(value)
    return not (type(issecretvalue) == "function" and issecretvalue(value))
end
local function integer(value, minimum)
    return public(value) and type(value) == "number" and value == value and value ~= math.huge
        and value ~= -math.huge and value % 1 == 0 and value >= (minimum or 0)
end
local function clean(value)
    if not public(value) or type(value) ~= "string" or value == "" then return nil end
    return #value > MAX_TEXT and value:sub(1, MAX_TEXT) or value
end

S.collectors.talents = function()
    if not C.IsForever() then return nil, { completeness = "unknown", reason = "Forever talent collector is version isolated" } end
    if type(GetNumTalentTabs) ~= "function" or type(GetTalentTabInfo) ~= "function"
        or type(GetNumTalents) ~= "function" or type(GetTalentInfo) ~= "function" then
        return nil, { completeness = "unknown", reason = "Talent APIs unavailable on this Forever client", stale = true }
    end
    local ok, tabCount = pcall(GetNumTalentTabs)
    if not ok or not integer(tabCount, 0) or tabCount > MAX_TABS then
        return nil, { completeness = "unknown", reason = "Talent tree count unavailable or outside bound", stale = true }
    end
    local trees, partial, unspent = {}, false, nil
    for tab = 1, tabCount do
        local tabOK, name, _, pointsSpent = pcall(GetTalentTabInfo, tab)
        name = tabOK and clean(name) or nil
        if not name then
            partial = true
        else
            local tree = { tab = tab, name = name, talents = {}, evidence = "OBSERVED" }
            if integer(pointsSpent, 0) then tree.pointsSpent = pointsSpent else partial = true end
            local countOK, talentCount = pcall(GetNumTalents, tab)
            if not countOK or not integer(talentCount, 0) or talentCount > MAX_TALENTS then
                tree.talentCoverage = "UNKNOWN"; partial = true
            else
                tree.talentCoverage = "OBSERVED"
                for index = 1, talentCount do
                    local talentOK, talentName, _, tier, column, currentRank, maxRank = pcall(GetTalentInfo, tab, index)
                    talentName = talentOK and clean(talentName) or nil
                    if not talentName then
                        partial = true
                    else
                        local talent = { index = index, name = talentName, evidence = "OBSERVED" }
                        if integer(tier, 1) then talent.tier = tier end
                        if integer(column, 1) then talent.column = column end
                        if integer(currentRank, 0) then talent.currentRank = currentRank else partial = true end
                        if integer(maxRank, 0) then talent.maxRank = maxRank else partial = true end
                        tree.talents[#tree.talents + 1] = talent
                    end
                end
            end
            trees[#trees + 1] = tree
        end
    end
    if type(UnitCharacterPoints) == "function" then
        local pointsOK, points = pcall(UnitCharacterPoints, "player")
        if pointsOK and integer(points, 0) then unspent = points end
    end
    return {
        formatVersion = 1,
        clientProfile = "Forever:" .. tostring(F and F.runtimeVersion) .. ":" .. tostring(F and F.runtimeBuild) .. ":" .. tostring(F and F.runtimeInterface),
        source = "legacy talent APIs",
        observedAt = S.Now(),
        coverage = "VISIBLE_CLASS_TALENT_TREES",
        trees = trees,
        unspentPoints = unspent,
    }, { completeness = partial and "partial" or "complete", reason = partial and "One or more talent fields were unavailable" or nil }
end
