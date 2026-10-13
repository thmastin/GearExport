return function(S, check, equal)
    local passed = 0
    local function c(value, message) check(value, "reputation: " .. message); passed = passed + 1 end
    local function e(a, b, message) equal(a, b, "reputation: " .. message); passed = passed + 1 end
    local changed = 0
    local function forbid() changed = changed + 1; error("reputation collector must not change the faction list") end
    local saved = { C_Reputation, GetNumFactions, GetFactionInfo, ExpandFactionHeader, CollapseFactionHeader, SetWatchedFactionIndex, FactionToggleAtWar }
    ExpandFactionHeader, CollapseFactionHeader, SetWatchedFactionIndex, FactionToggleAtWar = forbid, forbid, forbid, forbid

    c(S.collectors.reputation ~= nil, "Forever reputation collector registered")
    local inOrder = false
    for _, key in ipairs(S.order) do if key == "reputation" then inOrder = true end end
    c(inOrder, "reputation is in the Forever section order")

    C_Reputation, GetNumFactions, GetFactionInfo = nil, nil, nil
    local data, meta = S.collectors.reputation()
    e(data, nil, "missing APIs produce no data")
    e(meta.completeness, "unknown", "missing APIs are unknown, not empty")

    local list = {
        { name = "Alliance", isHeader = true },
        { name = "Ironforge", factionID = 47, reaction = 5, currentReactionThreshold = 3000, nextReactionThreshold = 9000, currentStanding = 4200, isWatched = true, atWarWith = false },
        { name = "Gnomeregan", factionID = 54, reaction = 4, currentReactionThreshold = 0, nextReactionThreshold = 3000, currentStanding = 250 },
        { name = nil },
    }
    C_Reputation = { GetNumFactions = function() return #list end, GetFactionDataByIndex = function(index) return list[index] end,
        SetWatchedFactionByIndex = forbid, ExpandFactionHeader = forbid, ToggleFactionAtWar = forbid }
    data, meta = S.collectors.reputation()
    e(data.source, "C_Reputation.GetFactionDataByIndex", "modern API preferred")
    e(#data.factions, 2, "header rows without reputation are not factions; nameless rows are skipped")
    e(data.factions[1].name, "Ironforge", "faction name")
    e(data.factions[1].standingID, 5, "standing from reaction")
    e(data.factions[1].barValue, 4200, "bar value from current standing")
    e(data.factions[1].barMax, 9000, "bar max from next threshold")
    e(data.factions[1].parentCategory, "Alliance", "parent header retained")
    e(data.factions[1].isWatched, true, "watched flag retained")
    e(meta.completeness, "partial", "visible rows only is partial coverage")

    C_Reputation = nil
    GetNumFactions = function() return 1 end
    GetFactionInfo = function() return "Darnassus", "desc", 4, 0, 3000, 100, false, true, false, false, false, false, false, 69 end
    data = S.collectors.reputation()
    e(data.source, "GetFactionInfo", "legacy fallback")
    e(data.factions[1].factionID, 69, "legacy faction ID")

    GetNumFactions = function() return 9999 end
    data, meta = S.collectors.reputation()
    e(data, nil, "row bound refused")
    e(changed, 0, "faction list was never changed")

    C_Reputation, GetNumFactions, GetFactionInfo, ExpandFactionHeader, CollapseFactionHeader, SetWatchedFactionIndex, FactionToggleAtWar = saved[1], saved[2], saved[3], saved[4], saved[5], saved[6], saved[7]
    return passed
end
