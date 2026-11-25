# Two defects fixed and verified against a control (place 551)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 551**.

## Fix 1 — enemies spawned on the ceiling

`EnemyService.spawn` raycast for ground from `position + (0, 40, 0)` downward. Indoors the ray starts *above the roof*, so its first hit was the roof's **top
surface** and `groundY` became the ceiling. Measured last batch: six of six spawns landed ~31 studs above the player.

```lua
local groundY = ground and ground.Position.Y or position.Y
if groundY > position.Y + 2 then
    groundY = position.Y
end
```

A "ground" above the requested point is never valid ground, so the spawn falls back to the requested height.

**Verified:** same spawn call under the same roof — `vertical = 3.1` studs (was 30.9–32.3), `flat = 11.4`. Placement is now level with the player.

## Fix 2 — hitmarkers on corpses

Shots at an already-dead enemy still produced `DamageFeedback` with `damage=18, killed=false` while health correctly stayed 0.

```lua
if enemyModel:GetAttribute("Dead") == true then
    return
end
```

**Verified with a control**, both targets on the aim line at the same height, 4 shots each:

```
corpse (Dead=true, HP 0):  health 0, unchanged,  0 hits
live   (HP 500):           health 428,            4 hits   (500 - 4x18 = 428 exactly)
```

`hits=4` in total — every counted hit came from the live target, none from the corpse. The guard rejects the corpse **before** damage and before feedback, and normal
damage is unaffected.

## Regression check

`CheckRunner`: **`passed=671 failed=17 nonDrift=0`** — identical to before the fixes, all failures still the catalogued spec drifts.

## Notes

- The spawn clamp uses a 2-stud tolerance, so a genuinely uneven surface slightly below the requested point is still honoured while a roof is rejected.
- Enemies deliberately placed on a platform *below* the caller still spawn there; only upward capture is rejected.
- The corpse guard returns early, so the shot still consumed ammo — correct, since a shot into a corpse is a miss for gameplay purposes.
- The roof behaviour was only observable indoors. It is now impossible via `spawn`, but any other code path that places enemies on ceilings directly is not covered.
