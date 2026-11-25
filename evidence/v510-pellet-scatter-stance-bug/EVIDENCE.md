# The 70-stud mystery was a bug in my pellet code (place 510)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 510**.

## What the previous batch left unresolved

Firing SG-04 at 70 studs produced **0 damage**, and I recorded the cause as unknown: either scatter genuinely missing, or a probe artifact.

## The probe artifact was real, and so was a code bug

**Artifact:** the first shot of any range sweep used a stale root position — `dist=750.7` on the first iteration, because I computed the aim
immediately after writing `root.CFrame`, before physics settled. Adding `task.wait(0.4)` and recomputing origin **after** the teleport fixed that
measurement.

**Real bug, in my own place-508 pellet loop:**

```lua
local angle = tonumber(weapon.adsSpread) or tonumber(weapon.spreadBase) or 1
```

that always used **ADS** spread, even when hip-firing. For SG-04 that is **4.5° instead of 0.15°** — a 30× wider cone than the stance calls for,
so most pellets sailed past a torso beyond ~30 studs. Fixed by hoisting `isAiming` and applying the same stance rule the primary spread uses:

```lua
local angle = (isAiming and (tonumber(weapon.adsSpread) or tonumber(weapon.spreadBase) or 1))
    or (tonumber(weapon.spreadBase) or 1)
```

## Measured after the fix

```
12 studs: delta=96.0  (h 210→174, sh 60→0)   dist=6.4
40 studs: delta=22.1  (h 210→210, sh 60→38)  dist=37.7
70 studs: delta=0.0                          dist=69.0
85 studs: delta=0.0                          dist=88.3
```

**`96.0` is the number that matters** — exactly the authored `8 × 12`, split as 60 shield and 36 health. That confirms this row's central figure for
the first time, and it only appeared once the stance bug was fixed.

## What remains unexplained

Mid-range damage is **partial and inconsistent**: 22.1 at ~38 studs means only about two of eight pellets landed. With `spreadBase 0.15°` the cone
at 38 studs is under a tenth of a stud wide, so all eight *should* connect. Either `spreadBase` is not 0.15 for this weapon in practice, or the
per-pellet jitter is being applied in a way I have not accounted for.

I have not solved it, and I am not going to guess: the honest statement is that **point-blank damage is correct and verified, mid-range pellet
behaviour is not**, and something in the scatter maths is still off.

## Note on the earlier 196.8 reading

That was headshots at 6 studs with the 4.5° cone. With the stance fix the same shot now reads 96.0 on the body — which means **my previous batch's
explanation of 196.8 was itself partly a consequence of the bug**, not merely of weak-point multipliers. It was a correct explanation of *that
measurement* but the measurement was distorted.
