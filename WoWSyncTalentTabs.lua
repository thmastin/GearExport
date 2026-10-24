-- Shared GetTalentTabInfo tuple adapter for Classic-family collectors.
local _, addon = ...
addon.TalentTabs = {}

function addon.TalentTabs.Read(index)
    if type(GetTalentTabInfo) ~= "function" then return "API_MISSING" end
    local result = { pcall(GetTalentTabInfo, index) }
    if not result[1] then return "API_ERROR" end
    local first, second = result[2], result[3]
    if type(first) == "number" and type(second) == "string" and second ~= "" then
        local points = result[6]
        if type(points) ~= "number" or points < 0 or points % 1 ~= 0 then return "UNKNOWN" end
        return "OBSERVED", first, second, points
    end
    if type(first) == "string" and first ~= "" then
        local points = result[4]
        if type(points) ~= "number" or points < 0 or points % 1 ~= 0 then return "UNKNOWN" end
        return "OBSERVED", nil, first, points
    end
    return "UNKNOWN"
end
