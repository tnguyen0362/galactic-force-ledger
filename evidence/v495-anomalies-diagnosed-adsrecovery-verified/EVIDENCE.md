# Both anomalies diagnosed; `adsRecovery` verified, `followUpSpeed` supported (place 495, no source change)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`. Instrumentation only — no source edits, no place save.

## Anomaly 1: "bloom=0.35 after three shots" — not reproducible, and the cause was my probes

A clean 4-shot run with per-shot instrumentation:

```
slots[2]: 1=FastHands,2=TargetDiscipline
#1 ammo 200->199 spread=0.600:bloom=0.35
#2 ammo 199->198 spread=0.758:bloom=0.51
#3 ammo 198->197 spread=0.917:bloom=0.67
#4 ammo 197->196 spread=1.076:bloom=0.83   reject=nil throughout
```

Every shot accepted, ammo decrementing, bloom accumulating. So the earlier `bloom=0.35` was not a firing fault.

**The real cause:** each of my probes was **mutating the persisted loadout** by equipping a different augment into slot 1. The "baseline" and "with augment" runs were therefore comparing *different loadouts*, and one of them had no spread-affecting augment at all. Dumping the slots alongside the measurement is what exposed it — the diagnostic that should have been in every probe from the start.

## Anomaly 2: `swap=0.8` where only one augment carries it — also my probes

Same root cause: `1=ReflexSear,2=TargetDiscipline` in one run and `1=FastHands,2=TargetDiscipline` in another. The readings were of different loadouts, not a double-counted slot.

## A third finding while trying to isolate the baseline

`unequipAugment` appeared to do nothing. It does work — the signature is:

```lua
function AugmentService.unequipAugment(profile, slot: number): boolean
```

**Two parameters.** My probe called `unequipAugment(profile, "AR01", i)`, so `slot` received the string `"AR01"` and the call wrote `slots["AR01"] = nil` — a silent no-op on a numeric slot table. Worth knowing for callers: slot numbers are a single table per loadout, not per weapon.

## Clean same-session A/B for the two keys

```
A_hip_base  [FastHands,TargetDiscipline]          0.759  bloom=0.51
B_ads_base  [FastHands,TargetDiscipline]          0.885  bloom=0.69
C_hip_mixed [ReflexSear,TargetDiscipline]         0.916  bloom=0.67
D_ads_mixed [ReflexSear,TargetDiscipline]         0.693  bloom=0.41
augs adsRecovery=0.25  followUp=-0.15
```

**`adsRecovery` is verified.** Three ADS shots produced `bloom=0.69` without it and `0.41` with `adsRecovery=0.25`. Predicted with 0.25: per-shot `0.35 × 0.75 = 0.2625`, decay `1.15/s` over 0.15 s (`0.1725`) gives `0.2625 → 0.3525 → 0.4425` — matching 0.41 within timing jitter. Without it, the same arithmetic gives `0.35 → 0.5275 → 0.705`, matching 0.69.

**`followUpSpeed` is supported but not isolated.** `TargetDiscipline` (`-0.15`) was in **both** arms, so there was no no-follow-up control. The observed decay does match `1.15×` baseline rather than `1.0×` (0.69 observed vs 0.65 predicted for no decay boost), which is consistent with the stat working — but that is arithmetic agreement, not an isolated A/B.

## State of the key census

13 of 14 keys are now wired: weakPoint, healthDamage, armorDamage, shieldDamage, magazine, reloadSpeed, adsSpeed, cooldown, blastRadius, recoil, movingAccuracy, adsRecovery (verified), followUpSpeed (supported, not isolated). Never applied: **swapSpeed** (no swap delay exists to scale) and **sentryAmmo** (sentry has no ammo pool).

## What I will not claim

- That `followUpSpeed` works — only that it is plausible and unrefuted.
- Any earlier reading from a probe that did not dump the loadout alongside it. That includes the place-495 "failure"; the code was probably right and the harness was wrong, which is worse, because a wrong harness looks like a passing test.
