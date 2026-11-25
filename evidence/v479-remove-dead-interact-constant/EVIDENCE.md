# Dead config removed: `Constants.Combat.InteractRange` (place 479)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, fresh Play VM. Place saved as **version 479**.

## Why remove rather than leave it

Last batch established that `Constants.Combat.InteractRange = 10` had **no consumers** while `ObjectiveService` uses its own
local `INTERACT_RANGE = 16`. That single dead entry caused a false lead: I spent part of a batch treating 10-vs-16 as a
contradiction when in fact only one of them was ever live.

A dead constant is not neutral. It reads as authoritative, it sits beside live values, and it invites exactly that mistake from
the next person — including me, twice.

## Verification before removal

Scanned **every** `LuaSourceContainer` under `ServerScriptService`, `ReplicatedStorage`, `ServerStorage`, `StarterPlayer` and
`StarterGui` for `interactrange`, case-insensitive:

```
project-wide InteractRange references: 1
ReplicatedStorage.GF.Shared.Constants        <- the definition itself
```

Zero consumers, project-wide.

## Change

Removed the single line `InteractRange = 10,` from `Constants.Combat`. Nothing else touched.

## Measured

```
Combat.InteractRange = nil
Combat keys = DownedTimeout, EnemyBudgetCap, MaxActiveEnemiesPerPlayer, ReviveDuration, ReviveRange
boot: ok=false  passed=638  failed=16
```

`passed` and `failed` are **identical to the previous batch** (638/16), which is the proof that no consumer broke — if anything
had read the key, the value would now be `nil` and an assertion or a boot path would have failed.

## What this does not fix

`ObjectiveService` still allows interaction at **16 studs** against the spec's **<=9**. Removing the dead constant makes the
real question clearer rather than resolving it:

- there is now exactly **one** interact range in the project (`ObjectiveService.INTERACT_RANGE = 16`), so there is no ambiguity
  about which number governs behaviour
- the value is still wrong, and still the owner's call, because tightening it changes pacing and combat pressure

When that decision is made, the clean shape is: move the value into `Constants.Combat` at **9**, have `ObjectiveService` read
it, and assert it in `CheckRunner` — which also makes it checkable for the first time. Doing it in that order means the check
never goes red against a constant nothing uses, which is what would have happened had I centralised the number last batch.

## Limits

- Removal is safe for this place only; an unpublished consumer outside these five services (a plugin, a command bar script)
  would not have been scanned.
- No behaviour was measured this batch — the evidence is the absence of a dependency plus boot parity.
