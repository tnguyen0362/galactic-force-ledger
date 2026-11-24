# Ability purchases, a duplicate guard, and overlapping buttons (build 426)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## Three fixes
1. **Duplicate slots refused.** Both slots could hold the same ability, wasting one. Measured refusal: `ability already in the other slot`, with `GF_Ability1` left unchanged.
2. **Four of six abilities were unobtainable.** `ArmoryService.buyAbility` charges rank and cost from config. Measured: `Sentry` (rank 4, 900) and `OrbitalStrike` (rank 8, 1800) both bought, `GF_AbilityBought = "OrbitalStrike:1800"`, and the purchased `Sentry` then equipped into slot 1 (`GF_Ability1 = "Sentry"`).
3. **Every alternative drew its button at the same coordinates.** The Ability 1 row rendered `UseDomeShield`, `UseOrbitalStrike`, `BuyOrbitalLance` and `BuyReflectiveBarrier` all at x = 300 — four invisible stacked buttons, only the last clickable. Replaced with one actionable alternative per row that cycles on repeat clicks (the same pattern the augment sockets already use).

## Measured
| Check | Result |
|---|---|
| `equipAbility slot 2 Airstrike` (other slot held it) | refused `ability already in the other slot` |
| Buy `Sentry` / `OrbitalStrike` | both `ok`; credits charged; `GF_AbilityBought` records the last |
| Equip the newly bought `Sentry` | `GF_Ability1 = "Sentry"` |
| Click `Ability1.UseAbility` (label `USE DomeShield`) | `GF_AbilityEquipped = "1:DomeShield"`, `GF_Ability1 = "DomeShield"` |
| Row after the fix | one button, `USE DomeShield @y314`, row at y = 305 — inside the viewport |

The click is the important one: the armory ability button is now **player-reachable and verified**, which the previous batch could not claim.

## Limits
- `OrbitalLance` and `ReflectiveBarrier` cost 0 in config, so the BUY path charges nothing for them — they are effectively free unlocks at rank 10, which may not be intended.
- Grenade rows still have no click test (same row pattern, untested).
- Only two abilities were purchased; the rank gate for `OrbitalLance`/`ReflectiveBarrier` (rank 10) was never exercised from a lower rank.
- Ability *behaviour* was not re-tested beyond the earlier dome cast.
