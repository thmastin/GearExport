# Forever 70291 compatibility capture

This candidate is pinned to Forever `1.60.1`, build `70291`, and interface `16001`. It carries forward only the production collectors selected from the build-70245 contracts. The exact earlier API evidence remains in `FOREVER_EVIDENCE_70245.md` and the historical production-validation report.

## Live validation status - 2026-10-08

Live validation passed for the supported 70291 capture/export path on Hallo.
The persisted export reports client `1.60.1`, build `70291`, interface `16001`,
and the matching `WoWSyncDB` profile is `Forever:1.60.1:70291:16001`. The
WOWSYNC v1 `latestExport` was generated at `1791497563`; character, equipment,
bags, and 70291 evidence observations in the same saved file carry timestamp
`1791497558`. The build, identity, equipped item references, and carried-item
aggregates in the text export were compared with the same-refresh structured
SavedVariables capture. The export remained within the strict WOWSYNC v1 text
shape. Captured file SHA256:
`C6A3720CD02C3081AEAD37CC38087BB8EABB2775BD62978801E93D1C725ACFDF`.

This validates the supported capture and export route on the observed client.
It does not validate fields marked unknown/partial below or establish general
API semantics beyond the observations in the capture. The full persisted
export and same-refresh SavedVariables are preserved at the live client path
`D:\World of Warcraft\_classic_beta_\WTF\Account\262269#1\SavedVariables\GearExport.lua`.

## Skill lines

The collector calls `C_SkillInfo.GetNumSkillLines()` and, when the count is a valid bounded integer, calls `C_SkillInfo.GetSkillLineInfo(index)` once for each index. It preserves index, API, input, return count and types, raw field keys/types/values, and the observed convenience fields `skillID`, `skillLineCategoryID`, `name`, `rank`, `maxRank`, and `isHeader`. Rows remain in runtime index order; duplicate names are not collapsed. Missing, nil, restricted, unsupported, and error results remain explicit. The capture does not invoke skill selection setters and does not convert ranks into weapon readiness or equipability. The live SavedVariables record both skill APIs as present and `GetNumSkillLines()` returned 26; row values remain raw evidence rather than interpreted proficiency conclusions.

## Item detail evidence extension (live capture validated)

The current candidate adds optional, read-only calls to `C_Item.GetItemInfo` and `C_Item.GetItemStats` for the exact itemStrings already observed in equipment and carried bags. The full return tuple is retained with per-position state/type/value. The stats table is copied into a deterministic, 100-entry-bounded array of primitive key/value observations; restricted, missing, unsupported, or failed results remain explicit. API presence and call errors are retained. These extra calls do not upgrade `itemFacts.completeness`, which continues to describe the already-validated identity/type/equippability sample coverage.

Hallo's 2026-10-09 live capture on Forever 1.60.1 build 70291 returned 18 GetItemInfo values and a populated GetItemStats table for all 30 exact itemString variants. No calls failed. Returned hyperlinks retained the exact input variants; item name, item class/subclass, equip-location, class/subclass IDs agreed with GetItemInfoInstant; equipped item and required levels agreed with structured equipment where both were observed. These cross-checks validate the selected GetItemInfo tuple positions on this build. They do not validate every field for every possible item or cache state.

GetItemStats table keys and numeric values remain raw client output. They are not translated into effective stats, primary/secondary stat meaning, weapon upgrades, build suitability, or an upgrade score. IsEquippableItem returned true for ammunition in the capture, so it must not be used alone as an equipment eligibility rule. The capture validates API response shape and exact-variant handling, not all Forever gameplay semantics.

## Trainer window

Trainer service APIs are called only if a supported trainer frame's `IsShown()` returns true at capture start. Service count is bounded at 200 and ability requirement probes at 20 indexes per service. Each call stores the API, input/context, provenance, return count, every tuple position including nil, and errors. Service ordering follows the runtime index. The service requirement count API is recorded as present/missing but not called because its return semantics were not validated. A nil terminator is preserved; reaching a safety limit is labeled partial. A trainer close during enumeration stops further calls and marks the attempted observation partial. No service purchase, learning, selection, or frame-opening API is called. On the live Hallo capture, no supported trainer frame was available; trainer services were `NOT_OBSERVED_FRAME_UNAVAILABLE`, and no trainer-service API contract was claimed validated.

Raw tuple strings such as `unavailable` remain uninterpreted. They do not imply learnability, eligibility, cost meaning, or complete prerequisites. When a supported frame exists and is hidden, the current capture says `NOT_OBSERVED_WINDOW_CLOSED`. If no supported frame object is available, it says `NOT_OBSERVED_FRAME_UNAVAILABLE`; this does not assert that the frame was positively observed closed. Both states retain any prior sample explicitly nested as `lastObserved` with its own timestamp and context.

## Export compatibility and integration

The strict WOWSYNC v1 text remains unchanged so the currently deployed Dashboard parser continues accepting it. This evidence section is persisted as structured SavedVariables and can be inspected using WoWSyncDB. A separate Dashboard parser/import change is required before the evidence becomes queryable by Dashboard workflows; this addon change does not modify or deploy Dashboard.

## Evidence boundaries

The capture does not establish exact transferability, character-specific equipability, class allow/deny restrictions, profession equip restrictions, binding semantics beyond the directly observed carried-stack facet, effective equipment stats, location, currency, playtime, XP, professions, known spells, bank contents, trainer learnability, or complete talent/build interpretation. GetItemStats remains uninterpreted raw evidence. Synthetic tests exercise collector behavior only; live validation is limited to the capture fields listed above.
