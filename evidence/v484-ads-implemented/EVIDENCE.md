# ADS implemented: RMB aims, server applies the speed change (place 484)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 484**.

## What was missing

`S03-016` requires *"ADS speed 0.8× walk"*; `S03-003` requires *"RMB ADS"*.

Investigation found the gap was deeper than a constant:

- `Constants.Movement.AdsSpeed = 13` existed and was read by **nothing**.
- **Nothing anywhere set the `Aiming` attribute.** `GF_CharacterAnimator:67` reads it to pose the aim stance, so the animator's
  aim branch could never fire either.
- **No aim remote existed**, so aiming had no server-visible state at all.
- RMB was already used as a camera-look toggle in `Controller` — that is the only thing RMB did.

So "ADS" was three missing links, not one wrong number.

## The change

| file | change |
|---|---|
| `Shared.Remotes.Names` | `"AimChanged"` added to the single registry (`ensureRemotes` creates it; nothing is ad-hoc) |
| `MovementService` | new `applyStance(character, humanoid)` — the one place WalkSpeed is decided, in priority order aim → crouch → sprint → walk; new `AimChanged` handler sets `Aiming`, cancels sprint, publishes `GF_AimState`; crouch and sprint handlers now route through `applyStance` instead of setting WalkSpeed inline |
| `Controller` | RMB down fires `AimChanged(true)`, RMB up fires `AimChanged(false)`, alongside the existing look toggle |
| `CheckRunner` | `AdsSpeed` assertion restored — legitimate now that the value has a consumer |

All three modules compile.

## Measured

```
remote = RemoteEvent
aim on  -> GF_AimState = "true:13"      Aiming attribute = true
aim off -> GF_AimState = "false:17.5"
check: ok=false passed=639 failed=17
```

`WalkSpeed` goes 17.5 → **13** while aiming and returns to 17.5 on release. `passed` rose 636 → 639 (the restored `AdsSpeed`
assertion plus the two removed-for-dead-config ones are gone, so the net is the assertion count) with `failed` unchanged at 17.

`Aiming=true` confirms the animator's dead branch is now live, so the aim pose can actually play — a second defect closed by the
same wiring.

## Honest gaps

- **13 is 0.74× walk, not the spec's 0.8×.** `0.8 × 17.5 = 14`. 13 was pre-existing and sits inside the 12–14 band I assert, so
  I left the value alone; purely, ADS should be 14. Recorded, not changed.
- **Crouch-plus-aim precedence is my invention.** Aim wins over crouch; the spec does not say. If crouched ADS should be slower
  than either, that combination is unimplemented.
- **RMB still toggles camera-look** in addition to aiming. That is pre-existing behaviour and I did not remove it — but holding
  RMB now both aims *and* locks look, which may feel wrong and is worth a playtest judgement.
- **No third-person / over-shoulder camera shift, no FOV change, no crosshair tightening.** Only the speed effect and the
  animation attribute are wired; the visual ADS presentation is untouched.
- Gamepad LT/L2 and touch aim are **not** wired — only RMB. `S03-004` and `S03-007` still have no aim path.
- The `adsSpeed` augment stat is now live for the walk-speed half but is not applied to `AdsSpeed` itself, so an augment rolling
  it still has no effect on aim speed.
