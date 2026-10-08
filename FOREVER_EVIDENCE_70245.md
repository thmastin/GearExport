# Forever 70245 skill and trainer evidence

This collector is loaded only by the Forever TOC guarded for version `1.60.1`, build `70245`, and interface `16001`. It records observations under the character's `WoWSyncDB` record at `sections.forever70245Evidence`; it does not enable the historical `WoWSyncForeverTrainers.lua` adapter.

## Skill lines

The collector calls `C_SkillInfo.GetNumSkillLines()` and, when the count is a valid bounded integer, calls `C_SkillInfo.GetSkillLineInfo(index)` once for each index. It preserves index, API, input, return count and types, raw field keys/types/values, and the observed convenience fields `skillID`, `skillLineCategoryID`, `name`, `rank`, `maxRank`, and `isHeader`. Rows remain in runtime index order; duplicate names are not collapsed. Missing, nil, restricted, unsupported, and error results remain explicit. The capture does not invoke skill selection setters and does not convert ranks into weapon readiness or equipability.

## Trainer window

Trainer service APIs are called only if a supported trainer frame's `IsShown()` returns true at capture start. Service count is bounded at 200 and ability requirement probes at 20 indexes per service. Each call stores the API, input/context, provenance, return count, every tuple position including nil, and errors. Service ordering follows the runtime index. The service requirement count API is recorded as present/missing but not called because its return semantics were not validated. A nil terminator is preserved; reaching a safety limit is labeled partial. A trainer close during enumeration stops further calls and marks the attempted observation partial. No service purchase, learning, selection, or frame-opening API is called.

Raw tuple strings such as `unavailable` remain uninterpreted. They do not imply learnability, eligibility, cost meaning, or complete prerequisites. When the frame is closed, the current capture says `NOT_OBSERVED_WINDOW_CLOSED`; the last observed sample, if any, stays explicitly nested as `lastObserved` with its own timestamp and context.

## Export compatibility and integration

The strict WOWSYNC v1 text remains unchanged so the currently deployed Dashboard parser continues accepting it. This evidence section is persisted as structured SavedVariables and can be inspected using WoWSyncDB. A separate Dashboard parser/import change is required before the evidence becomes queryable by Dashboard workflows; this addon change does not modify or deploy Dashboard.

## Evidence boundaries

The capture does not establish exact transferability, general equipability, profession equip restrictions, binding semantics for bag locations, effective equipment stats, or complete talent/build interpretation. Those remain UNKNOWN. Synthetic tests exercise the contract but are not live 70245 evidence.
