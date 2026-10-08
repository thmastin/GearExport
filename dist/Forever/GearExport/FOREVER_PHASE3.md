# Forever build 70245: API probe and scoped capture

## Runtime evidence

Hallo's running client and the isolated `ForeverGearProbe` SavedVariables
snapshot report `GetBuildInfo()` = `1.60.1`, build `70245`, date `Oct 5
2026`, interface `16001`. The probe version is `0.1.0`; its snapshot timestamp
is `2026-10-08T11:48:15Z`. This is runtime evidence for that capture only.

The build-70009 production guard was not bypassed. A 70245 package revision
must match version, build, interface, and the explicit Forever TOC marker.

## APIs observed

- `ItemLocation:CreateFromEquipmentSlot(slot)` returned a location object;
  `C_Item.DoesItemExist`, `GetItemID`, `GetItemLink`, and
  `GetCurrentItemLevel` returned usable values for occupied equipment slots.
- `C_Item.GetItemLink(location)` returned a complete colored hyperlink with an
  embedded `item:` string. The probe persisted the exact hyperlink and exact
  item string. Representative captured values included
  `item:1364::::::::8:1485:::::::::` and
  `item:2195::::::::8:1485::11:::::::`.
- `C_Item.GetItemInfo(hyperlink-or-itemID)` returned an 18-value tuple in this
  sample. Its name, link, quality, item level, minimum level, class/subclass
  labels, equip location and numeric metadata were retained as raw returns by
  the probe. Passing an `ItemLocation` raised a usage error. This does not
  establish that every tuple field has the same meaning on every item.
- `C_Item.GetItemInfoInstant(link-or-itemID)` returned seven values in the
  captured equipment sample, including item ID, class/subclass labels, equip
  location and numeric class/subclass values.
- `C_Container.GetContainerNumSlots` and `GetContainerItemInfo` were observed
  across carried container indices 0..5. The observed capacities were
  20, 6, 6, 6, 0, 0; 29 occupied rows had exact hyperlinks, stack counts and
  boolean `isBound` fields, and nine slots returned nil. These are one
  character's sampled carried containers, not account-wide coverage.
- `C_Item.IsEquippableItem` returned true for the already equipped samples.
  This only describes those existing equipped observations; it does not prove
  that an unequipped candidate is legal for Hallo or another character.
- `C_ClassTalents.GetActiveConfigID()` returned `1195360`;
  `C_Traits.GetConfigInfo(1195360)` returned a table naming `Hunter`, one tree
  ID, config ID, type, and shared-action-bar flag. This is partial active-config
  context, not a full talent allocation or build string.

## Missing or ambiguous evidence

- `C_Item.IsBound` exists, but the probe's candidate call passed the wrong input
  type. The runtime usage error says it expects an `ItemLocation`. Its correct
  return on an equipment location is therefore UNKNOWN. Container
  `isBound=true/false` is an observed stack facet only and does not prove
  transferability.
- `C_Item.GetItemBindType`, `IsAccountBound`, `GetItemProfession`, the
  candidate required-skill functions, and `C_Item.IsItemBound` were unavailable
  in the sampled API surface. `GetItemInfo` includes a bind-type position in
  its usage signature, but no build-matched Blizzard source was found to
  independently establish that field's contract.
- `GetWeaponSkill`, `GetNumSkillLines`, `GetSkillLineInfo`, and the tested
  `C_WeaponSkill` functions were unavailable or errored. A
  `C_SkillInfo.GetSkillLineInfo` function exists but requires an index; no
  enumerator or UI-correlated current/max weapon skill was observed.
- Trainer API names were partly present, but the trainer window was closed.
  All trainer data calls were correctly recorded as `NOT_OBSERVED` and were not
  invoked.
- Several classic talent/specialization calls were unavailable. The class
  talent config context remains partial.
- This machine had no Blizzard UI source matching 1.60.1.70245. The available
  upstream beta mirror reports a different build and was not used as a contract.

## Capture contract for this package revision

This revision is intentionally limited to runtime-observed character identity,
build, equipment and carried-container paths. Location is not collected.
Character data includes race as observed, while faction, money, XP, playtime,
and unprobed location fields remain unknown. Equipment retains exact
itemString, location-specific item level and required level. Effective stats
remain unknown because 70245 values were not correlated with its UI tooltip.
Carried items retain physical stack rows,
exact itemString, quantity and the direct `isBound` facet. The reader scans
only indices 0..5 observed as carried containers, checks the range for drift,
and rejects locked, malformed, inconsistent or changing input. It does not
scan bank storage.

Bank, trainer, profession, spell, and skill collectors from the earlier
70009 package are not registered for 70245 until their contracts receive a
separate build-matched audit. Empty equipment requires an explicit false from
the item-presence API. Missing values remain unknown. Neither equippability
metadata nor binding flags are interpreted as allocation eligibility or item
transferability.

The package keeps the existing WOWSYNC v1 text shape and SavedVariables
names. Retail, TBC and Classic Era TOCs and behavior are unchanged. BankCleanup
is not loaded by the Forever package and was not edited.

## Live validation remaining

Local tests and static review do not validate a production addon on the live
client. Before claiming completion, preserve the currently installed GearExport
folder and SavedVariables, deploy the reviewed 70245 package, have the user
reload once and run `/wowsync`, then read the resulting SavedVariables directly.
Compare the real export with this probe snapshot and a read-only character
panel. A correct `C_Item.IsBound(ItemLocation)` probe and trainer/skill evidence
can be added separately when those specific questions matter.
