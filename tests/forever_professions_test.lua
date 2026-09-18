-- Synthetic build-69913 ProfessionInfo records; no profession names/tier data
-- are inferred from skill IDs outside the documented runtime response.
return function(S, check, equal, advance)
    local saved = C_TradeSkillUI
    local secret = {}
    local oldSecret = issecretvalue
    issecretvalue = function(value) return value == secret end
    local records = {
        [182] = { profession = 2, professionID = 182, professionName = "Herbalism", skillLevel = 7, maxSkillLevel = 75 },
        [186] = { profession = 3, professionID = 186, professionName = "Mining", skillLevel = 0, maxSkillLevel = 75 },
        [1182] = { profession = 2, professionID = 1182, professionName = "Herbalism", skillLevel = 7, maxSkillLevel = 75 },
        [9999] = { professionID = 9999, professionName = "Test Profession [DNT]", skillLevel = 0, maxSkillLevel = 0 },
    }
    C_TradeSkillUI = {
        GetAllProfessionTradeSkillLines = function() return { 186, 182, 1182, 9999 } end,
        GetProfessionInfoBySkillLineID = function(id) return records[id] end,
    }
    local data, meta = S.collectors.professions()
    equal(meta.completeness, "partial", "excluded unrecognized line is recorded")
    equal(data.entries[1].name, "Herbalism", "runtime name sorted")
    equal(data.entries[1].rank, 7, "runtime skill")
    equal(data.entries[2].name, "Mining", "runtime name retained")
    equal(data.entries[2].rank, 0, "known zero skill")
    equal(#data.entries, 2, "duplicate Forever skill-line IDs collapse by player profession enum")
    check(meta.reason:find("Excluded 1 unrecognized", 1, true), "DNT excluded by API identity, not name")
    S.RequestSync(); advance(2)
    local text = S.RenderSection("professions", S.GetSnapshot())
    check(text:find("Coverage: Forever player profession enums", 1, true), "explicit API coverage")
    check(text:find("profession\tskill\tmaxSkill", 1, true), "existing WOWSYNC schema")
    check(text:find("Herbalism\t7\t75", 1, true), "observed profession row")
    check(S.eventFrame.events.SKILL_LINES_CHANGED and S.eventFrame.events.TRADE_SKILL_LIST_UPDATE,
        "profession refresh events registered")
    C_TradeSkillUI.GetAllProfessionTradeSkillLines = function() return {} end
    data, meta = S.collectors.professions()
    equal(#data.entries, 0, "observed empty profession API is not UNKNOWN")
    equal(meta.completeness, "complete", "observed empty remains complete")
    records[186].professionName = nil
    C_TradeSkillUI.GetAllProfessionTradeSkillLines = function() return { 186 } end
    data, meta = S.collectors.professions()
    equal(data.entries[1].name, nil, "missing name unknown")
    equal(meta.completeness, "partial", "partial runtime record")
    records[186].professionName = "Mining"
    records[186].skillLevel = secret
    data, meta = S.collectors.professions()
    equal(data.entries[1].rank, nil, "restricted skill unknown")
    equal(meta.completeness, "partial", "restricted data partial")
    records[186].skillLevel = 80
    equal(S.collectors.professions(), nil, "skill beyond max rejected")
    records[186].skillLevel = 0
    records[186].professionID = 999
    equal(S.collectors.professions(), nil, "runtime identity mismatch rejected")
    records[186].professionID = 186
    records[1182].skillLevel = 8
    C_TradeSkillUI.GetAllProfessionTradeSkillLines = function() return { 182, 1182 } end
    equal(S.collectors.professions(), nil, "conflicting duplicate profession records rejected")
    records[1182].skillLevel = 7
    C_TradeSkillUI.GetAllProfessionTradeSkillLines = function() return { 186, 186 } end
    equal(S.collectors.professions(), nil, "duplicate skill line list rejected")
    C_TradeSkillUI.GetAllProfessionTradeSkillLines = function() return { "186" } end
    equal(S.collectors.professions(), nil, "typed skill line ID required")
    C_TradeSkillUI.GetAllProfessionTradeSkillLines = function() error("unavailable") end
    equal(S.collectors.professions(), nil, "throwing enumeration unknown")
    C_TradeSkillUI.GetAllProfessionTradeSkillLines = nil
    equal(S.collectors.professions(), nil, "missing enumeration unknown")
    C_TradeSkillUI = saved
    issecretvalue = oldSecret
end
