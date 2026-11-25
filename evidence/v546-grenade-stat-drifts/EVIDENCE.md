# `S04-053` grenade stats: seven measured drifts, one dead field (place 546)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`. **No source changes this batch** — audit and measurement only, so the place was not re-saved.

## Spec vs build

Spec: *"Frag (starter, max3) radius 15, center 135, fuse 2.5s from impact or 4s max flight; EMP (rank4, 550 Credits, max3) radius 13, 90 shield
damage/15 health and 2s disable turret/robot subsystem or suppress energy gun."*

| field | spec | build | verdict |
|---|---|---|---|
| Frag radius | 15 | **22** | drift (+47%) |
| Frag centre damage | 135 | **110** | drift (−19%) |
| Frag fuse | 2.5 s | **2.6** | drift |
| Frag max flight 4 s | 4 s cap | no such concept | **absent** — the bomb is a tween to the aim point, not a projectile, so there is no flight cap to enforce |
| EMP radius | 13 | **26** | drift (exactly 2×) |
| EMP shield damage | 90 | enemy shield set to **0 regardless of amount**; players take `damage × shieldMultiplier` = 40 × 3 = **120** | drift, and a semantic change |
| EMP health damage | 15 | **no health damage to enemies at all** (only 20 self-damage to the thrower when unshielded) | absent |
| EMP disable | 2 s turret/robot subsystem, or suppress energy gun | `EMPStunUntil = now + 2.5` | drift (2.5 s) **and dead** — see below |
| max charges | 3 / 3 | 3 / 3 | ✓ |
| EMP rank 4, 550 Credits | ✓ | `unlockRank=4`, `cost=550` | ✓ |

Config source: `Economy.Grenades` = `Frag damage=110 radius=22`, `EMP damage=40 radius=26 shieldMultiplier=3`; fuse table `{ Frag = 2.6, EMP = 1.9 }` in
`GrenadeRuntime`.

## The dead field

```
EMPStunUntil references: 1
GrenadeRuntime:117  enemy:SetAttribute("EMPStunUntil", os.clock() + 2.5)
```

**Written, never read anywhere in the project.** So EMP's "disable" — the whole point of the grenade according to the requirement — has **no effect on enemies**.
Only the shield drain does anything.

This is the same defect class recorded repeatedly in this project: a value that is described and even written, but never consumed.

## Live attempt, and why it proved nothing about EMP

I tried to measure the EMP drain against a scratch enemy with 300 shield. `GFDebug` showed the throw executed (`LastGrenade=EMP`, `LastGrenadeRadius=26`), and the
EMP branch ran — but reported `LastEmpDrained=0`, `LastEmpStunned=0`: my target sat outside the blast (`LastGrenadePos` z ≈ −18.2 while I placed the target 8 studs
ahead of a character that had rotated). **A probe placement failure, not evidence that EMP fails to drain.** I am not claiming either way from that run.

## Why this is not fixed

Every item is a **tuning number in an owner-authored table** (radius, damage, fuse, stun duration) — changing them silently would be re-balancing the game, which
the goal explicitly defers to documented playtest evidence. The dead `EMPStunUntil`, however, is a genuine implementation gap rather than a tuning question: the
requirement asks for a disable and nothing implements it.

## Next step

Owner decision on the numbers, then either implement the disable (consume `EMPStunUntil` in enemy movement/fire logic, 2 s per spec, scoped to turret/robot
subsystems or energy guns) or record EMP-disable as cut.
