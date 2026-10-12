# Forever client update resilience

## Runtime and loader policy

The Forever package no longer uses an exact build list as an addon-load or
export gate. It requires the Forever addon TOC marker and the Forever client
project identity (`WOW_PROJECT_ID == WOW_PROJECT_CAMELOT` when the constant is
available). The fallback is the ID 18 observed in the 1.60.1 build 70338
capture, constrained to interface IDs 16000–19999 and client versions 1.60–1.99.
Retail (project 1), Classic Era (2), TBC (5), and other version families are
rejected. The fallback is isolated in `WoWSyncForever.lua` and has a regression
test.

The Forever TOC retains interface 16001, the last directly captured interface,
and now declares `AllowLoadGameType: camelot`. If Forever changes its interface
number, the player must use WoW's built-in **Load Out of Date AddOns** option
until a reviewed package updates the TOC interface. The option is the supported
loader compatibility route; interface metadata is not rewritten speculatively.
The package builder verifies this TOC policy and never copies into another
client flavor.

Builds 70291 and 70338 at 1.60.1/interface 16001 remain the only exact profiles
marked `VERIFIED_PROFILE`. Any recognized newer Forever 1.x profile runs
capability-guarded collectors and is labeled `UNVERIFIED_BUILD` in the
character observation and WOWSYNC export. Its exact version/build/interface
continues to scope SavedVariables capture profiles, so evidence is not reused
as current across updates. Each collector already distinguishes unavailable,
nil, error, stale, partial, and observed data; it does not infer zero from an
API failure. An incompatible individual API therefore fails its observation
section through existing guarded collector boundaries without suppressing
unrelated successful sections.

The guarded installer still requires the dedicated
`_classic_beta_/Interface/AddOns/GearExport` destination, a closed `WowB.exe`,
a readable `WowB.exe` FileVersion, committed source, verified package hashes,
and an integrity-checked rollback backup. It accepts versioned Forever 1.60–1.99
client updates because exact build equality is no longer a compatibility
claim. This change does not install or deploy the addon.

## Evidence and limitations

- `WOW_PROJECT_CAMELOT` identifies Forever in the Warcraft Wiki project table;
  build 70338 previously produced numeric project ID 18 in a real probe.
- Installed addons in the local Forever client use
  `## AllowLoadGameType: camelot`, confirming the TOC directive in this client
  installation.
- Exact addon API behavior on any build newer than 70338 remains unverified.
  A new build is allowed to load and report `UNVERIFIED_BUILD`; this is not a
  claim that every collector's APIs stayed compatible.
- A TOC interface mismatch can still require the player to enable **Load Out
  of Date AddOns**. No universal wildcard interface declaration is used.
- Runtime capability guards and automated fixtures cannot prove that a
  particular newer client's API return types are unchanged. A real capture is
  required before declaring that profile fully validated.

## Sources and precedent

- [Warcraft Wiki: WOW_PROJECT_ID](https://warcraft.wiki.gg/wiki/WOW_PROJECT_ID)
  identifies `WOW_PROJECT_CAMELOT` as Forever, value 18.
- [Blizzard UI source mirror](https://github.com/Gethe/wow-ui-source) remains
  the reference for versioned UI/API declarations; modern branches are not
  assumed to define old-client API behavior.
- Local Forever addon TOCs (including ForeverDingAssistant and
  EllesmereUIForeverEssentials) use `AllowLoadGameType: camelot`.
- Altoholic/DataStore's source-separated per-character persistence and
  TradeSkillMaster's UI-context recipe observation informed the existing
  account evidence / open-window collection design. No third-party code or
  mandatory dependency was added.
