-- Synthetic build-69913 C_SpellBook records; spell identity is never inferred.
return function(S, check, equal, advance)
    local savedAPI, savedEnum, oldSecret = C_SpellBook, Enum, issecretvalue
    local secret = {}
    issecretvalue = function(value) return value == secret end
    Enum = { SpellBookItemType = { Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 },
        SpellBookSpellBank = { Player = 0, Pet = 1 } }
    local items = {
        [1] = { itemType = 1, isOffSpec = false, spellID = 100, name = "Arcane Shot" },
        [2] = { itemType = 2, isOffSpec = false, spellID = 101, name = "Future" },
        [3] = { itemType = 3, isOffSpec = false, spellID = 102, name = "Pet action" },
        [4] = { itemType = 4, isOffSpec = false, spellID = 103, name = "Flyout" },
        [5] = { itemType = 1, isOffSpec = true, spellID = 104, name = "Off spec" },
        [6] = { itemType = 1, isOffSpec = false, spellID = 100, name = "Arcane Shot" },
    }
    C_SpellBook = {
        GetNumSpellBookSkillLines = function() return 2 end,
        GetSpellBookSkillLineInfo = function(line)
            return line == 1 and { itemIndexOffset = 0, numSpellBookItems = 6, shouldHide = false }
                or { itemIndexOffset = 6, numSpellBookItems = 2, shouldHide = true }
        end,
        GetSpellBookItemInfo = function(index, bank)
            equal(bank, 0, "player bank only")
            return items[index]
        end,
    }
    local data, meta = S.collectors.spells()
    equal(meta.completeness, "complete", "complete player spellbook")
    equal(#data.entries, 1, "future/pet/flyout/off-spec and duplicate IDs excluded")
    equal(data.entries[1].spellID, 100, "observed spell ID")
    equal(data.entries[1].name, "Arcane Shot", "observed spell name")
    S.RequestSync(); advance(2)
    local text = S.RenderSection("spells", S.GetSnapshot())
    check(text:find("100\tArcane Shot\t-", 1, true), "existing WOWSYNC spell schema")
    check(not text:find("Future", 1, true) and not text:find("Pet action", 1, true), "excluded spellbook types absent")
    check(S.eventFrame.events.SPELLS_CHANGED and S.eventFrame.events.SPELL_TEXT_UPDATE, "spell refresh events")
    C_SpellBook.GetNumSpellBookSkillLines = function() return 1 end
    C_SpellBook.GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = 1, shouldHide = false } end
    items[1] = { itemType = 1, isOffSpec = false, spellID = nil, name = "Pending" }
    data, meta = S.collectors.spells()
    equal(#data.entries, 0, "missing ID is not guessed")
    equal(meta.completeness, "partial", "missing identity partial")
    items[1] = { itemType = 1, isOffSpec = false, spellID = secret, name = "Restricted" }
    data, meta = S.collectors.spells()
    equal(#data.entries, 0, "restricted ID unknown")
    items[1] = { itemType = 1, isOffSpec = false, spellID = 100, name = "Arcane Shot" }
    C_SpellBook.GetSpellBookItemInfo = function() return nil end
    equal(S.collectors.spells(), nil, "missing item pending")
    C_SpellBook.GetSpellBookItemInfo = function() error("unavailable") end
    equal(S.collectors.spells(), nil, "throwing spell API unknown")
    C_SpellBook.GetSpellBookItemInfo = nil
    equal(S.collectors.spells(), nil, "missing spell API unknown")
    C_SpellBook, Enum, issecretvalue = savedAPI, savedEnum, oldSecret
end
