# Forever professions: live-validated

This build adds professions only. It was live-validated on Hallo, level 7,
Forever build `69913`.

The build-69913 source tag (`70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e`)
documents `C_TradeSkillUI.GetAllProfessionTradeSkillLines()` and
`GetProfessionInfoBySkillLineID(skillLineID)`. `ProfessionInfo` supplies the
runtime `professionName`, `skillLevel`, and `maxSkillLevel`, along with its
own `professionID` and nullable player `profession` enum. Forever returns
distinct skill-line IDs for the same player profession; equivalent records
collapse by that enum, not by display name. A line without the player enum is
excluded as unrecognized non-player data. This handles the live `Test
Profession [DNT]` record by API identity; its name is never an exclusion rule.
Conflicting duplicate records remain UNKNOWN rather than selecting one. The
adapter records only these observed fields in the
existing WOWSYNC v1 `profession, skill, maxSkill` schema. It does not infer
tiers, expansions, categories, names, or skills from IDs.

An empty enumerated list is OBSERVED empty. Missing, throwing, restricted,
duplicate, malformed, mismatched, or range-inconsistent results leave the
section UNKNOWN or partial as appropriate. The test fixture uses synthetic
records and covers those cases; no real profession data is invented.

## Live acceptance

Hallo's live export reports Engineering `20/75`, Mining `22/75`, and the other
player profession enums as `0/0`. No duplicate rows remain. Two unrecognized,
non-player skill lines are excluded and reported in the OBSERVED/partial
coverage note. This validates the enum-based normalization and DNT handling;
it does not authorize inferred tiers, expansions, categories, names, or skills.

After manual installation, validate a fresh `/wowsync` on Hallo. Capture the
exact results of `/dump C_TradeSkillUI.GetAllProfessionTradeSkillLines()` and,
for every returned ID, `/dump C_TradeSkillUI.GetProfessionInfoBySkillLineID(ID)`
before extending behavior to any absent profession classes.
