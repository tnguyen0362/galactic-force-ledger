# Authored per-event reward table, fractional, single floor (place 474)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 474**.

## What was added

`RewardLedgerService` now carries the authored event table from `GOAL_2026-11-24.md` L150–L157 and the difficulty multipliers
from L161, and computes each event's value **fractionally** with no rounding:

```lua
EVENTS = {
    primary_complete  = { credits = 300, xp = 350, mastery = 0 },
    extraction_success = { credits = 100, xp = 100, mastery = 0 },
    optional_task     = { credits = 50,  xp = 65,  mastery = 0 },
    kill_Rifleman/Scout/Marksman = { credits = 1, xp = 10, mastery = 10 },
    kill_Heavy        = { credits = 3,  xp = 20,  mastery = 20 },
    kill_Officer      = { credits = 5,  xp = 35,  mastery = 35 },
    kill_BastionWalker = { credits = 60, xp = 100, mastery = 100 },
    kill_HighMarshalVeyr = { credits = 100, xp = 250, mastery = 250 },
}
CREDIT_MULT = { Easy = 0.8, Normal = 1, Hard = 1.35, Extreme = 1.65 }
XP_MULT     = { Easy = 1,   Normal = 1.25, Hard = 1.75, Extreme = 2.5 }
```

`appendEvent(eventType, difficulty, sourceId, userId)` stores the computed `credits`, `xp`, `mastery` and `difficulty` on the
event. `totals()` sums them fractionally. **Nothing floors or rounds per event** — L161 is explicit: *"Compute fractional
event totals then floor at settlement, no rounding each hit."*

Still **record-only**. `RewardsService` continues to pay its own way; the ledger does not gate or alter a payout.

## Measured

```
value primary_complete@Normal   cr=300.00  xp=437.50  m=0.00
value primary_complete@Extreme  cr=495.00  xp=875.00  m=0.00
value kill_Heavy@Normal         cr=3.00    xp=25.00   m=25.00
```

`300 × 1.65 = 495` and `350 × 2.5 = 875` confirm the Extreme multipliers; `×1.25` on Normal XP confirms the fractional path.

A real mission on Normal, primary completed then extracted:

```
#1 primary_complete@Normal    cr=300.00  xp=437.50  m=0.00
#2 extraction_success@Normal  cr=100.00  xp=125.00  m=0.00
totals                        cr=400.00  xp=562.50  m=0.00
floored at settlement would be 400 cr / 562 xp
```

`562.50 → 562` is the single-floor rule working: the fraction is carried through accumulation and floored exactly once.

## The same instrument bug I keep finding — this time in my own new code

The first measurement printed `#1 primary_complete cr=-1.00 xp=-1.00 m=-1.00` even though `totals()` returned the correct
400/562.5. Cause: `appendEvent` set the values on the stored event, but `snapshot()` copies events through a fixed field list
that did not include `credits`, `xp`, `mastery` or `difficulty`. So the stored data was right and the *view* dropped it.

That is the eighth instance of this pattern in the project, and this one I wrote myself an hour after documenting it. Fixed by
copying the fields in `snapshot()`, with the reason in a comment.

## Still record-only, and still short of `S09-025`

- **No `eligibleUserIds`** — a single `userId` per event, not the eligibility set.
- **Not durable** — in-memory; a restart loses the ledger.
- **Settlement does not read it.** Deliberate. Payouts still come from `RewardsService.compute`.

So `S10-012`–`S10-021` are now PARTIAL rather than ABSENT: the authored values exist, are difficulty-scaled and are
fractionally accumulated, but they do not yet determine what a player is paid.
