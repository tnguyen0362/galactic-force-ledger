# The shotgun fires one ray, not eight pellets (place 507)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, plugin-level source inspection. No place changes.

## Finding

A keyword scan of every script under `ServerScriptService` and `StarterPlayer` for **`pellet`** returns **zero references**.

`SG-04` is configured with `damage = 96`, which is exactly `8 × 12` — the authored per-pellet damage times the authored pellet count. So the
*database* was transcribed correctly, but `CombatService.fire` resolves a single ray and applies the summed 96 as one hit.

## What that changes in play

| authored | build |
|---|---|
| 8 independent rays, 12 damage each | 1 ray, 96 damage |
| graded damage at range (some pellets hit) | all-or-nothing hit or miss |
| per-pellet falloff | one falloff applied to the total |
| shotgun spread pattern | single-ray spread only |
| partial hits on a moving target | binary outcome |

The gameplay difference is largest exactly where a shotgun is defined: at the edge of its range a piece of the pattern should connect. Here
either 96 lands or nothing does. It also means the scatter model added at place 492 applies **once** to one ray for the shotgun, instead of
distributing 8 pellets — so `SG-04`'s authored 4.5° ADS spread has a different meaning than intended.

## Which rows this touches

- **`S04-022`** — *"shotgun **per pellet**, explosion radia…"*: the clause is unmet; the rest of that row (linear falloff, reject beyond max
  range) was previously verified.
- **`S04-WPN-SG04`** — *"Role: pump shotgun **8 pellets**; D: 12/pellet"*: the damage figure (96) matches the total, but the pellet mechanic
  does not exist.

## Why this was easy to miss

The data looks right. `damage = 96` and the authored `12/pellet × 8` agree arithmetically, so every data-conformance check passes — including
the weapon table audit one batch ago, where I recorded SG-04 as `96 = 8 × 12 ✓`. That check was **correct about the arithmetic and wrong about
the mechanic**, which is the same class of error as asserting a dead constant: the number agrees, the behaviour does not.

## Not implemented

Adding pellets is a combat-model change: eight raycasts per trigger pull, each with its own falloff and spread, and a damage accumulation path.
It alters every TTK measurement for the shotgun and needs a decision about whether partial pellet hits on a single enemy stack fully. Recorded
rather than built.

## Confidence

High for the absence: zero `pellet` occurrences is unambiguous, and `fire` computes a single direction and one damage application. The only way
pellets could exist is if they were modelled under a different word — `shot`, `ray`, `multi` — which I did not screen for, so this claim rests on
the conventional vocabulary.
