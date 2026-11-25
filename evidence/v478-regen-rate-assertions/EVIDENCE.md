# Regen rates and roll recharge now asserted — all three conform (place 478)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, fresh Play VM. Place saved as **version 478**.

## Closing the gap I named

The constants batch ended with an explicit list of what it had *not* covered:

> *"Not yet covered: `Combat.EnemyBudgetCap`, `MaxActiveEnemiesPerPlayer`, `InteractRange`, `RollRecharge`, and the regen
> **rates** (only delays are asserted)."*

Three of those are numerically pinned in the specification, so they were added:

| assertion | value | spec |
|---|---|---|
| `Vitals.ShieldRegenRate` | 25 | *"regenerate 25/s"* |
| `Vitals.HealthRegenRate` | 8 | *"HP after 9s regenerate 8/s"* |
| `Movement.RollRecharge` | 3.5 | *"individual charges recharge ~3.5 s"* |

## Measured

```
before:  passed=635  failed=16
after:   passed=638  failed=16
new-section drifts: 0
```

`+3` passing, `failed` unchanged at 16, **zero new drifts**. Unlike the previous two batches, everything in this set conforms —
so the check grew without finding anything wrong. That is the outcome a healthy value should have, and it is worth recording
that not every audit finds a defect.

## The two I deliberately did not add

- **`Combat.InteractRange`** — not pinned numerically anywhere I could find in the spec. `v388`'s evidence mentions
  `INTERACT_RANGE (16 studs)` while `Constants.Combat.InteractRange` is **10**. That is a possible discrepancy, but I could not
  locate an authored value to assert against, so it stays unasserted rather than being asserted against evidence prose.
- **`EnemyBudgetCap` / `MaxActiveEnemiesPerPlayer`** — the spec defines the concurrent cap as a *formula*
  (`round(4+2*(P-1))` scaled by a difficulty count factor), not as constants. Asserting 12 or 3 against a formula would be
  inventing the mapping, and the formula path needs a real measure with 1 and 4 players.

Both remain listed as open in `WORK_STATE`, which is more useful than a green tick built on a guess.

## Limits

- These are **declarations**, not demonstrated rates. Nothing was damaged and allowed to regenerate to time 25/s; the constants
  are asserted, the behaviour is not.
- `InteractRange 10` versus the `16` in a prior evidence file is now a recorded open question. If 10 is wrong, interacting with
  objective terminals at 10–16 studs silently fails, which is precisely the sort of thing `v388` would have hit if it had tested
  the boundary.
