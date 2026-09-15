# Retail compatibility audit and validation

Status: audit and automated implementation complete; live acceptance pending. This is a
compatibility/package target, not a separate exporter or a public support claim.

## Baseline and API source

Audited before implementation on 2026-09-13. `retail-compat` starts at `c438566`
on the validated Classic Era branch, including multi-category trainer persistence.
TBC remains interface 20506; Era remains 11509. Baseline: 141 assertions including
20 legacy report comparisons, Lua 5.1 syntax, deterministic rendering, Classic
fixtures, and BankCleanup SHA-256 all pass; zero gameplay actions.

Retail source: Blizzard's extracted UI and generated API documentation, mirrored
in [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source/tree/4e3cbb8c5609e4bfc332c0aebbfa4d79731fab59),
live commit `4e3cbb8c5609e4bfc332c0aebbfa4d79731fab59`, `version.txt` =
`12.1.0.69814`. Target interface **120100** (12.1.0); installed Retail build is
12.1.0.69587. Interface is corroborated by installed current Retail addon TOCs
(including DejaCharacterStats), not copied from a previous expansion. Verify the
actual `GetBuildInfo()` interface in live acceptance. Blizzard's own shipped TOCs
mostly omit Interface or use 0 and cannot themselves supply this number.

All source paths below are relative to `Interface/AddOns/` at that pinned commit.

## Dependency assessment

| Area / existing dependencies | Retail finding and implementation decision |
| --- | --- |
| Character: UnitName, UnitClass, UnitLevel, UnitGUID, UnitFactionGroup, GetRealmName, GetMoney, UnitXP, UnitXPMax, GetBuildInfo | Shared player reads. Keep MoneyCopper and omit XP ratio at zero cap. Add client family and interface to exported metadata. GUID-keyed character storage remains unchanged. NPC identity can be unavailable; never infer trainer category from NPC name. |
| Location: GetRealZoneText, GetSubZoneText, C_Map.GetBestMapForUnit, GetPlayerMapPosition, vector GetXY | Shared (`MapDocumentation.lua`); map/position can be nil indoors or during transitions. Preserve available zone and unknown coordinates, never invent position. |
| Container counts/free/link/info and ContainerIDToInventoryID | Modern C_Container supported (`ContainerDocumentation.lua`). Info is a table, including hyperlink, itemID, stackCount, isLocked and isBound. Use modern API on Retail. Inventory mapping applies only to equipped carried bags, never bank tabs. |
| Carried ranges: NUM_BAG_SLOTS, NUM_BANKBAGSLOTS, BANK_CONTAINER | Classic arithmetic is invalid. `BagIndexConstantsDocumentation.lua`: backpack 0, normal bags 1–4, reagent bag 5, character tabs 6–11, account tabs 12–16. Use Enum.BagIndex for carried range and C_Bank purchased tab enumeration for banks. Profession bags are normal equipped bag slots; family is preserved. |
| Banking: GetNumBankSlots, classic main bank/reagent bank/bank bags | Current Retail uses character bank tabs. No separate legacy main/reagent bank or equipped bank bags in this target. `BankDocumentation.lua` and `Blizzard_UIPanels_Game/Mainline/BankFrame.lua`: C_Bank.CanViewBank, FetchNumPurchasedBankTabs, FetchPurchasedBankTabIDs and C_Container support character/account views. Capture character tabs; explicitly label account storage as supported but deferred for this initial character-state port. Do not read negative Classic container IDs or claim account bank is empty. |
| Bank freshness/events | BANKFRAME_OPENED/CLOSED and PLAYERBANKSLOTS_CHANGED remain; BANK_TABS_CHANGED and PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED are modern events. Classic PLAYERBANKBAGSLOTS_CHANGED may be absent (existing optional registration tolerates this). Viewability must gate capture even during an open bank frame. Failed/settling reads preserve previous observation and honest stale state. |
| Equipment: GetInventoryItemLink/ID/Texture, slots 1–19 | Shared; slot 18 is legacy ranged and unused in Retail. Keep canonical slots for compatibility. Profession equipment is outside these slots and excluded with documented coverage. Preserve the entire hyperlink item payload including bonus IDs, gems, enchants, crafted modifiers and upgrade identity, never just itemID. |
| GetItemInfo, GetItemStats, GetItemCount | Normalize to C_Item.GetItemInfo/GetItemStats/GetItemCount on Retail (`ItemDocumentation.lua`). Legacy globals cannot be assumed. C_Item.GetDetailedItemLevelInfo uses the full item reference for instance level. Metadata can return nothing; request item data by ID and retry on ITEM_DATA_LOAD_RESULT/GET_ITEM_INFO_RECEIVED. Never substitute a generic cached item link for missing instance identity. |
| Equipment tooltip/stat reader | Classic scans GameTooltip font strings to recover suffix stats. Retail can use C_Item.GetItemStats and C_TooltipInfo.GetInventoryItem without hidden tooltip scanning. Stats are an exposed subset, not a simulation of procs, buffs, crafted quality or upgrade-track labels. Full itemRef retains identity; separate upgrade-track parsing is deferred. Restricted/secret or unavailable data must remain partial, never coerced to zero. |
| Spellbook: GetNumSpellTabs/GetSpellTabInfo/GetSpellBookItemName/Info/GetSpellLink/BOOKTYPE_SPELL | Removed/replaced as documented in `Blizzard_Deprecated/11_0_0_SpellBookAPITransitionGuide.lua`. Use C_SpellBook skill lines and SpellBookItemInfo with Enum.SpellBookSpellBank.Player. Exclude future, off-spec and pet entries. Include known player spells/passives/racials and known flyout spells, deduplicate spell IDs. No invented rank; subName is not a Classic rank. Recipe catalogues remain excluded. |
| Professions: GetNumSkillLines/GetSkillLineInfo and ranked spell evidence | Classic skill/rank identification is unsuitable. `Blizzard_ProfessionsBook/Blizzard_ProfessionsBook.lua` uses GetProfessions/GetProfessionInfo (primary, archaeology, fishing, cooking). Preserve skillLine/name/current/max and optional skillLineName tier. C_TradeSkillUI.GetProfessionInfoBySkillLineID adds expansion/parent identity where exposed. Do not open professions or switch data sources to enumerate historical tiers; full expansion catalogue and specializations/knowledge are outside parity. |
| Trainer service tuple and level | Retail `Blizzard_TrainerUI/Mainline/Blizzard_TrainerUI.lua` reads name,status,texture,requiredLevel from GetTrainerServiceInfo. Classic reads name,rank,status,expanded plus GetTrainerServiceLevelReq. Normalize in Compat for both canonical and legacy readers. Retail rank is absent. |
| Trainer costs, skill/ability requirements and lifecycle | GetNumTrainerServices, GetTrainerServiceCost, GetTrainerServiceSkillReq, GetTrainerServiceNumAbilityReq/AbilityReq, GetTrainerServiceTypeFilter, IsTradeskillTrainer and ClassTrainerFrame remain in Retail UI. GetTrainerServiceSkillLine supplies profession evidence. Preserve all categories, filters, lifecycle and zero-service partial/UNKNOWN handling. IsTalentTrainer/legacy level API are optional. Never infer CLASS or WEAPON merely from nonempty Retail services or requirements. Automatic class learning is represented by known spells; manufacture no training rows. |
| Scheduler/UI: CreateFrame, RegisterEvent, SetScript, GetTime, GetServerTime/time, date, UIParent, UISpecialFrames, SlashCmdList, font/texture/editbox/scroll/button methods, DEFAULT_CHAT_FRAME | Shared UI facilities; retain one UI and bounded event-coalesced retries. Event registration remains guarded. UI output changes only after explicit export completion, preserving copy stability. No protected action widgets added. |
| Inventory movement: GetCursorInfo, BAG_UPDATE/DELAYED, ITEM_LOCK_CHANGED, UNIT_INVENTORY_CHANGED, PLAYER_EQUIPMENT_CHANGED | Shared observation; locked/cursor/settling captures retry without any action. Add Retail bank/profession/spec observation events where needed. |
| Other events: login/world/logout, skill/spell/level/money/XP/zone/trainer/item events | Existing lifecycle remains; unsupported events guarded. PLAYER_SPECIALIZATION_CHANGED and TRADE_SKILL_DATA_SOURCE_CHANGED/LIST_UPDATE trigger observational refreshes. No trade-skill opening, filter mutation or recipe selection. |
| Legacy GearExport/BagsX/TrainerX, tooltip binding and optional TSM | Reuse existing report builders with Compat adapters for changed APIs/ranges/tuples. Retain Classic output byte comparisons. Retail BagsX character bank only; account quantities are not silently included. TSM remains optional and outside canonical WoWSync. Legacy tooltip binding is conservative when data is absent. |
| BankCleanup | SHA-256 `54cbbd5ea9f8ac6b0307a475b270220bd7ea190e2ec6755950df34f50b67a6ba`; byte-for-byte unchanged. Exclude file from Retail TOC/package, since its Classic transfer semantics do not apply. TBC/Era packages continue loading it. |

## Scope and schema decisions

One core, collectors, renderer, UI, SavedVariables model and `WOWSYNC v1` section
order. Optional client/interface, container storage category, bank coverage, and
profession identity/tier fields are additive. Existing canonical names stay intact.
Retail bank coverage explicitly identifies CHARACTER tabs, legacy reagent storage
as not applicable, and ACCOUNT storage as deferred. No combined account totals.

Warband bank is API-supported but intentionally deferred, not API-inaccessible.
Account currencies (C_CurrencyInfo), Great Vault (C_WeeklyRewards), crafting orders
(C_CraftingOrders), profession knowledge (C_ProfSpecs), talent loadouts (C_ClassTalents,
C_Traits), renown (C_MajorFactions), reputation (C_Reputation), weekly objectives
(quest/task APIs), and collections (mount/pet/toy/transmog APIs) are separate state
domains, not dependencies of the current model. No collectors or actions for these
systems are introduced. A future small opt-in currency view could be useful;
MoneyCopper continues to mean character gold only.

Future account state should own shared Warband storage and account balances once,
with independent observation time/access/coverage. Character views must reference
that state rather than duplicate it across alts or add it into character totals.
Preserve the documented account roster/metadata versus character identity,
location, equipment, bags, bank, professions, spells, trainers and freshness split.
No account export modes or migration to that architecture during this port.

## Packaging and live acceptance

Retail package uses `GearExport-Retail.toc` copied to `GearExport.toc` in the
installed GearExport folder; only the selected target TOC is shipped. TBC/Era source
TOCs remain intact. One repository can produce three game-version-specific files
for one CurseForge project; no public release is made before live validation.
Use shared README/LLM prompts and a future shared icon; artwork does not block this port.

An initial user-supplied live export confirms generation on 12.1.0 build 69814,
interface 120100 (Generated 1789344996). The full live smoke checklist is still
pending; initial evidence is recorded in `RETAIL_TEST_PLAN.md`. Automated fixtures cannot verify
actual client readiness, restricted values, UI taint or event ordering. The final
validation build will include exact install and smoke-test instructions.

The build and smoke matrix are now available in [RETAIL_TEST_PLAN.md](RETAIL_TEST_PLAN.md).
`node scripts/package.cjs Retail` produces the reviewable install folder.
Checkpoint test results: 141 existing assertions including 20 legacy comparisons,
1,264 Retail assertions, deterministic rendering, nine Lua 5.1 syntax checks,
all three TOCs, observer action scan and BankCleanup baseline hash pass. Retail
assertion counts include API argument/range checks repeated during event simulations.
Historical Era acceptance checkboxes are retained as recorded; the user reports
substantial in-game validation on that branch. This port does not claim a new
TBC/Era live regression session.

Final API review also includes profession-book ability slots from GetProfessionInfo's
numSpells/spellOffset tuple, read through C_SpellBook's Player bank just as Blizzard's
ProfessionsBook does. They can lie outside the class/spec skill-line ranges. These
abilities are included without accessing recipe catalogues. Container range and
required-capacity differences stay in Compat, not duplicated Classic arithmetic in
collectors. Account-bank mutation events are intentionally not subscribed because
that storage is outside the initial capture coverage.

## Pushed development checkpoints

| Commit | Checkpoint | Validation |
| --- | --- | --- |
| 36c82d1 | Audit and Retail TOC scaffold | 141 existing assertions; syntax/static/integrity passed |
| 1c573de | Compatibility adapters | 37 Retail + 141 existing assertions passed |
| 9eef1b1 | Shared collectors/renderer and legacy normalization | 462 Retail + 141 existing assertions passed |
| d3e94ea | Expanded Retail automated coverage | 1,229 Retail + 141 existing assertions; packaging/static checks passed |
| 63cbf12 | Installed manual validation build and reproducible packages | 1,254 Retail + 141 existing assertions; three package manifests and installed hashes passed |

Each checkpoint above was committed on `retail-compat` and pushed to origin without
force-push or history rewriting. Final regression/polish follows these checkpoints;
its hash is available in git history. Live smoke acceptance remains outstanding.
