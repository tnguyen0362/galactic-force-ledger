# `recoil` and `movingAccuracy` wired — plus two sign bugs, one of them mine (place 493)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 493**.

## The data decided the sign, and I had it backwards

The spread model from place 492 used `1 - recoilCut`. Then I read the actual augment data:

```
StabilityCompensator -0.15   BorePolish -0.12   LightBolt -0.10   HeatSink -0.18
StableStock -0.20            MasterworkBore -0.25   RazorBolt -0.12   CounterweightDrum -0.14
```

**Every recoil value is negative**, and negative means *less dispersion*. So `1 - recoilCut` was **increasing** spread by up to 25%
for augments whose entire purpose is to reduce it. Corrected to `1 + recoilCut`.

## Worse: my own clamp from place 490 deleted the whole stat

The clamp table added an hour earlier does `math.clamp(v, 0, cap)` — floor at 0. With every recoil value negative, **that zeroed all
eight recoil augments outright**. The spec's "negative floor 0" reads naturally, but it cannot apply to stats whose benefit *is* a
negative number.

Fixed with a signed-clamp set:

```lua
local SIGNED = { recoil = true, adsSpeed = true, movingAccuracy = true }
-- those clamp to [-cap, cap]; everything else floors at 0
```

`adsSpeed` belongs there too — its only augment is `-0.08`. `movingAccuracy` carries **both** signs in the data (`Bipod +0.2`,
`LongBarrel -0.05`), so symmetric clamping is the only safe treatment.

## `movingAccuracy` implemented

Firing with `AssemblyLinearVelocity > 2` widens the cone by 1.5°, reduced by a positive `movingAccuracy` value. **The 1.5° base
penalty is mine** — the spec names the stat but authors no magnitude.

## Measured

```
stand                 0.600
moving                2.100     = 0.600 + 1.5 penalty
+ MasterworkBore      0.450     = 0.600 x (1 + -0.25)      recoil now REDUCES spread
recoil attribute      -0.25     survived the signed clamp   (floor-0 would have zeroed it)
```

Under the old formula the same augment would have produced `0.750` — a 25% *penalty* on a stat named "recoil reduction".

## Limits

- `movingAccuracy` was exercised only with nothing equipped (`moveBonus = 0`); neither `Bipod` nor `LongBarrel` was equipped, so the
  augment side of that stat is unverified.
- Movement was simulated by writing `AssemblyLinearVelocity`, not by walking, so the real velocity magnitudes players produce are
  unmeasured.
- The 1.5° moving penalty and the `> 2` studs/s threshold are both my invention.
- Only `AR01` was used; no ADS+movement combination was measured, so the two penalties stacking is unverified.
- Shotgun pellet paths still do not consult spread at all.
