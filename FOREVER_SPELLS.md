# Forever known spells: live-validated

Build-70009 source documents `C_SpellBook.GetNumSpellBookSkillLines`,
`GetSpellBookSkillLineInfo`, and `GetSpellBookItemInfo(slot, Player bank)`.
The adapter scans visible, active player skill lines only. It includes entries
whose documented item type is `Spell` and whose runtime spell ID and name are
both available. It excludes future spells, pet actions, flyouts, hidden and
off-spec lines, and the Pet spellbook. Duplicate spell IDs collapse.

The API's `SpellBookItemInfo` has no rank field, so ranks render as `-` in the
existing WOWSYNC v1 schema rather than being inferred. Missing or restricted
identity makes coverage partial; missing structural APIs or skill-line/item
records leaves the section UNKNOWN. Tests use synthetic API records only.

Hallo's prior build-69913 live export captured all 15 visible active player spells
correctly. This validates the observed player-bank path only; it does not
authorize inferred ranks, pet spells, flyouts, future spells, hidden lines, or
off-spec entries.
# Forever learned spell reporting

The Forever package keeps the owner's learned spellbook in the existing
`spells` section. Active-pet learned abilities are captured separately in the
structured `petSpells` section of `WoWSyncDB`; they are not added to WOWSYNC v1
text, owner spells, trainer offers, or action-bar evidence.

Pet evidence uses `C_SpellBook.HasPetSpells()` and the `Pet` spell bank. Each
observation carries the active pet GUID and any available name, family, and
level. An unavailable spellbook, absent pet, or pet switch during enumeration
does not create an observed empty list. Carried data remains `LAST_SEEN` at its
original observation time and retains the pet identity. The pet bank's
spellbook subName is retained as `subName` (it may describe an ability subtype,
not a rank); a `rank` is emitted only when the returned text explicitly has the
`Rank N` form.

The synthetic harness covers hunter and warlock examples, pet switching,
missing pets/APIs, event scheduling, and separation from owner spells. These
fixtures do not establish live compatibility. Validate in-game on each client
build before treating its result as live-observed; build 70790 remains
`UNVERIFIED_BUILD` until that work is completed.

The Dashboard reads this data separately through `get_character_pet_spells`.
Use `surname` or `identityKey` when name-only selection is ambiguous.

For live validation, with a hunter or warlock pet active, run this read-only
probe in-game after `/reload` and again after changing pets:

```text
/run local c,t=C_SpellBook.HasPetSpells(); print("PET",UnitGUID("pet"),UnitName("pet"),UnitCreatureFamily("pet"),c,t); for i=1,c or 0 do local n,s=C_SpellBook.GetSpellBookItemName(i,Enum.SpellBookSpellBank.Pet); local k,a,id=C_SpellBook.GetSpellBookItemType(i,Enum.SpellBookSpellBank.Pet); print(i,k,a,id,n,s) end
```

Record the exact client build, pet GUID/name/family, `c`/`t`, and each printed
spell type/action ID/spell ID/name/subName. Repeat with no pet and confirm the
probe yields no enumeration. This establishes live API returns and the
observation cases; the synthetic fixtures above are not a substitute.
