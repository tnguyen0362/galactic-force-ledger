# A spread model exists: bloom, ADS tightening, recoil cut, determinism switch (place 492)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 492**.

I implemented the thing I deferred last batch. The deciding argument: spread is an **authored functional requirement** with
explicit values in the spec table, not a polish item — and the search found the fields already present in config, so the intended
design was clear.

## What was added

**Data:** `adsSpread` did not exist on any weapon — the spec's ADS column had never been transcribed. Added for all eight from
`GOAL_2026-11-24.md` L53–L60: AR-01 0.55, SMG-03 0.85, LMG-12 0.75, SG-04 4.5, MR-07 0.18, GL-22 1.0, RL-09 0.20, P-01 2.2.

**Model**, in `CombatService.fire` immediately before the raycast:

- bloom accumulates by `spreadPerShot` per shot and decays at **1.0 units/s** between shots, capped at 6
- hip fire uses `spreadBase`; aiming uses the authored `adsSpread`
- the `recoil` augment cuts the remainder, floored at 0.4 (already capped at 0.35 by the clamp table)
- jitter is applied by rotating the unit direction about perpendicular axes with `tan`
- **`GF_ForceNoSpread`** disables all of it, so the existing exact-shot evidence (18-shot TTK, 90/240 falloff, `v461`) remains
  reproducible

## Measured

```
hip fire, 6 consecutive shots at 600 RPM:
  0.600 0.817 1.026 1.250 1.467 1.682        <- bloom building per shot
GF_ForceNoSpread = true:  disabled            <- truthful, not stale

hip:  0.600   (spreadBase)
ads:  0.550   (adsSpread, exactly the authored AR-01 value)
```

Two things I got wrong and fixed mid-batch:

1. **Stale attribute.** With the switch on I never wrote `GF_LastSpread`, so the "disabled" run reported the previous
   `0.667` — reading as if spread were still applied. Now published as `"disabled"`. This is the fourth stale-attribute trap
   this session; I walked into it in code I had written ten minutes earlier.
2. **Decay too strong.** At 2.5/s the decay nearly cancelled per-shot growth (`0.600 → 0.667` over six shots, effectively no
   bloom). At 1.0/s the growth is visible and meaningful (`0.600 → 1.682`).

## What is mine, not the spec's

- **Decay rate 1.0/s and the bloom ceiling of 6** are my invention. The spec authors `spreadBase` and `spreadPerShot` but says
  nothing about recovery.
- **The 0.4 floor on the recoil cut** is mine (a 100% recoil reduction would make spread purely `adsSpread`).
- **Jitter shape is uniform, not gaussian** — cheap and symmetric, but a uniform square distribution clusters differently from a
  circular one.

## Limits

- Scatter was verified as an **angle**, not as hit geometry. No target was shot at repeatedly to measure group size, so I cannot
  claim the on-screen cone matches the numbers.
- `recoil` was not exercised: the account has no recoil augment equipped, so `recoilCut` read 0.00 in every run.
- Existing TTK/falloff evidence was **not recaptured**. It remains valid only under `GF_ForceNoSpread = true`, which is a caveat
  now attached to those rows rather than a re-measurement.
- Shotgun pellet logic and launcher paths were not reviewed for interaction with the new jitter.
