# Six armour suits + the armory anchor bug (build 420)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client. Character kept **anchored** for every station test (see the rule added at build 418).

## Armour did not exist
No `Configs/Armor` entry, and `AppearanceService` built one hardcoded kit (navy fatigues, off-white plates, cyan visor) with colour constants. The profile carried `armor = "Standard"` and nothing read it.

## Implemented
- `Configs/Armor`: **six** suits — STANDARD, RECON, SIEGE, VANGUARD (rank 1/3/6/9, 0/400/800/1200 cr) and two requisition suits TROPHY (rank 12, 2200) and BLACKSTAR (rank 16, 3200). Each carries plate/fatigue/accent/dark/steel colours.
- `AppearanceService.dress(character, suitId)` is palette-driven and tags every kit part `GF_KitPart`, stripping the previous kit first so plates cannot stack. It sets `character.GF_ArmorSuit`.
- `ArmoryService.buyArmor/equipArmor`, `profile.ownedArmor` (STANDARD owned by default), and `state.armor` with owned/equipped flags.
- Armory UI renders an armour row per suit with `WEAR`, `BUY <cost>`, `LOCKED · RANK n` or `WORN`.

## Measured
| Check | Result |
|---|---|
| `state.armor` | 6 rows with tier, rank, cost, owned/equipped flags |
| Buy SIEGE | `GF_ArmorBought = "SIEGE:800"` |
| Equip SIEGE | `GF_ArmorEquipped = "SIEGE:true"`, `GF_ArmorSuit = "SIEGE"`, **12** kit parts, chest plate `0.808, 0.745, 0.620` = RGB(206,190,158) |
| Buy + equip TROPHY | suit `TROPHY`, chest plate `0.471, 0.329, 0.376` = RGB(120,84,96), kit parts still **12** (no stacking) |
| Buy BLACKSTAR at rank 15 | refused `requires rank 16` (`GF_ArmoryRejected`) |
| UI rows | `ArmorSTANDARD -> Wear`, `ArmorSIEGE -> Wear`, `ArmorRECON -> Buy`, `ArmorVANGUARD -> Buy`, `ArmorTROPHY -> label` (worn), `ArmorBLACKSTAR -> label` (locked) |

## Real bug found: the armory anchored to an arbitrary rack
The station has **three** armory racks (z = −26, 0, +26). `findAnchor()` returned the first descendant it happened to walk into, so a player standing at the z = −40 approach was measured **66 studs** from the anchor rack (limit 46) and the panel closed on every Heartbeat frame — it opened for one frame and vanished.

Fixed by returning the **nearest** rack. Measured after the fix: `Panel.Visible` stayed `true` across eight consecutive samples with 55 rows rendered.

## Limits
- The armour `WEAR`/`BUY` buttons were **not clicked**: those rows sit below the scroll viewport, so a synthetic click on the instance path does nothing. The same closure shape was click-verified for loadout slots at build 418, and the remote path is verified above, but this is not a click proof.
- Armour is cosmetic only; no piece-level inventory (`S01-019`) and no stat effect.
- Only two of six suits were worn; RECON and VANGUARD were never equipped.
- Persistence across a rejoin untested.
