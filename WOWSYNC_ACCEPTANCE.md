# WoWSync implementation and acceptance checklist

Status: stable v1 scope accepted following user-reported primary in-game validation
and final automated regression checks. No new export modes or companion features
were added. A narrow equipment-readiness lifecycle correction is regression-tested;
its effect on the previously reported in-game partial flag is not yet observed.

Version naming: the legacy baseline is GearExport 2.1 (`6f58d2e`); this package's TOC
is 2.2, while the canonical export and structured schema remain WoWSync v1. The user
referred to the tested build as WoWSync v2.1; these labels do not require a schema change.

## Scope and baseline

- [x] Start from v2.1 (`6f58d2e`), including per-export SavedVariables slots.
- [x] Keep `/gearx`, `/gearexport`, `/itemx`, `/bagsx`, `/trainerx`, `/gearhelp`, and `/bankx`.
- [x] Preserve traditional Markdown formats and the meaning of `GearExportDB` fields.
- [x] Keep `BankCleanup.lua` byte-for-byte unchanged.
- [x] Capture structured state independently of slash commands and rendered text.
- [x] Keep one current section snapshot per character GUID; no event-history database.
- [x] Make consolidated copy/paste the default `/wowsync` operation.
- [x] Keep section rendering pure and independent, using the same underlying schema.
- [x] Optional hidden-by-default, movable SYNC launcher: `/wowsync button`.
- [x] Normal sync never reloads. Existing `/reload` remains available to flush disk data.
- [x] No automatic item movement, vending, mail, auctions, purchases, training,
      equipment changes, spells, or cleanup.
- [x] Defer TSM price enrichment, mailbox/AH capture, recipe catalogues, and pet spells.

## Automated validation

Run from the GearExport directory, with a temporary installation of
`fengari-node-cli` and `luaparse` outside the addon:

```text
node tests/run.cjs PATH_TO_TEMP_NODE_MODULES PATH_TO_UNMODIFIED_V2_1_GearExport.lua
git diff --check
```

The baseline argument is needed for the byte-for-byte legacy comparisons. Without
it, the harness still checks WoWSync behavior but skips those comparisons. Fengari
uses Lua 5.3; the separate parser checks Lua 5.1 syntax. Neither replaces a WoW client.

- [x] Final automated run: 120 assertions passed, including 20 byte-for-byte legacy report
      comparisons (four reports across five bank/TSM/cache scenarios), zero gameplay
      actions, and seven Lua files parsed as Lua 5.1. `git diff --check` passed.
- [x] Candidate installed in the Anniversary GearExport directory; all six changed/new
      runtime files match workspace SHA-256 hashes. BankCleanup remains unchanged
      (`54CBBD5EA9F8AC6B0307A475B270220BD7EA190E2EC6755950DF34F50B67A6BA`).
      Original v2.1 Lua/TOC and BankCleanup are backed up in the workspace archive
      `GearExport-before-WoWSync-20260910.zip` (not part of the addon distribution).

## Completed primary in-game validation

Evidence: user-reported test results supplied for the final review, corroborated by
inspection of the local structured SavedVariables. Recorded client version is
**2.5.6, build 69546, interface 20506**. User actions below were manual; WoWSync
observed the resulting state.

- [x] **Voodan, Thunder Bluff:** received/opened mail from Torahn before the bank
      test, changing bags for an unrelated reason. Opened the bank, withdrew 10
      Bolts of Linen Cloth, closed/reopened the bank, and ran `/wowsync`. Export
      showed **bags 10 / bank 51**, with bank `OBSERVED; complete` and a fresh
      observation timestamp. This confirms real bank rescanning/reconciliation
      despite preceding unrelated bag activity; it does not claim mailbox capture.
- [x] **Torahn, level 30 Shaman, Southern Barrens:** current bags complete; bank
      snapshot complete from the earlier Thunder Bluff visit; equipment captured
      with an honest partial-metadata warning; professions and known spellbook
      captured; Shaman trainer snapshot present.
- [x] **Trainer progression:** captured available/unavailable services, required
      levels, copper costs, and prerequisites. Reported examples: Chain Lightning
      Rank 1, Purge Rank 2, Windfury Totem, and Fire Nova Totem Rank 3 at level 32;
      Strength of Earth Totem Rank 3 at level 38; Chain Heal at level 40. These are
      validation observations from the supplied trainer export, not a new spell database.
- [x] Trainer partial/filtered coverage reported honestly.
- [x] Independent character records observed in SavedVariables; no need to append
      every alt to the default handoff.
- [x] User explicitly confirmed primary validation passed and authorized the README
      LLM documentation gate to open.

These results establish the primary working workflow. They do not claim every
stress test or BankX checklist case below was repeated in this pass. The existing
BankX test record remains authoritative for previously recorded manual cases.

## Final review decisions and remaining limitations

- [x] No change to bank scanning, transfers, BankCleanup, export ordering/columns,
      command names, schema, or optional SYNC button behavior in the polish pass.
- [x] Equipment tooltip readiness is now sampled before Hide/cleanup. Regression
      tests cover successful reads followed by line cleanup and genuinely missing
      data. Interpreted stats and all legacy report strings remain unchanged.
- [x] Missing item names/links or unavailable equipped tooltips still produce the
      existing `partial` coverage note. The previous aggregate flag cannot identify
      a failing slot; no claim is made that all 2.5.6 partial equipment is just timing
      or that the small correction resolves every in-game case.
- [x] Bounded retries remain; later item-info events or a new SYNC can refresh data.
      No fabricated stats, permanent polling, or verbose diagnostics were introduced.
- [x] Trainer IDs remain unknown when not exposed by the adapter; filtered trainer
      lists and collapsed profession headers remain partial. Spellbook scope does
      not include recipe catalogues or pet abilities.
- [x] LAST_SEEN storage remains a timestamped observation, not current remote access.
      TSM enrichment and mailbox/AH/account aggregation remain future work.
- [x] SYNC persists in memory without reloading; external disk readers still require
      a normal client save (logout or explicit reload). No companion is implemented.

## Extended in-client regression checklist: TBC Anniversary

Record the exact `GetBuildInfo()` version/build/interface. The existing TOC interface
is retained as `20506`, confirmed in the tested 2.5.6 snapshots. Retain this checklist
for future regressions; do not infer unreported cases passed from the primary results.

1. Reload once to load the new files. Run `/wowsync` with bank and trainer closed.
   Character, location, bags, equipment, professions, and known spells should appear.
   A bank/trainer never visited with WoWSync must say UNKNOWN, not EMPTY.
2. Copy the entire block using Ctrl+C. Confirm `WOWSYNC v1` through `[END]`, all
   columns, long item references, and large spell lists survive copying without loss.
3. Loot/use/split an inexpensive stack manually. Wait for it to settle and export.
   Quantities must match, without running `/bagsx` or any other legacy exporter.
4. Open the bank and wait briefly. Export with the bank open, then close it and
   export again. Main bank, purchased bank bags, equipped bag identities/capacities,
   and bank-only items must survive; the closed export must label bank LAST_SEEN.
5. Move one inexpensive item manually while the bank is open. Check bags and bank
   after settling. Repeat closing immediately during an update: preserve the last
   observation and show uncertainty, never silently replace the bank with zero.
6. Open a class trainer and a profession trainer in separate visits. Test delayed
   data, available/unavailable/known filters, and collapsed categories. WoWSync must
   respect the UI filters and label incomplete coverage. Close quickly once; no
   delayed callback may replace the snapshot with another trainer's data.
7. If naturally training an ability, do it manually. Confirm spellbook and trainer
   status update; required skill, prerequisite ability, and copper cost are correct.
   Unknown trainer spell IDs must remain `?`, never a guessed ID or UI row number.
8. Change gear manually, including random-suffix equipment if available. Compare
   effective stats against `/gearx`. Gain a profession point normally and verify it.
   Collapse skill headers and check that coverage becomes partial, without UI changes.
9. Run `/wowsync button`, drag the launcher, click it, toggle it off/on, and reload.
   Visibility and position must persist. Normal SYNC must never reload the client.
10. Leave the copy window open while state changes. Its text must remain stable;
    pressing SYNC should refresh it. Closing while refresh is pending must keep it closed.
11. Export on a second character and reload. GUID-separated structured state must
    retain the first character without mixing bank/trainer snapshots.
12. Verify disk persistence after an explicit `/reload` or normal logout:
    `WoWSyncDB` shares `SavedVariables/GearExport.lua` with `GearExportDB`.
    Legacy `exports`, `exportMeta`, and `latestExport` must keep their previous meaning.
13. Repeat legacy commands with/without TSM and with bank open/closed. Compare
    representative reports, help behavior, and per-export SavedVariables slots.
14. Repeat BankX P1, S1-S7 where practical, T1-T4, W1-W4, V1, and V3 from
    `BANK_CLEANUP_TESTS.md` with synchronization active. Require one explicit click
    per move, immediate live validation, exact post-move verification, and no
    automatic follow-up. Record errors/taint, unexpected movement, or stuck cursor.
15. Observe rapid bag events and an ordinary play session. There must be no persistent
    scanning while idle, no runaway retries, and no history accumulating in SavedVariables.

For each case record pass/fail, client build, relevant export, and any Lua error.

## Multi-character and future-extension acceptance

- [x] Current-character-only remains the canonical `/wowsync` default; automated
      coverage verifies that a saved second character does not enter that output.
- [x] Account state and GUID-keyed character state are conceptually separated in
      `WOWSYNC_SCHEMA.md`, without duplicating the roster or migrating working data.
- [x] Evaluate current-only, optional compact alt summaries, full account snapshots,
      and account/economy projections. Recommend explicit opt-in account scope.
- [x] Document future deterministic character ordering, per-character freshness,
      partial/unknown totals, asynchronous transfer double-counting, and source scope.
- [x] All eight independent section renderers match their portions of the canonical
      export in regression tests. Focused commands remain a documented extension path.
- [x] Document the read-only SavedVariables companion, deterministic rule engine,
      optional LLM reasoning, and notifications; explicitly prohibit memory access,
      injection, simulated input, clicks, gameplay actions, and a command channel.
- [x] No new account/focused slash commands or companion functionality added in v1.

## README LLM documentation — completed after primary validation

The user explicitly confirmed validation passed and requested these prompts in the
final review. The README LLM section was first drafted after that confirmation.

README now contains:

- [x] A general copy/paste prompt for using a WoWSync export with an LLM.
- [x] Focused gear prompt.
- [x] Focused inventory/bank prompt.
- [x] Focused trainer prompt.
- [x] Focused professions prompt.
- [x] Focused economy prompt (respecting which market data is actually present).
- [x] Focused leveling/character-planning prompt.
- [x] A custom-prompt template for the user's own question.
- [x] Prompt examples checked against the final export names, columns, freshness,
      unknown values, filter coverage, and actual feature boundaries.

Prompts are generic, have copy/paste export placeholders, and contain no personal
character names or private project goals. They distinguish current-character scope
from separately supplied account data and preserve manual gameplay decisions.
