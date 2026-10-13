return function(S, check, equal)
    local passed = 0
    local function c(value, message) check(value, "talents: " .. message); passed = passed + 1 end
    local function e(a, b, message) equal(a, b, "talents: " .. message); passed = passed + 1 end
    local spent = 0
    LearnTalent = function() spent = spent + 1; error("talent collector must never learn talents") end

    c(S.collectors.talents ~= nil, "Forever talent collector registered")
    c(S.structuredOnly.talents == true, "talents travel only in the structured sidecar")
    local inOrder = false
    for _, key in ipairs(S.order) do if key == "talents" then inOrder = true end end
    c(inOrder, "talents are in the Forever section order")

    local savedTabs, savedTab, savedNum, savedInfo, savedPoints = GetNumTalentTabs, GetTalentTabInfo, GetNumTalents, GetTalentInfo, UnitCharacterPoints
    GetNumTalentTabs, GetTalentTabInfo, GetNumTalents, GetTalentInfo = nil, nil, nil, nil
    local data, meta = S.collectors.talents()
    e(data, nil, "missing APIs produce no data")
    e(meta.completeness, "unknown", "missing APIs are unknown, not empty")

    GetNumTalentTabs = function() return 3 end
    GetTalentTabInfo = function(tab) return ({ "Balance", "Feral Combat", "Restoration" })[tab], "icon", tab == 1 and 2 or 0 end
    GetNumTalents = function(tab) return tab == 3 and 1 or 2 end
    GetTalentInfo = function(tab, index)
        if tab == 2 and index == 2 then return nil end
        return "Talent " .. tab .. "-" .. index, "icon", index, 1, tab == 1 and index == 1 and 2 or 0, 5
    end
    UnitCharacterPoints = function() return 1 end
    data, meta = S.collectors.talents()
    e(#data.trees, 3, "three trees observed")
    e(data.trees[1].name, "Balance", "tree name retained")
    e(data.trees[1].pointsSpent, 2, "points spent retained")
    e(data.trees[1].talents[1].currentRank, 2, "talent rank retained")
    e(data.trees[1].talents[1].maxRank, 5, "talent max rank retained")
    e(#data.trees[2].talents, 1, "a missing talent row is skipped, not invented")
    e(meta.completeness, "partial", "a missing talent row makes coverage partial")
    e(data.unspentPoints, 1, "unspent points observed")
    c(type(data.clientProfile) == "string" and data.clientProfile:match("^Forever:") ~= nil, "Forever profile recorded")

    GetNumTalentTabs = function() return 50 end
    data, meta = S.collectors.talents()
    e(data, nil, "an out-of-bound tree count is refused")
    e(meta.completeness, "unknown", "out-of-bound count is unknown")
    e(spent, 0, "no talent was learned")

    GetNumTalentTabs, GetTalentTabInfo, GetNumTalents, GetTalentInfo, UnitCharacterPoints = savedTabs, savedTab, savedNum, savedInfo, savedPoints
    LearnTalent = nil
    return passed
end
