# The fire path works; three of my probes were misbuilt (place 522)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Verification only.

## Purpose

The previous batch recorded an unresolved anomaly: *"a live shot into a spawned enemy returns 0 damage with no rejection reason."* This batch chased it
to ground. **The fire path is fine; three separate defects were in my probes.**

## Defect 1 — I read the wrong attribute container

`CombatService`'s diagnostics do not write to `workspace`:

```lua
local function note(key, value) debug():SetAttribute(key, value) end   -- writes to workspace.GFDebug
```

So `GF_LastReject`, `GF_Accepted`, `GF_Hits` never existed on `workspace`. Every "no rejection reason" reading was **nil because I was looking in the wrong
folder**, which made a rejected shot look like an accepted-but-silent one.

## Defect 2 — my own earlier probes poisoned the shot sequence

```lua
if not shotId or shotId <= s.lastShotId then return reject(...) end
```

Another probe in this project had fired with `shotId = math.random(1e6)`, so a subsequent test passing `4242` was **rejected as stale** and produced no
damage. Using `s.lastShotId + 1` made every shot land.

## Defect 3 — I expected `damageEnemy` to apply the multiplier

I called `damageEnemy(model, 18, player, "Head", 2)` and measured 18, concluding the multiplier was ignored. Reading the function shows the `mult`
argument is only a **flag** for augment bonuses:

```lua
if augs and mult and mult > 1 then amount = amount * (1 + augs.weakPoint) end
```

The hit multiplier is applied by the **caller** — `fire` does `damage = damagePerPellet * falloff * mult`. My test bypassed the only place that applies it,
so it proved nothing. The multiplier is real.

## What the fixed probes establish

```
torso shot through fire:      18.0        (= AR01 base damage exactly)
weakMultiplier("Head"):       2.00        (both head parts)
weakMultiplier("Torso"):      1.00
aim ray at Head part:         hits "Head"
aim ray at Torso part:        hits "ChestPlate"   <- chest plate is in front of the torso
marked WeakPoint attributes:  none on any rig part
```

So: **body damage is exact**, the head multiplier is **2.00 against the authored 1.5**, and the *marked weakpoint* concept has no data behind it.

## One thing I still cannot measure

An end-to-end headshot through `fire` returned 18 rather than 36 — because the enemy is moving, and the ray that the server casts hits `ChestPlate` (in front
of `Torso`) as often as `Head`. A separate `workspace:Raycast` sampled moments later hit `Head` cleanly, showing the geometry allows it.

To verify headshot damage live, the target must be stationary between aim and fire. I did not achieve that here, so the ×2 applies to a **proven multiplier and
proven caller path** but not to a measured in-play headshot.

## Method note

All three defects have the same shape as the rest of this session's errors — **a probe that encoded an assumption about where state lives, what a parameter
means, or what a prior test did.** The code was correct each time. Before writing "X is broken", confirm the probe observes the mechanism X actually uses.
