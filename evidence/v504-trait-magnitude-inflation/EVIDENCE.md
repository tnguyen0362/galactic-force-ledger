# Trait magnitudes are 3–8× the authored per-rarity bands (place 504)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, plugin-level config inspection. No place changes.

## The authored bands

`GOAL_2026-11-24.md` S11-042 gives sample trait ranges as **percent magnitude, Common/Rare/Epic/Legendary**:

| stat | Common | Rare | Epic | Legendary |
|---|---|---|---|---|
| recoil reduction | 3–6 | 5–9 | 8–13 | 10–17 |
| reload speed | 2–4 | 3–6 | 5–9 | 7–12 |
| magazine capacity | 3–6 | 5–10 | 8–15 | 12–20 |
| ADS spread reduction | 3–5 | 4–8 | 7–11 | 10–15 |
| weakpoint bonus | 2–3 | 3–5 | 4–7 | 6–10 |
| body damage | 1–2 | 2–3 | 3–5 | 4–7 |

## What the config actually carries

```
recoil        Common  BorePolish 9-14, LightBolt 7-12, StabilityCompensator 12-17
              Rare    HeatSink 14-20, StableStock 16-24
magazine      Common  BeltFeed 20-32          Legendary CounterweightDrum 32-48
reloadSpeed   Rare    QuickFeed 10-16, ShellRack 16-26
              Epic    FastHands 16-24, QuickLoad 20-32
weakPoint     Common  Choke 16-24, PrecisionChamber 16-25
              Legendary BreachChoke 22-34, ExecutionerOptic 28-40
```

Every band is inflated, by differing factors:

| stat | config Common | authored Common | ratio |
|---|---|---|---|
| recoil | 7–17 | 3–6 | **~2.5×** |
| magazine | 20–32 | 3–6 | **~5×** |
| weakpoint | 16–25 | 2–3 | **~8×** |
| reload (Rare) | 10–26 | 3–6 | **~3×** |

## Rarity ordering is not respected either

A **Common** recoil augment (`StabilityCompensator 12–17`) overlaps the authored **Legendary** band (`10–17`) and beats every authored
rarity except top-end Legendary. A **Common** weakpoint augment (`16–24`) is roughly four times the authored **Legendary** ceiling
(`6–10`). So rarity does not predict power the way the spec's ladder intends.

## Why this explains earlier findings

This is the same root cause behind three things I recorded separately:

- the measured **47.85% cooldown reduction** and **+85% stacked blast radius** — the data was authored at 3–8× scale, so stacking two
  augments overshoots a 20–25% cap immediately;
- the clamp table I implemented at place 490 (cooldown 0.20, blastRadius 0.25, weakPoint 0.20) **fights** numbers that were never at that
  scale, so clamped augments feel far weaker than their displayed ranges promise;
- `StabilityCompensator` rolling **−0.08** against a declared range of `12–17%` — the roll and the range disagree, which is why my first
  sign fix looked inconsistent.

## Not retuned

Rescaling every trait band to the authored table changes the power of all 36 augments and therefore the whole economy. It belongs in the
same owner pass as the drop distributions, boss HP, cooldowns, mission length and the ADS ratio — and it should probably go **first**,
because the clamp caps only make sense once the underlying magnitudes are authorised.

## Confidence

High for the comparison: both sides are literal numbers, and the config dump is complete for every trait-bearing archetype. What I did
**not** verify is whether the *roll* uses these ranges — `rollTrait` samples them, but I did not test that a Common recoil augment never
exceeds 6% in practice, because the declared range already exceeds it by construction.
