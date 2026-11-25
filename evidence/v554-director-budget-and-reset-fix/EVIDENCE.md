# Encounter director: per-mission spawn budget added; `reset()` leak fixed (place 554)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 554**.

## Finding 1 — there was no budget, only a concurrency cap

`EncounterDirector` documents itself as *"Budget is capped so a long fight cannot overpopulate the map"*, and the spec requires *"authored mission waves + dynamic
patrol budget, **not infinite spawning**"*. What actually existed:

- `MAX_ACTIVE = 8` — a **concurrency** cap, checked in `spawnAround` and the extraction loop
- `spawnedThisMission` — incremented on every spawn, **never compared to a limit**; only reported by `stats()`

Measured by repeatedly spawning then clearing:

```
spawned: 5 -> 13 -> 17 -> 21, still rising
```

Killing hostiles freed capacity, so the extraction loop could run forever. Total spawns were unbounded.

## What changed

```lua
local MISSION_SPAWN_BUDGET = MAX_ACTIVE * 4      -- 32
...
for i = 1, count do
    if activeCount() >= MAX_ACTIVE then break end
    if spawnedThisMission >= MISSION_SPAWN_BUDGET then break end
```

`stats()` now reports `budget` alongside `active`, `cap` and `spawned`. The value is a **named multiple of the concurrency cap**, not a balance figure invented here —
it is one constant to tune if the owner wants longer or shorter missions.

**Verified by draining the budget:** five rounds of "spawn 8, clear all" placed **exactly 32**, then:

```
post-drain asked=8 placed=0
```

Refused. Unbounded before, bounded now.

## Finding 2 — `reset()` never cleared enemies

`reset()` destroyed `ActiveActors` children that had a `Humanoid`. **Enemies have no Humanoid** (confirmed earlier: `humHP=nil` on a spawned Rifleman), so reset
removed nothing. Measured before the fix:

```
ED.reset() -> EnemyService.count() still 9
```

Those 9 survivors also blocked the concurrency cap, which is how this surfaced: a fresh spawn request placed 0 enemies.

Fixed by also matching the `GFEnemy` attribute:

```lua
if model:FindFirstChildOfClass("Humanoid") or model:GetAttribute("GFEnemy") == true then
    model:Destroy()
end
```

**Verified:** `before=9 afterReset=0`.

## Regression

`CheckRunner`: **`passed=671 failed=17 nonDrift=0`** — unchanged.

## Still open on `S06-035`

- **A mission starts above its own cap.** `beginMission` spawns posts (2) + patrol (4) + an optional commander + a boss without a joint check; measured `active=9, cap=8`.
  Each call respects the cap individually, the combination does not.
- **"Dynamic" patrol budget is static.** `PATROL_COUNT = 4` and the budget is fixed; nothing adapts to squad size, difficulty or elapsed time.
- Extraction pressure is interval-driven (2 every 9 s) rather than authored wave composition.

## Limits

- Verified by driving the director API directly, not by playing a full mission to completion.
- The budget counts every director spawn, including bosses, so a boss consumes one slot of 32.
- Clearing enemies by hand mimics kills; real kills run through `EnemyService`, which also decrements `EnemyService.count()` — that is what the probes relied on and it
  behaved consistently (`count` fell to 0 immediately after destroying models).
