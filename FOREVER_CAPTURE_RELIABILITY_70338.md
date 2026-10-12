# Forever capture reliability audit — 2026-10-10

## Scope and evidence

This checkpoint audits Forever 1.60.1 builds 70291 and 70338, interface 16001. Build acceptance remains an explicit allowlist; this change does not admit other builds. API names and call contracts below were checked against the version-matched Gethe UI-source Forever branch for 70338 and its generated API declarations (the declaration tree is unchanged from the 70291 source revision). This establishes documented API support, not that every live return value was observed after these changes. Real prior observations remain the source for the earlier 70291 live claims in `FOREVER_EVIDENCE_70291.md`.

## Changes

- Restored the existing location collector after the build-scoped collector table replacement had accidentally dropped it.
- Forever character output now includes race, faction, money in copper, current/max XP, and same-GUID playtime values when observed. `RequestTimePlayed()` is requested through the asynchronous client contract; total and level time remain absent until `TIME_PLAYED_MSG` is received for the current GUID. No timeout or API failure is converted to zero.
- The existing zone/subzone collector is again in the Forever section set. Location remains subject to the APIs returning a usable value.
- Equipment keeps numeric inventory slot IDs and exports presentation labels for the 19 documented Forever equipment slots.
- Equipment-name lookup now uses the exact link when available and falls back to an observed item ID if the link has not hydrated. A missing cache value triggers one bounded `RequestLoadItemDataByID` request per ID; item-data events clear that request and refresh equipment/bag/bank observations. No variant string is synthesized from the base ID.
- Forever bank contents are collected only while the character bank is open and viewable through `C_Bank`; observed tab IDs, slot capacity, empty slots, item IDs/links, counts, binding facet, and section completeness are retained. Account/Warband storage is explicitly excluded. A closed or inaccessible bank remains unknown/last-seen, never empty.
- Learned profession name/current skill/max skill is collected via the documented `GetProfessions` / `GetProfessionInfo` tuple. Profession spellbook tabs are included through the indices returned by `GetProfessions`. Spell rows do not claim ranks that the source does not provide.
- Trainer services are not interpreted by the legacy tuple adapter: its file is not loaded by the Forever TOC, and the exact data is retained only as bounded raw evidence when a supported trainer window is open. Learnability, rank, cost meaning, spell identity, and complete requirements remain unknown.
- Forever's own renderer emits race, named equipment slots, and explicit missing/unknown character values within the existing WOWSYNC v1 format.

## Field coverage after code changes

| Area | Capture path | State / limitation |
|---|---|---|
| Name, surname, realm, race, class, level | Forever character collector; v1 renderer/parser | API-backed; surname support pre-existed. Race now emits on allowlisted Forever profiles. Live confirmation of newly added fields is pending. |
| Faction | `UnitFactionGroup("player")` | Captured when returned; otherwise absent/UNKNOWN. |
| XP | `UnitXP("player")`, `UnitXPMax("player")` | Captured when returned; absent remains unknown. |
| Money | `GetMoney()` copper | Captured with numeric precision; absent remains unknown, observed 0 remains 0. |
| Total and level playtime | `RequestTimePlayed()` then `TIME_PLAYED_MSG` | Asynchronous and GUID-scoped; no response means unknown. API call and event need consolidated live confirmation on 70338. |
| Zone/subzone | Existing `GetRealZoneText` / subzone collector | Collector is restored; field stays unknown if API returns no value. |
| Hearthstone/home bind location | No exact verified capture API or collector established in this pass | Not collected; remains UNKNOWN. Do not infer from Hearthstone item, zone, or inn visit. |
| Equipment slots | Equipment collector + shared version-scoped labels | Numeric IDs retained. Empty means the slot-presence API explicitly said empty; it is not a recommendation that the slot needs gear. |
| Item identity/name/level | `C_Item` exact link/ID calls | Exact link is preserved when available. ID-only fallback has no variant. Async item cache is retried on item-data event. Item names for 4237/4239/4362 require a new capture to verify. |
| Item stats/durability/enchant | Existing/raw item evidence as applicable | Raw stats are not interpreted as effective stats or upgrade decisions. Unsupported or absent values remain unknown. |
| Durability/enchantments | No complete, verified Forever equipment-slot capture added | Not collected as authoritative fields; absent remains UNKNOWN. Exact item links alone do not establish current durability/enchant semantics. |
| Bags and free slots | Existing Forever `C_Container` reader | Section status and exact links/quantities retained; names can be unresolved during cache miss. |
| Binding and transfer traits | Existing carried-item binding observations plus raw item API evidence; bank collector records `isBound` when returned | Preserve raw boolean/bindType/API result and source. Bind semantics and transfer route remain UNKNOWN; no general transferability conclusion. |
| Character bank | `C_Bank.CanViewBank`, `FetchPurchasedBankTabIDs`, `C_Container` while open | Only tabs exposed in that visit; empty requires a complete slot scan. Not observed outside visit. |
| Professions and skills | `GetProfessions` + `GetProfessionInfo` | Learned entries/current/max skill only. No conclusion that an absent/unavailable section means no professions. |
| Spells/profession abilities | `C_SpellBook` skill lines plus profession indices | Visible spellbook observations; no ranks, trainer learnability, or complete recipe list inferred. |
| Learned recipes and outputs | Forever profession-panel collector; recipe enumeration, learned-state check, schematic, output item APIs, and bounded requirement calls | Positively learned recipe rows can carry observed schematic/reagent and output-item API evidence. Candidate coverage remains partial/UNKNOWN. This does not establish smelting conversion, a minimum skill requirement, full eligibility, or an upgrade. |
| Trainer services | Visible trainer evidence collector | Raw, bounded API tuples only. Adapter disabled until live contract is verified; no learnability claim. |
| Faction, class, proficiency, item eligibility | Raw character/item evidence | Capture does not turn `CanUseItem`, item category, or missing data into full equip eligibility. |

## Exact item-name diagnosis

For equipped IDs 4237, 4239, and 4362, the collector already had the numeric ID and current item level, but only requested `GetItemInfo` when `GetItemLink` supplied a link. A link cache miss therefore prevented a name request even when the item ID was known. The parser and Dashboard did not invent the `item:<id>, ilvl <n>` fallback; that fallback was presentation for an unresolved source name. The new path requests item info using the observed ID and retries once a client item-data event arrives. It preserves the ID, preserves an exact link only when actually observed, labels name source, and renders unresolved state clearly. A new live capture is needed to establish whether those three names resolve on build 70338.

## Validation and limits

The Lua fixture suite, release/package guards, and deployment fixtures exercise both allowed builds, unknown-build rejection, field missing/error behavior, time-played events, item-ID fallback, delayed item-data retry, profession and spell rows, and unknown trainer semantics. Fixtures are not live-client proof. Do not deploy this candidate from this checkpoint. The next real capture must verify basic fields, the three item names, a bank visit, profession/spell capture, and trainer-window raw return shapes in one session.

## Forever learned-recipe output evidence (candidate; not live-validated)

The Forever package now loads `WoWSyncForeverRecipes.lua`. Recipe observations are captured only while the player's profession window is open and the panel can be matched to a learned profession. A recipe receives candidate-output evidence only when its learned state is positively observed true. The collector does not change filters, start crafting, or infer a complete recipe catalogue.

Each positively learned recipe may include an additive `outputItemEvidence` object under the existing structured `professionRecipes` SavedVariables section:

- `itemID`: exact output item ID returned by the recipe schematic.
- `itemReferenceKind`: `MINIMAL_ID_REFERENCE_NO_VARIANT`. Item information and stats are queried using the observed numeric output ID; this is not an item instance and does not create an `itemString`.
- `itemInfo` / `itemInfoInstant`: raw API call state and only the tuple fields actually returned, including name, quality, item level, required level, class/subclass, and equip location when present.
- `itemStats`: raw returned stat keys and numeric values. No stat valuation or upgrade score is produced.
- `isEquippableItem` and `canUseItem`: raw player-scoped API results; neither is promoted to complete destination-character eligibility.
- `cacheState`, request call state/result, and any later load-event result: separate cache/API evidence. A successful load event does not imply metadata or stats became available.
- API names and observation timestamps: stored with the corresponding evidence.

The optional `requirements` object preserves the exact `GetRecipeRequirements` values (`name`, `met`, and numeric `type`) and its own timestamp. It does not treat recipe difficulty, maximum trivial skill, or reagent-slot metadata as a minimum profession skill. Unreturned or unavailable requirement fields stay UNKNOWN.

Collection is bounded: at most 128 requirement queries and 128 distinct output-item evidence rows per pass, with at most 32 requirement rows copied from any one API result and at most 32 item-data load requests per addon login session (one request attempt per item per session). Rows outside a bound remain partial/unresolved. Load events can schedule one normal collector refresh while the profession panel remains open; there is no polling loop or blocking wait.

The only change to the export contract is this additive structured SavedVariables content in the Forever `professionRecipes` section. The legacy `WOWSYNC v1` text export is unchanged. Existing consumers that ignore unknown structured fields remain compatible, but a downstream importer must explicitly project these nested fields before they are available to Dashboard/REST/MCP assessments. No Dashboard, database schema, or non-Forever package is changed here.

The bag collector now falls back from an absent/unusable `GetContainerItemInfo().hyperlink` to the item's slot link from `C_Container.GetContainerItemLink(bag, slot)`, validating that the link item ID matches the independently observed slot ID. It never synthesizes an exact variant from an ID. Contradictory non-empty links and unresolved identity fail the scan; existing stale/partial-section behavior is retained so a failed scan cannot become an empty bag.

All new collector behavior is automated-tested with fixtures only. The candidate still requires one live build-70338 capture to validate recipe-window events, cache request/load behavior, output metadata/stat returns, requirement return shapes, and the bag link fallback against the actual client.

## Forever 70338 bag-link conflict follow-up (automated candidate)

Rordin's post-install live capture at generation `1791807982` reported bag 0,
slot 6 with `GetContainerItemInfo().itemID=10421` and a non-empty embedded
hyperlink that failed item-ID validation. The old collector returned at that
point and explicitly recorded that `C_Container.GetContainerItemLink` was not
used. This proves a collector control-flow defect: a second available source
was skipped. It does not establish whether the client's embedded value was
malformed, stale, or genuinely identified a different item; the original raw
link was not captured.

The follow-up evaluates the slot-link API independently whenever the embedded
link is absent, malformed, unreadable, or mismatched. Each link is parsed
without trusting the expected ID first. An exact link is accepted only when
its parsed base item ID matches the same-slot `itemID`; its actual item-string
variant is preserved without synthesis. If the fallback matches after an
unusable but unparseable embedded value, the item records bounded
`identityDiagnostics` (states and parsed IDs, never raw links) and the section
is marked partial. If both sources provide parseable but different IDs, the
slot is rejected even when one source matches the slot's reported ID; the
conflict is recorded in the bounded `lastAttemptError` with bag/slot, reported
ID, both parsed IDs, API availability/state, and rejection reason. Nil, API
error, malformed, and mismatched outcomes remain distinct.

The bag snapshot contract does not support trustworthy current rows alongside
unresolved slots: it represents one complete container scan. Therefore an
unresolved or contradictory slot keeps the existing all-or-stale behavior.
Previous contents remain LAST_SEEN and the failed scan cannot publish an
empty or complete inventory. Automated fixtures cover embedded success,
malformed embedded plus valid fallback, mismatch conflict, missing and nil
fallbacks, exact variant retention, partial recovered evidence, and stale
failure. This follow-up is not live-validated; a new controlled Forever
capture is required before claiming the real slot conflict is resolved.
