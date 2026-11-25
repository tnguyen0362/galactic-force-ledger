# The rewards event ledger exists — record-only, no payout changed (place 473)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 473**.

## Why this was deferred four times, and why that stopped

`GOAL_2026-11-24.md` L145 asks for an append-only rewards ledger:

> *"append immutable events `(missionId, seq, eventType, serverTime, eligibleUserIds, resourceDelta, sourceId)`; per-source
> claim once."*

It is the wall behind `S09-033` (a failed mission pays nothing for kills or participation), `S09-040` (unique settlement id and
journal), and the whole `S10-012`–`S10-019` per-event reward table. I kept deferring it because "shape it wrong and it is
expensive to unwind". That was true, and it was also an excuse for not starting.

The resolution: build the **recording** half only. It cannot break the economy because it does not touch a single payout.
`RewardsService` still computes and grants exactly what it did before. Money moves only when a later batch deliberately makes
settlement read from the ledger.

## What exists now

New `ServerScriptService.GF.Services.RewardLedgerService`:

| function | purpose |
|---|---|
| `begin(context)` | new mission id, `seq` back to 0, claims cleared |
| `append(eventType, resourceDelta, sourceId, userId)` | immutable event; returns `nil` and records a rejection when the `sourceId` was already claimed |
| `isClaimed(sourceId)` | claim-once check |
| `snapshot()` | defensive copy for inspection |
| `count()`, `reset()` | diagnostics |

Two invariants it enforces: `seq` is monotonic per mission, and a `sourceId` can be claimed **exactly once** — so a retry or a
double fire cannot pay twice.

Wired at three call sites, **every one `pcall`-wrapped** so a ledger fault cannot take down gameplay:

- `ObjectiveService.setup` → `begin(template)`
- `ObjectiveService.complete` → `append("primary_complete", 0, "primary:" .. templateId)`
- `ExtractionService.finish` → `append("extraction_success" | "extraction_failed", 0, "extraction:" .. template)`, recorded
  **before** the payout runs so a crash between the two leaves evidence of intent

Observability: `GF_LedgerMission`, `GF_LedgerCount`, `GF_LedgerSeq`, `GF_LedgerLast`, `GF_LedgerRejected`.

## Measured

Probe `Script` in `ServerScriptService`, live module instances:

```
after setup     mission=m2-…-SABOTAGE_RELAY  seq=0 count=0
after complete  mission=m2-…-SABOTAGE_RELAY  seq=1 count=1
events:         #1 primary_complete(primary:SABOTAGE_RELAY)
duplicate source accepted? false   rejectedAttr="duplicate source: primary:SABOTAGE_RELAY"
after extraction seq=2 count=2
events:         #1 primary_complete(...), #2 extraction_success(extraction:SABOTAGE_RELAY)
isClaimed(extraction:SABOTAGE_RELAY) = true
after next setup mission=m3-…-RECOVER_TECH   seq=0 count=0
old source still claimed? false            <- claims are per-mission, correctly scoped
```

All four invariants hold: monotonic `seq`, per-mission scoping, claim-once, and rejection telemetry that says *why*.

## What is deliberately still missing

This is **not** a finished `S09-025`, and the ledger row says PARTIAL rather than VERIFIED:

- **No `eligibleUserIds`.** Events carry a single `userId`, not the eligible-participant set the spec names. The squad
  eligibility rules (active/downed/pending-life, disconnect grace) live in `SquadService` and were not consulted.
- **Not durable.** The ledger is in-memory; a server restart loses it. The spec wants "durable receipt history/settlement
  retention", which needs `ProfileService` or DataStore integration — a real design decision about who owns the journal.
- **Does not drive settlement.** Payouts are unchanged. That is intentional and is the whole reason this was safe to ship.
- **No `resourceDelta` content.** Every event carries `0`, because nothing computes per-event deltas yet (`S10-012`–`S10-019`).

## The honest summary

The hard thinking — event schema, claim key, per-mission scope, crash ordering — is now settled and proven. What remains is
durability and eligibility, and the per-event reward table that finally gives `S09-033` something to pay.
