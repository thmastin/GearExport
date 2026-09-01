# GearExport

GearExport is a small, dependency-free World of Warcraft addon for **Burning Crusade Classic Anniversary**. It creates clean Markdown reports that can be copied into a `.md` file or pasted into ChatGPT for character, equipment, and inventory analysis.

TradeSkillMaster is optional. When it is installed, GearExport uses its public API to include market pricing and current-character inventory-location data.

## Installation

Copy the `GearExport` directory into:

```text
World of Warcraft\_anniversary_\Interface\AddOns\
```

The resulting layout should be:

```text
Interface\AddOns\GearExport\GearExport.toc
Interface\AddOns\GearExport\GearExport.lua
Interface\AddOns\GearExport\BankCleanup.lua
```

Start World of Warcraft or run `/reload` after updating the addon.

## Commands

| Command | Description |
| --- | --- |
| `/gearx` | Export character details, equipment, effective item stats, professions, and bag capacity. |
| `/itemx` | Export the item currently under the mouse pointer. |
| `/itemx <item link or item ID>` | Export a specific item. |
| `/bagsx` | Export carried inventory, available location quantities, vendor values, and TSM market data. |
| `/bankx` | Import, review, and execute an assisted normal-bank cleanup plan one move per click. |
| `/gearhelp` | Show command help. |
| `/gearx help` | Show command help. |

The report window automatically focuses and selects its contents. Press `Ctrl+C` to copy the report. Press Escape or use the Close button to dismiss the window.

WoW addons cannot write directly to the operating-system clipboard, so one manual `Ctrl+C` is required.

## Character export

`/gearx` includes:

- Character name, level, class, and money
- Every equipment slot, including empty slots
- Item level and required level
- Fixed and random-suffix equipment stats
- Primary and secondary professions with current and maximum skill
- Free and total carried bag slots

Random-property stats are resolved from the actual equipped-item tooltip when Burning Crusade Classic's `GetItemStats()` omits them.

## Item export

`/itemx` includes:

- Name, item ID, quality, and carried quantity
- Per-item and total vendor value
- Available TSM prices

Supported TSM sources include DBMarket, DBMinBuyout, DBRegionMarketAvg, DBRegionSaleAvg, DBRegionSaleRate, DBRegionSoldPerDay, and Destroy value.

## Inventory market export

`/bagsx` scans carried bags on demand and aggregates physical stacks of the same item. It includes economically useful Common items and vendor trash; quest and conjured items are excluded where the client identifies them reliably.

When TSM is available, the report attempts to include current-character bank, mail, and Auction House quantities through TSM's public API. Carried bag quantities always come from the live Blizzard container API. Running `/bagsx` while the bank is open provides live bank enumeration and discovers bank-only items.

Market totals are estimates based on DBMarket, not guaranteed sale proceeds. Soulbound, Bind-on-Pickup, mixed-binding, and unknown-binding items do not contribute to the estimated auctionable DBMarket total.

### Inventory limitations

TSM's public API can query location quantities for a known item, but it does not expose an iterator over every cached item. As a result:

- Carried items are always discoverable.
- Bank-only items are discoverable while the bank is open.
- Mail-only or Auction-House-only items cannot be discovered unless the same item is also carried or visible during live bank enumeration.
- Cached location data can be stale until TSM has refreshed that location.

GearExport does not maintain a separate persistent inventory database.

## Assisted bank cleanup

`/bankx` imports a strict, versioned plan produced from an inventory review:

```text
GEARX_BANK_PLAN_V1
DEPOSIT|2589|20
WITHDRAW|6291|5
```

Only `DEPOSIT` and `WITHDRAW` are supported. Importing a plan never moves an item. The player must review the plan and explicitly click **Execute Next Move** for each transfer. GearExport revalidates live inventory before that click, performs at most one transfer, waits for Anniversary inventory events to settle, and verifies the exact result before enabling the next move.

Each plan line must be satisfiable from one physical source stack. GearExport stops safely if inventory changed, the cursor is occupied, an item is locked, destination capacity is unavailable, or exact post-move verification fails. There is no Execute All or unattended transfer loop. Execution requires the normal character bank to be open.

## SavedVariables

`GearExportDB` stores only:

- `exports` — the most recent Markdown report for each export type, kept in its own slot (`character` from `/gearx`, `inventory` from `/bagsx`, `trainer` from `/trainerx`, `item` from `/itemx`). Each slot is a plain string and survives a `/reload`, so every export can be read at once. Command help is never persisted.
- `exportMeta` — for each slot, the `time`, `character`, and `level` the export was generated at, so a reader can tell how fresh each slot is.
- `latestExport` — the single most recent report, updated on every export for backward compatibility.
- The exporter window position

## Compatibility

GearExport targets **Burning Crusade Classic Anniversary** with interface version `20506`. It favors the Classic APIs available in that client and has no required external libraries.

The currently tested optional integration is TradeSkillMaster 4 using its public `TSM_API` functions. Missing TSM APIs or price sources are ignored without preventing the rest of the export.

## Development

The exporter and assisted bank-cleanup implementation are kept in separate Lua files. Keep changes small, avoid Retail-only assumptions, and test in the Anniversary client after modifying API-facing behavior.

Suggested smoke test:

1. Run `/reload`.
2. Run `/gearx` and verify equipment and professions.
3. Run `/itemx` on a known item and compare TSM values.
4. Run `/bagsx` and verify live carried quantities and stack aggregation.
5. Open `/bankx` and verify plan import does not move inventory.
6. Copy each report with `Ctrl+C` and verify the complete Markdown output.

## License

GearExport is available under the [MIT License](LICENSE).
