# Difficulty is cosmetic: no HP/damage/cadence scaling, and rewards run backwards (place 518)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, plugin-level config + reader inspection. No place changes.

## The spec asks for four combat modifiers

`S06-032`: `(HP, damage, attack cadence, reinforcement pressure)` = `(.70,.60,.85,.65), (1,1,1,1), (1.50,1.30,1.10,1.25), (2,1.60,1.20,1.50)`

`Configs.Difficulties` contains **none of these four fields**. Its full numeric surface is:

```
Easy     eliteFrequency=0.1   enemyBudget=8    reactionMultiplier=1.4  rewardMultiplier=1    ticketBase=3 ticketPerPlayer=2
Normal   eliteFrequency=0.35  enemyBudget=12   reactionMultiplier=1    rewardMultiplier=1.7  ticketBase=2 ticketPerPlayer=2
Hard     eliteFrequency=0.7   enemyBudget=16   reactionMultiplier=0.8  rewardMultiplier=2.6  ticketBase=1 ticketPerPlayer=1
Extreme  eliteFrequency=1     enemyBudget=18   reactionMultiplier=0.65 rewardMultiplier=3.5  ticketBase=0 ticketPerPlayer=1
```

And nothing in combat reads difficulty at all — `EnemyService` and `CombatService` both return **zero** references to it. The only consumers anywhere are
`StationService`/`StationWarTable` for tickets, payout and spawn budget.

**So Hard and Extreme are not harder to fight. They field slightly more enemies (`enemyBudget` 16/18 vs 8/12) and pay more.** The authored 60% damage
reduction on Easy, the 2× HP on Extreme and the 1.3× enemy damage are all absent.

## Reaction delay is fixed, not banded

`S06-009` wants reaction delay bands per difficulty: Easy `.5–.9s`, Normal `.25–.6s`, Hard `.2–.45s`, Extreme `.15–.35s`.

`EnemyService` uses a per-enemy-type constant:

```lua
local windUp = tonumber(def.chargeTime) or tonumber(def.telegraph) or 0.55
```

so every difficulty telegraphs at the same speed. `Difficulties.reactionMultiplier` (1.4 / 1 / 0.8 / 0.65) is **read by nothing** — a dead field, the same
defect class as the earlier `adsRecovery`/`sentryAmmo` findings.

Note: `S06-033` requires cadence not to shorten heavy/marksman warning below 0.9s. That clause is trivially satisfied today because cadence does not vary
at all — satisfied by absence, not by design.

## Tickets are inverted

| | spec (tickets) | config tickets, solo | config tickets, 4p |
|---|---|---|---|
| Easy | 1 | **5** | 11 |
| Normal | 1.25 | **4** | 10 |
| Hard | 1.75 | **2** | 5 |
| Extreme | 2.5 | **1** | 4 |

The spec has tickets **rise** with difficulty (1 → 2.5). The build has them **fall** (5 → 1), so a player is paid most for the easiest content and roughly
a fifth as much for Extreme where the spec pays 2.5×. `ticketBase=3` on Easy with `ticketPerPlayer=2` is the dominant term.

## Credits multiplier is steeper than authored

| | spec (credits) | config `rewardMultiplier` |
|---|---|---|
| Easy | 0.8 | **1** |
| Normal | 1 | **1.7** |
| Hard | 1.35 | **2.6** |
| Extreme | 1.65 | **3.5** |

The spec *penalises* Easy to 0.8 and tops out at 1.65; the build pays 1.0 rising to 3.5 — over **2× the authored Extreme payout** and no Easy penalty.

## A misreading I caught before writing it down

My first dump printed keys alphabetically, and I initially read `Easy … reactionMultiplier=1.4 rewardMultiplier=1` as "Easy rewardMultiplier 1.4". The
1.4 is the **reaction** multiplier. Both numbers are quoted correctly above; had I not re-read the line, this evidence would have reported Easy paying
1.4× when it pays 1×.

## Why this matters more than a number

A difficulty selector that does not change enemy lethality is a **labelling** feature, not a difficulty feature. The prototype can pass a smoke test
for "four difficulties" while the authored challenge curve is entirely absent.

## Confidence and limits

High on the absences — config field enumeration is exhaustive and both combat services have zero difficulty references. I did **not** check whether
enemy stat tables are duplicated per difficulty elsewhere (e.g. per-difficulty enemy definitions), which would change the "no scaling" conclusion; the
`Configs.Enemies` list carries per-role base stats only, and `S06-023`–`S06-027` show those are "Normal" baselines.
