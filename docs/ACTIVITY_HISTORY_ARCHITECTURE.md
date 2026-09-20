# WoWSync Activity History — Retail Architecture

## Executive Summary

WoWSync snapshots answer **what is true now**. Activity History will answer
**what the Retail client directly observed happening**, without turning a later
state change into an asserted cause.

The selected architecture is a bounded, append-only journal of normalized
Retail **OBSERVED** events and lifecycle records, transported separately from
the unchanged WOWSYNC v1 snapshot export. The Dashboard persists those events
idempotently, then creates deterministic, provenance-linked session and range
projections at read time. Snapshots and their existing diffs remain a separate
**DERIVED state-transition** history; they never become evidence of activity.

Retail is the only Phase 1 collector target. Client adapters later emit the
same normalized evidence envelope only for facts their client can directly
support. Unsupported client capability is UNKNOWN, never backfilled from a
different client's API.

## Current Architecture Relevant to Activity

The addon stores `WoWSyncDB` per player GUID with current sections, visit
context, section timestamps/revisions, and one latest export. `WoWSyncCore.lua`
debounces many Blizzard events into refreshed state collectors; it deliberately
does not retain event history. Its collectors are client-specific where needed,
and its renderer is pure over a detached snapshot.

The Dashboard is a separate repository and currently receives manual WOWSYNC
v1 text exports. Its SQLite store has append-only `snapshots` plus `characters`.
Each snapshot keeps exact source text and parsed JSON. Snapshot chronology uses
generation/import time with SQLite row ID as a deterministic tie-breaker.
`diffSnapshots` creates changes only when both endpoints are known.
`AccountFacts`, `AccountContext`, and `LlmContext` are deterministic pure
projections. The compact LLM projection exists because sending full historical
context caused cross-character hallucination; Activity must preserve that
discipline.

The existing snapshot transport has no character GUID in its text identity:
Dashboard identity is version + realm + name. Activity must validate the same
identity envelope initially and explicitly retain this limitation. It must not
merge data across WoW versions or realms by name alone.

## Problem Statement

Inventory, XP, money, location, and level snapshot differences can show that a
state changed, but generally cannot show why. `Copper Ore +5` is not evidence
of mining; it may be loot, trade, mail, a purchase, or a quest. Likewise an XP
increase is not evidence of quest completion. The product needs direct activity
evidence while retaining these distinctions for deterministic consumers and an
LLM.

## Design Goals

- Preserve snapshots as the authoritative current-state model.
- Persist only direct, client-supported, normalized observations as canonical
  activity facts.
- Make OBSERVED, DERIVED, and UNKNOWN structurally distinct.
- Be idempotent across re-export/import and safe under duplicate events.
- Bound addon work, SavedVariables growth, SQLite growth, and LLM context.
- Keep API-specific behavior in the Retail collector/adapter and client-neutral
  trust semantics in shared Core/Dashboard code.
- Preserve auditability: summaries link to source evidence and rule versions.

## Non-Goals

- No Activity History implementation is included in this document.
- No raw combat-log database, kill/damage/healing history, or combat analysis.
- No parsing localized loot/chat strings as canonical acquisition facts.
- No mining/herbalism/fishing/crafting claim from inventory, profession, XP, or
  spell changes alone.
- No asserted vendor, auction, mail, trade, quest, or loot cause from a gold or
  item state change.
- No LLM-generated persisted summary, causal classification, or retention
  decision.
- No WOWSYNC v1 snapshot/schema change and no automatic Classic/TBC/Forever
  compatibility claim.

## Competing Designs

### Design A — Raw Blizzard event sourcing

Persist raw event names and arguments, normalize later. This maximizes forensic
detail, but commits storage and consumers to unstable client tuples, includes
noisy/duplicated UI signals, risks localization/privacy leaks, and makes later
reinterpretation of ambiguous data too tempting. Rejected as canonical storage.

### Design B — Snapshot transitions only

Use existing Dashboard snapshot diffs as history. It is cheap and already
useful for progression, inventory, and gold *changes*, but cannot establish
activity causes. Retained as a DERIVED companion, rejected as Activity History.

### Design C — Normalized observed-event journal plus sessions

The Retail adapter validates selected direct events and emits stable event
types/payloads. Core/Dashboard persist them immutably and derive session/range
views. This provides auditability, extensibility, deterministic ordering, and
strong trust boundaries. Selected.

### Design D — Persist only session summaries/evidence buckets

This minimizes volume, but a bucket alone loses source ordering and makes
changed aggregation logic silently alter history. Selected only as a derived
read model. A coalesced state observation may be a canonical event when it
carries its explicit observation window and source, but never replaces direct
events.

### Design E — Bounded circular addon log

Useful as a transport guardrail but unsafe as history because it silently
evicts evidence. Rejected. A collector cap must emit/retain an explicit
coverage-limited marker and stop/drop only with a known count; it must not
overwrite older facts invisibly.

## Agent Critique

Six independent reviews informed this decision.

| Mandate | Key finding | Decision impact |
| --- | --- | --- |
| Retail API/event specialist | Quest accepted/turned-in, level-up, and learned-spell events have direct payloads; bag, loot UI/chat, and refresh events do not establish causes. | Narrow Retail allow-list; defer gathering/item acquisition/combat. |
| Data model architect | Current SQLite has append-only snapshots but no migration framework; session UUID + sequence is needed because timestamps tie. | New versioned activity migration, immutable ID/sequence identity, explicit indexes. |
| LLM/AccountContext architect | Full context previously caused hallucination; existing LLM projection is intentionally compact and pure. | Bounded deterministic ActivityContext/LlmActivityContext, not full journal to model. |
| Minimalist/performance engineer | Useful Phase 1 can be low-volume direct milestones plus coalesced state observations. | No raw combat, bag polling, criteria spam, or arbitrary chat; strict collector budget. |
| Adversarial reviewer | Payload/time dedupe can erase real repeated actions; crashes/reloads leave incomplete history. | Transport-identity dedupe, coverage metadata, open/interrupted sessions, no invented end. |
| Alternative architect | Evidence buckets should be projections, not the sole record; snapshot transition history cannot prove activity. | Canonical normalized evidence first; derived buckets reference sources. |

The main disagreement was whether a short ring buffer/evidence bucket should be
canonical. The Retail/API and data-model critiques resolve it: retain
low-volume normalized direct evidence; aggregate only in derived views. If an
operational cap occurs, expose PARTIAL coverage rather than silently losing
facts.

## Architectural Decision

Persist a bounded, append-only journal of normalized Retail OBSERVED events and
session boundaries. Generate deterministic, provenance-linked session/day/range
projections at read time. Retain snapshot transitions as separate DERIVED
state-change history. Do not persist raw Blizzard tuples, LLM summaries,
ambiguous item-acquisition claims, combat logs, or a silently overwritten ring
buffer.

“Bounded” means the taxonomy and payloads are bounded and collector budgets are
explicit; it does **not** mean silently circular retention. Database retention
is an explicit user-visible policy introduced only after measurement and a
coverage-preserving compaction design.

## Canonical Data Model

The following interfaces are an implementation specification; field names may
be adapted to existing package conventions without weakening semantics.

```ts
export const ACTIVITY_SCHEMA_VERSION = 1 as const;
export type ActivityTrust = "OBSERVED" | "DERIVED";
export type ActivityCompleteness = "COMPLETE" | "PARTIAL" | "UNKNOWN";

export interface ActivitySource {
  client: "retail";
  adapter: "retail-activity";
  apiOrEvent: string;
  clientBuild?: string;
  collectorVersion: number;
}

export interface ActivityEvent<TPayload = Record<string, unknown>> {
  schemaVersion: typeof ACTIVITY_SCHEMA_VERSION;
  /** addon-generated immutable transport identity: sessionId + sequence */
  eventId: string;
  character: { version: "retail"; realm: string; name: string };
  addonSessionId: string;
  observedSequence: number; // positive, strictly increasing within session
  occurredAt?: number; // addon server epoch seconds; absent is UNKNOWN, never import time
  eventType: ActivityEventType;
  trust: "OBSERVED";
  completeness: ActivityCompleteness;
  source: ActivitySource;
  payloadVersion: number;
  payload: TPayload; // direct event/API facts only; omitted fields are unknown
  observationWindow?: { startAt?: number; endAt?: number }; // only coalesced reads
  correlationId?: string; // bounded deferred enrichment linkage
}

export interface ActivitySession {
  schemaVersion: typeof ACTIVITY_SCHEMA_VERSION;
  addonSessionId: string;
  character: { version: "retail"; realm: string; name: string };
  startedAt?: number;
  endedAt?: number;
  status: "OPEN" | "CLOSED" | "INTERRUPTED";
  endReason?: "PLAYER_LOGOUT" | "UNCONFIRMED";
  coverage: {
    collectorStartedAt?: number;
    collectorStoppedAt?: number;
    supportedEventTypes: string[];
    completeness: ActivityCompleteness;
    reason?: string;
    droppedCountsByType?: Record<string, number>;
  };
}

export interface DerivedActivityProjection {
  trust: "DERIVED";
  derivation: { ruleId: string; ruleVersion: number };
  sourceEventIds: string[];
  completeness: ActivityCompleteness;
  payload: Record<string, unknown>;
}
```

`DERIVED` is never inserted into the canonical observed-event table. It is a
distinct projection type and always identifies source events and a deterministic
rule/version. `UNKNOWN` is represented by missing/partial payload fields and
coverage reasons, never by zero, an empty list, or a claim that nothing happened.

### Persistence tables and indexes

Dashboard migration 1 must use a real migration runner (`PRAGMA user_version`,
numbered transactional migrations) rather than changing the current fresh-DB
`CREATE TABLE` string alone. It must enable foreign-key enforcement and retain
the current explicit child-first deletion safety.

```sql
CREATE TABLE activity_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  character_id INTEGER NOT NULL REFERENCES characters(id),
  addon_session_id TEXT NOT NULL,
  schema_version INTEGER NOT NULL,
  started_at INTEGER,
  ended_at INTEGER,
  status TEXT NOT NULL,
  end_reason TEXT,
  coverage_json TEXT NOT NULL,
  UNIQUE(character_id, addon_session_id)
);

CREATE TABLE activity_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  character_id INTEGER NOT NULL REFERENCES characters(id),
  session_id INTEGER REFERENCES activity_sessions(id),
  event_id TEXT NOT NULL,
  schema_version INTEGER NOT NULL,
  occurred_at INTEGER,
  observed_sequence INTEGER NOT NULL,
  imported_at INTEGER NOT NULL,
  event_type TEXT NOT NULL,
  trust TEXT NOT NULL CHECK(trust = 'OBSERVED'),
  completeness TEXT NOT NULL,
  source_json TEXT NOT NULL,
  payload_version INTEGER NOT NULL,
  payload_json TEXT NOT NULL,
  observation_window_json TEXT,
  correlation_id TEXT,
  UNIQUE(character_id, event_id),
  UNIQUE(character_id, session_id, observed_sequence)
);
CREATE INDEX idx_activity_events_character_time
  ON activity_events(character_id, occurred_at, observed_sequence, id);
CREATE INDEX idx_activity_events_session_sequence
  ON activity_events(session_id, observed_sequence, id);
CREATE INDEX idx_activity_events_type_time ON activity_events(event_type, occurred_at, id);
```

Dashboard import validates the activity character envelope against the existing
version/realm/name identity key. It stores imported activity atomically and
idempotently. A collision with the same transport identity but different
immutable contents is quarantined/rejected, never overwritten. Character
deletion must atomically remove activity events and sessions along with
snapshots.

## Event Taxonomy

Phase 1 is intentionally narrow. Exact runtime payload ordering and availability
must be captured before enabling an event type marked “runtime validation.”

| Event | Observed source | Direct payload / rule | Volume & reliability | Dedupe |
| --- | --- | --- | --- | --- |
| `retail.session_started` | successful player identity after `PLAYER_LOGIN`/world readiness | session ID, build, capability matrix | once/load; direct lifecycle | session ID |
| `retail.session_ended` | `PLAYER_LOGOUT` | end time and logout reason | once/graceful logout only | session ID/end seq |
| `retail.quest_accepted` | `QUEST_ACCEPTED(questID)` | quest ID; optional deferred title | low; direct ID, title may be pending | transport sequence |
| `retail.quest_turned_in` | `QUEST_TURNED_IN(questID,xpReward,moneyReward)` | quest ID and supplied rewards; optional title | low; direct completion/turn-in evidence | transport sequence |
| `retail.level_changed` | `PLAYER_LEVEL_UP(level,...)` | supplied level; optional verified current level | rare; direct | transport sequence |
| `retail.spell_learned` | `LEARNED_SPELL_IN_SKILL_LINE(spellID,...)` | spell ID, line index, guild-perk flag | low; direct; guild policy explicit | transport sequence |
| `retail.money_observed` | `PLAYER_MONEY` + successful `GetMoney` baseline/read | before/after only when both observed; coalesced window | moderate; no cause | one flush sequence/window |
| `retail.xp_observed` | `PLAYER_XP_UPDATE` + valid `UnitXP/UnitXPMax` | current/before values where known; window | potentially noisy; coalesced | one flush sequence/window |
| `retail.location_observed` | zone event + stable map/location read | changed zone/subzone/map only | noisy signal; coalesced only if changed | one flush sequence/window |
| `retail.equipment_observed` | `PLAYER_EQUIPMENT_CHANGED(slot,hasCurrent)` + cache-ready item read | slot, observed empty or item identity | low/moderate; delayed enrichment | original trigger correlation + sequence |

`retail.quest_removed` is not Phase 1 completion evidence because removal is
ambiguous. Quest criteria updates are deferred due volume/localized text.
Profession rank refresh is deferred until a direct Retail contract and readiness
experiment establish reliable semantics. Death, instance entry/exit, encounter
outcomes, crafting result, and currency events are Phase 2 candidates after live
payload validation; they must not be enabled by guesswork.

### Explicitly excluded from Phase 1

- `COMBAT_LOG_EVENT_UNFILTERED`, damage/healing/kills, and per-combat actions.
- `BAG_UPDATE`, `UNIT_INVENTORY_CHANGED`, and inventory snapshot changes as
  acquisition causes.
- `CHAT_MSG_LOOT`, `ITEM_PUSH`, `LOOT_READY`, and loot-window events as
  locale-independent item acquisition/gathering proof.
- Mining/herbalism/fishing/gathering labels from materials, spell casts, or
  profession state. A future gathering event requires a validated dedicated
  interaction/source contract; an item receipt alone is not mining.
- Chat parsing, tooltip text parsing, arbitrary raw API tuple storage, and
  trainer UI opening as player training activity.
- Unvalidated currency, dungeon completion, or profession-change causes.

Combat is explicitly not represented in Phase 1. Its volume, privacy surface,
and semantics would create a separate combat-log product rather than Activity
History.

## Provenance and Trust Model

Every canonical event says `trust: OBSERVED`, names its Retail event/API and
collector version, and contains only payload facts supported by that source.
Follow-up API reads are recorded as a read after a trigger; they do not turn the
trigger into a cause. For example, money after `PLAYER_MONEY` may be an observed
balance transition, not “gold earned” or “gold spent.”

Derived projections use `trust: DERIVED`, `derivation.ruleId/ruleVersion`, and
source event IDs. Snapshot diffs are DERIVED transitions with their two snapshot
identities, not activity events. LLM prose is an unpersisted interpretation and
must preserve these labels. UNKNOWN is explicit coverage/payload absence; lack
of retained events is never proof of inactivity.

## Session Model

A session is a lifecycle/coverage envelope, not proof that every contained
event has a common gameplay cause. The Retail addon creates a random
`addonSessionId` after stable player identity and maintains a monotonic sequence
in SavedVariables. It starts a new session on a new addon lifecycle. It closes
only when `PLAYER_LOGOUT` is observed.

Reload, disconnect, crash, forced termination, or an addon enabled mid-session
cannot safely assert an end time or logout. On a later same-character startup,
Core marks an older open session `INTERRUPTED` with `endReason: UNCONFIRMED` and
unknown end time. It must not merge sessions merely because a gap is short.
Character switches are separate identity-bound sessions.

Within a session canonical order is `observedSequence`. Display/query order is
`occurredAt`, then session sequence, then database ID for stable ties. Events
from different sessions with tied wall time are not asserted to have causal
order.

## Persistence, Aggregation, and Retention

The addon owns a small activity transport queue separate from snapshot sections;
the activity artifact is versioned and imported separately. It must survive
reload until exported/imported, but is a transport buffer, not a silent circular
history. It validates primitive bounded payloads only and has per-type/session
budgets. Reaching a cap preserves high-signal milestones where possible and
creates explicit PARTIAL coverage with known dropped counts; it never silently
evicts facts.

The Dashboard owns retained history. Start by retaining the low-volume journal
and measuring actual size. Do not automatically compact/delete in Phase 1.
Before a later user-configurable retention horizon, define a transactional
compaction policy that retains deterministic session/day projections with rule
version, source event ranges/counts, and an explicit detailed-evidence-expired
marker. Never delete sessions while retained events reference them.

Aggregation belongs in pure Core read models:

1. addon: validate/directly normalize selected Retail signals and bounded
   deferred enrichment;
2. Core import: validate identity/schema/idempotency and persist immutable facts;
3. `ActivityFacts`: deterministic session/range counts, timelines, coverage;
4. `ActivityContext`: canonical capped API/developer projection;
5. `LlmActivityContext`: a smaller deterministic projection; and
6. LLM: prose/advice only, never stored fact generation.

Session summaries are deterministic DERIVED projections. They can say “observed
two quest turn-ins” or “net observed money value changed in this coalesced
window,” never “the player quested for money” absent evidence.

## Retail Addon Collector Architecture

Add a Retail-only activity adapter/collector behind a capability gate. It must
not alter existing snapshot collectors or WOWSYNC v1 rendering.

```text
Retail Blizzard event
  -> synchronous tiny envelope (session ID, sequence, source, direct args)
  -> optional bounded pending enrichment keyed to envelope correlation ID
  -> normalized observed activity transport record
  -> SavedVariables activity queue / explicit activity export artifact
```

The envelope is retained if its primary fact is direct even when optional title
or item metadata is unavailable; it is `PARTIAL`, not dropped or fabricated.
For a no-payload invalidation (`PLAYER_MONEY`, XP, zone, equipment cache), read
only the relevant state after debounce. Emit an explicit coalesced observation
only after a successful valid read; record its observation window. Do not attach
the nearest bag/loot/quest event as an explanation.

Item cache handling follows current collector practice: retain trigger
correlation, retry a small bounded number of times on item-data readiness, then
emit partial direct trigger evidence or a coverage reason. Late data may enrich
only the matching correlation ID, never an event selected merely by time.

## Core, AccountFacts, AccountContext, and LLM Integration

Keep `SnapshotStore` snapshot behavior unchanged. Add an `ActivityStore` (or a
strictly additive store interface) with activity batch import, event/session
range queries, and deletion support. Add pure `activityFacts.ts`,
`activityContext.ts`, and `llmActivityContext.ts`; they receive explicit loaded
events/sessions and injected `now` where needed, matching existing deterministic
conventions.

`AccountFacts` remains authoritative for account state. `ActivityFacts` is a
sibling explaining retained observed history. `AccountContext` includes a
version/character-isolated Activity block with coverage, selected recent sessions,
and snapshot transitions clearly labeled DERIVED. It must not duplicate the
complete event journal.

Initially context selection is deterministic rather than question-parsed:

- latest session per selected character;
- most recent bounded sessions/events in canonical order;
- deterministic daily/session rollups;
- explicit earliest/latest retained time, event cap, and truncation/coverage;
- no cross-character aggregation without identity labels.

Later question-aware retrieval may be added only with an explicit query contract
(character, date range, event type) and hard limits. The model does not choose
unbounded retrieval. `Ask My Account` continues to self-fetch canonical context,
then applies one pure compact LLM projection. The LLM receives direct event IDs,
source/provenance labels, deterministic summaries, and coverage caveats—not raw
full history. Its system prompt must prohibit causal wording from a state change
and distinguish retention truncation from “nothing happened.”

## Error, Reload, Disconnect, and Unknown Handling

| Condition | Required behavior |
| --- | --- |
| Event before API/item data ready | retain direct envelope; bounded correlated retry; partial/unknown optional field on expiry |
| Duplicate delivery/export retry | idempotently ignore only same character + session + sequence/event ID; conflicting duplicate quarantined |
| Same-second events | preserve session sequence; timestamp is not a total order |
| UI reload | new lifecycle/session unless direct continuation protocol exists; old session is not silently merged |
| Logout | close only from observed `PLAYER_LOGOUT`; flush coalesced reads best effort |
| Crash/disconnect/kill | retain open then later mark interrupted/unconfirmed; no invented end/duration |
| Collector cap | explicit partial coverage/loss metadata; no circular overwrite |
| Missing payload/API | omit unknown field, set completeness/reason; never zero/default/cause |
| Character/version collision | validate current Dashboard identity scope; never cross-version merge |

## Performance and Storage Analysis

Phase 1 handlers are O(1) envelopes with primitive bounded payloads. No bag
scan, tooltip scan, combat event, localized chat parser, or item lookup runs in
a high-frequency handler. XP/money/location are coalesced; quest criteria and
combat are excluded. A representative conservative budget is at most 250
activity records per session with an explicit coverage marker if reached, but
the exact cap must be measured and must preserve/directly report dropped scope.

At a deliberately conservative 50 low-volume records/hour for four hours/day,
180 days is roughly 36,000 small rows per character. SQLite indexes and small
JSON payloads are practical locally; actual measurement, not this estimate,
governs retention. Payloads should be limited to a few KB and exclude tooltip
lines, raw combat data, and arbitrary Lua tables. API/UI range queries paginate;
AccountContext and LLM projections never load/send all rows.

## Testing Strategy

- Retail addon mocked-event tests for allowed/ignored events, payload validation,
  sequence generation, coalescing, bounded retries, cache pending/resolved/expired,
  reload, logout, and coverage caps.
- Captured Retail runtime activity fixtures for each enabled event contract.
- Core parser/normalizer tests for malformed/unknown/partial payloads, payload
  size, client/version isolation, and no inferred cause from state transition.
- SQLite migration tests for fresh and upgrade paths, idempotent batch replay,
  duplicate conflict rejection, ordering ties, transaction rollback, indexes,
  and activity cascade on character deletion.
- Pure byte-identical `ActivityFacts`, `ActivityContext`, and LLM projection
  tests with fixed time; context cap/truncation/source-link assertions.
- Server/system-prompt tests proving activity provenance and truncation rules
  reach Ask My Account without leaking full history.
- Regression tests proving absent activity input leaves existing snapshot parser,
  diff, AccountFacts, AccountContext, exports, and client behavior unchanged.

## Future Client Compatibility

Shared code owns envelope validation, trust labels, persistence, session/range
projections, and context selection. Retail owns event registration, payload
normalization, cache correlation, capability reporting, and event allow-list.
Classic Era, TBC Anniversary, and Forever later add adapters only for their
validated direct evidence. A missing capability is reported as unsupported or
UNKNOWN coverage; it never falls back to Retail behavior or uses snapshot
inference.

## Open Questions / Required Runtime Experiments

Before enabling each corresponding Retail event type, capture real payloads,
duplicates, and ordering for:

1. `QUEST_ACCEPTED`/`QUEST_TURNED_IN`: quest ID, rewards, title readiness, and
   relation to XP/money events.
2. Level/XP ordering across normal gain and level-up, including XP rate to tune
   coalescing windows.
3. `PLAYER_MONEY` baseline/read ordering and repeated/batched notifications.
4. Equipment slot event versus item-link/item-data readiness, including swaps and
   unequips.
5. Zone/instance transitions and map API readiness/noise.
6. Learned spell duplicate behavior and guild-perk filtering.
7. Logout, `/reload`, disconnect/crash, addon enable mid-session, and character
   switch lifecycle/queue recovery.
8. Currency event payload semantics and any future loot/crafting/gathering
   contract. Do not enable acquisition/gathering from chat/UI observation until
   ownership, quantity, and cause semantics are proven.

## Recommended Phase 1 Implementation Plan

1. Define the separate versioned Retail activity transport artifact and
   SavedVariables queue; leave WOWSYNC v1 snapshot text unchanged.
2. Add Retail lifecycle/session ID/monotonic sequence and direct-event envelope
   helpers with capability/coverage metadata.
3. Implement and live-validate only session, quest accepted/turned-in, level-up,
   and learned-spell events.
4. Add bounded, explicitly coalesced money/XP/location/equipment observations
   after their baseline/readiness experiments pass.
5. Add Dashboard migration runner, activity tables, idempotent importer, range
   queries, and atomic deletion behavior.
6. Add pure ActivityFacts/Context/LLM projections with fixed caps, provenance,
   and retention coverage fields; update the LLM system prompt.
7. Add unit, migration, fixture, and end-to-end import tests, then measure real
   volume before choosing a user-visible retention/compaction policy.
8. Only then consider Phase 2 candidates (profession state, death, instances,
   currency, crafting, or gathering) one validated contract at a time.

This plan deliberately does not implement Activity History in this branch.
