# Destructible objectives + Shattered Aegis — measured evidence (place version 387)

Session: 2026-11-24, Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client, attributes read from the Server datamodel.

## New shared capability: destructible objective structures
`ServerScriptService/GF/Services/CombatService`:
- `resolveStructure(instance)` walks up from a raycast hit to a part carrying `GFIntegrityMax`.
- `CombatService.damageStructure(part, amount)` subtracts the falloff-adjusted weapon damage the shot would have dealt to an enemy, writes `GFIntegrity`, and on zero sets `GFDestroyed`, hides and unqueries the part, spawns a short neon burst, and increments `GF_StructuresDestroyed`.
- The shot path now falls through `enemy → structure → miss`, so a single weapon path serves both.
- `GFShielded` is an explicit damage gate. **Measured defect:** `CanQuery = false` alone did not stop damage — six shots at a shielded emitter took it from 700 to 568. The gate is now an attribute check that increments `GF_ShieldDeflected`, and the same six shots then left integrity at 700 with `GF_ShieldDeflected = 6`.

Parts use `GFIntegrityMax`, `GFIntegrity`, `GFStructure`, `GFDestroyed`, `GFShielded`. Nothing else needs to know about weapons; the objective stage machine polls attributes every 0.4 s.

## New variant: Sabotage | Shattered Aegis (`SABOTAGE_AEGIS`)
Stages: destroy two linked generators (300 HP each) → emitter is exposed → destroy emitter (700 HP).

Measured with **real weapon fire** through the `FireWeapon` remote (AR01, 22 damage at that range, 28-round magazine):
| Step | Result |
|---|---|
| Deploy Normal | `GF_DeployRejected` nil, `GF_AegisStage=1`, generators `300/300`, emitter `700/700`, `CanQuery=false`, `GFShielded=true` |
| Six shots at shielded emitter | integrity stayed `700`, `GF_ShieldDeflected=6`, stage stayed 1 |
| Fire at generators | 13 shots → GeneratorA `0`, destroyed; 14 shots → GeneratorB `0`, destroyed |
| Both down | `GF_AegisStage=2`, `GFExposed=true`, `GFShielded=false`, emitter `CanQuery=true` |
| Fire at emitter | 56 shots with two magazine reloads → integrity `0`, `GFDestroyed=true` |
| Final | `GF_ObjectiveComplete=true`, `GF_StructuresDestroyed=3` |

Capture `ScreenCapture_AEGIS_SHIELDED` shows the new objective line `PRIMARY OBJECTIVE / Destroy the shield generators (0 / 2)` in the mission HUD with the compound behind the player.

## Notes on the harness
- The first firing attempts were rejected with `origin-too-far`: a camera-origin shot is more than the allowed distance from `HumanoidRootPart`. Shots fired from `root + (0, 2, 0)` were accepted. Useful for future automation.
- `no-ammo` after 28 rounds, as expected; `ReloadWeapon` then worked.
- The game's debug folder `workspace.GFDebug` carries `Received`, `Accepted`, `Rejected`, `LastReject`, `LastStructure` — the fastest way to tell a rejected shot from a miss.

## Limits
- The variant is destruction only; the spec's "hacking" flavour of Sabotage is still absent (`S08-036`–`S08-043`).
- No defense-object HP or failure path yet: nothing damages the objective, and enemies still target players only.
- Kills of *enemies* in this batch were not re-exercised; only structure damage was (and it is the same code path).
- Solo only; no second client.
