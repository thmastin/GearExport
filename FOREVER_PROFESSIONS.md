# Forever professions: live findings and readiness guard

Earlier verified Forever `1.60.1` build `69913` recorded Hallo Emberstone with Engineering `20/75`
and Mining `23/75`.

## Hydration finding

Immediately after login/reload, `C_TradeSkillUI` enumerated every profession
enum as `0/0`, including Mining and Engineering, while the Skills UI displayed
Mining `23/75`. Opening the general Skills/Professions UI did not change those
values. Opening Smelting did hydrate the C_TradeSkillUI values; a later export
then showed Engineering `20/75` and Mining `23/75`.

Consequently, C_TradeSkillUI all-profession rows are not used as current skill
evidence. Its pre-hydration `0/0` records cannot prove a profession is learned
at zero skill.

## Collector contract

The Forever Skills UI uses `GetProfessions()` to return learned profession
indices and `GetProfessionInfo(index)` to return the learned profession name,
current skill, maximum skill, and optional skill-line identity. The collector
uses that independent tuple as its authoritative observation source:

- Nil index: an unlearned profession; no learned entry is fabricated.
- Learned entry with a non-empty name and valid `current/max`, where `max > 0`:
  OBSERVED.
- Learned `0/75`: valid observed data.
- Learned `0/0`, unavailable/restricted/malformed data, or a changed tuple:
  UNKNOWN, with retry; it is never rendered as current observed `0/0`.
- If a prior complete learned-profession observation exists when a later tuple is
  unavailable, that prior data remains explicitly `LAST_SEEN` at its original
  observation timestamp with a refresh issue. It is not relabeled as current
  `OBSERVED` data; the next authoritative tuple replaces it.

This preserves the existing WOWSYNC v1 `profession, skill, maxSkill` schema.
It does not infer profession identity, tiers, expansions, categories, or skill
values from C_TradeSkillUI IDs or cached prior observations.

## Regression coverage and live acceptance

Synthetic regression coverage includes pre-hydration C_TradeSkillUI `0/0`,
hydrated Engineering `20/75` and Mining `23/75`, retained `LAST_SEEN` data
after a later unavailable tuple, a valid learned `0/75`, unlearned nil slots,
unavailable values, and malformed tuples.

The fresh-login live regression passed after `/reload`, before opening Smelting
or any actual trade-skill window: `/wowsync` reported Cooking `5/75`,
Engineering `20/75`, and Mining `23/75` as current OBSERVED complete data. No
unlearned `0/0` rows were fabricated. The defensive UNKNOWN/LAST_SEEN paths
remain covered for malformed or unavailable learned tuples.
