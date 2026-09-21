# WoWSync v1 developer contract

## Client compatibility

The schema and canonical text export are shared by TBC Anniversary, Classic
Era and the Retail validation target. TBC loads through `GearExport.toc` with interface `20506`;
Classic Era loads through `GearExport-ClassicEra.toc` with interface `11509`.
Retail selects `GearExport-Retail.toc`, interface `120100`, packaged as the sole
`GearExport.toc`. Retail live acceptance remains pending.
`WoWSyncCompat.lua` provides only narrow API normalization. Character/build/interface
metadata in the `character` section identifies the active client.

Client content is not interchangeable: item and spell IDs, item-link variants,
trainer services, ranks, costs, and profession skills come from the active client.
The schema keeps those values in the same fields. Delayed item information and
partially populated trainer windows remain explicitly partial rather than being
filled with inferred values. The renderer does not read client APIs and therefore
produces the same deterministic format for every target.

WoWSync is loaded by GearExport after the legacy exporter and BankCleanup. It has
no required dependencies. BankCleanup does not consume WoWSync data or callbacks.
Retail excludes BankCleanup; its source and TBC/Era behavior are unchanged.

`WoWSyncDB` is declared by GearExport's TOC and saved in the same
`SavedVariables/GearExport.lua` file as `GearExportDB`. Writes update Lua memory
immediately; the client persists that memory on normal logout/reload. There is no
per-event disk writing. A copied export needs no reload.

## Structured state

Root: `schemaVersion=1`, `settings`, `characters[UnitGUID("player")]`.
Settings: `showButton` (defaults false), `buttonPosition` (optional).
Character: `identity`, `sections`, `visits`, `itemMetadata`, `latestExport` (at
most one text block).

Each section has `data`, `observedAt`, `changedAt`, `revision`, `completeness`,
`source`, `capture`, and optional `reason`. An unsuccessful read adds
`lastAttemptAt` and `lastAttemptError` without replacing the observation or its
timestamp. A successful replacement clears the last error. Epoch seconds are used
for persistence; session scheduling uses `GetTime()` only in memory.

- `character`: identity display fields, level, faction, moneyCopper, xp/xpMax,
  clientVersion/clientBuild/interface.
- `location`: zone, subzone, optional mapID and x/y in percent.
- `equipment`: `slots[1..19]`, occupied entries only; item identity and structured
  `stats={ {name,value}, ... }` from the shared GearExport interpretation.
- `bags`, `bank`: ordered `containers`, each with id, capacity, free, family,
  optional equipped bag identity, and sparse `slots[slot]` item records. Items
  retain itemID, full itemString, name/quality/levels/vendorCopper when available,
  stack count, and optional bound flag. No economic filtering. Bank also has
  purchasedBagSlots and a copy of the visit context associated with that snapshot.
  `bank` is always character-owned; Retail Warband storage is not folded into it.
- `professions`: entries with name/rank/maxRank and identification method.
  Visible legacy skill lines are used without expanding/collapsing the UI.
- `spells`: player spellbook entries with spellID/name/rank/kind and scope text.
  This is not a crafting-recipe database or pet spellbook.
- `trainer`: `snapshots[category]`, where each observed category retains its visit,
  name, trainerType, services, filters, collapsed, moneyAtVisit, coverage,
  observedAt, completeness, and optional reason. Service fields: name/rank/status/
  cost/requiredLevel, optional skillRequirement and abilityRequirements. Categories
  are derived from trainer flags and observed skill requirements (`PROF_<SKILL>`,
  `WEAPON`, `CLASS`, `TRADE`, or `UNKNOWN`); NPC names are display context only.
  The current adapter cannot reliably obtain trainer spell IDs; indices and names
  are never used to invent them.
- `itemMetadata`: a separate cache of static base-item facets encountered while
  collecting the current character's equipment or storage. It is not nested into
  an item observation and never affects a section's observation/revision/hash.

`visits.bank` records the most recent bank visit. `visits.trainers[category]` records
the latest visit for each observed trainer category, including openedAt, closedAt,
NPC name/GUID, location, session token, and optional unreconciled marker. A failed
new visit does not destroy an older valid category snapshot; the export lists each
category independently. Legacy single-trainer data is normalized to `UNKNOWN` when
its category cannot be recovered.

Unavailable data is absent, never substituted with zero. A partial snapshot may
contain reliable quantities with pending names. No historical event list is kept.
Transient locks/cursor activity and inconsistent occupied/free counts reject a
container scan instead of publishing a transient inventory state.

### Additive Retail fields and declared coverage

The schema remains v1: its eight established sections retain their order. Retail
may add `[ACCOUNT BANK]` immediately after `[BANK]` as a separately scoped,
additive section.
Older snapshots without these optional fields render as before:

- `character.clientFamily`: `Retail`, rendered as ClientFamily alongside Interface.
- `containers[].storage`: CARRIED, REAGENT_BAG or CHARACTER, rendered as
  `ContainerStorage <id>`. Bank only enumerates purchased character tabs; it adds
  `purchasedTabs` and `coverage`. Negative Classic bank IDs,
  separate reagent bank and equipped bank bags do not apply to this Retail target.
- Item identity remains the complete `itemString`; C_Item supplies modern metadata
  and instance item level. Missing links stay partial even if generic item data is
  cached. Exposed item stats are not a full simulation of buffs/procs/effects.
- `professions.entries[]` optionally adds `skillLineID`, `tier`, `expansion`,
  `category` (PRIMARY/SECONDARY). Retail rows append these columns after the
  existing profession/skill/maxSkill columns. Coverage is tracked professions and
  the exposed tier, not every historical tier, recipe, specialization or knowledge.
- Retail player/profession spellbook rows have no rank (`-`); subName is not interpreted as
  rank. Future/off-spec/pet entries are excluded; known flyouts are expanded and IDs
  deduplicated. Spell coverage text states this explicitly.
- Retail trainer category uses service skill-line API evidence, not NPC name or
  an assumption that any skill requirement means weapon training. Unknown remains
  a separate snapshot and never overwrites named profession/class categories.

Retail also emits an additive `[ACCOUNT BANK]` section when the Account bank is
viewable. It is stored once at `WoWSyncDB.account.sections.bank`, not under any
GUID, and rendered with `Scope: ACCOUNT_WARBAND`. It uses only the returned
`C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Account)` IDs and has independent
freshness/UNKNOWN/LAST_SEEN behavior. It is never aggregated into a character's
bank.

Retail may also emit `[GUILD BANK]`, separately scoped as `GUILD`. It is keyed
in SavedVariables by the observed `C_Club.GetGuildClubId()` value, with guild name
as display metadata only; it is never character- or account-owned storage. A tab
is OBSERVED only after it was reported `canView=true`, was the sole outstanding
`QueryGuildBankTab` request, and then received `GUILDBANKBAGSLOTS_CHANGED`.
An all-nil scan before that response is UNKNOWN; an all-nil scan after it is an
observed empty permitted tab. `canView=false` is rendered `INACCESSIBLE`, never
empty. A Guild Bank snapshot is complete only for all tabs currently permitted to
the observing character; inaccessible guild-owned tabs remain outside its observed
contents. Failed/closed/timed-out captures are partial and do not replace a prior
complete guild observation.

### Additive item metadata block

`[ITEM METADATA]` is appended after the established observation sections without
changing `schemaVersion` or the meaning of any item row. It has exactly one
tab-separated row per base item ID referenced by equipment, bags, Character Bank,
Warband Bank, or Guild Bank in the exported snapshot:

```text
baseItemID  classID  subclassID  bindType  expansionID  isCraftingReagent
```

Rows sort by numeric `baseItemID`. `?` means that facet was not supplied by the
client; an observed `isCraftingReagent=false` renders `no`, while true renders
`yes`. `classID` and `subclassID` may be supplied by `GetItemInfoInstant` while
full item data is unavailable. `bindType`, `expansionID`, and
`isCraftingReagent` require the full item-info tuple and remain `?` until it is
available. The client-returned `expansionID` is a raw numeric fact only: WoWSync
does not map it to an expansion name, reinterpret sentinel-like values, or infer
it from an item ID/name/class.

The export envelope's character client version/build/family establishes the
game-version context for the base ID. Consumers combining exports from different
products must key metadata by that context plus `baseItemID`; WoWSync does not
claim that Retail metadata applies to Classic Era, TBC Anniversary, or Forever.
Readers that do not recognize this additive section can skip it. Existing item
rows, ownership scopes, quantities, binding observations, and storage hashes are
unchanged.
On validated Retail clients, capture is started/stopped from `GuildBankFrame`
OnShow/OnHide; `GUILDBANKFRAME_OPENED/CLOSED` are supplementary signals and cannot
be the sole lifecycle source. Closed or unavailable banks preserve a previous
complete observation as LAST_SEEN rather than claiming current empty storage.

## Consumer API

`WoWSync.apiVersion == 1`:

- `RequestSync()` schedules all accessible sections. Returns success/error.
- `GetSnapshot()` returns a detached character snapshot with schemaVersion,
  generatedAt, access flags, and pending section flags.
- `GetSection(key)` returns a detached section observation.
- `RenderSection(key, snapshot)` renders one section without live APIs or mutation.
- `Render(snapshot[, orderedSectionKeys])` renders a framed export, all sections
  by default. The optional selection is the extension point for future focused UI.
- `Export(callback)` refreshes accessible state and calls back once with the text
  after settling or a bounded three-second wait. Pending/partial data stays labeled.

Consumers should use these functions, not mutate `WoWSyncDB` or scheduler internals.
Section keys in default order: character, location, equipment, bags, bank,
professions, spells, trainer, itemMetadata. Retail additionally inserts
accountBank and guildBank after bank. Future schema versions must be explicitly
migrated; an unknown version is preserved and synchronization refuses to overwrite it.

## Text format

`WOWSYNC v1`, generation time and format legend, independently renderable sections,
then `[END]`. Tables are tab-separated with explicit headers. `?` means unknown;
`EMPTY` is reserved for observed empty slots/containers. Backslash, tab, CR, and LF
are escaped in values. Times are Unix seconds and money is integer copper.

Section status includes observation time and completeness. Closed bank/trainer
snapshots are LAST_SEEN; filters, failed refreshes, and unresolved closure are
explicit. Trainer costs/status/requirements describe the observation, not a promise
that the character can train the ability now.

Inventory output aggregates matching item references/binding/metadata, sorted by
numeric item ID then identity. Physical stacks remain in the schema. Equipment uses
numeric slot order; professions/spells/trainer collectors normalize entry order.
Rendering never reads clocks/APIs, changes state, requests data, or queries TSM.

The UI freezes each displayed block until the user presses SYNC again. Background
capture does not update legacy Markdown slots or the previously generated block.

## Account state versus character state

The existing root already provides the required conceptual separation; no v1 schema
migration is needed. ACCOUNT STATE is the schema version, shared settings, and known
character index derived from `characters[guid].identity`. CHARACTER STATE is each
GUID's identity, location, bags, bank, equipment, professions, spells, trainer,
visits, and section timestamps. Future account-level metadata belongs at the root,
not copied into each character. Avoid storing a second mutable character roster
when it can be derived from the same records.

The database represents characters observed in this client's SavedVariables scope,
not proof of every character on a Battle.net account. Never key by display name
alone. GUID is authoritative within that scope; realm/name remain display context.
An external reader combining installations/accounts must add an explicit source
namespace rather than silently merging matching names or GUIDs.

| Export concept | Value and cost | Recommendation |
| --- | --- | --- |
| Current character only | Complete current handoff with predictable size; no unrelated alt sections. | Keep `/wowsync` as the v1 default and canonical machine/LLM handoff. |
| Current character plus compact known-alt summaries | Useful for shared materials, profession coverage, and planning; adds one bounded row per selected alt. | Eventual opt-in summary view, not an automatic expansion of every normal export. |
| Full account snapshots | Thorough cross-character analysis; can become very large and contains observations from different times. | Explicit `/wowsync account` mode later, with summary by default and an explicit full option. |
| Account/economy-focused view | Combines money, professions, bags/bank, binding and freshness without repeating all gear/spells. | Eventual focused account projection; market inputs remain separately sourced and optional. |

Recommended eventual UX: leave `/wowsync` current-only; use explicit `account` for
compact summaries and an explicit `account full` for every selected snapshot.
An `economy` view should default to the current character, with a clearly requested
account scope. A future summary row can contain identity, level/class, profession
ranks, money, and separate bag/bank observation times and coverage. Unknown sections
remain unknown. Large rosters need an explicit selection/count rather than silent
truncation. These command forms are proposals, not registered v1 commands.

Rendering is a projection over structured state. Current `RenderSection(key,
snapshot)` and `Render(snapshot, orderedSectionKeys)` already support future `gear`,
`trainer`, and other focused views. A higher-level account renderer can compose the
same functions over detached character snapshots, with an explicit scope/identity
envelope. It must not parse the canonical export or call live APIs for logged-out
characters. Collectors and stored character sections do not need redesign.

Future account acceptance criteria:

- Keep default output independent of the size of the known-alt roster.
- Sort character records by stable realm/name/GUID ordering with complete tie-breaks;
  retain the existing stable section/item ordering within each character.
- Identify every subtotal by character and location; never merge item variants or
  binding states. Aggregated presentation must not destroy physical-stack records.
- A full/account export's generation time must not refresh alt observation times.
  Stored access/session flags cannot imply that an alt's bank or trainer is open.
- Report unknown, partial, and stale contributions in account totals. Do not imply
  all gold/items are currently accessible or transferable across characters/realms.
- Do not infer mail/AH holdings from a missing item or a bag/bank delta. A transfer
  seen at different times by two characters can otherwise be double-counted; label
  account totals as asynchronous observations until fresh evidence reconciles them.
- Make text scope explicit (current, selected characters, all known) and preserve
  each record's identity, section coverage, and timestamp.

## Read-only external companion — future design only

```text
WoW -> WoWSync addon -> SavedVariables -> read-only companion
    -> deterministic change/trigger engine -> optional LLM reasoning -> notification
```

No companion, file watcher, notifications, or LLM calls are implemented in this addon.
The future input is structured `WoWSyncDB`, not screenshots or scraped UI text.
Parse SavedVariables as a restricted data format; never execute arbitrary Lua from
the input file. Validate schema/version/types, reject incomplete file writes, and
retain the last valid read until a stable file is available.

The companion would only observe file snapshots flushed by WoW. SYNC updates memory;
normal logout or explicit reload makes it available on disk. File modification time
is not a substitute for per-section `observedAt`. There is no claim of continuous
real-time synchronization, and the companion must not trigger reloads automatically.

Changes should be computed deterministically per source, character GUID, and section
from structured content and revision/freshness metadata. Deduplicate unchanged
observations and repeated notifications; distinguish a failed/partial read from a
real inventory loss. Session-local `capture`/visit tokens are not global sequence
numbers. Rule examples could identify a newly reached training level or relevant
material threshold, but uncertain snapshots should not produce confident triggers.
The LLM, if enabled, reasons over only the necessary sections after deterministic
rules select an event. User-selected data scope and explicit opt-in govern external
LLM transmission; the only outcome is an advisory notification.

The companion must never read WoW process memory, inject code, simulate keyboard or
mouse input, click UI elements, issue gameplay commands, or automatically move,
buy, train, vendor, mail, auction, equip, cast, craft, or clean up items. It must not
write commands into SavedVariables or build an execution channel back into WoW.
All gameplay decisions and actions remain explicit user actions.

## Equipment readiness review

The inspected 2.5.6 build 69546 snapshot contains names and itemRefs for the occupied
equipment slots while the section is partial. The stored schema does not identify
which slot failed the aggregate readiness check, so it cannot prove the original
cause was item-cache timing. The existing code also queried `NumLines()` after
`Hide()`. The final polish captures readiness before that cleanup; the interpreted
stats and legacy report strings are unchanged. A regression fixture that resets
tooltip lines on Hide confirms that a successfully scanned tooltip stays complete.

The 2.5.6 [Classic tooltip source](https://github.com/Gethe/wow-ui-source/blob/2.5.6/Interface/AddOns/Blizzard_GameTooltip/Classic/GameTooltip.lua)
shows a distinct hide/reset lifecycle; it does not prove a particular slot's timing
or that every Hide clears lines. The pre-hide check avoids relying on that lifecycle.
Genuinely unavailable item names/links or empty/failed equipped tooltips still yield
partial coverage, with bounded retries and later sync/item-info refreshes. Existing
random-property tooltip interpretation is retained. No Retail API replacement,
permanent polling, fabricated stats, or verbose per-item diagnostics were added.
## Character playtime (additive WOWSYNC v1 fields)

`[CHARACTER]` always renders `PlayedSeconds` and `LevelPlayedSeconds` after
`MoneyCopper`. SavedVariables uses numeric `playedSeconds` and
`levelPlayedSeconds` in `sections.character.data`. Values are raw nonnegative
integer seconds from `TIME_PLAYED_MSG`: total character time and time at the
current level, respectively. Zero is known; unavailable values are absent in
SavedVariables and render as `?`, independently for each field. Existing field
names, meanings and section ordering are unchanged.

Login/world entry and explicit SYNC request fresh server observations. Export
waits up to its existing three-second deadline; missing APIs, failed requests,
missing responses and invalid/restricted values remain unknown. A response
arriving later updates the stored snapshot without changing an already displayed
export. Values are last received observations, never estimates advanced by a
local clock. A new request clears the session observation, and a level change
invalidates previous level time and requests another observation. Persisted
values survive reload as part of the snapshot, but are not reused as fresh
session observations. No duration formatting is stored.

See [the cross-client API audit](PLAYTIME_API_AUDIT.md) for source evidence and
live validation limitations.
