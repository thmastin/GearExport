-- Forever profession readiness: C_TradeSkillUI can enumerate all professions
-- with pre-hydration 0/0 data. Only the skills UI's learned-profession tuple is
-- authoritative for current/max rank.
return function(S, check, equal, advance)
    local savedLines, savedInfo, savedTrade, oldSecret = GetProfessions, GetProfessionInfo, C_TradeSkillUI, issecretvalue
    local secret, hydrated = {}, false
    issecretvalue = function(value) return value == secret end
    C_TradeSkillUI = {
        GetAllProfessionTradeSkillLines = function() return { 171, 164, 333, 202, 182, 186, 393, 165, 197 } end,
        GetProfessionInfoBySkillLineID = function(id)
            return { profession = id, professionID = id, professionName = "Unhydrated " .. id,
                skillLevel = 0, maxSkillLevel = 0 }
        end,
    }

    -- A pre-hydration C_TradeSkillUI 0/0 table cannot establish learned skill.
    GetProfessions = function() return 1, 2, nil, nil, nil end
    GetProfessionInfo = function()
        if not hydrated then return "Mining", nil, 0, 0, nil, nil, 186 end
        return "Mining", nil, 23, 75, nil, nil, 186
    end
    equal(S.collectors.professions(), nil, "pre-hydration learned 0/0 is UNKNOWN, not observed")
    S.RequestSync(); advance(2)
    local preHydration = S.RenderSection("professions", S.GetSnapshot())
    check(preHydration:find("State: UNKNOWN", 1, true), "pre-hydration export remains UNKNOWN")
    check(not preHydration:find("Mining\t0\t0", 1, true), "pre-hydration export never claims Mining 0/0")

    local records = {
        [1] = { "Mining", 23, 75, 186 },
        [2] = { "Engineering", 20, 75, 202 },
    }
    hydrated = true
    GetProfessionInfo = function(index)
        local record = records[index]
        if not record then return end
        return record[1], nil, record[2], record[3], nil, nil, record[4]
    end
    local data, meta = S.collectors.professions()
    equal(meta.completeness, "complete", "hydrated learned professions are complete")
    equal(#data.entries, 2, "unlearned C_TradeSkillUI enums are not presented as learned")
    equal(data.entries[1].name, "Engineering", "deterministic learned profession ordering")
    equal(data.entries[1].rank, 20, "hydrated Engineering skill")
    equal(data.entries[2].name, "Mining", "hydrated Mining identity")
    equal(data.entries[2].rank, 23, "hydrated Mining skill")
    equal(data.entries[2].maxRank, 75, "hydrated Mining maximum")
    S.RequestSync(); advance(2)
    local text = S.RenderSection("professions", S.GetSnapshot())
    check(text:find("Engineering\t20\t75", 1, true), "rendered hydrated Engineering")
    check(text:find("Mining\t23\t75", 1, true), "rendered hydrated Mining")
    check(not text:find("Unhydrated", 1, true), "C_TradeSkillUI placeholder professions never render")
    check(S.eventFrame.events.SKILL_LINES_CHANGED and S.eventFrame.events.TRADE_SKILL_LIST_UPDATE,
        "profession refresh events remain registered")

    -- A later unhydrated tuple cannot relabel the last authoritative values as
    -- current OBSERVED data. The preserved timestamp identifies them as LAST_SEEN
    -- until a new authoritative tuple replaces them.
    local observedAt = S.record.sections.professions.observedAt
    hydrated = false
    GetProfessionInfo = function()
        return "Mining", nil, 0, 0, nil, nil, 186
    end
    S.RequestSync(); advance(2)
    local staleText = S.RenderSection("professions", S.GetSnapshot())
    check(staleText:find("State: LAST_SEEN", 1, true), "unhydrated refresh retains professions as LAST_SEEN")
    equal(S.record.sections.professions.observedAt, observedAt, "unhydrated refresh preserves original observation timestamp")
    check(staleText:find("RefreshIssue: Forever learned profession skill values unavailable", 1, true),
        "unhydrated refresh explains why current skill is unknown")
    hydrated = true
    GetProfessionInfo = function(index)
        local record = records[index]
        if not record then return end
        return record[1], nil, record[2], record[3], nil, nil, record[4]
    end
    S.RequestSync(); advance(2)
    local refreshedText = S.RenderSection("professions", S.GetSnapshot())
    check(refreshedText:find("State: OBSERVED", 1, true), "authoritative refresh clears stale profession state")
    check(refreshedText:find("Mining\t23\t75", 1, true), "authoritative refresh replaces retained profession data")

    -- A genuinely learned zero-current profession remains valid when max skill is
    -- authoritative; an unlearned slot is nil and produces no entry.
    records[1] = { "Mining", 0, 75, 186 }
    GetProfessions = function() return 1, nil, nil, nil, nil end
    data, meta = S.collectors.professions()
    equal(meta.completeness, "complete", "learned 0/75 remains an observed value")
    equal(#data.entries, 1, "absent profession slots are not inferred")
    equal(data.entries[1].rank, 0, "authoritative learned zero is retained")
    equal(data.entries[1].maxRank, 75, "authoritative learned maximum retained")

    GetProfessionInfo = function() return "Mining", nil, secret, 75, nil, nil, 186 end
    equal(S.collectors.professions(), nil, "restricted learned skill remains UNKNOWN")
    GetProfessionInfo = function() return "Mining", nil, 80, 75, nil, nil, 186 end
    equal(S.collectors.professions(), nil, "skill beyond maximum remains UNKNOWN")
    GetProfessionInfo = function() return "Mining", nil, 0, 0, nil, nil, 186 end
    equal(S.collectors.professions(), nil, "learned 0/0 is not authoritative")
    GetProfessionInfo = function() error("unavailable") end
    equal(S.collectors.professions(), nil, "throwing learned-profession API remains UNKNOWN")
    GetProfessions = function() return 1, 1, nil, nil, nil end
    equal(S.collectors.professions(), nil, "duplicate learned profession indices rejected")
    GetProfessions = function() return "1", nil, nil, nil, nil end
    equal(S.collectors.professions(), nil, "typed learned profession index required")
    GetProfessions = nil
    equal(S.collectors.professions(), nil, "missing learned-profession API remains UNKNOWN")

    GetProfessions, GetProfessionInfo, C_TradeSkillUI, issecretvalue = savedLines, savedInfo, savedTrade, oldSecret
end
