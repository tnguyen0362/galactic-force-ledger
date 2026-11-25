# No class lock (verified) — and the entire reroll/dismantle/fusion lifecycle is absent (place 504)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, plugin-level inspection. No place changes.

## `S11-005` — no player class lock: VERIFIED

`ArmoryService` touches `selectedClass` in exactly four places: a comment claiming sole write ownership, the class list exposure, the
state payload, and the setter at line 473 (`profile.selectedClass = id`). **No lock check exists** — no class-gated weapon, ability or
augment path.

Behaviourally confirmed too: at place 495 all four classes were applied in sequence on one profile through `ClassService.apply`
(`Assault → Heavy → Recon → Support`), each returning `ok=true` with its own modifiers. A locked class system could not do that.

## `S11-057`–`S11-067` — reroll / dismantle / fusion: ABSENT

A project-wide search:

```
reroll      CacheService only — both hits are "preRolled", a substring
dismantle   NO references
fuse        only inside "refused" (GrenadeRuntime, ObjectiveService, ExtractionService, …)
fusion      NO references
```

So none of the eleven rows in that cluster has any implementation:

| row | requirement |
|---|---|
| `S11-057` | reroll costs Scrap 25/50/100/200 by rarity, optional lock |
| `S11-058` | defining stat fixed, its value rerolls, others reroll unless locked |
| `S11-059` | a locked negative is kept and the pool still satisfied |
| `S11-060` | deduct once, show old/new compare, Accept or Keep, both consume cost |
| `S11-061` | pending offer persisted against force-close rerolling |
| `S11-062` | one pending offer at a time, no concurrent fuse/dismantle/equip |
| `S11-063` | equipped item may reroll in lobby, loadouts frozen in mission |
| `S11-064` | dismantle returns Scrap C8/R18/E40/L85, bulk filter and preview |
| `S11-065` | fusion consumes 3 same rarity+category non-protected → next rarity |
| `S11-066` | fusion result generated at next rarity, not from a cache |
| `S11-067` | expected dismantle-vs-fuse cost balance (24/54/120 Scrap) |

This is not eleven separate gaps; it is **one missing subsystem** — the augment item lifecycle. Every row depends on per-instance augment
records that can hold a pending offer, a lock flag and a protected flag, which is the same instance model still blocked on `S11-031`.

## Why this matters beyond the count

The ledger's economy rows were written assuming these verbs exist. Dismantle is also the only sink that makes inventory capacity
(`S11-032`, now verified) meaningful: with 200 slots and no way to dismantle, a full inventory can only be expanded, never cleaned. And
`S11-042`'s trait ranges are already partly sampled at open time, so reroll would be cheap to add once instances exist — the blocker is
identity, not the roll.

## Confidence

High for absence: three independent keyword searches, each cross-checked for substring false positives (`preRolled`, `refused`). No
runtime test was attempted because there is no entry point to call.
