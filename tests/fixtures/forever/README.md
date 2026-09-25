# Forever real export fixtures

`hallo-level6-equipment.lua` records the equipment cells supplied by the user
from export `1789704998`, client `1.60.1`/`69913`, interface `16001`. The pasted
table had one cell per line. The fixture preserves its nine equipped item
variants and metadata, ten explicitly empty slots, and unknown effective stats.
The equipment test replays these values and checks all 19 canonical rows.

`hallo-level4.lua` returns the unmodified `latestExport.text` read from the actual
Forever beta GearExport SavedVariables on September 17, 2026. The source file
was read only. This export's location is Anvilmar; the later saved location
observation is different and was not substituted into this export.

`forever_snapshot_test.lua` replays the captured character/location values and
requires byte-identical rendered sections. Equipment tests use explicitly
synthetic data because Phase 1 did not observe equipment.

The real capture retains build `69893`; current guard tests use verified build
`70009`. Replaying historical data does not authorize the old running build.

The full level-1 export was not available in the repository or current
SavedVariables. Its user-reported summary is recorded in `FOREVER_PHASE1.md`;
it is not a substitute for the missing full regression fixture. That historical
capture is not required for equipment validation; the level-4 capture is the
current baseline.
