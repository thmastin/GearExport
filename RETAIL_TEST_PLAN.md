# Retail validation build

Retail implementation is ready for manual smoke testing. **Retail support is not
complete or released:** an initial live export has been received; the full in-game cases below remain pending. Automated mock results
are recorded separately from client evidence.

## Install

Source branch: `retail-compat`. Target: Retail 12.1.0, interface 120100. Folder name
must be `GearExport`, preserving existing slash commands and SavedVariables names.

1. From the repository, run `node scripts/package.cjs Retail`.
2. Copy `dist/Retail/GearExport` into
   `D:\World of Warcraft\_retail_\Interface\AddOns\GearExport`.
   The package contains one `GearExport.toc`, selected from `GearExport-Retail.toc`.
   Do not copy the source tree's TBC default TOC or Classic flavor aliases into it.
3. Verify the installed files before testing:
   `node scripts/verify-install.cjs Retail "D:\World of Warcraft\_retail_\Interface\AddOns\GearExport"`.
   A mismatch means rebuild/copy again; building or pushing alone does not install.
4. Enable **WoWSync (Retail - validation build)** in Retail's AddOns list. Restart
   the client if this is a newly installed addon; otherwise `/reload`.
5. Use `/wowsync`. Copy from `WOWSYNC v1` through `[END]`. Check `ClientFamily:
   Retail`, `Interface: 120100`, character, level and MoneyCopper.
   `[CHARACTER]` must include `PlayedSeconds` and `LevelPlayedSeconds`, even when
   their values are `?`. Compare both values with `/played` after response delivery.
   A missing label indicates an older renderer, not an unavailable playtime value.

BankCleanup is absent from the Retail package. `/bankx` is not a Retail command.
The installed Anniversary and Era addons are not changed by building this package.
The same builder accepts `TBC` and `ClassicEra` for separate packages; those retain
BankCleanup. No libraries or TSM are required for `/wowsync`.

## Manual smoke matrix

### Passed live playtime validation

After updating the installed package, the user confirmed Retail 12.1.0 build
69814: `/played` reported 12630 total and 686 current-level seconds; WoWSync
reported 12638 and 694 eight seconds later. Both counters increased by exactly
eight seconds. **Playtime comparison: passed.** Other smoke cases below retain
their individual pending status.

### Initial live export evidence

The user supplied the first canonical export (Generated `1789344996`) from Retail
12.1.0 build 69814, interface 120100, on a level-6 hunter. The user explicitly
said the checklist still needs to be performed. This establishes successful live
export generation, not completion of the smoke matrix or independent verification
of every exported value. Personal character identifiers and the full inventory
are not copied into public repository documentation.

Observed in that export:

- The WOWSYNC v1 envelope and all eight canonical sections are present.
- Character, location, equipment, bags, professions and spells report OBSERVED.
- Retail family/interface metadata, level/XP/money, zone/map/coordinates are populated.
- Equipment retains complete itemRef payloads, item levels and exposed stats;
  empty equipment slots remain explicit.
- Carried storage reports 50 slots, 32 free: a 20-slot backpack and a 30-slot bag.
  The unequipped reagent bag is represented with zero capacity, not fabricated items.
- No professions are exposed on this character; this does not validate learned
  professions or tier handling.
- Spell rows have numeric identities and no invented ranks. Hunter pet-management
  abilities appear in the player spellbook; this alone is not evidence of scanning
  the pet spellbook. Actual learned/future/spec coverage still requires comparison.
- Unvisited bank and trainers remain UNKNOWN / Not observed.

No Lua error report accompanied the export; an error-free session has not yet
been explicitly confirmed. Login/reload, movements, equipped reagent bag, bank,
learned professions, trainers, alternate characters and full UI/error checks remain
pending. Raw stat keys and full-precision numeric values are current output, not
evidence that the exported item identities were reduced or lost.

Record pass/fail/N/A, actual client version/build/interface, character, relevant
export, and the full Lua error/stack (if any). Actions below are performed manually
by the tester; WoWSync only observes.

| Case | Procedure and expected result | Status |
| --- | --- | --- |
| Baseline | Login, `/reload`, `/wowsync`; verify name/realm/class/faction/level/gold, zone/subzone/map/coordinates. At max level no invented XP progress. | Pending |
| Equipment | Compare all equipped slots, ilvl and full itemRef against actual links. Inspect an enchanted/gemmed/crafted/upgraded item. Slot 18 is legacy/unused; profession equipment is not included. Stats describe exposed item stats, not every proc/buff. | Pending |
| Delayed items | Immediately export after login/equipment changes. Missing metadata is partial, full available itemRef survives, later SYNC completes after loading. No Lua errors on restricted data. | Pending |
| Bags | Normal bags plus reagent bag (if equipped), occupied/free counts, bound state. Move a stack manually and export after BAG_UPDATE settles; no duplicate quantity or locked intermediate snapshot. | Pending |
| Character bank | Open bank, inspect all purchased character tabs and counts; manually mutate items and switch tabs. Check PurchasedBankTabs and CHARACTER labels. No Classic negative IDs or imaginary bank bags. | Pending |
| Bank stale state | Close/reopen bank, change items, export immediately and after settling. Closed/unviewable data is LAST_SEEN; never visited is UNKNOWN; old data survives a failed read. | Pending |
| Legacy bank/reagent storage | Current Retail 12.1 uses character tabs: classic main bank, equipped bank bags and separate reagent bank are N/A. Report a mismatch with the actual client rather than assuming a pass. | Pending verification |
| Warband/account bank | Open an Account banker (or the Account tab where it is viewable). Record `C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Account)`, capacity/free counts and representative itemRefs. `[ACCOUNT BANK]` must be `Scope: ACCOUNT_WARBAND`, separate from `[BANK]`; unviewable/never-opened must be UNKNOWN, never EMPTY. | Pending live validation |
| Guild Bank | Open a Guild Bank with at least two viewable tabs, one populated and one empty if possible, plus an inaccessible tab. `/wowsync` serializes `QueryGuildBankTab`: one request, wait for `GUILDBANKBAGSLOTS_CHANGED`, then scan all 98 slots before requesting the next tab. Verify a queried empty tab is OBSERVED empty, an inaccessible tab is INACCESSIBLE, no selection/UI change occurs, and closing/timing out preserves a prior complete snapshot. `GuildBankFrame` OnShow/OnHide is the validated lifecycle, not documented open/close events alone. | Live validated: Ciao, populated tabs plus a genuinely empty fourth tab; complete OBSERVED then closed LAST_SEEN persistence |
| Professions | Test primary and secondary professions, including a sparse set such as only Fishing. Compare current/max skill and exposed tier/expansion. Historical tiers, knowledge and recipes are not a full catalogue here. | Pending |
| Spellbook | Verify class/active spec/passive/racial and known flyout spells. Change spec manually, export again. No future/off-spec/pet spells, duplicates, zero IDs, or fabricated Classic ranks. | Pending |
| Trainer profession | Visit two different profession trainers with useful services. Check service status/level/cost/requirements and independent PROF categories. Filters remain untouched. | Pending |
| Trainer empty/class | Visit class/no-service trainer if available. Empty services remain partial; no fabricated abilities/category. Useful known category evidence is retained; generic NPC name is not category evidence. | Pending |
| Trainer persistence | Visit a second category and UNKNOWN, close, `/reload`, export: previous categories and per-category timestamps remain. | Pending |
| Multiple characters | Export on two characters; each has distinct GUID state. Current export includes only active character, old character snapshots survive reload/logout. | Pending |
| UI | `/wowsync`, SYNC, `/wowsync button`, copy complete text; background events do not change text being copied. Closing while a refresh runs does not reopen window. | Pending |
| Legacy commands | `/gearx`, `/itemx 6948` (or owned item), `/bagsx`, `/trainerx` while trainer is open. Retail bags include reagent slots; bank totals are character-only. | Pending |
| Error/regression | Capture Lua errors via existing BugSack/BugGrabber or `/console scriptErrors 1`. Ordinary gameplay with addon loaded: no automated moves, purchases, training, casting or crafting. | Pending |

## Evidence handoff

Send the baseline export, bank open/closed exports, profession and two trainer
category observations, plus actual errors and matrix results. `/reload` or normal
logout flushes data to
`_retail_/WTF/Account/<account>/SavedVariables/GearExport.lua` for local inspection.
Do not supply account credentials. Saved exports and error evidence, not a successful
mock run, are required before changing live acceptance to passed.

## Automated validation

Existing test dependencies are `luaparse` and `fengari-node-cli` in a temporary
node_modules directory. Run from the repository:

```text
node tests/run.cjs <path-to-node_modules> <path-to-v2.1-GearExport.lua>
node scripts/package.cjs Retail
node scripts/package.cjs ClassicEra
node scripts/package.cjs TBC
```

The v2.1 comparison source is `git show 23e0ef2:GearExport.lua` written to a temporary
UTF-8 file. Keep that argument to run all 20 legacy output comparisons. The runner
requires successful final markers because Fengari can exit zero after an assertion.
Checks cover TBC/Era fixtures, Retail fixtures, Lua 5.1 parsing, deterministic shared
rendering, observational-only code, package targets and BankCleanup's baseline hash.
