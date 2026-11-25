# Mastery now settles only on a completed primary (place 467)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, fresh Play VM. Place saved as **version 467**.

## The defect

`S09-034` / `GOAL_2026-11-24.md` L145: *"Weapon mastery settles on mission completion (primary completed before individual
cutoff), not on incomplete primary; a dead player whose primary already completed can receive earned mastery."*

The build did the opposite. `CombatService` called `ProfileService.addMastery(...)` on every kill, and `addMastery` writes the
profile and marks it dirty immediately. So mastery was banked the instant an enemy died — a player could farm kills, fail the
primary, walk away and keep every point. The previous batch fixed the *scale* of mastery (cap 10 → 650, per-archetype awards)
but deliberately left this gate alone, because it is a structural change rather than a constant.

## The change

Three edits, each with an exactly-one-match guard:

| file | change |
|---|---|
| `State` | `PlayerState.pendingMastery` — an in-mission bucket, initialised empty per player |
| `CombatService` | kill credits `s.pendingMastery[weaponId]` instead of writing the profile |
| `ExtractionService.finish` | settles the bucket through `ProfileService.addMastery` **only when `payoutObjective` is true**, then clears it either way; publishes `GF_MasterySettled` |

All three modules pass `loadstring`.

## Measured

Probe `Script` in `ServerScriptService` sharing the live module instances, real loaded profile, using `SMG03` because `AR01`
was already at the 650 cap from the earlier ladder test:

```
case1 before  mastery=0  settled=nil
case1 after   mastery=0  settled=0     <- primary NEVER completed: 50 earned, 0 credited
case2 before  mastery=0  settled=0
case2 after   mastery=50 settled=50    <- primary completed: 50 credited despite a FAILED extraction
```

Case 1 previously credited 50 on the kill itself. Case 2 confirms the requirement's other half — mastery is independent of the
way out, so a squad that wins the primary and loses the dropship still keeps what it earned, and a dead player whose primary
completed still receives it.

## Side effect

`case2` genuinely wrote 50 mastery XP to `SMG03` on the test profile and `Obj.complete()` committed a war point. Both are real
persisted effects of testing the real path.

## Limits

- The kill path itself was **not** exercised this batch; `pendingMastery` was set directly. The one-line change from
  `addMastery(...)` to `s.pendingMastery[...]` is read, not fired — so "a kill credits the bucket" rests on source, while "the
  bucket settles correctly" is measured.
- Only `SABOTAGE_RELAY` was used, and only a solo player.
- `pendingMastery` is session state, so a player who disconnects mid-mission loses their bucket. That matches "voluntary
  abandon forfeits", but a crash-reconnect case is untested.
- `S10-039` (mastery progress shown in the debrief and Armory) is still unmet — nothing renders it.

## Note on a wrong citation

Earlier evidence in this audit cited `HANDOFF.md` at the repository root. It actually lives at `.goal/HANDOFF.md`. Several
`evidence_ref`-style mentions of `HANDOFF` should be read with that path.
