# Trait-band rescale: 12 authored bands, 14 config keys, 4 unmapped (place 504)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, plugin-level config inspection against `GOAL_2026-11-24.md` S11-042. No place changes.

## Why this is analysis rather than an edit

Last batch established that trait magnitudes run 3–8× the authored bands and that this is the root cause of the stacked-bonus overshoot
and of the clamp table fighting itself. The obvious fix is to transcribe the authored bands.

**It cannot be done cleanly, because the spec does not cover every key the config uses.** Rescaling only the covered ones would leave the
augment catalog at two incompatible scales — worse than one wrong scale, because rarity would then mean different things per stat.

## The authored bands (S11-042, verbatim)

```
recoil reduction       3–6 / 5–9 / 8–13 / 10–17
reload speed           2–4 / 3–6 / 5–9  / 7–12
magazine capacity      3–6 / 5–10 / 8–15 / 12–20   (round final integer, one-shot excluded)
ADS spread reduction   3–5 / 4–8 / 7–11 / 10–15
range extension        3–6 / 5–9 / 8–13 / 12–18
body damage            1–2 / 2–3 / 3–5  / 4–7
weakpoint bonus        2–3 / 3–5 / 4–7  / 6–10
shield damage          3–5 / 5–8 / 8–12 / 10–16
blast radius           3–5 / 5–8 / 7–11 / 10–15
support cooldown rate  2–3 / 3–5 / 4–7  / 6–10
support damage         2–4 / 4–6 / 6–9  / 8–12
sentry HP              3–6 / 5–9 / 8–13 / 10–17
```

Plus two structural rules: *"Dome duration remains guaranteed 10s (do not alter with Augments)"*, and *"Universal swap reduction ranges
same as reload"* — so `swapSpeed` inherits the **reload speed** bands.

## Mapping to the 14 config keys

| config key | authored band | status |
|---|---|---|
| `recoil` | recoil reduction | mapped |
| `reloadSpeed` | reload speed | mapped |
| `magazine` | magazine capacity | mapped |
| `adsSpeed` | ADS spread reduction | mapped |
| `healthDamage` | body damage | mapped |
| `weakPoint` | weakpoint bonus | mapped |
| `shieldDamage` / `armorDamage` | shield damage | mapped (armour has no separate band) |
| `blastRadius` | blast radius | mapped |
| `cooldown` | support cooldown rate | mapped |
| `swapSpeed` | "same as reload" (S11-051) | mapped by rule |
| **`sentryAmmo`** | — | **unmapped** (sentry *HP* is specified, not ammo) |
| **`movingAccuracy`** | — | **unmapped** (only appears as a negative tradeoff "spread +8–15%") |
| **`adsRecovery`** | — | **unmapped** (distinct from ADS spread reduction) |
| **`followUpSpeed`** | — | **unmapped** (never given a band) |

Also unmapped: `range` has an authored band but **no config key uses it**, so "range extension" is specified but unimplemented.

## What this means

- **10 of 14 keys can be transcribed** from the spec today.
- **4 cannot**, and one authored band (`range extension`) has no consumer.
- A rescale of the 10 would leave `sentryAmmo`, `movingAccuracy`, `adsRecovery` and `followUpSpeed` at 3–8× the others — so a Common
  augment would be weak on recoil and overwhelming on follow-up speed. That inconsistency is worse than the current uniform inflation.

## Recommendation

The owner should supply bands for the four missing keys — or explicitly authorise "match the nearest equivalent" for each — and then the
whole catalog can be rescaled in one pass. That pass should precede any further clamp tuning.

## Confidence

High. Both sides are literal values from the config dump and the spec text, and the mapping is a reading of key names rather than behaviour.
The one judgement call is `sentryAmmo` vs "sentry HP", which I have deliberately *not* treated as equivalent.
