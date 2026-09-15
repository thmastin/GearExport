# Character playtime API audit

Audited 2026-09-15 against Blizzard's extracted generated API documentation and
UI source mirrored by Gethe. All paths below are under `Interface/AddOns/`.

| Target | Pinned source | Result |
| --- | --- | --- |
| TBC Anniversary | [1463c686](https://github.com/Gethe/wow-ui-source/tree/1463c686270b6c64e2c5c228f447c4597c0f8ba6/Interface/AddOns/Blizzard_APIDocumentationGenerated) | Global `RequestTimePlayed()`; `TIME_PLAYED_MSG(totalTimePlayed, timePlayedThisLevel)` |
| Classic Era | [33e177d9](https://github.com/Gethe/wow-ui-source/tree/33e177d9bf38d76d5c6c6e05d5da78db1899659a/Interface/AddOns/Blizzard_APIDocumentationGenerated) | Same independently verified contract |
| Retail 12.1.0 | [4e3cbb8c](https://github.com/Gethe/wow-ui-source/tree/4e3cbb8c5609e4bfc332c0aebbfa4d79731fab59/Interface/AddOns/Blizzard_APIDocumentationGenerated) | Same independently verified contract; both values exposed |

For each target, `PlayerScriptDocumentation.lua` declares the request with no
arguments or direct return values; `SystemDocumentation.lua` declares the two
numeric event arguments in that order. The event's `SynchronousEvent` annotation
does not provide a response-time guarantee; collection waits for event delivery.

Retail was also checked against
`Blizzard_ChatFrameBase/Shared/SlashCommands.lua`, which invokes the request for
`/played`, `Mainline/ChatFrameOverrides.lua`, which passes both event arguments
to `ChatFrameUtil.DisplayTimePlayed`, and `Shared/ChatFrameUtil.lua`, which
formats each seconds count for chat. WoWSync consumes neither chat text nor
formatted durations. It does not assume an undocumented suppression argument;
the normal client chat display may appear when the request completes. No chat
handlers are hooked, replaced or filtered.

`WoWSyncCompat.RequestPlayed` guards absent/failing request APIs;
`PlayedSeconds` rejects missing, negative, fractional, nonnumeric, nonfinite and
secret values before storage. No target-specific API substitution is required
by the audited sources. Registration failure and response timeout degrade to
unknown. No session-duration API substitutes for lifetime or current-level time.

Automated coverage runs the shared playtime lifecycle fixture on TBC, Era and
Retail, alongside their complete existing suites. It covers raw known and zero
values, each missing argument, absent/failing API, timeout, late delivery,
coalescing, level changes, restricted values and deterministic frozen rendering.
The headless fixtures cannot establish live server timing or UI taint behavior.
Live acceptance: login, export, compare both values with `/played`, level up,
export again, and reload on each client. A small elapsed-time difference between
separate server requests is expected. No live acceptance is claimed here.

## Checkpoint validation

- Full `tests/run.cjs` with the v2.1 legacy baseline: 207 TBC/Era assertions,
  1,495 Retail assertions, zero gameplay actions; Lua 5.1 syntax and all release,
  Classic and Retail invariants pass.
- Canonical byte comparisons on all three fixtures against renderer baseline
  `b086ef60975a2e6366e0b11719704fbf853d667a` pass after removing only the two new
  fields. To repeat, extract that commit's `WoWSyncRender.lua` and set
  `WOWSYNC_BASELINE_RENDERER` to its path before running `tests/run.cjs`.
- All three package builds and `tests/check_packages.cjs` pass.
- `git diff --check` passes. BankCleanup remains byte-identical with SHA-256
  `54cbbd5ea9f8ac6b0307a475b270220bd7ea190e2ec6755950df34f50b67a6ba`.
