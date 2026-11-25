# Reward payout branches, missing event ledger, and two blueprint/mastery defects (place 463)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`. `RewardsService.compute` called directly; source read for the
rest.

## The payout table, measured

`RewardsService.compute(difficulty, success, objectiveComplete, squadSize)` on Normal, squad 1:

| case | credits | xp | salvage |
|---|---|---|---|
| extracted, primary complete | 450 | 600 | 0 |
| extracted, primary **failed** | 0 | 0 | 0 |
| **failed evac, primary complete** | **450** | **600** | 0 |
| failed evac, primary failed | 0 | 0 | 0 |

Two things this corrects:

1. **A failed extraction after a completed primary DOES pay full base** (450/600, salvage withheld). The
   `S09-033` note previously implied failure always pays nothing. It does not — the zero-payout case is an
   **objective failure**, not an extraction failure.
2. The zero is `compute`'s first branch: `if not objectiveComplete then return { credits = 0, xp = 0, ... }`. So on a failed
   objective nothing accrues at all, which is where the specification's *"rank XP and Credits earned from completed tasks,
   kills and participation survive failure"* is unmet.

Fixing that is not a one-line change: it needs the per-event reward ledger, and **that does not exist** — see below.

## `S09-025` — the rewards event ledger is absent

The specification requires an append-only ledger: `(missionId, seq, eventType, serverTime, eligibleUserIds, resourceDelta,
sourceId)` with per-source claim-once.

Scanned every `LuaSourceContainer` under `ServerScriptService.GF`: **no module contains `eventType`, `resourceDelta`, or
`appendEvent`**. `RewardsService` is 150 lines with three functions (`compute`, `grant`, `grantAll`) and holds no event
list. There is also no kill-XP table anywhere, so `S10-012`–`S10-019` have nothing to accumulate into.

This is the missing subsystem underneath `S09-033`, `S10-015`–`S10-019`, `S10-037` and `S09-040`.

## `S06-072` — pity is 3, and the code *believes* the spec says 3

`ProfileService` lines 82-85:

```lua
-- The spec requires the blueprint to be guaranteed on the third qualifying clear. It was set to 5, so a
local BOSS_PITY = 3
local BOSS_BLUEPRINT_CHANCE = 0.34
```

`GOAL_2026-11-24.md` L102 says: *"Guaranteed blueprint pity at **5** qualifying extracted boss kills; earlier success
probability **15%/kill**."*

The comment is not covering a deliberate balance change — it asserts the specification requires 3, and the specification
does not. So the value moved from 5 to 3 on a **misreading**, not a decision. `BOSS_BLUEPRINT_CHANCE = 0.34` is likewise
34%, not the authored 15%.

Both are recorded, neither changed: the number that governs how often a player receives a boss blueprint is a gameplay
lever, and the right fix may be to correct the comment and the code together. But the *justification* currently in the
file is false and should not be trusted as a decision record.

## `S10-037` / `S09-034` — mastery exists, its ladder and its settlement do not

`ProfileService` carries `weaponMastery = {}` (line 28) and a writer, `ProfileService.addMastery(player, weaponId, amount)`
(line 224), which sets `GF_Mastery_<weaponId>`.

Writers found: `CombatService:231` calls it with amount 1 **per hit**, and `ArmoryService:503` with 5 as a test hook.

Neither defect is subtle:

- **No level ladder.** The spec's five levels with thresholds `[0, 100, 240, 420, 650]` do not exist — no module contains
  those thresholds. Mastery is a bare accumulating number.
- **No settlement gate.** The spec says mastery settles on **mission completion** and not on an incomplete primary
  (`S09-034`), but the counter increments per hit during the mission. A player who fails the primary and leaves keeps the
  mastery they accrued, which is the opposite of the rule.

## Not changed

All of it. Each item above is either a missing subsystem (the event ledger) or a payout-rate lever (pity, drop chance,
mastery accrual). None is a one-line correctness fix like `S09-035` was.

## Limits

- `compute` was called directly; no mission was played for this batch.
- Branch table only covers `Normal`. Easy/Hard/Extreme base values come from `tableFor` and were not read.
- Absence claims were checked against alternate naming (`blueprint`, `pity`, `transaction`, `mastery`) before being
  recorded, because a first grep miss is how four previous false negatives were produced.
