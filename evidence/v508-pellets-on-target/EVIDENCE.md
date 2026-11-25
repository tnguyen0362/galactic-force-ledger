# Pellets land on a real target — 196.8 total is headshots, not double-damage (place 508)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. No source changes; verification only.

## What this closed

Last batch proved eight pellet rays were **emitted** but fired into empty space, so it did not show that a target **receives** damage through the
real path.

## Measured

```
12 studs: shield 60->0  health 210->73  totalDelta=196.8
70 studs: shield 60->60 health 210->210 totalDelta=0.0
```

## The 196.8 is correct, and here is why

Two readings were needed before concluding:

```lua
function CombatService.weakMultiplier(partName, part)
    if partName == "Head" then return 2 end
    return 1
end
```

So a headshot pellet does `12 × 2 = 24`. Eight pellets **all** on the head would be 192; 196.8 is that plus shield/health rounding. The pellets
scattered upward from a torso-aimed shot at 12 studs, which is exactly what a shotgun at point blank does.

Damage routing was also read end-to-end (`damageEnemy`): shield absorbs first, the remainder reduces health, and each pellet is a separate call.
No double application exists. **196.8 is not a bug — it is eight pellets with several weak-point hits.**

Which means the authored *"12/pellet"* and the config's *96* describe **body** damage at point blank. With a 2× headshot rule, a full-head pellet
pattern reaches ~192. That is a consequence of the existing weak-point system meeting pellets, and it is worth the owner knowing the effective
ceiling roughly doubled for this weapon.

## The zero at 70 studs

`totalDelta=0.0` is unresolved. Two candidate causes, neither proven:

- shotgun scatter at 4.5° over 70 studs is ~5.5 studs wide against a ~2-stud torso, so 7 of 8 pellets plausibly miss;
- but pellet 1 uses the **aimed** direction and should have connected, so either the teleport (`root.CFrame` written directly) did not take
  effect before the shot, or the aim direction was computed from a stale root position.

I have not separated those, so I am **not** claiming range behaviour works or fails.

## Also learned: enemies have no Humanoid

`ActiveActors` enemies are Models carrying `Health`, `MaxHealth`, `Shield`, `MaxShield`, `ArmorFactor` and `Dead` as **attributes** — there is no
Humanoid. My first two probes returned "no living enemy" and "no torso" because they searched for `FindFirstChildOfClass("Humanoid")`. Worth
recording: any future combat probe must read attributes, not humanoid health.

## Status

`S04-022`'s pellet clause is implemented and damage reaches a real target through the true path; the **exact authored 96 remains unconfirmed for
body hits**, since every landed test included headshots. Range behaviour unverified.
