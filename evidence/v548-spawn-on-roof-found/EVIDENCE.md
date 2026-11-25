# `S04-032` attempt 2: found why my shots miss — enemies can spawn on overhead platforms (place 548)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. **No source changes**; probe and watcher removed.

## What I measured

Spawned a `Rifleman` 16 studs ahead of the player, then read its **real** bounding box instead of moving a part:

```
model:GetBoundingBox() -> centre 0.00, 800.08, 5.19   size 4.5 x 6.2 x 2.5
player position        -> 0.00, 766.5,  21.8
```

The enemy sat **34 studs directly above the player**. Aiming at its true centre still produced `hits=nil`, because the shots were blocked by the platform between us — not mis-aimed.

## Root cause of the offset (found, not guessed)

`EnemyService.spawn`:

```lua
local ground = workspace:Raycast(position + Vector3.new(0, 40, 0), Vector3.new(0, -160, 0), groundParams)
local groundY = ground and ground.Position.Y or position.Y
local model = buildModel(def, CFrame.new(Vector3.new(position.X, groundY + 3.1 * scaleHint, position.Z)) ...)
```

The ray starts **40 studs above** the requested point. If a platform sits above the player within that window, the ray begins *above the platform* and its first hit is
the platform's **top** surface — so `groundY` becomes the roof and the enemy is placed on top of it. Requested Y 766.5, spawned at 800.08: a 33.6-stud lift, exactly
what the 40-stud probe window allows.

**This is a real spawn-placement defect**, independent of my thrashing: an enemy can appear on a roof or gantry instead of beside the player whenever the spawn point
is under geometry. It also explains the inconsistent hit results across this batch — same aiming code, different nearby geometry.

## `S04-032` remains PARTIAL

Unchanged from last batch: **server-confirmed damage is verified exactly** (12 shots, `Hits=12`, shield 80→0, health 240→104, arithmetic exact to the point), while
**hitmarker/kill delivery to the client is unverified**. This attempt failed for a newly understood reason rather than an unknown one — the target was unreachable
through intervening structure.

## Fix for the next attempt (cheap and specific)

Spawn the enemy **where the ray cannot be captured by overhead geometry** — for example raise the probe 40 studs with nothing above it, or spawn then explicitly
verify `(model:GetBoundingBox().Position - playerPos).Magnitude < 25` before firing, retrying elsewhere if not. Then aim at the verified box centre and read the
`LocalScript` feedback log.

## Also worth fixing eventually

`EnemyService.spawn` should reject a ground hit that is **above** the requested Y (a roof) and fall back to `position.Y`, or clamp `groundY <= position.Y + small
tolerance`. Not changed here: it alters spawn behaviour for every encounter, and the current placement has not been measured in real mission contexts yet.
