-- Synthetic build-70009 C_SpellBook records; spell identity is never inferred.
return function(S, check, equal, advance)
    local savedAPI, savedEnum, oldSecret, savedProfessions = C_SpellBook, Enum, issecretvalue, GetProfessions
    local savedExists, savedGUID, savedName, savedFamily, savedLevel = UnitExists, UnitGUID, UnitName, UnitCreatureFamily, UnitLevel
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
            return line == 1 and { name = "General", itemIndexOffset = 0, numSpellBookItems = 6, shouldHide = false }
                or { name = "Class", itemIndexOffset = 6, numSpellBookItems = 2, shouldHide = true }
        end,
        GetSpellBookItemInfo = function(index, bank)
            equal(bank, 0, "player bank only")
            return items[index]
        end,
    }
    GetProfessions = function() return 3, nil, nil, nil, nil end
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
    C_SpellBook.GetSpellBookSkillLineInfo = function() return { name = "General", itemIndexOffset = 0, numSpellBookItems = 1, shouldHide = false } end
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
    -- Synthetic hunter/warlock bank fixtures: these validate adapter behavior, not live client output.
    local activeGUID, petName, petFamily = "Pet-1", "Wolf", "Wolf"
    UnitExists = function(unit) return unit == "pet" end
    UnitGUID = function(unit) return unit == "pet" and activeGUID or "Player-1" end
    UnitName = function(unit) return unit == "pet" and petName or "Hunter" end
    UnitCreatureFamily = function() return petFamily end
    UnitLevel = function() return 20 end
    C_SpellBook = {
        HasPetSpells = function() return 2, "PET" end,
        GetSpellBookItemName = function(index, bank) equal(bank, 1, "pet bank used"); return index == 1 and "Bite" or "Dash", index == 1 and "Basic Ability" or "Rank 3" end,
        GetSpellBookItemType = function(index, bank) equal(bank, 1, "pet item bank used"); return 1, nil, index == 1 and 17253 or 23145 end,
    }
    data, meta = S.collectors.petSpells()
    equal(meta.completeness, "complete", "synthetic hunter pet enumeration complete")
    equal(data.pet.guid, "Pet-1", "pet GUID observed")
    equal(data.pet.family, "Wolf", "pet family observed")
    equal(data.entries[1].spellID, 17253, "hunter learned spell ID")
    equal(data.entries[1].subName, "Basic Ability", "pet subtype is preserved separately")
    equal(data.entries[1].rank, nil, "pet subtype is not mislabeled as rank")
    equal(data.entries[2].rank, "Rank 3", "explicitly exposed rank preserved")
    petName, petFamily, activeGUID = "Imp", "Imp", "Pet-2"
    C_SpellBook.HasPetSpells = function() return 1, "PET" end
    C_SpellBook.GetSpellBookItemName = function() return "Firebolt", "" end
    C_SpellBook.GetSpellBookItemType = function() return 1, nil, 3110 end
    data = S.collectors.petSpells()
    equal(data.pet.guid, "Pet-2", "warlock pet identity replaces hunter pet identity")
    equal(data.entries[1].name, "Firebolt", "warlock pet ability captured")
    C_SpellBook.HasPetSpells = function() return 1, "PET" end
    C_SpellBook.GetSpellBookItemName = function() activeGUID = "Pet-3"; return "Wrong-pet ability", "" end
    C_SpellBook.GetSpellBookItemType = function() return 1, nil, 999 end
    local switched
    switched, meta = S.collectors.petSpells()
    equal(switched, nil, "mid-enumeration pet switch rejects mixed evidence")
    check(meta.stale, "mid-enumeration switch preserves previous pet as historical")
    activeGUID = "Pet-2"
    UnitExists = function() return false end
    local noPet
    noPet, meta = S.collectors.petSpells()
    equal(noPet, nil, "no pet is not an observed empty list")
    check(meta.stale, "no pet retains prior evidence as LAST_SEEN")
    UnitExists = function() return true end
    C_SpellBook.HasPetSpells = nil
    local unavailable
    unavailable, meta = S.collectors.petSpells()
    equal(unavailable, nil, "unavailable API is not an observed empty list")
    check(meta.stale, "unavailable API retains prior evidence")
    check(S.eventFrame.events.UNIT_PET, "pet identity change event registered")
    check(S.eventFrame.events.PET_BAR_UPDATE, "pet spellbar refresh event registered")
    check(table.concat(S.order, ","):find("petSpells", 1, true) ~= nil, "pet collector included in scheduled capture order")
    UnitExists, UnitGUID, UnitName, UnitCreatureFamily, UnitLevel = savedExists, savedGUID, savedName, savedFamily, savedLevel
    C_SpellBook, Enum, issecretvalue, GetProfessions = savedAPI, savedEnum, oldSecret, savedProfessions
end
