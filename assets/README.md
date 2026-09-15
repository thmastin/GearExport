# WoWSync icon artwork

`WoWSyncIcon-source.png` is an unchanged copy of the user-supplied download
`ChatGPT Image Sep 15, 2026, 12_41_27 PM.png`. Original SHA-256:

`49c857b2a9f6d3d83ce555b6e605d9942f422fadf697b516a6411832933f3eab`

The runtime asset is `../WoWSyncIcon.tga`: 256x256, uncompressed true-color TGA,
32-bit BGRA with eight alpha bits and bottom-left origin. The complete square
composition is resized with bicubic interpolation. There is no crop, redraw,
added text, recoloring, or generated replacement. Only the TGA ships in client
packages; the original PNG stays here for archival and future format conversion.

Reproduce on Windows with the built-in System.Drawing library:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/convert-icon.ps1
```

The execution-policy override is local to that process; no system setting changes
or external conversion dependencies are needed. Packages use the prebuilt TGA.

All targets use `Interface\AddOns\GearExport\WoWSyncIcon.tga` in TOC
`IconTexture` metadata. The existing installation folder remains `GearExport`.
Blizzard's AddOns-list source reads this metadata on
[Anniversary](https://github.com/Gethe/wow-ui-source/blob/classic_anniversary/Interface/AddOns/Blizzard_AddOnList/AddonList.lua),
[Classic Era](https://github.com/Gethe/wow-ui-source/blob/classic_era/Interface/AddOns/Blizzard_AddOnList/AddonList.lua),
and [Retail](https://github.com/Gethe/wow-ui-source/blob/4e3cbb8c5609e4bfc332c0aebbfa4d79731fab59/Interface/AddOns/Blizzard_AddOnList/AddonList.lua).
One power-of-two TGA serves all clients; no client-specific variants are needed.

The converted TGA was decoded for visual inspection at 256, 64 and 32 pixels.
The central W and arrows remain recognizable; fine text loses detail at small
sizes. Tests verify source preservation, TGA dimensions/header/payload, every
TOC path, and packaged bytes/hashes. Actual AddOns-list appearance still needs
an in-client check after installing the updated package and reloading WoW.
