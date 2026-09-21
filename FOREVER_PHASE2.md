# Forever Phase 2: live-validated equipment

This build adds equipment observation only. Equipment was live-validated on
Hallo before starting bags, professions, known spells, trainers or playtime. The
build process does not install anything. Interface remains `16001`.

## Current verified client

The beta installation's `WowB.exe` file/product version and the running process
at `D:\World of Warcraft\_classic_beta_\WowB.exe` were independently inspected:
both report `1.60.1.69913`. The user also confirmed runtime interface `16001`.
The guard now accepts exactly version `1.60.1`, build `69913`, and the explicit
Forever package marker. Other builds, including the superseded `69893`, are
rejected. The rejection message describes an unverified running client without
referring to Phase 1.

## Live equipment acceptance

The user confirmed a successful real `/wowsync` export on Hallo on build
`69913`: slot presence, itemRef, name, item level and required level are correct.
This historical equipment milestone preceded later live effective-stat, bank,
trainer, playtime, and spell observations; see current Forever documents.
The equipment regression fixture checks each accepted field, confirmed empty
slots, delayed refreshes and unavailable/restricted data. Its item values remain
explicitly synthetic. A second fixture preserves the user-provided live level-6
equipment values (export `1789704998`) and checks all 19 rendered rows, including
the nine equipped item variants and ten confirmed empty slots.

The original source audit and level-4 export below were captured on `69893`;
their evidence is preserved, not relabeled as build `69913`.

## Equipment adapter

The Forever-only collector normalizes location-based item APIs into the
existing `slots`/item structure and reuses the unchanged WOWSYNC v1 renderer.
It observes slot, item ID/variant reference, name, current item level and
required level. Missing or restricted values remain `?`. Only an explicit
`DoesItemExist == false` yields EMPTY; an unknown slot has an unknown row,
and total unavailability leaves the section UNKNOWN. Cache/equipment events
use existing shared core handlers, with bounded retries for pending metadata.

The exact Blizzard UI source mirror audited is commit
[`4d5d706b8e01c5ebe01c8dd9b7a07151d8d37069`](https://github.com/Gethe/wow-ui-source/tree/4d5d706b8e01c5ebe01c8dd9b7a07151d8d37069),
whose `version.txt` is `1.60.1.69893`:

- `Blizzard_APIDocumentationGenerated/PaperDollInfoDocumentation.lua`:
  `C_PaperDollInfo.GetInventorySlotInfoForInvSlot` validates slot mapping.
- `Blizzard_ObjectAPI/Mainline/ItemLocation.lua`: equipment-slot constructor.
- `Blizzard_APIDocumentationGenerated/ItemDocumentation.lua`:
  `C_Item.DoesItemExist`, `GetItemID`, `GetItemLink`, `GetCurrentItemLevel`,
  and `GetItemInfo` (name return 1, required level return 5).
- `Blizzard_UIPanels_Game/Camelot/PaperDollFrame.lua` uses equipment
  ItemLocations and `C_Item.DoesItemExist` in the build's UI implementation.

The directories named Mainline in this source tree do not select the addon
target. Forever retains its explicit TOC marker and version/build guard.
These source contracts support guarded implementation, not a claim of live
equipment acceptance by themselves. Unexpected runtime behavior stays unknown.

## Effective stats: live-validated conservative mappings

Retail's `WoWSyncCompat.GetEquipmentStats` reads a structured
`C_Item.GetItemStats(itemLink)` table, filters numeric exposed values, and
requires `C_TooltipInfo.GetInventoryItem("player", slot)` with populated lines
before the shared collector calls the result ready. Its renderer emits the
normalized `{name,value}` values in the existing `effectiveStats` column.

The Forever build-69913 generated item contract is materially weaker:
`C_Item.GetItemStats(itemLink)` accepts only an item link and returns an
untyped `LuaValueVariant`; it has no `ItemLocation` argument and no stated
equipped/effective semantics. `C_Item.GetItemInfo(itemInfo)` supplies identity
and static metadata (including name, level and required level), while
`C_Container` supplies physical item/container state; neither supplies stat
values. The equipment item location does provide the observed current item
level, but no equivalent resolved-stat payload. No validated Forever tooltip
data path has been captured that establishes a replacement semantic.

Hallo live evidence establishes two equipped-item mappings: Ragged Leather Vest
returned `RESISTANCE0_NAME=31`, matching its `31 Armor` tooltip line, and
Anvilmar Knife returned `ITEM_MOD_DAMAGE_PER_SECOND_SHORT=1.875`, matching its
rounded `1.9 damage per second` tooltip line. The Forever-only collector emits
these as `Armor=31` and `Damage Per Second=1.875` in the unchanged `{name,value}`
WOWSYNC v1 effective-stats schema. A tooltip is not a runtime requirement: the
live comparison established the mappings, so a numeric table from an already
observed equipped item is sufficient. Nil stats are cache-pending and use the
existing bounded item-data retry. Empty/malformed/secret values and unknown
keys remain unrepresented with partial coverage; min/max damage and weapon
speed are never derived from tooltip text.

Before the live comparisons, even a table-shaped Forever `GetItemStats` result was not copied
into `effectiveStats`: it could be static/base link data rather than the
equipped item’s effective values. The column stays `?`; generic/base stats and
tooltip text are not guessed to mean effective stats. Regression tests cover
populated, malformed and nil variants to prevent accidental normalization.

After installing this build manually, capture a `/wowsync` export and compare
the equipped slots with Hallo's character panel. Confirm a known empty slot
is EMPTY, occupied slots show their item references, and changing equipment
refreshes the observation. Re-export after item metadata has loaded.

For an occupied slot (replace `5` if the chest is empty), capture these exact
read-only checks, including nil values and any errors:

```text
/dump C_PaperDollInfo.GetInventorySlotInfoForInvSlot(5)
/dump C_Item.DoesItemExist(ItemLocation:CreateFromEquipmentSlot(5))
/dump C_Item.GetItemID(ItemLocation:CreateFromEquipmentSlot(5))
/dump C_Item.GetItemLink(ItemLocation:CreateFromEquipmentSlot(5))
/dump C_Item.GetCurrentItemLevel(ItemLocation:CreateFromEquipmentSlot(5))
/dump C_Item.GetItemInfo(C_Item.GetItemLink(ItemLocation:CreateFromEquipmentSlot(5)))
/dump C_Item.GetItemStats(C_Item.GetItemLink(ItemLocation:CreateFromEquipmentSlot(5)))
/dump C_TooltipInfo and C_TooltipInfo.GetInventoryItem and C_TooltipInfo.GetInventoryItem("player", 5)
```

Record the equipped tooltip text alongside the stat table. To establish
effective semantics, include an actually available item with displayed stats
and any naturally available damaged/enhanced variant; report absent cases
rather than fabricating them. Do not implement stats until those results
establish the shape and meaning of the returned values.

## Regression evidence and scope

The real level-4 export is preserved in `tests/fixtures/forever/hallo-level4.lua`.
Character/location replay must render byte-identical sections. The level-4
capture is the current baseline; a historical level-1 capture is not required
for equipment validation and its summary is not expanded into fabricated data.
Equipment fixtures are synthetic and cover empty, missing, partial, delayed,
restricted, inconsistent and changed API responses.

No changes are made to shared core, renderers, other client adapters,
BankCleanup or SavedVariables. The equipment package was installed with user
authorization and verified against its manifest. This document preserves Phase
2 evidence; later Forever work is recorded separately.
