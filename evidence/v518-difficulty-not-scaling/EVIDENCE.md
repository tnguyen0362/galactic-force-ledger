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

---

# CORRECTION (same session): the ticket and credits claims were wrong

Two findings in this document are retracted after reading the code that actually applies them.

## Retraction 1 — "tickets run inverted against spec 1/1.25/1.75/2.5"

**Wrong.** `1 / 1.25 / 1.75 / 2.5` are **XP and mastery multipliers** from `S10-020`:

> *"Difficulty XP/mastery multipliers Easy1, Normal1.25, Hard1.75, Extreme2.5; Credits multiplier Easy.8, Normal1, Hard1.35, Extreme1.65."*

I compared `Difficulties.ticketsFor` against the XP column and called the ticket curve inverted. **The spec does not specify ticket counts anywhere** — a search for "ticket" returns one unrelated hit about TeleportService reserved servers.

Related: `Configs/Difficulties` line 30 carries the comment

```lua
-- Reinforcement tickets = base + perPlayer * squadSize (spec: Easy 3+2P, Normal 2+2P, Hard 1+P, Extreme P)
```

Those formulas **do not appear in the spec**. The values may be a reasonable design, but the comment asserts a spec basis that does not exist — worth removing or relabelling, because it makes a fabricated citation look like conformance.

## Retraction 2 — "credits multiplier 1/1.7/2.6/3.5 against a specified 0.8/1/1.35/1.65"

**Wrong target.** The multipliers that actually compute rewards live in `RewardLedgerService`, and they match the spec **exactly**:

```lua
local CREDIT_MULT = { Easy = 0.8, Normal = 1, Hard = 1.35, Extreme = 1.65 }
local XP_MULT     = { Easy = 1,   Normal = 1.25, Hard = 1.75, Extreme = 2.5 }
```

I compared the spec against `Difficulties.rewardMultiplier` (1 / 1.7 / 2.6 / 3.5), which is a **different field**. Its only reader is `StationWarTable` line 201 — the **reward estimate shown before deploying**.

So the precise statement is narrower and more useful:

- **Reward maths conforms.** Credits and XP/mastery multipliers are authored correctly and used to compute per-event values (`S10-019` × `S10-020` → e.g. a Veyr kill on Extreme = 165 credits, 625 XP).
- **The war table's estimate is wrong**, because it reads `Difficulties.rewardMultiplier` (1/1.7/2.6/3.5) instead of the real multipliers (0.8/1/1.35/1.65). A player sees an inflated preview, especially on Easy where the estimate implies 1× but the payout is 0.8×.
- **Settlement uses a third path.** `RewardsService.compute` reads `Economy.PayoutByDifficulty` (Easy 250cr/330xp … Extreme 950cr/1350xp), not the multiplier model. `RewardLedgerService` documents this as transitional: *"Settlement still computes payouts the old way until a later batch switches it."*

## What survives from the original document

- **`S06-032` ABSENT** — no HP/damage/cadence/reinforcement-pressure scaling anywhere; `EnemyService` and `CombatService` have zero difficulty references. This is the load-bearing finding and it is unaffected.
- **`S06-009` PARTIAL** — reaction delay is a per-type constant; `reactionMultiplier` is read by nothing.
- **`S06-033`** — vacuously satisfied, since cadence does not vary.

## Pattern

This is the eighth wrong conclusion of the session, and the third that came from comparing a spec number against **the wrong config field** rather than from a missing value (`e.stats`/`e.effect`, and now `rewardMultiplier` vs `CREDIT_MULT`). The discipline that catches it: before asserting a drift, find the field that **feeds the behaviour**, not the field whose name resembles it.
