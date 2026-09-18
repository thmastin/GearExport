-- Forever build 69913 C_TradeSkillUI profession contracts.
local _, addon = ...
local S, F = addon.Sync, addon.Forever

local function Field(object, key)
    return function() return object[key] end
end

S.collectors.professions = function()
    local api = type(C_TradeSkillUI) == "table" and C_TradeSkillUI or {}
    if type(api.GetAllProfessionTradeSkillLines) ~= "function"
        or type(api.GetProfessionInfoBySkillLineID) ~= "function" then
        return nil, { reason = "Forever profession APIs unavailable" }
    end
    local issues = {}
    local ids = F.Read("Profession skill lines", api.GetAllProfessionTradeSkillLines,
        1, "table", issues)
    if not ids then return nil, { reason = "Forever profession skill lines unavailable", retry = true } end
    local entries, seenIDs, seenProfessions, excluded = {}, {}, {}, 0
    for _, id in ipairs(ids) do
        if type(id) ~= "number" or id <= 0 or id % 1 ~= 0 or seenIDs[id] then
            return nil, { reason = "Forever profession skill-line list changed", retry = true }
        end
        seenIDs[id] = true
        local info = F.Read("Profession " .. id, api.GetProfessionInfoBySkillLineID, 1, "table", issues, id)
        if not info then return nil, { reason = "Forever profession details pending", retry = true } end
        local name = F.Read("Profession " .. id .. " name", Field(info, "professionName"), 1, "string", issues)
        local rank = F.Number("Profession " .. id .. " skill", Field(info, "skillLevel"), issues)
        local maxRank = F.Number("Profession " .. id .. " maximum", Field(info, "maxSkillLevel"), issues)
        -- Nullable player Profession enum identifies a profession across the
        -- distinct skill-line IDs exposed by the Forever runtime.
        local profession = info.profession
        if profession ~= nil and (not F.Number("Profession " .. id .. " enum", Field(info, "profession"), issues)
            or profession <= 0) then return nil, { reason = "Forever profession enum changed", retry = true } end
        local reportedID = F.Number("Profession " .. id .. " ID", Field(info, "professionID"), issues)
        if reportedID and reportedID ~= id then return nil, { reason = "Forever profession identity changed", retry = true } end
        if rank and maxRank and rank > maxRank then return nil, { reason = "Forever profession skill range inconsistent", retry = true } end
        if profession == nil then
            -- A missing player enum makes the line unrecognized non-player
            -- data. This handles DNT without filtering by display text.
            excluded = excluded + 1
        else
            local previous = seenProfessions[profession]
            if previous then
                if previous.name ~= name or previous.rank ~= rank or previous.maxRank ~= maxRank then
                    return nil, { reason = "Forever duplicate profession records disagree", retry = true }
                end
            else
                local entry = { name = name, rank = rank, maxRank = maxRank }
                seenProfessions[profession] = entry
                entries[#entries + 1] = entry
            end
        end
    end
    table.sort(entries, function(a, b) return (a.name or "") < (b.name or "") end)
    table.sort(issues)
    if excluded > 0 then issues[#issues + 1] = "Excluded " .. excluded .. " unrecognized non-player profession skill line(s)" end
    return { entries = entries, coverage = "Forever player profession enums; current and maximum skill from C_TradeSkillUI" },
        { completeness = #issues > 0 and "partial" or "complete",
            reason = #issues > 0 and table.concat(issues, "; ") or nil, retry = #issues > 0 }
end
