# Kill credits the mastery bucket, and nothing reaches the profile (place 467)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, fresh Play VM. No source changes this batch, so the place was
not re-saved.

## The gap this closes

`evidence/v467-mastery-settlement-gate` proved the **settlement** logic by setting `pendingMastery` directly, and said so:
*"the kill path itself was not exercised this batch; the one-line change from `addMastery(...)` to `s.pendingMastery[...]` is
read, not fired."*

This batch fires it.

## Method

Probe `Script` in `ServerScriptService` sharing the live module instances:

1. equip `SMG03` the way an armory equip would (`s.weaponId = "SMG03"`), so credit lands on a weapon that is not already at the
   650 cap
2. `EnemyService.spawn("Rifleman", root.Position + (0,0,18))`
3. `CombatService.damageEnemy(model, 100000, player, "Torso", 1)` — a real kill through the real damage path
4. read the profile attribute and the bucket after the kill
5. `ExtractionService.finish(false)` with the primary never completed, to confirm the bucket is discarded

## Measured

```
weapon=SMG03 profile=0 pending=0
spawned=true
afterKill           profile=0  pending=10  dead=true
afterFailFinish     profile=0  pending=0   settled=0
```

Three things confirmed at once:

- **The kill credits the bucket**: a Rifleman is worth the authored **10** mastery XP, exactly as `GOAL_2026-11-24.md` L150
  specifies, and that is what appeared.
- **The profile is not written on the kill**: `profile=0` before and after. Before place 467 this same kill would have
  called `addMastery` and moved the profile immediately.
- **A failed primary discards it**: `pending=0`, `settled=0`, profile still 0.

The `weaponId` was set directly rather than through an armory purchase. That is the same field `applyLoadout` writes, so it is
the real input to the mastery branch, but it does skip the equip UI.

## An anomaly I could not explain, recorded rather than dismissed

The previous batch's settlement test wrote **50** mastery XP to `SMG03` on this same account. This server read `SMG03` mastery
as **0**.

Possible explanations, none confirmed:

- `ProfileService.markDirty` buffers and the spec's autosave window is ~60–90 s (`GOAL_2026-11-24.md` L222); the previous
  server was stopped shortly after the write, so the dirty profile may never have been flushed.
- `weaponMastery` may not survive the DataStore round-trip, which would be a real persistence defect and would make every
  mastery value session-only.

This matters because `S10-037` claims mastery is tracked per weapon. **I am not calling it a defect** — there is not enough
evidence, and the autosave explanation is at least as likely. The way to settle it is a deliberate test: award mastery, wait
past the autosave window, stop the server, start a new one, and read the same weapon.

## Still open on mastery

- The debrief and Armory still do not display mastery progress (`S10-039`).
- The second augment socket is not verified to unlock at level 5.
- "Independently track every **owned** weapon" is not enforced — any weapon id on the session state gets a credit.
- Whether mastery persists across servers is now an open question, not an assumption.
