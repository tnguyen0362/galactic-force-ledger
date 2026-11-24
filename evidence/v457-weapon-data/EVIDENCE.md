# Weapon stats aligned to spec, AR-01 verified (build 457)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## What was wrong
`Configs/Weapons` held reasonable balance numbers, but five of the eight weapons disagreed with the authored rows in the checklist. Nobody had compared them.

| Weapon | Field | Spec | Was | Now |
|---|---|---|---|---|
| AR-01 | damage / reload | 18 / 2.1 | 22 / 2.2 | **18 / 2.1** |
| P-01 | damage / rpm / reserve / reload | 22 / 300 / 72 / 1.5 | 26 / 400 / 96 / 1.6 | **22 / 300 / 72 / 1.5** |
| SG-04 | rpm / reserve | 72 / 42 | 90 / 36 | **72 / 42** |
| MR-07 | damage / rpm / mag / reserve / reload | 51 / 150 / 12 / 72 / 2.4 | 65 / 180 / 10 / 60 / 2.6 | **51 / 150 / 12 / 72 / 2.4** |
| LMG-12 | damage / rpm / reserve / reload | 17 / 660 / 225 / 3.7 | 20 / 650 / 300 / 4.5 | **17 / 660 / 225 / 3.7** |

SMG-03, GL-22 and RL-09 already matched spec exactly and were left alone.

## Verified after the change
Firing AR-01 at an Officer from 12 studs, five client shots:

| Reading | Value |
|---|---|
| `GFDebug.LastDamage` | **18** |
| `Hits` / `Accepted` | 5 / 5 |
| `TotalDamage` | **81** |
| Officer shield | 160 → **79** |

81 is exactly 5 × 18 × 0.9 — so armour is applied to the incoming amount **before** shields soak it, and the config value is what the server actually uses.

That also explains the previous batch's odd "6.6 per shot": the server was running a different `Weapons` module instance than the one I read (a known module-cache quirk in this harness). With the config reloaded, the two agree.

## Design question this raises
`CombatService.damageEnemy` applies `armorFactor` **before** shields, so a Heavy at 0.75 reduces damage that lands on its shield, not just its health. The spec describes armour as a *health* factor. If shields should absorb pre-armour damage, this is a behaviour change — recorded, not silently changed.

## Limits
- Only AR-01 was fired. P-01, SG-04, MR-07 and LMG-12 changed values but were not re-fired.
- Reload durations changed on four weapons but **no reload was performed** — the reload path (`ReloadWeapon`) is unverified.
- Mag/reserve changes were not validated through an actual magazine dump.
