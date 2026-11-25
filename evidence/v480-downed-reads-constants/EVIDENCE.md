# My own conformance check was certifying dead config (place 480)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, fresh Play VM. Place saved as **version 480**.

## What I set out to do

Enumerate every service-local numeric tunable that `CheckRunner` cannot see, so the "unreachable config" gap became a finite list
instead of an open concern. The scan found **64** such tunables.

Two of them were alarming.

## Finding 1 — the check was right about the numbers and wrong about the object

`DownedService` declares its own locals:

```lua
local BLEEDOUT = 45
local REVIVE_TIME = 3.5
local REVIVE_RANGE = 12
```

and it **never requires `Constants` at all** (`Constants referenced? false`). Meanwhile `Constants.Combat` carries
`DownedTimeout = 45`, `ReviveDuration = 3.5`, `ReviveRange = 12` — and a consumer scan found:

```
DownedTimeout    consumers outside Constants/CheckRunner: NONE
ReviveDuration   consumers outside Constants/CheckRunner: NONE
ReviveRange      consumers outside Constants/CheckRunner: NONE
RollRecharge     consumers outside Constants/CheckRunner: MovementService
ShieldRegenRate  consumers outside Constants/CheckRunner: VitalsService
HealthRegenRate  consumers outside Constants/CheckRunner: VitalsService
Pity             consumers outside Constants/CheckRunner: ProfileService
```

So my own "CONST DRIFT: DownedTimeout = 45" and "CONST DRIFT: ReviveDuration = 3.5" assertions were **certifying values that
nothing reads**. That is precisely the failure mode I warned about one batch earlier when I refused to centralise
`INTERACT_RANGE` — and I had already committed it two batches before saying so.

The *numbers* happened to agree (45 and 3.5 in both places), so the reported drift was still true of behaviour. The **method**
was wrong: a check pointed at an unused copy of a value proves nothing about the value in use. Had `DownedService` said 30 while
`Constants` said 45, the check would have passed while the game bled out players in 30 seconds.

## The fix

`DownedService` now reads the shared constants, with the old literals as fallbacks:

```lua
local CombatConstants = require(ReplicatedStorage.GF.Shared.Constants).Combat or {}
local BLEEDOUT = tonumber(CombatConstants.DownedTimeout) or 45
local SOLO_REDEPLOY_DELAY = 10
local REVIVE_TIME = tonumber(CombatConstants.ReviveDuration) or 3.5
local REVIVE_RANGE = tonumber(CombatConstants.ReviveRange) or 12
```

Values unchanged (45 / 3.5 / 12) — **centralisation, not retuning**. One source of truth, and the conformance check now measures
what actually governs behaviour.

## Measured

```
boot ok=false  passed=638  failed=16        <- identical to before, behaviour unchanged
  spec drift: DownedTimeout = 45, spec 60-60
  spec drift: ReviveDuration = 3.5, spec 3-3
Constants.Combat: DownedTimeout=45 ReviveDuration=3.5 ReviveRange=12
DownedService loads=true
```

Boot parity confirms the move changed no behaviour. The two drifts are now **meaningful**: they are asserted against the values
`DownedService` reads, so fixing `Constants.Combat.DownedTimeout` to 60 would now actually change the bleedout.

## Finding 2 — the mission clock is 25 minutes, not 15

From the same scan: `StationService.MISSION_SECONDS = 1500`.

`GOAL_2026-11-24.md` says *"15min standard active clock"* (also *"15min including 60–90s extraction defense"*). 1500 s is **25
minutes**. The `v433` evidence recorded a fresh deploy reading `MISSION 24:52` — the measurement was correct and nobody compared
it to the spec.

Recorded rather than changed: mission length is a pacing decision, and shortening it by 40% changes the whole game's shape.

## The general lesson, now with my own name on it

Three separate values this session were asserted, measured, or documented while being **unread by the running game**:
`InteractRange` (removed), `DownedTimeout`/`ReviveDuration` (just centralised), and — earlier in the project's history — the
pity constants. A conformance check is only worth its assertions if it points at the code path that executes.

The mechanical rule that would prevent it: **assert the value at its consumer, or centralise so the consumer cannot disagree.**

## Limits

- Only `DownedService` was centralised. The scan lists 64 service-local tunables; most are technical (animation amplitudes, deck
  heights, tick rates) and appropriately local. The spec-governed ones among them — `EncounterDirector.MAX_ACTIVE`,
  `ObjectiveService.SABOTAGE_HOLD`/`RECOVER_HOLD`/`DEFEND_TIME`, `ExtractionService.COUNTDOWN`/`EMERGENCY_GRACE`,
  `DispatchService.MAX_SQUAD` — remain unasserted and are the real backlog.
- `MISSION_SECONDS` was not changed.
- No behaviour was measured this batch beyond boot parity.
