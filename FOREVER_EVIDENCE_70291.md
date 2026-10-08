# Forever 70291 compatibility capture

This candidate is pinned to Forever `1.60.1`, build `70291`, and interface `16001`. It carries forward the production collectors that were live-validated on build 70245. The exact 70245 API shapes and unknown-value rules are documented in the preserved `FOREVER_EVIDENCE_70245.md`, production-validation report, and synthetic regression fixtures. The 70291 production capture remains pending; successful API behavior must be verified against that capture before compatibility is declared.

## Skill lines

The collector calls `C_SkillInfo.GetNumSkillLines()` and, when the count is a valid bounded integer, calls `C_SkillInfo.GetSkillLineInfo(index)` once for each index. It preserves index, API, input, return count and types, raw field keys/types/values, and the observed convenience fields `skillID`, `skillLineCategoryID`, `name`, `rank`, `maxRank`, and `isHeader`. Rows remain in runtime index order; duplicate names are not collapsed. Missing, nil, restricted, unsupported, and error results remain explicit. The capture does not invoke skill selection setters and does not convert ranks into weapon readiness or equipability. These calls' 70291 presence and shapes are pending the real export.

## Trainer window

Trainer service APIs are called only if a supported trainer frame's `IsShown()` returns true at capture start. Service count is bounded at 200 and ability requirement probes at 20 indexes per service. Each call stores the API, input/context, provenance, return count, every tuple position including nil, and errors. Service ordering follows the runtime index. The service requirement count API is recorded as present/missing but not called because its return semantics were not validated. A nil terminator is preserved; reaching a safety limit is labeled partial. A trainer close during enumeration stops further calls and marks the attempted observation partial. No service purchase, learning, selection, or frame-opening API is called. Trainer-frame and service contracts on 70291 remain pending live comparison.

Raw tuple strings such as `unavailable` remain uninterpreted. They do not imply learnability, eligibility, cost meaning, or complete prerequisites. When a supported frame exists and is hidden, the current capture says `NOT_OBSERVED_WINDOW_CLOSED`. If no supported frame object is available, it says `NOT_OBSERVED_FRAME_UNAVAILABLE`; this does not assert that the frame was positively observed closed. Both states retain any prior sample explicitly nested as `lastObserved` with its own timestamp and context.

## Export compatibility and integration

The strict WOWSYNC v1 text remains unchanged so the currently deployed Dashboard parser continues accepting it. This evidence section is persisted as structured SavedVariables and can be inspected using WoWSyncDB. A separate Dashboard parser/import change is required before the evidence becomes queryable by Dashboard workflows; this addon change does not modify or deploy Dashboard.

## Evidence boundaries

The capture does not establish exact transferability, general equipability, profession equip restrictions, binding semantics for bag locations, effective equipment stats, or complete talent/build interpretation. Those remain UNKNOWN. Synthetic tests exercise the carried-forward contracts only; they are not live 70291 evidence. Do not label 70291 compatibility validated until the real WOWSYNC export and same-refresh SavedVariables are inspected.
