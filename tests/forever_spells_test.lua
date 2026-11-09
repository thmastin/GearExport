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
    -- Live probe regression fixtures supplied by the user (Forever build 70790).
    -- Every source row had itemType=PetAction (3); nil spellID rows are commands/stances,
    -- and actionID values are packed pet-action identifiers, never spell IDs.
    local liveVoidwalker = {
        { 3, 100663298, nil, "Aggressive Pet Stance", "" }, { 3, 100663299, nil, "Assist Pet Stance", "" },
        { 3, 117440514, nil, "Attack Pet Command", "" }, { 3, 16794983, 17767, "Consume Shadows", "Rank 1" },
        { 3, 100663300, nil, "Defensive Pet Stance", "" }, { 3, 117440513, nil, "Follow Pet Command", "" },
        { 3, 117440516, nil, "Move To Pet Command", "" }, { 3, 100663296, nil, "Passive Pet Stance", "" },
        { 3, 16785028, 7812, "Sacrifice", "Rank 1" }, { 3, 117440512, nil, "Stay Pet Command", "" },
        { 3, 3238006404, 3716, "Torment", "Rank 1" },
    }
    local liveImp = {
        { 3, 100663298, nil, "Aggressive Pet Stance", "" }, { 3, 100663299, nil, "Assist Pet Stance", "" },
        { 3, 117440514, nil, "Attack Pet Command", "" }, { 3, 3238010492, 7804, "Blood Pact", "Rank 2" },
        { 3, 100663300, nil, "Defensive Pet Stance", "" }, { 3, 2164263811, 2947, "Fire Shield", "Rank 1" },
        { 3, 3238010487, 7799, "Firebolt", "Rank 2" }, { 3, 117440513, nil, "Follow Pet Command", "" },
        { 3, 117440516, nil, "Move To Pet Command", "" }, { 3, 100663296, nil, "Passive Pet Stance", "" },
        { 3, 3238007199, 4511, "Phase Shift", "" }, { 3, 117440512, nil, "Stay Pet Command", "" },
    }
    local function useLivePetFixture(rows)
        C_SpellBook = {
            HasPetSpells = function() return #rows, "DEMON" end,
            GetSpellBookItemName = function(index, bank) equal(bank, 1, "live fixture uses pet bank"); return rows[index][4], rows[index][5] end,
            GetSpellBookItemType = function(index, bank) equal(bank, 1, "live fixture uses pet bank"); return rows[index][1], rows[index][2], rows[index][3] end,
        }
    end
    activeGUID, petName, petFamily = "Pet-0-7073-0-3-1860-0821A254F2", "Mezzkresh", "Voidwalker"
    UnitLevel = function() return 11 end
    useLivePetFixture(liveVoidwalker)
    data, meta = S.collectors.petSpells()
    equal(#data.entries, 3, "live Voidwalker fixture keeps only rows with explicit spell IDs")
    equal(data.pet.guid, "Pet-0-7073-0-3-1860-0821A254F2", "live Voidwalker identity retained")
    local consumeShadows
    for _, ability in ipairs(data.entries) do if ability.spellID == 17767 then consumeShadows = ability end end
    equal(consumeShadows.name, "Consume Shadows", "packed action ID is not substituted for spell ID")
    equal(consumeShadows.spellID, 17767, "live Voidwalker spell ID retained")
    equal(consumeShadows.rank, "Rank 1", "live Voidwalker rank retained")
    S.Commit("petSpells", data, meta)
    local voidwalkerObservedAt = S.record.sections.petSpells.observedAt
    UnitExists = function() return false end
    local missingPet, missingMeta = S.collectors.petSpells()
    equal(missingPet, nil, "live no-pet fixture is UNKNOWN, not empty")
    S.Attempt("petSpells", missingMeta.reason, missingMeta.stale)
    equal(S.record.sections.petSpells.data.pet.guid, "Pet-0-7073-0-3-1860-0821A254F2", "no-pet period retains Voidwalker identity as LAST_SEEN")
    equal(S.record.sections.petSpells.observedAt, voidwalkerObservedAt, "no-pet attempt never refreshes carried timestamp")
    check(S.record.sections.petSpells.lastAttemptStale, "no-pet attempt marks carried section stale")
    UnitExists = function() return true end
    activeGUID, petName, petFamily = "Pet-0-7073-0-3-416-B91DE90ECA", "Laznip", "Imp"
    UnitLevel = function() return 12 end
    useLivePetFixture(liveImp)
    local impData, impMeta = S.collectors.petSpells()
    equal(#impData.entries, 4, "live Imp fixture keeps its four learned abilities")
    equal(impData.pet.guid, "Pet-0-7073-0-3-416-B91DE90ECA", "live Imp identity replaces Voidwalker")
    local abilityIDs = {}
    for _, ability in ipairs(impData.entries) do abilityIDs[ability.spellID] = ability end
    check(abilityIDs[7804] and abilityIDs[2947] and abilityIDs[7799] and abilityIDs[4511], "all live Imp ability IDs captured")
    equal(abilityIDs[4511].name, "Phase Shift", "live Phase Shift captured")
    equal(abilityIDs[4511].rank, nil, "blank Phase Shift rank remains absent")
    advance(2)
    S.Commit("petSpells", impData, impMeta)
    equal(S.record.sections.petSpells.data.pet.guid, "Pet-0-7073-0-3-416-B91DE90ECA", "new observation replaces rather than mixes prior pet")
    check(S.record.sections.petSpells.observedAt > voidwalkerObservedAt, "new Imp observation gets its own timestamp")
    check(not S.record.sections.petSpells.lastAttemptStale, "new observed pet clears prior stale state")
    UnitExists = function() return true end
    activeGUID, petName, petFamily = "Pet-2", "Imp", "Imp"
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

    -- Synthetic end-to-end regression: the pet is already out when PLAYER_LOGIN
    -- fires, so no UNIT_PET/PET_BAR_UPDATE is available to trigger the first scan.
    -- Login/world sync and a following export must still write OBSERVED data to
    -- WoWSyncDB. This verifies capture flow, not live build compatibility.
    activeGUID, petName, petFamily = "Pet-0-7073-0-3-416-B91DE90ECA", "Laznip", "Imp"
    UnitExists = function(unit) return unit == "pet" end
    UnitGUID = function(unit) return unit == "pet" and activeGUID or "Player-Forever-Test" end
    UnitLevel = function(unit) return unit == "pet" and 12 or 10 end
    useLivePetFixture(liveImp)
    WoWSyncDB.characters["Player-Forever-Test"].sections.petSpells = nil
    S.record = nil -- emulate addon initialization on reload using the existing SavedVariables table
    S.dirty.petSpells = nil
    S.eventFrame.scripts.OnEvent(S.eventFrame, "PLAYER_LOGIN")
    advance(1)
    local loginSection = WoWSyncDB.characters["Player-Forever-Test"].sections.petSpells
    check(loginSection and loginSection.data and loginSection.completeness == "complete",
        "already-summoned pet is observed on login without waiting for a pet-change event")
    equal(loginSection.data.pet.guid, "Pet-0-7073-0-3-416-B91DE90ECA", "login capture keeps active Imp identity")
    equal(#loginSection.data.entries, 4, "login capture stores all active Imp abilities")
    local exportText
    check(S.Export(function(text) exportText = text end), "export after login pet scan is accepted")
    advance(3.2)
    check(type(exportText) == "string", "export completes after the scheduled pet scan")
    local savedSection = WoWSyncDB.characters["Player-Forever-Test"].sections.petSpells
    check(savedSection.data and savedSection.completeness == "complete", "export leaves the OBSERVED pet section in SavedVariables")
    equal(savedSection.data.pet.guid, "Pet-0-7073-0-3-416-B91DE90ECA", "SavedVariables pet section is not tied to a later pet event")
    UnitExists, UnitGUID, UnitName, UnitCreatureFamily, UnitLevel = savedExists, savedGUID, savedName, savedFamily, savedLevel
    C_SpellBook, Enum, issecretvalue, GetProfessions = savedAPI, savedEnum, oldSecret, savedProfessions
end
