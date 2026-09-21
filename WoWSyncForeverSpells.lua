-- Forever build 69913 C_SpellBook player-bank contracts.
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
    local entries, seen = {}, {}
    for line = 1, lines do
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
                        entries[#entries + 1] = { spellID = spellID, name = name }
                    end
                end
            end
        end
    end
    table.sort(entries, function(a, b) return a.spellID < b.spellID end)
    table.sort(issues)
    return { entries = entries,
        coverage = "Forever visible active player spellbook; excludes future, pet, flyout and off-spec entries; ranks not exposed" },
        { completeness = #issues > 0 and "partial" or "complete",
            reason = #issues > 0 and table.concat(issues, "; ") or nil, retry = #issues > 0 }
end
