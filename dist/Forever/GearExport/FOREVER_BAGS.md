# Forever carried bags: uncommitted validation build

Equipment was committed separately as `edd63a7`. This working change adds only
carried-bag observation and does not implement bank, professions, spells,
trainers, playtime or effective equipment stats. It is not live-validated or
installed automatically.

## Build-specific source evidence

The `1.60.1` source tag resolved to commit
[`70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e`](https://github.com/Gethe/wow-ui-source/tree/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e),
whose `version.txt` is `1.60.1.69913`. The relevant Blizzard source files are:

- `Blizzard_APIDocumentationGenerated/ContainerDocumentation.lua`:
  `C_Container.GetContainerNumSlots`, `GetContainerNumFreeSlots` (free count,
  optional bag family), `GetContainerItemInfo` (nullable structure), and
  `ContainerIDToInventoryID` for equipped bag identity.
- `ContainerItemInfo` fields: `itemID`, `hyperlink`, `itemName`, `stackCount`,
  `isBound`, and `isLocked`. Binding is the observed boolean, not item bind type.
- `Blizzard_APIDocumentationGenerated/BagIndexConstantsDocumentation.lua`:
  named Backpack, Bag_1 through Bag_4, and ReagentBag indices. Bank indices
  and Keyring are excluded from this carried-bag implementation.
- `Blizzard_FrameXMLBase/Constants.lua` and the shared
  `Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua`: bag counts come from
  `Constants.InventoryConstants.NumBagSlots` and `NumReagentBagSlots`. The
  latter determines whether the reagent bag is scanned; it is not presumed
  present just because its enum exists.

The Forever-only module normalizes those records into the unchanged shared
WOWSYNC v1 bag renderer. It reads equipped bag metadata through the already
validated `ItemLocation`/`C_Item` path and per-item vendor copper from return
11 of `C_Item.GetItemInfo`. No legacy container fallback is used.

## UNKNOWN and consistency rules

Missing APIs/constants leave the section UNKNOWN without futile retries.
Missing or inconsistent capacity, free count, quantity, identity, lock state,
or slot enumeration prevents publishing a new inventory. A previous successful
observation is retained with the shared refresh-error marker.

Successful nil slot information is considered empty only when occupied slots
reconcile with the observed capacity/free count. Capacity/free are rechecked
after each bag scan. Locked items and changing counts cause bounded retries.
An equipped bag reporting zero capacity is pending, not an empty missing bag.

Known item identity/quantity may be retained with missing name, binding, price,
or variant represented as `?`/ID-only itemRef and partial coverage. Known zero
vendor price and explicit false binding are preserved. No price is inferred
from `hasNoValue`, and no quantities or capacities are invented.

The existing BAG_UPDATE, BAG_UPDATE_DELAYED, ITEM_LOCK_CHANGED, equipment and
item-cache handlers schedule refreshes. No shared runtime files are changed.

## Validation

`tests/forever_bags_test.lua` uses explicitly synthetic container records.
It covers normal/reagent bags, no reagent bag, missing equipped bags, item
variant and binding distinctions, known zero prices, missing metadata,
asynchronous cache refresh, restricted/throwing/missing APIs, locked items,
inconsistent counts, unknown identity/quantity, empty inventory, and preservation
of previous observations on failure. No real bag contents have been fabricated.

After an explicitly requested installation, compare a fresh `/wowsync` with
Hallo's carried bags. Check capacity/free counts, bag references, stack counts,
binding, vendor values and empty slots; re-export after looting or moving a
stack manually. If data is UNKNOWN, capture these read-only runtime values
for the affected bag/occupied slot (replace `0, 1` as appropriate):

```text
/dump Constants.InventoryConstants.NumBagSlots, Constants.InventoryConstants.NumReagentBagSlots
/dump C_Container.GetContainerNumSlots(0)
/dump C_Container.GetContainerNumFreeSlots(0)
/dump C_Container.GetContainerItemInfo(0, 1)
/dump C_Container.ContainerIDToInventoryID(1)
```

Do not use nil/missing runtime evidence as proof of an empty bag.
