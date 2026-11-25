# Damage and cadence scaling verified live — my earlier "unproven" was a test-world artifact (place 522)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Verification only; no source changes this batch.

## The blocker was a gate, not a bug

The previous batch recorded damage/cadence scaling as *wired but unprovable*, because an enemy 6–9 studs away produced zero shield loss and I
diagnosed "hostiles never engaged".

Two things were wrong with that diagnosis:

1. **Hostiles do engage.** A probe watching the tracked/engaged counters returned `tracked=1 engaged=1 tickErrors=0` — the enemy acquired the player
   and fired.
2. **The damage was swallowed on purpose.** `VitalsService.applyDamage` opens with

```lua
if workspace:GetAttribute("GF_InMission") == false then
    return 0
end
```

My test world had `GF_InMission = false`, so every hit was discarded by design. There was no AI failure, and my earlier "not proven" note was an
artifact of testing outside a mission. Setting `GF_InMission = true` and clearing `GF_DeployGraceUntil` makes the path measurable.

## Damage scaling, measured

```
Normal:  shield 100 -> 28   hits=9  sizes=[8.0 ×9]
Extreme: shield 100 -> 0    hits=8  sizes=[12.8 ×7, 10.4]
```

- Normal delivers **8.0** per hit — the `Rifleman` base damage exactly.
- Extreme delivers **12.8** = 8 × **1.60**, the authored damage multiplier.
- The final Extreme hit is **10.4**, the remaining shield, so shield absorption clamps correctly rather than over-damaging.

## Cadence scaling, measured

```
Normal:  gaps=[0.20, 0.17, 1.30, 0.20]
Extreme: gaps=[1.10, 0.20, 0.17, 1.07]
```

`Rifleman` fires a burst (intra-burst gaps of 0.20 s / 0.17 s) then waits out an attack cooldown. The **post-burst gap shrinks from ~1.30 s to ~1.08 s**,
a ratio of 1.20 — exactly the authored cadence rate — while the intra-burst spacing is unchanged.

That is the correct behaviour for a *rate* multiplier: it scales the attack cycle, not the burst pattern. It also confirms the interpretation flagged last
batch (cadence as rate, not interval), at least in effect.

## What is now proven vs still open

| component | status |
|---|---|
| HP scaling | **verified** — 168 / 240 / 360 / 480 for base 240 |
| Damage scaling | **verified** — 8.0 vs 12.8 per hit |
| Cadence scaling | **verified** — cycle gap 1.30 s → 1.08 s |
| Pressure multiplier | **not implemented** — budget and eliteFrequency are a separate mechanism |
| Shield scaling | **not implemented** — spec column says "HP" |

## Method note worth keeping

This is the inverse of the session's recurring error. I did not assert a wrong number — I asserted *absence of behaviour* and was wrong, because
**an intended gate looked identical to a broken system** from outside. The lesson: before recording "X does not work", check whether something upstream is
deliberately suppressing it. `GF_InMission`, deploy grace and console mitigation are all silencers on this exact path.

## Limits

- Measured with one player, one enemy, one weapon type at one range. Burst structure may differ by archetype.
- `GF_InMission` was forced true, so mission systems were not running normally around the test.
- Shield deliberately raised to 100000 in the cadence probe to keep it from breaking; restored by session end.
