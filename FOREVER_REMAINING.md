# Forever current limits and live validation

Build 70009 uses the shared asynchronous `RequestTimePlayed()` request and
`TIME_PLAYED_MSG(total, level)` event handling. Both fields are stored only as
non-negative integer event payloads; no response leaves them `?`. Hallo live
validation supplied `9206` total and `1757` level seconds.

Learned professions use `GetProfessions()` / `GetProfessionInfo(index)`, rather
than `C_TradeSkillUI`'s all-profession enumeration. On Hallo immediately after
`/reload`, before opening Smelting or any other trade-skill window, this
authoritatively returned Cooking `5/75`, Engineering `20/75`, and Mining
`23/75`. This avoids the demonstrated `C_TradeSkillUI` pre-hydration `0/0`
records. A learned `0/75` remains observed; a learned `0/0`, malformed,
restricted, or unavailable tuple remains UNKNOWN. Nil learned-profession slots
produce no fabricated rows. If a later tuple is unavailable, a prior complete
profession snapshot remains LAST_SEEN with its original observation timestamp
and refresh issue until a new authoritative tuple replaces it.

The bank collector only runs during an open bank visit and uses
`C_Bank.CanViewBank(Enum.BankType.Character)` and
`C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Character)`. Each returned ID
is then observed through `C_Container`; negative Classic bag IDs, bank-bag
slots, reagent-bank assumptions and account/warband tabs are deliberately not
used. It was live-validated on Hallo for one purchased tab: returned container
ID `6`, `CharacterBankTab 1`, capacity `48`, explicit empty and Rough Stone
`x3` observations, free-slot/quantity accounting, and LAST_SEEN persistence.

The trainer collector only runs during a trainer visit. Build-70009's
`Blizzard_TrainerUI/Mainline/Blizzard_TrainerUI.lua` consumes
`GetTrainerServiceInfo(index)` as `name, status, texture, requiredLevel`; the
previous adapter incorrectly read it as the Classic `name, rank, status,
expanded` tuple, treating its texture field as a status and returning UNKNOWN.
The corrected adapter preserves status, required level, cost, skill
requirements and ability prerequisites. It was live-validated at Regnus
Thundergranite: representative Hunter services, required levels, costs, and
requirements matched the UI; close retains LAST_SEEN. Rank and spell ID are not
exposed by this tuple and remain `-`/`?`; neither is inferred from the UI index.

Known spells use the documented build-70009 `C_SpellBook` player bank; Hallo
live validation captured 15 visible active player spells correctly. Effective
equipment stats have live-confirmed conservative Armor and Damage Per Second
mappings; unsupported keys remain UNKNOWN/partial.
