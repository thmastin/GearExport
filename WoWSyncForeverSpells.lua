-- Forever 1.60.1 C_SpellBook player-bank contracts. Keep the collector
-- fail-closed: unavailable/changed rows make the section partial, not empty.
local _, addon = ...
local S, F = addon.Sync, addon.Forever

local function Field(object, key)
    return function() return object[key] end
end

S.collectors.spells = function()
    local api = type(C_SpellBook) == "table" and C_SpellBook or {}
    local enum = type(Enum) == "table" and Enum or {}
    local types, banks = enum.SpellBookItemType or {}, enum.SpellBookSpellBank or {}
    if type(api.GetNumSpellBookSkillLines) ~= "function" or type(api.GetSpellBookSkillLineInfo) ~= "function"
        or type(api.GetSpellBookItemInfo) ~= "function" or type(types.Spell) ~= "number"
        or type(banks.Player) ~= "number" then
        return nil, { reason = "Forever spellbook APIs unavailable" }
    end
    local issues = {}
    local lines = F.Number("Spellbook skill-line count", api.GetNumSpellBookSkillLines, issues)
    if not lines or lines == 0 then return nil, { reason = "Forever spellbook not ready", retry = true } end
    local entries, seen, lineIndices = {}, {}, {}
    for line = 1, lines do lineIndices[line] = { index = line, profession = false } end
    if type(GetProfessions) == "function" then
        local ok, first, second, archaeology, fishing, cooking = pcall(GetProfessions)
        if ok then
            local professionIndices = { first, second, archaeology, fishing, cooking }
            for position = 1, 5 do
                local index = professionIndices[position]
                if type(index) == "number" and index > 0 and index % 1 == 0 then
                    local exists = false
                    for _, row in ipairs(lineIndices) do if row.index == index then exists = true; row.profession = true end end
                    if not exists then lineIndices[#lineIndices + 1] = { index = index, profession = true } end
                elseif index ~= nil then
                    issues[#issues + 1] = "Forever profession spellbook index unavailable"
                end
            end
        else
            issues[#issues + 1] = "Forever profession spellbook indices unavailable"
        end
    else
        issues[#issues + 1] = "Forever profession spellbook indices unavailable"
    end
    table.sort(lineIndices, function(a, b) return a.index < b.index end)
    for _, lineRow in ipairs(lineIndices) do
        local line = lineRow.index
        local info = F.Read("Spellbook skill line " .. line, api.GetSpellBookSkillLineInfo, 1, "table", issues, line)
        if not info then return nil, { reason = "Forever spellbook skill line pending", retry = true } end
        local offset = F.Number("Spellbook skill line " .. line .. " offset", Field(info, "itemIndexOffset"), issues)
        local count = F.Number("Spellbook skill line " .. line .. " count", Field(info, "numSpellBookItems"), issues)
        local hidden = F.Read("Spellbook skill line " .. line .. " hidden", Field(info, "shouldHide"), 1, "boolean", issues)
        local offSpec = info.offSpecID ~= nil
        if not offset or not count or count < 0 then return nil, { reason = "Forever spellbook skill-line range pending", retry = true } end
        if not hidden and not offSpec then
            for index = offset + 1, offset + count do
                local item = F.Read("Spellbook item " .. index, api.GetSpellBookItemInfo, 1, "table", issues, index, banks.Player)
                if not item then return nil, { reason = "Forever spellbook item pending", retry = true } end
                local itemType = F.Number("Spellbook item " .. index .. " type", Field(item, "itemType"), issues)
                local itemOffSpec = F.Read("Spellbook item " .. index .. " off-spec", Field(item, "isOffSpec"), 1, "boolean", issues)
                if itemType == types.Spell and itemOffSpec == false then
                    local spellID = F.Number("Spellbook item " .. index .. " ID", Field(item, "spellID"), issues)
                    local name = F.Read("Spellbook item " .. index .. " name", Field(item, "name"), 1, "string", issues)
                    if not spellID or spellID <= 0 or not name then
                        issues[#issues + 1] = "Spellbook item " .. index .. " identity pending"
                    elseif not seen[spellID] then
                        seen[spellID] = true
                        entries[#entries + 1] = { spellID = spellID, name = name,
                            skillLineName = F.Read("Spellbook skill line " .. line .. " name", Field(info, "name"), 1, "string", issues),
                            professionAbility = lineRow.profession }
                    end
                end
            end
        end
    end
    table.sort(entries, function(a, b) return a.spellID < b.spellID end)
    table.sort(issues)
    return { entries = entries,
        coverage = "Forever visible player spellbook including GetProfessions tab indexes; excludes future, pet, flyout and off-spec entries; ranks not exposed" },
        { completeness = #issues > 0 and "partial" or "complete",
            reason = #issues > 0 and table.concat(issues, "; ") or nil, retry = #issues > 0 }
end

-- Class ability catalog: spellbook entries the client lists as not yet learned (future spells), with the
-- level the client reports for each. Read-only; nothing is cast, learned or trained.
local MAX_FUTURE = 300
S.collectors.classSpellCatalog = function()
    local api = type(C_SpellBook) == "table" and C_SpellBook or {}
    local enum = type(Enum) == "table" and Enum or {}
    local types, banks = enum.SpellBookItemType or {}, enum.SpellBookSpellBank or {}
    if type(api.GetNumSpellBookSkillLines) ~= "function" or type(api.GetSpellBookSkillLineInfo) ~= "function"
        or type(api.GetSpellBookItemInfo) ~= "function" or type(banks.Player) ~= "number" then
        return nil, { completeness = "unknown", reason = "Forever spellbook APIs unavailable" }
    end
    if type(types.FutureSpell) ~= "number" then
        return { entries = {}, futureSpellType = "UNAVAILABLE", observedAt = S.Now() },
            { completeness = "unknown", reason = "This client exposes no future-spell spellbook type" }
    end
    local issues, entries, seen = {}, {}, {}
    local lines = F.Number("Spellbook skill-line count", api.GetNumSpellBookSkillLines, issues)
    if not lines or lines == 0 then return nil, { reason = "Forever spellbook not ready", retry = true } end
    local levelOf = function(index, spellID)
        if type(api.GetSpellBookItemLevelLearned) == "function" then
            local ok, level = pcall(api.GetSpellBookItemLevelLearned, index, banks.Player)
            if ok and type(level) == "number" and level > 0 then return level, "C_SpellBook.GetSpellBookItemLevelLearned" end
        end
        if type(C_Spell) == "table" and type(C_Spell.GetSpellLevelLearned) == "function" then
            local ok, level = pcall(C_Spell.GetSpellLevelLearned, spellID)
            if ok and type(level) == "number" and level > 0 then return level, "C_Spell.GetSpellLevelLearned" end
        end
        if type(GetSpellLevelLearned) == "function" then
            local ok, level = pcall(GetSpellLevelLearned, spellID)
            if ok and type(level) == "number" and level > 0 then return level, "GetSpellLevelLearned" end
        end
        return nil, nil
    end
    for line = 1, lines do
        local info = F.Read("Spellbook skill line " .. line, api.GetSpellBookSkillLineInfo, 1, "table", issues, line)
        if not info then return nil, { reason = "Forever spellbook skill line pending", retry = true } end
        local offset = F.Number("Spellbook skill line " .. line .. " offset", Field(info, "itemIndexOffset"), issues)
        local count = F.Number("Spellbook skill line " .. line .. " count", Field(info, "numSpellBookItems"), issues)
        if not offset or not count or count < 0 then
            issues[#issues + 1] = "Spellbook skill line " .. line .. " range unavailable"
        elseif info.shouldHide ~= true and info.offSpecID == nil then
            for index = offset + 1, offset + count do
                local item = F.Read("Spellbook item " .. index, api.GetSpellBookItemInfo, 1, "table", issues, index, banks.Player)
                if item and item.itemType == types.FutureSpell and #entries < MAX_FUTURE then
                    local spellID = F.Number("Spellbook item " .. index .. " ID", Field(item, "spellID"), issues)
                    local name = F.Read("Spellbook item " .. index .. " name", Field(item, "name"), 1, "string", issues)
                    if spellID and spellID > 0 and name and not seen[spellID] then
                        seen[spellID] = true
                        local level, levelSource = levelOf(index, spellID)
                        entries[#entries + 1] = { spellID = spellID, name = name, levelLearned = level, levelSource = levelSource,
                            skillLineName = type(info.name) == "string" and info.name or nil, evidence = "OBSERVED" }
                    end
                end
            end
        end
    end
    table.sort(entries, function(a, b) return (a.levelLearned or 999) < (b.levelLearned or 999) or ((a.levelLearned or 999) == (b.levelLearned or 999) and a.spellID < b.spellID) end)
    table.sort(issues)
    return { entries = entries, futureSpellType = "OBSERVED", observedAt = S.Now(),
        coverage = "Forever spellbook future-spell entries (class and general tabs); ranks and training costs are not exposed here" },
        { completeness = #issues > 0 and "partial" or "complete", reason = #issues > 0 and table.concat(issues, "; ") or nil }
end
