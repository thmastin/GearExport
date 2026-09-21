# Forever known spells: live-validated

Build-69913 source documents `C_SpellBook.GetNumSpellBookSkillLines`,
`GetSpellBookSkillLineInfo`, and `GetSpellBookItemInfo(slot, Player bank)`.
The adapter scans visible, active player skill lines only. It includes entries
whose documented item type is `Spell` and whose runtime spell ID and name are
both available. It excludes future spells, pet actions, flyouts, hidden and
off-spec lines, and the Pet spellbook. Duplicate spell IDs collapse.

The API's `SpellBookItemInfo` has no rank field, so ranks render as `-` in the
existing WOWSYNC v1 schema rather than being inferred. Missing or restricted
identity makes coverage partial; missing structural APIs or skill-line/item
records leaves the section UNKNOWN. Tests use synthetic API records only.

Hallo's build-69913 live export captured all 15 visible active player spells
correctly. This validates the observed player-bank path only; it does not
authorize inferred ranks, pet spells, flyouts, future spells, hidden lines, or
off-spec entries.
