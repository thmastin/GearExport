-- Forever build 69913 uses the modern trainer tuple used by its Mainline UI:
-- name, status, texture, requiredLevel. It is not the Classic rank/status tuple.
local _, addon = ...
local S, F = addon.Sync, addon.Forever
local function Optional(fn, ...) local ok, a, b, c, d = pcall(fn, ...); if ok then return a, b, c, d end end

S.collectors.trainer = function()
    if not S.trainerOpen then return nil, { reason = "Forever trainer is closed" } end
    if type(GetNumTrainerServices) ~= "function" or type(GetTrainerServiceInfo) ~= "function" then
        return nil, { reason = "Forever trainer APIs unavailable" }
    end
    local issues = {}
    local count = F.Number("Trainer service count", GetNumTrainerServices, issues)
    if count == nil then return nil, { reason = "Forever trainer data pending", retry = true } end
    local filters = {}
    for _, status in ipairs({ "available", "unavailable", "used" }) do
        if type(GetTrainerServiceTypeFilter) == "function" then filters[status] = Optional(GetTrainerServiceTypeFilter, status) end
    end
    local services, empty = {}, count == 0
    for index = 1, count do
        local name, status, texture, level = Optional(GetTrainerServiceInfo, index)
        if type(name) ~= "string" or name == "" or type(status) ~= "string" then
            return nil, { reason = "Forever trainer service tuple unavailable or changed", retry = true }
        end
        -- The modern UI emits only services; texture is display-only and rank
        -- is not exposed. Never reinterpret texture as a rank.
        if texture ~= nil and type(texture) ~= "number" and type(texture) ~= "string" then
            return nil, { reason = "Forever trainer texture field changed", retry = true }
        end
        if level ~= nil and (type(level) ~= "number" or level < 0 or level % 1 ~= 0) then
            return nil, { reason = "Forever trainer required-level field changed", retry = true }
        end
        if status ~= "header" then
            local cost = type(GetTrainerServiceCost) == "function" and Optional(GetTrainerServiceCost, index) or nil
            local service = { name = name, status = status,
                cost = type(cost) == "number" and cost >= 0 and cost % 1 == 0 and cost or nil,
                requiredLevel = level }
            if service.cost == nil then issues[#issues + 1] = "Trainer cost unavailable for " .. index end
            if service.requiredLevel == nil then issues[#issues + 1] = "Trainer level requirement unavailable for " .. index end
            local skill, skillRank, skillMet
            if type(GetTrainerServiceSkillReq) == "function" then skill, skillRank, skillMet = Optional(GetTrainerServiceSkillReq, index) end
            if type(skill) == "string" and skill ~= "" then service.skillRequirement = { name = skill, rank = skillRank, met = skillMet } end
            local reqs
            if type(GetTrainerServiceNumAbilityReq) == "function" then reqs = Optional(GetTrainerServiceNumAbilityReq, index) end
            if type(reqs) == "number" and reqs > 0 then
                service.abilityRequirements = {}
                for req = 1, reqs do
                    local reqName, met
                    if type(GetTrainerServiceAbilityReq) == "function" then reqName, met = Optional(GetTrainerServiceAbilityReq, index, req) end
                    if type(reqName) == "string" and reqName ~= "" then service.abilityRequirements[#service.abilityRequirements + 1] = { name = reqName, met = met } else issues[#issues + 1] = "Trainer prerequisite unavailable for " .. index end
                end
            end
            services[#services + 1] = service
        end
    end
    table.sort(services, function(a, b) return a.name == b.name and (a.rank or "") < (b.rank or "") or a.name < b.name end)
    local category = type(IsTradeskillTrainer) == "function" and Optional(IsTradeskillTrainer) and "PROFESSION"
        or type(IsTalentTrainer) == "function" and Optional(IsTalentTrainer) and "CLASS" or "UNKNOWN"
    S.trainerCategory = category
    local visit = S.currentTrainerVisit or S.record.visits.trainers[category]
    if visit then S.record.visits.trainers[category] = visit end
    local data = { visit = S.Copy(visit), name = visit and visit.name, trainerType = category, services = services, filters = filters,
        moneyAtVisit = F.Number("Trainer visit money", GetMoney, issues),
        coverage = "Forever modern trainer tuple (name/status/texture/required level); rank and spell ID are not exposed" }
    return { category = category, snapshot = data }, { completeness = (#issues > 0 or empty) and "partial" or "complete",
        reason = #issues > 0 and table.concat(issues, "; ") or empty and "No service rows; trainer completeness unknown" or nil,
        retry = empty }
end
