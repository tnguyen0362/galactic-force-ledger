# `S04-032`: server-side damage confirmed exactly; client feedback delivery unproven (place 548)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. **No source changes**; the temporary probe and observer scripts were removed.

## Proven: the server confirms actual damage, and the arithmetic is exact

A `Rifleman` (240 HP, 80 shield) was spawned and frozen 18 studs down the aim line, then 12 well-formed shots were fired at the remote:

```
Accepted=12  Hits=12  LastDamage=18  LastShieldHit=Rifleman  TotalDamage 249 -> 465 (+216)
enemy: shield 80 -> 0      health 240 -> 104
```

12 × 18 = 216 total damage. Shield absorbed 80, so health should fall by 216 − 80 = **136** → 240 − 136 = **104**. It did, exactly. Damage is
server-computed, server-applied, and internally consistent — the client never sent a damage value (`S04-030` established the payload has no damage field).

## Not proven: the client receiving hitmarker/kill feedback

`CombatService` does fire `DamageFeedback:FireClient` with `damage`, `weakPoint` and `killed` (three call sites: explosive, enemy hit, structure). The client
weapon script consumes it for hitmarkers and `HUD.showKill`.

**I could not observe that delivery.** Three attempts:

1. Tool-VM client listener → empty. Likely the connection does not persist beyond the tool call.
2. Persistent `LocalScript` observer writing to a `StringValue` → empty, **but** `GFDebug.Hits` was never created in that run and `LastMiss` was set, so **all
   shots missed** — the observer had nothing to receive.
3. Replaced the enemy relative to the *current* character position (10 studs, same height) → `hits=nil` again, i.e. **still missing**, so again inconclusive.

So the null result is consistent with a miss, not with a broken payload. It proves nothing either way, and I am not claiming the hitmarker or kill path either way.

## Why the misses are plausibly a probe artefact

`EnemyService.spawn` ground-snaps from a 40-stud raycast (`groundY + 3.1 * scaleHint`). My probes then moved **only `PrimaryPart`** to the desired position. If
the model's hit parts are not welded to the primary part, the hitboxes stay at the snapped position while my aim follows the part I moved — so the ray passes
through empty space. That would explain one batch hitting 12/12 and later runs hitting 0, with identical aiming code.

## Ledger effect

`S04-032` → **PARTIAL**: "server confirms actual damage" is measured exactly; "hitmarker and kills" are **not** verified.

## Next step

Spawn the enemy, then read the model's **actual hit-part position** (or `GetBoundingBox`) and aim at that, rather than at a part the probe relocated. Then re-run the
`LocalScript` observer to confirm `killed=true` arrives on a real kill.
