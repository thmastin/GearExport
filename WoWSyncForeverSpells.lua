-- Forever 1.60.1 C_SpellBook player-bank contracts. Keep the collector
-- fail-closed: unavailable/changed rows make the section partial, not empty.
local _, addon = ...
local S, F = addon.Sync, addon.Forever

local function Field(object, key)
    return function() return object[key] end
end

-- Separate active-pet spellbook. HasPetSpells() is the Forever count/token
-- contract; the bank APIs are called only with Enum.SpellBookSpellBank.Pet.
-- Synthetic collector fixtures exercise the supported signatures, not a live client.
S.collectors.petSpells = function()
    local api = type(C_SpellBook) == "table" and C_SpellBook or {}
    local enum = type(Enum) == "table" and Enum or {}
    local banks, types = enum.SpellBookSpellBank or {}, enum.SpellBookItemType or {}
    local petExists = F.Read("Pet exists", UnitExists, 1, "boolean", {}, "pet")
    if petExists ~= true then return nil, { reason = "No active pet; learned pet abilities not observed", stale = true } end
    local guid = F.Read("Pet GUID", UnitGUID, 1, "string", {}, "pet")
    local name = F.Read("Pet name", UnitName, 1, "string", {}, "pet")
    if not guid then return nil, { reason = "Active pet identity unavailable", stale = true } end
    local family = F.Read("Pet family", UnitCreatureFamily, 1, "string", {}, "pet")
    local level = F.Number("Pet level", UnitLevel, {}, "pet")
    if banks.Pet == nil or type(types.PetAction) ~= "number" or type(types.Spell) ~= "number"
        or type(api.HasPetSpells) ~= "function"
        or type(api.GetSpellBookItemName) ~= "function" or type(api.GetSpellBookItemType) ~= "function" then
        return nil, { reason = "Forever pet spellbook APIs unavailable", stale = true }
    end
    local ok, count, token = pcall(api.HasPetSpells)
    if not ok or type(count) ~= "number" or count < 0 or count % 1 ~= 0 then
        return nil, { reason = "Forever pet spellbook enumeration unavailable", retry = true, stale = true }
    end
    if count == 0 and token == nil then return nil, { reason = "Pet spellbook unavailable", retry = true, stale = true } end
    local entries, issues, seen = {}, {}, {}
    for index = 1, count do
        local nameOk, spellName, subName = pcall(api.GetSpellBookItemName, index, banks.Pet)
        local typeOk, itemType, actionID, spellID = pcall(api.GetSpellBookItemType, index, banks.Pet)
        if not nameOk or not typeOk then
            issues[#issues + 1] = "Pet spellbook item " .. index .. " unavailable"
        -- Forever reports type PetAction for both commands/stances and learned
        -- spells. Only its explicit spellID distinguishes abilities; actionID
        -- contains packed pet-action identifiers and must never be substituted.
        elseif itemType == types.Spell or itemType == types.PetAction and type(spellID) == "number" and spellID > 0 then
            if type(spellID) ~= "number" or spellID <= 0 or type(spellName) ~= "string" or spellName == "" then
                issues[#issues + 1] = "Pet spellbook item " .. index .. " identity pending"
            elseif not seen[spellID] then
                seen[spellID] = true
                local exposedRank = type(subName) == "string" and subName:match("^Rank%s+%d+$") and subName or nil
                entries[#entries + 1] = { spellID = spellID, name = spellName,
                    subName = type(subName) == "string" and subName ~= "" and subName or nil,
                    rank = exposedRank }
            end
        end
    end
    -- A pet change during enumeration invalidates the entire read.
    local afterGUID = F.Read("Pet GUID after enumeration", UnitGUID, 1, "string", {}, "pet")
    if afterGUID ~= guid then return nil, { reason = "Active pet changed during spellbook enumeration", retry = true, stale = true } end
    table.sort(entries, function(a, b) return a.spellID < b.spellID end)
    table.sort(issues)
    return { pet = { guid = guid, name = name, family = family, level = level }, entries = entries,
        coverage = "Active pet spellbook via HasPetSpells and Pet spell bank; ranks only where subName is exposed" },
        { completeness = #issues > 0 and "partial" or "complete", reason = #issues > 0 and table.concat(issues, "; ") or nil, retry = #issues > 0 }
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
