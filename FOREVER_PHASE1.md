# Forever Phase 1

Target client: installed `D:\World of Warcraft\_classic_beta_\WowB.exe`,
version 1.60.1 build 69893. The referenced build configuration identifies
`WOW-69893patch1.60.1_ForeverBeta`, product `wow_classic_beta`.

## Verified runtime interface

Hallo's live `/dump GetBuildInfo()` check, reported September 17, 2026, returned
version `1.60.1`, build `69893`, build date `Sep 16 2026`, and interface `16001`.
The dedicated `GearExport-Forever.toc` uses this observed interface value.

Blizzard UI source mirrored at commit
[`4d5d706b8e01c5ebe01c8dd9b7a07151d8d37069`](https://github.com/Gethe/wow-ui-source/tree/4d5d706b8e01c5ebe01c8dd9b7a07151d8d37069)
has `version.txt` = `1.60.1.69893`. Its generated `BuildDocumentation.lua`
confirms the fourth `GetBuildInfo` result is `interfaceVersion` but does not
publish its numeric value. `ProjectConstants.lua` declares MAINLINE=1 and
CLASSIC=2; do not invent a Forever project constant or assume either value.

## Limited implementation

The dedicated TOC loads shared `WoWSyncCompat.lua`, a Forever-only bootstrap,
shared `WoWSyncCore.lua`, Forever-only collectors, and shared renderer/UI.
It must set `X-WoWSync-Target: Forever`. Detection requires this package marker
and the audited version/build; it never selects Retail/Classic collectors based
on an assumed project ID. It fails closed on another build pending review.

Guarded observations: name, realm, class, level, faction, money in raw copper,
raw XP/XP maximum, zone/subzone, map ID and position when exposed. Missing,
throwing, restricted or differently typed values remain unknown, with sorted
diagnostic reasons in the existing section coverage note. A missing player GUID
prevents assigning a snapshot to a character; no identity is fabricated.

Playtime is deliberately deferred until a live Forever request/event payload is
validated. Both canonical seconds fields render `?`; the package sends no
`RequestTimePlayed` calls and registers no `TIME_PLAYED_MSG` handler. No local
clock estimates or chat parsing substitute for the server values.

Bank, inventory, equipment, professions, spells and trainers are not observed.
Their sections remain UNKNOWN, preserving canonical ordering. The package must
exclude BankCleanup, the legacy exporter and the full existing collectors.
The shared `/wowsync` UI and canonical WOWSYNC v1 renderer remain in use.

Build with `node scripts/package.cjs Forever`
to `dist/Forever/GearExport`, then run `node tests/check_packages.cjs Forever`.
Existing client package outputs
and runtime behavior must remain unchanged. No new SavedVariables names or
folder names are introduced.

## Validation boundaries

`tests/forever_test.lua` uses an explicitly synthetic interface value to verify
that export metadata is read from the API, never computed from the version.
It tests target/build routing, known and zero fields, absent/throwing/restricted
APIs, deterministic rendering, no bank or playtime requests, and shared UI loading.
These fixtures are not live beta evidence. SavedVariables persistence across a
client restart and the deferred collectors still need separate live checks.

## Live Phase 1 acceptance

The Forever package was installed into
`D:\World of Warcraft\_classic_beta_\Interface\AddOns\GearExport` after user
authorization. All 18 installed files matched the built package byte-for-byte.
The user subsequently confirmed successful addon loading and a real export on
Hallo in the actual Forever beta:

```text
Client: 1.60.1 build 69893
Interface: 16001
ClientFamily: Forever
Character: Hallo Emberstone
Realm: Classic Beta PvP 2
Level 1 Hunter, Alliance
XP 0/400
Dun Morogh / Coldridge Valley
```

This validates the limited Phase 1 character export. It does not expand support
to playtime, bank, inventory, equipment, professions, spells or trainers.
