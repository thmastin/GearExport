# Forever 70291 compatibility capture

This candidate is pinned to Forever `1.60.1`, build `70291`, and interface `16001`. It carries forward only the production collectors selected from the build-70245 contracts. The exact earlier API evidence remains in `FOREVER_EVIDENCE_70245.md` and the historical production-validation report.

## Exact-build compatibility extension - 2026-10-10

The installed `WowB.exe` reports FileVersion `1.60.1.70338`; Forever logs
written on 2026-10-10 and crash metadata independently report build `70338`.
The client flavor marker is `wow_classic_beta`. A same-session
`ForeverDingAssistant.lua` capture stores build `1.60.1.70338` and interface
`16001` in its `HUNTER-12-trainer` record. Gethe's Blizzard UI-source mirror's
`forever` branch is at commit
[`943764493e6b16d63ded3ab304150d1f05e58b57`](https://github.com/Gethe/wow-ui-source/commit/943764493e6b16d63ded3ab304150d1f05e58b57),
which identifies itself as `1.60.1 (70338)`; its Forever TOCs use interface
`16001`. The corresponding generated API documentation directory is byte-for-
byte unchanged from the source revision identifying build 70291
(`9465cb2`, `1.60.1 (70291)`). This includes the declarations for build
detection, character/unit data, items and item stats, containers, banks, skills,
professions, and trainers. This is version-matched source evidence for unchanged
API declarations, not proof of live runtime behavior or of every returned value.

The runtime guard and deployment manifest now permit only exact client pairs
`1.60.1 / 70291 / 16001` and `1.60.1 / 70338 / 16001`. Captures use the actual
allowlisted build in `captureProfile`, so a 70338 refresh archives rather than
mixes active 70291 observations. The package retains the same collectors,
section shapes, and WOWSYNC v1 projection; unknown builds remain rejected.
Forever 70338 has not yet been run through `/wowsync` with this package, so its
live collector compatibility remains pending one real capture. No bank,
profession, or recipe collector was enabled by this change; those observations
remain absent/UNKNOWN exactly as before.

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

The source now also captures `C_Item.GetItemStatDelta(candidateItemString, equippedItemString)` for distinct carried/equipped exact-item pairs, bounded to 256 pairs. It records the ordered inputs, API errors, and bounded raw result table. The Forever 1.60.1 API reference lists this API, but its result shape, direction, and agreement with GetItemStats are not yet live-validated. The field is raw comparison evidence only and does not state that the candidate is an upgrade.

The allocation implementation also records bounded raw results from `C_Item.GetItemSpecInfo(exactItemString)`, `C_SpecializationInfo.GetSpecialization()`, and, when a bounded positive index is returned, `C_SpecializationInfo.GetSpecializationInfo(index)`. These calls do not select or change a specialization. Warcraft Wiki documents these APIs for Forever 1.60.1; the array/tuple interpretation and usefulness of item specialization tags have not yet been observed in a Forever capture. Dashboard suitability therefore remains UNKNOWN unless a fresh, complete exact-item tag list and a fresh active-specialization tuple agree. Even a match is only a suitability hint, never proof of talent build, equipability, or upgrade value.

For the allocation screen, the collector additionally records raw `C_PlayerInfo.CanUseItem(itemID)` results for each exact observed itemString and optional `C_Item.IsItemBindToAccount(itemString)` / `C_Item.IsItemBindToAccountUntilEquip(itemString)` calls. `CanUseItem` receives only the base item ID: the associated exact itemString is context for the observed variant, not proof that the boolean distinguishes that variant. The result is current-player scoped and cannot be reused for another character. Binding output includes the raw GetItemInfo return at index 14 (`bindType`) and the API tuples with exact input identities; `semanticInterpretation` is always `UNKNOWN_UNVALIDATED` on this build until its Forever-specific behavior is observed. These calls are bounded to the already observed item list, read-only, and do not affect candidate completeness or launch protected actions.

GetItemStats table keys and numeric values remain raw client output. They are not translated into effective stats, primary/secondary stat meaning, weapon upgrades, build suitability, or an upgrade score. IsEquippableItem returned true for ammunition in the capture, so it must not be used alone as an equipment eligibility rule. The capture validates API response shape and exact-variant handling, not all Forever gameplay semantics.

## Trainer window

Trainer service APIs are called only if a supported trainer frame's `IsShown()` returns true at capture start. Service count is bounded at 200 and ability requirement probes at 20 indexes per service. Each call stores the API, input/context, provenance, return count, every tuple position including nil, and errors. Service ordering follows the runtime index. The service requirement count API is recorded as present/missing but not called because its return semantics were not validated. A nil terminator is preserved; reaching a safety limit is labeled partial. A trainer close during enumeration stops further calls and marks the attempted observation partial. No service purchase, learning, selection, or frame-opening API is called. On the live Hallo capture, no supported trainer frame was available; trainer services were `NOT_OBSERVED_FRAME_UNAVAILABLE`, and no trainer-service API contract was claimed validated.

Raw tuple strings such as `unavailable` remain uninterpreted. They do not imply learnability, eligibility, cost meaning, or complete prerequisites. When a supported frame exists and is hidden, the current capture says `NOT_OBSERVED_WINDOW_CLOSED`. If no supported frame object is available, it says `NOT_OBSERVED_FRAME_UNAVAILABLE`; this does not assert that the frame was positively observed closed. Both states retain any prior sample explicitly nested as `lastObserved` with its own timestamp and context.

## Export compatibility and integration

The strict WOWSYNC v1 text remains unchanged so the currently deployed Dashboard parser continues accepting it. This evidence section is persisted as structured SavedVariables and can be inspected using WoWSyncDB. A separate Dashboard parser/import change is required before the evidence becomes queryable by Dashboard workflows; this addon change does not modify or deploy Dashboard.

## Evidence boundaries

The capture does not establish exact transferability, character-specific equipability, class allow/deny restrictions, profession equip restrictions, binding semantics beyond the directly observed carried-stack facet, effective equipment stats, location, currency, playtime, XP, professions, known spells, bank contents, trainer learnability, or complete talent/build interpretation. GetItemStats remains uninterpreted raw evidence. Synthetic tests exercise collector behavior only; live validation is limited to the capture fields listed above. The newly added item-specialization and active-specialization calls are not live-validated by the 2026-10-09 capture and must remain UNKNOWN until the consolidated capture validates their raw shapes.
