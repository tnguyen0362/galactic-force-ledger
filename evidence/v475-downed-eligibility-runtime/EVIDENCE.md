# Downed players stay eligible — now tested, not just read (place 475)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. No source changes, so the place was
not re-saved.

## The gap being closed

The `eligibleUserIds` batch recorded this honestly:

> *"**downed** — spec says a downed player is still eligible. Not exercised; I did not down the player and check that their
> state survives… source reading, not a runtime downing test."*

`S09-027` requires shared credits and salvage to be credited to *"each eligible present active/downed/pending-life
participant"*, so a downed soldier dropping out of the eligible set would under-pay exactly the player who most needs the
payout.

## Measured

Probe `Script` in `ServerScriptService`, live module instances, real `VitalsService` calls:

```
before down    state=true  downed=false  eligible=1[1889759131]
Vitals.downPlayer(plr) -> ok=true
after down     state=true  downed=true   eligible=1[1889759131]
Vitals.revive(plr)     -> ok=true
after revive   state=true  downed=false  eligible=1[1889759131]
```

Three things confirmed:

- **A downed player remains eligible** (`downed=true` with `eligible=1`). `DownedService` sets a flag and never calls
  `State.clear`, so the entry survives — the source reading was correct.
- **Revive restores the same state** without churn to the eligible set.
- The eligible set is stable across a down/revive cycle, so settlement cannot see a player flicker in and out.

## Still unproven

- **pending-redeploy** — a soldier waiting to redeploy has no distinct `State` representation, so whether they count as
  eligible is genuinely unknown rather than untested.
- **co-op** — one client. Multi-player sets, and the "not divided by P" rule in `S09-027`, remain unexercised.
- **disconnect grace** — no restore path exists; the ledger is in-memory and a disconnect simply drops the player from later
  events.
- The probe downed the player via `VitalsService.downPlayer` directly, not by taking lethal damage in combat, so the
  damage→down transition is not what was exercised.
