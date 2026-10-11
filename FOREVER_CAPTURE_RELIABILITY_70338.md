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
| Equipment slots | Equipment collector + shared version-scoped labels | Numeric IDs retained. Empty means the slot-presence API explicitly said empty; it is not a recommendation that the slot needs gear. |
| Item identity/name/level | `C_Item` exact link/ID calls | Exact link is preserved when available. ID-only fallback has no variant. Async item cache is retried on item-data event. Item names for 4237/4239/4362 require a new capture to verify. |
| Item stats/durability/enchant | Existing/raw item evidence as applicable | Raw stats are not interpreted as effective stats or upgrade decisions. Unsupported or absent values remain unknown. |
| Bags and free slots | Existing Forever `C_Container` reader | Section status and exact links/quantities retained; names can be unresolved during cache miss. |
| Character bank | `C_Bank.CanViewBank`, `FetchPurchasedBankTabIDs`, `C_Container` while open | Only tabs exposed in that visit; empty requires a complete slot scan. Not observed outside visit. |
| Professions and skills | `GetProfessions` + `GetProfessionInfo` | Learned entries/current/max skill only. No conclusion that an absent/unavailable section means no professions. |
| Spells/profession abilities | `C_SpellBook` skill lines plus profession indices | Visible spellbook observations; no ranks, trainer learnability, or complete recipe list inferred. |
| Trainer services | Visible trainer evidence collector | Raw, bounded API tuples only. Adapter disabled until live contract is verified; no learnability claim. |
| Faction, class, proficiency, item eligibility | Raw character/item evidence | Capture does not turn `CanUseItem`, item category, or missing data into full equip eligibility. |

## Exact item-name diagnosis

For equipped IDs 4237, 4239, and 4362, the collector already had the numeric ID and current item level, but only requested `GetItemInfo` when `GetItemLink` supplied a link. A link cache miss therefore prevented a name request even when the item ID was known. The parser and Dashboard did not invent the `item:<id>, ilvl <n>` fallback; that fallback was presentation for an unresolved source name. The new path requests item info using the observed ID and retries once a client item-data event arrives. It preserves the ID, preserves an exact link only when actually observed, labels name source, and renders unresolved state clearly. A new live capture is needed to establish whether those three names resolve on build 70338.

## Validation and limits

The Lua fixture suite, release/package guards, and deployment fixtures exercise both allowed builds, unknown-build rejection, field missing/error behavior, time-played events, item-ID fallback, delayed item-data retry, profession and spell rows, and unknown trainer semantics. Fixtures are not live-client proof. Do not deploy this candidate from this checkpoint. The next real capture must verify basic fields, the three item names, a bank visit, profession/spell capture, and trainer-window raw return shapes in one session.
