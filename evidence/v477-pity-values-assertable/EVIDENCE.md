# Pity values moved out of `ProfileService` locals and asserted (place 477)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, fresh Play VM. Place saved as **version 477**.

## The problem

`ProfileService` held the boss blueprint pity as two file-local constants:

```lua
-- The spec requires the blueprint to be guaranteed on the third qualifying clear. It was set to 5, so a
local BOSS_PITY = 3
local BOSS_BLUEPRINT_CHANCE = 0.34
```

That comment asserts the specification requires **3**. `GOAL_2026-11-24.md` L102 requires **5** qualifying clears at **15%/kill**.
So the numbers deviate, and the comment claiming otherwise makes the deviation look like a decision.

No check could see them: locals inside a service module are unreachable from `CheckRunner`. The only way to find this was a
human reading the file — which is exactly how it was found, three batches ago.

## The change

| file | change |
|---|---|
| `Constants` | new `Constants.Pity = { Target = 3, Chance = 0.34 }` |
| `ProfileService` | reads `Constants.Pity` instead of two locals, with the old literals as fallbacks |
| `CheckRunner` | asserts `Pity.Target == 5` and `Pity.Chance == 0.15` |

**The values were moved, not retuned.** Behaviour is byte-identical: `Constants.Pity` reads `Target=3 Chance=0.34`, so pities
still resolve on the third clear at 34%. Changing them is a gameplay decision and stays the owner's.

## Measured

```
ok=false  passed=635  failed=16
  spec drift: Pity.Target = 3, spec 5-5
  spec drift: Pity.Chance = 0.34, spec 0.15-0.15
Constants.Pity Target=3 Chance=0.34
```

`failed` went 14 → 16 (`DownedTimeout`, `ReviveDuration`, plus these two). `passed` is unchanged, because both new assertions
fail — which is the correct outcome for values that genuinely deviate.

## What this buys

The pity deviation is now **visible at every boot**, in the same place as the other fifteen, and it can no longer be described
by a comment claiming the spec says otherwise. A future session cannot quietly inherit the false claim: the check argues with
it.

It also makes the fix trivial and safe — setting `Constants.Pity.Target = 5` and `Chance = 0.15` is a one-line change in one
obvious place, rather than editing a service internals file.

## Also worth noting

The false comment is still in `ProfileService` above the (now removed) local. It was written when the value changed from 5 to 3
and asserts a specification requirement that does not exist. It is left in place rather than deleted so the record of *why* the
value moved survives — but it is now contradicted by a failing assertion instead of standing unchallenged.

## Limits

- Only the two pity numbers moved. Other service-local tunables remain unassertable, and I have not enumerated them.
- The pity path itself (three boss clears → guaranteed blueprint) was not re-run this batch; only the values and their
  assertion were verified.
- `S06-072` remains PARTIAL: the deviation is now loudly *detected*, not resolved.
