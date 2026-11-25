# `adsRecovery` and `followUpSpeed` wired — but NOT verified, and there is an unexplained anomaly (place 495)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`. Place saved as **version 495**.

**This batch's verification failed.** The code is in and compiles; I am recording it as unverified rather than asserting success.

## Signs, read from the data first (the lesson from the last two batches)

```
adsRecovery:  FastHands 0.15 (Pistol variant), ReflexSear 0.25      positive = helps
followUpSpeed: TargetDiscipline -0.15, PrecisionChamber -0.15       negative = helps
```

Opposite conventions, like `recoil` vs `adsSpeed`. Both fit `1 - bonus`:

- **`followUpSpeed`** multiplies the bloom **decay** rate: `sincePrev * 1.0 * max(0.2, 1 - followUp)` — so `-0.15` recovers 15%
  faster.
- **`adsRecovery`** scales per-shot **bloom growth**, and only while aiming: `perShot * max(0.2, 1 - adsRecovery)`.

## What the measurements showed

```
slot1 ReflexSear=true  slot2 TargetDiscipline=true
adsRecovery=0.25  followUp=-0.15  swap=0.8000590953796903
hip3 = 0.600:bloom=0.35
ads3 = 0.550:bloom=0.35
```

Two problems, both unexplained:

1. **`bloom=0.35` after three shots.** A single `spreadPerShot` for AR-01 is 0.35, and the earlier control run reached `bloom=0.82`
   after three shots. Here only one shot's worth accumulated, so **shots 2 and 3 almost certainly did not reach the spread block** —
   yet the probe reported no rejection. The likely candidates are rate-limiting or a reject path I did not instrument, but I have
   not proven which.
2. **`swap=0.8000590953796903`** — ReflexSear carries `swapSpeed = 0.4`, and 0.8 looks like it is counted **twice**. Two different
   augments were equipped (ReflexSear, TargetDiscipline) and only one of them has `swapSpeed`, so a slot appears to be
   double-counted. Combined with the first anomaly, the loadout table may hold a duplicate entry after repeated probe equips across
   this session.

Neither can be explained without more instrumenting, and guessing would repeat exactly the mistake I have made twice already this
session. So: **wired, not verified.**

## What is actually proven

- `adsRecovery=0.25` and `followUp=-0.15` are read correctly from a real equipped loadout — the `forPlayer` plumbing works for both
  keys, which is the part that was previously dead.
- `hip 0.600` vs `ads 0.550` confirms the ADS spread path still works with two augments equipped.
- The code compiles and the place saved.

## What is not proven

- That `adsRecovery` changes bloom growth in practice — the run that should have shown it produced a one-shot bloom instead.
- That `followUpSpeed` accelerates decay in practice.
- Why the third and second shots did not accumulate bloom.

## Next batch must start here

Instrument the reject path during a burst: publish `rejects`, `lastShotAt`, `ammo` and `lastShotId` per attempt, and dump
`selectedLoadout.weaponAugments` to see whether a slot is duplicated. That will settle both anomalies before any further stat is
wired. Wiring more keys on top of an unexplained measurement would compound the uncertainty.

## Worth noting about this session

Three batches in a row have ended with me correcting or failing to verify a stat I "wired". The pattern is consistent: the
**plumbing** (reading augment tables, clamping, publishing attributes) is reliable, but the **sign and magnitude conventions** of
the authored data are not what I assume, and my probes have repeatedly measured the wrong thing. The remedy that actually works is
the one that found `recoil` and `movingAccuracy`: print the real data and the real intermediate values *before* writing the
formula — and instrument the reject path here.
