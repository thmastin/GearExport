-- Replay only values present in the real export. No missing gameplay values
-- are invented; API stubs replay the captured character/location observations.
return function(S, equal)
    local text = assert(loadfile("tests/fixtures/forever/hallo-level4.lua"))()
    local fields = {}
    for name, value in text:gmatch("\n([%w]+): ([^\n]+)") do fields[name] = value end
    local xp, maxXP = fields.XP:match("(%d+)/(%d+)")
    local x, y = fields.PositionPercent:match("([%d.]+),([%d.]+)")
    local version, build = fields.Client:match("(%S+) build (%S+)")
    local saved = {}
    local replacements = {
        UnitName = function() return fields.Name end,
        GetRealmName = function() return fields.Realm end,
        UnitClass = function() return nil, fields.Class end,
        UnitLevel = function() return tonumber(fields.Level) end,
        UnitFactionGroup = function() return fields.Faction end,
        GetMoney = function() return tonumber(fields.MoneyCopper) end,
        UnitXP = function() return tonumber(xp) end,
        UnitXPMax = function() return tonumber(maxXP) end,
        GetBuildInfo = function() return version, build, nil, tonumber(fields.Interface) end,
        GetRealZoneText = function() return fields.Zone end,
        GetSubZoneText = function() return fields.Subzone end,
        C_Map = { GetBestMapForUnit = function() return tonumber(fields.MapID) end,
            GetPlayerMapPosition = function() return { GetXY = function()
                return tonumber(x) / 100, tonumber(y) / 100
            end } end },
    }
    for name, value in pairs(replacements) do saved[name] = _G[name]; _G[name] = value end
    for key, label in pairs({ character = "CHARACTER", location = "LOCATION" }) do
        local expected = assert(text:match("%[" .. label .. "%]\n(.-)\n\n"))
        local data, meta = S.collectors[key]()
        local snapshot = { sections = { [key] = { data = data,
            completeness = meta.completeness, reason = meta.reason,
            observedAt = tonumber(expected:match("observed=(%d+)")) } } }
        equal(S.RenderSection(key, snapshot), "[" .. label .. "]\n" .. expected,
            "real Hallo level-4 " .. key .. " export byte-identical")
    end
    for name in pairs(replacements) do _G[name] = saved[name] end
end
