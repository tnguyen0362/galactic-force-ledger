# `eligibleUserIds` on ledger events, derived from live session state (place 475)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 475**.

## Why it had to be derived

`S09-025` names `eligibleUserIds` as a required field, and `S09-027` defines who is owed: *"credited in full to each eligible
present active/downed/pending-life participant (not divided by P)"*.

`SquadService` exposes `join, leave, add, snapshot, total, reset` — there is **no eligibility notion to call**. So the set is
derived from live session state instead: a player who still has a runtime `State` entry is present and still owed. A player
whose state has been cleared (permanently dead and removed, or disconnected) is not.

## The change

`RewardLedgerService.eligibleUserIds()` builds a sorted id list from `Players` × `State.get`, `pcall`-guarded so a missing
dependency cannot fault the ledger. `appendEvent` attaches it to every authored event, and `snapshot()` copies it (an earlier
batch proved that a field missing from `snapshot()` reads as "never computed", so it is copied explicitly).

Observability: `GF_LedgerEligible` attribute.

## Measured

```
#1 primary_complete        eligible=1889759131
#2 extraction_success      eligible=1889759131
expected player userId=1889759131
GF_LedgerEligible=1889759131
eligible with state=1, after State.clear=0
```

The last line is the one that matters: with the player's runtime state cleared, the eligible set is **empty**. That is the
permanent-dead / disconnected case behaving correctly rather than paying someone who is no longer there.

## Still not verified — and this is the honest part

The set is correct for the states I could produce. What I could **not** test:

- **downed** — spec says a downed player is still eligible. Not exercised; I did not down the player and check that their state
  survives, though `State` carries a `downed` flag and is not cleared on downing, so it should be included.
- **pending-life / redeploy** — `pendingMastery`-style transient states are not modelled in `State`, so whether a
  pending-redeploy soldier counts as eligible is unproven.
- **co-op** — one local client only. Multi-player eligibility, and the "not divided by P" rule, are untested.
- **disconnect grace** — spec allows a reconnect to restore the ledger. Nothing here does that; the ledger is per-server and
  in-memory, so a disconnect simply removes the player from future events.

## Where the ledger now stands

| field on each event | state |
|---|---|
| `missionId`, `seq`, `eventType`, `serverTime`, `sourceId` | ✅ |
| `resourceDelta` (credits/xp/mastery, fractional) | ✅ |
| `eligibleUserIds` | ✅ single-client, downed/co-op/pending unproven |
| durability across restart | ❌ in-memory |
| settlement reads the ledger | ❌ still deliberate |

**Durability is now the only missing input.** The spec wants sustained retention and idempotent recovery; an in-memory journal
cannot provide either, and wiring settlement into one that evaporates on restart would produce a build that looks implemented
and loses money on the first server bounce.
