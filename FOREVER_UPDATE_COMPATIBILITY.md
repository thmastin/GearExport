# Forever client-update compatibility

## Runtime policy

Forever identity is gated on the explicit `wow_classic_beta` client marker and
exact client version `1.60.1`. The runtime does not authorize or reject a client
by build number. The `.toc` `Interface` value remains WoW metadata: the game
decides whether to load a stale-interface addon according to the user's **Load
Out of Date AddOns** setting. Changing that metadata requires no Lua build
allowlist update; the package verifier checks that the numeric TOC interface
matches the manifest.

This is not a claim that every future Forever build is API-compatible. Each
collector checks the API and return shape it relies on. Missing, throwing, or
malformed optional APIs leave that section unavailable/partial with a reason;
unaffected sections continue. Captures remain scoped to the observed client
version, build, and interface. When a new build is observed, the previous
profile is archived instead of mixed into the active capture. A wrong client
marker or version is rejected; there is no Retail or Anniversary fallback.

## Evidence and limitations

Builds 70291 and 70338 are the previously observed Forever builds. Build 70291's
capture/export has live evidence; 70338 has source-contract review but this
package has not been live-tested there. Future-build fixtures validate gate and
failure behavior only. They do not establish live WoW API compatibility.

The current account capture, auction-house/economy workflows, and less common
API return shapes remain launch risks. Do not infer missing values from another
client family. Use explicit UNKNOWN/unsupported evidence until the relevant
Forever API is observed and validated.

## Windows live-validation procedure

After this change is committed and independently reviewed, update a clean
Windows GearExport checkout to the exact reviewed commit. With Forever closed,
run the repository's guarded command from a normal PowerShell session (change
only the destination if the actual Forever path differs):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\dev\wow-addons\GearExport\scripts\deploy-forever.ps1" -Destination "D:\World of Warcraft\_classic_beta_\Interface\AddOns\GearExport"
```

The workflow builds and verifies the package, checks Forever version/build
metadata and destination, preserves a verified backup, and verifies exact
installed file hashes. Start Forever, run `/reload`, then `/wowsync`. Save the
export evidence and SavedVariables after a normal reload/logout. Confirm addon
load, export completion, identity/build, supported existing fields, UNKNOWN for
unavailable data, no fabricated values, and no relevant Lua errors. This is the
required live test for any future client build; synthetic fixtures are not a
substitute.
