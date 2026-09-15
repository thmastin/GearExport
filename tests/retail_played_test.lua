-- Retail 12.1.0/69814 contract: request returns no values; server response is
-- delivered later through TIME_PLAYED_MSG. Durations below are synthetic,
-- not measurements of the user's character or a claim of live server timing.
return function(S, check, equal, advance)
    local oldLevel, oldClass, oldXP, oldXPMax, oldRequest = UnitLevel, UnitClass, UnitXP, UnitXPMax, RequestTimePlayed
    UnitLevel = function() return 78 end
    UnitClass = function() return "Evoker", "EVOKER" end
    UnitXP = function() return 413 end
    UnitXPMax = function() return 72820 end
    local replyAt, requestCount = nil, 0
    RequestTimePlayed = function()
        requestCount = requestCount + 1
        replyAt = GetTime() + 1.2
        -- No synchronous totals or return value.
    end
    local function pump(duration)
        for _ = 1, math.ceil(duration / 0.1) do
            advance(0.1)
            if replyAt and GetTime() >= replyAt then
                replyAt = nil
                check(S.eventFrame.events.TIME_PLAYED_MSG, "Retail response event registered")
                S.eventFrame.scripts.OnEvent(S.eventFrame, "TIME_PLAYED_MSG", 123456, 45678)
            end
        end
    end
    S.played, S.playedPending, S.playedLevel = nil, nil, nil
    local output
    S.Export(function(text) output = text end)
    pump(0.5)
    equal(output, nil, "Retail export awaits server event")
    local pending = S.RenderSection("character", S.GetSnapshot())
    check(pending:find("PlayedSeconds: ?\nLevelPlayedSeconds: ?", 1, true), "both labels exist before response")
    check(pending:find("XP: 413/72820", 1, true), "reported non-max-level Retail shape")
    pump(1.2)
    equal(requestCount, 1, "one request for delayed Retail response")
    check(output and output:find("PlayedSeconds: 123456\nLevelPlayedSeconds: 45678", 1, true), "delayed Retail event reaches export")
    equal(S.record.sections.character.data.playedSeconds, 123456, "Retail total stored as integer")
    equal(S.record.sections.character.data.levelPlayedSeconds, 45678, "Retail level time stored as integer")
    local frozen = output
    pump(1)
    equal(output, frozen, "display remains frozen after completion")
    RequestTimePlayed = function() requestCount = requestCount + 1 end
    output = nil
    S.Export(function(text) output = text end); pump(3.5)
    check(output and output:find("PlayedSeconds: ?\nLevelPlayedSeconds: ?", 1, true), "timeout retains both field labels")
    RequestTimePlayed = oldRequest
    UnitLevel, UnitClass, UnitXP, UnitXPMax = oldLevel, oldClass, oldXP, oldXPMax
    S.played, S.playedPending, S.playedLevel = nil, nil, nil
end
