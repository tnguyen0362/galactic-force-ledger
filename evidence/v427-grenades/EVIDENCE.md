# Grenades: distinct effects measured; a layout drift fixed (build 427)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## Both grenade types do different things — measured
Three tagged hostiles at the objective (`Marksman` 100 HP / 40 shield, `Officer` 180/100, `Heavy` 260/150), all with `GFEnemy = true`.

| Throw | Feedback |
|---|---|
| `EMP` at the Heavy | `LastGrenade = EMP`, **`LastEmpDrained = 100`**, **`LastEmpStunned = 1`** |
| `Frag` at the Heavy | `LastGrenade = Frag`, `LastGrenadeTargets = 1`, **`LastGrenadeDamage = 57`** |

Neither touched health directly, which is correct: damage lands on shields first, so a 57-damage frag into a 150-shield Heavy leaves HP at 260. The distinction the spec asks for — *Frag kills, EMP opens* — is real in the code and now measured in play.

## A layout defect found by trying to click
Grenade rows rendered at **y = 1313** because their `LayoutOrder` was `6 + order`, and `order` is a shared counter that had already climbed past 300 through the other sections. The grenades were technically in the list and completely unreachable. They now sort at 7–8, next to the ability rows.

After the fix the rows sat at y = 397/439, still partly clipped by the 453-pixel viewport edge, so the click missed once more. Scrolling 80 px put `GrenadeFrag.Equip` at y = 368 and the click landed: `GF_GrenadeEquipped = "Frag"`.

## Measured summary
| Check | Result |
|---|---|
| EMP drain / stun | 100 shield, 1 stunned |
| Frag damage / targets | 57 damage, 1 target |
| Grenade row position | 397/439 (was 1313) |
| Click `GrenadeFrag.Equip` | `GF_GrenadeEquipped = "Frag"` |

## Limits
- Enemy shield totals were unchanged in a later read, which suggests shield regeneration or that the drain hit a different hostile in the radius; the drain counter is the reliable signal, the per-enemy reading is not.
- Frag max-3 charge, EMP rank-4/550-credit unlock (`S04-053`) were **not** verified — only the effect.
- Throw arc, ground preview and the 2.5 s fuse were not timed.
- One client; no co-op.
