-- Shared lifecycle contract, invoked inside each complete client fixture.
return function(S, check, equal, advance, addon)
    local originalRequest, originalLevel = RequestTimePlayed, UnitLevel
    local function event(...) S.eventFrame.scripts.OnEvent(S.eventFrame, ...) end
    local requests = 0
    RequestTimePlayed = function(...)
        equal(select("#", ...), 0, "documented request has no arguments")
        requests = requests + 1
    end
    S.playedPending = nil
    S.RequestSync(); S.RequestSync()
    equal(requests, 1, "coalesce outstanding requests")
    advance(0.5)
    equal(S.record.sections.character.data.playedSeconds, nil, "pending total unknown")
    local output
    S.Export(function(text) output = text end)
    advance(0.5)
    equal(output, nil, "export waits for response")
    event("TIME_PLAYED_MSG", 123456, 45678); advance(0.5)
    local data = S.record.sections.character.data
    equal(data.playedSeconds, 123456, "SavedVariables raw total seconds")
    equal(data.levelPlayedSeconds, 45678, "SavedVariables raw level seconds")
    check(output and output:find("PlayedSeconds: 123456\nLevelPlayedSeconds: 45678", 1, true), "export includes raw seconds")
    local frozen = S.GetSnapshot()
    local frozenText = S.Render(frozen)
    equal(S.Render(frozen), S.Render(frozen), "playtime rendering deterministic")
    local baselinePath = os.getenv("WOWSYNC_BASELINE_RENDERER")
    if baselinePath then
        local currentRender, currentSection = S.Render, S.RenderSection
        assert(loadfile(baselinePath))("GearExport", addon)
        local baseline = S.Render(frozen)
        S.Render, S.RenderSection = currentRender, currentSection
        local withoutPlayed = frozenText:gsub("\nPlayedSeconds: [^\n]*", ""):gsub("\nLevelPlayedSeconds: [^\n]*", "")
        equal(withoutPlayed, baseline, "all existing canonical output byte-identical")
    end
    event("TIME_PLAYED_MSG", 0, 0); advance(0.5)
    equal(S.record.sections.character.data.playedSeconds, 0, "known zero total")
    equal(S.record.sections.character.data.levelPlayedSeconds, 0, "known zero level")
    event("TIME_PLAYED_MSG", 123, nil); advance(0.5)
    equal(S.record.sections.character.data.playedSeconds, 123, "independent total")
    equal(S.record.sections.character.data.levelPlayedSeconds, nil, "missing level unknown")
    event("TIME_PLAYED_MSG", nil, 45); advance(0.5)
    equal(S.record.sections.character.data.levelPlayedSeconds, 45, "independent level")
    equal(S.record.sections.character.data.playedSeconds, nil, "missing total unknown")
    for _, invalid in ipairs({ -1, 1.5, "123", math.huge, 0/0, false }) do
        event("TIME_PLAYED_MSG", invalid, invalid); advance(0.5)
        equal(S.record.sections.character.data.playedSeconds, nil, "invalid seconds unknown")
    end
    local secret = {}
    local oldSecret = issecretvalue
    issecretvalue = function(value) return value == secret end
    event("TIME_PLAYED_MSG", secret, 0); advance(0.5)
    equal(S.record.sections.character.data.playedSeconds, nil, "restricted total unknown")
    issecretvalue = oldSecret
    RequestTimePlayed = nil
    S.RequestSync(); advance(0.5)
    check(S.Render(S.GetSnapshot()):find("PlayedSeconds: ?\nLevelPlayedSeconds: ?", 1, true), "missing API exports unknowns")
    RequestTimePlayed = function() error("Unavailable") end
    check(S.RequestSync(), "request failure does not break sync")
    RequestTimePlayed = function() end
    S.playedPending = nil
    output = nil
    S.Export(function(text) output = text end); advance(3.5)
    check(output and output:find("PlayedSeconds: ?", 1, true), "no response completes bounded export")
    event("TIME_PLAYED_MSG", 500, 100); advance(0.5)
    equal(S.record.sections.character.data.playedSeconds, 500, "late response captured")
    local level = UnitLevel("player") + 1
    UnitLevel = function() return level end
    event("PLAYER_LEVEL_UP", level); advance(0.5)
    equal(S.record.sections.character.data.levelPlayedSeconds, nil, "level change invalidates old seconds")
    event("TIME_PLAYED_MSG", 501, 0); advance(0.5)
    equal(S.record.sections.character.data.levelPlayedSeconds, 0, "new level captures zero")
    S.playedPending = nil
    S.unsupportedEvents.TIME_PLAYED_MSG = true
    local before = requests
    RequestTimePlayed = function() requests = requests + 1 end
    S.RequestSync(); advance(0.5)
    equal(requests, before, "unsupported event prevents request")
    equal(S.record.sections.character.data.playedSeconds, nil, "unsupported event unknown")
    S.unsupportedEvents.TIME_PLAYED_MSG = nil
    RequestTimePlayed = function() event("TIME_PLAYED_MSG", 600, 1) end
    S.RequestSync(); advance(0.5)
    equal(S.record.sections.character.data.playedSeconds, 600, "immediate event captured")
    equal(S.playedPending, nil, "immediate event completes request")
    equal(S.Render(frozen), frozenText, "later events leave frozen snapshot deterministic")
    RequestTimePlayed, UnitLevel = originalRequest, originalLevel
    S.played, S.playedPending, S.playedLevel = nil, nil, nil
end
