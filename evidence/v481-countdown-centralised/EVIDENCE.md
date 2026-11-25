# Extraction countdown centralised and asserted: 45 against a 60–90 range (place 481)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, fresh Play VM. Place saved as **version 481**.

## Applying the rule from last batch, in the right order

Last batch's lesson was: *assert the value at its consumer, or centralise so the consumer cannot disagree* — and specifically,
**centralise first, assert second**, or the check goes red against something nothing reads.

This batch does that for the extraction defence countdown, which was a `ExtractionService` local:

```lua
local COUNTDOWN = 45
```

## Spec

`GOAL_2026-11-24.md`, verbatim:

> *"…nearest validated extraction zone after primary, no mandatory walk before call; **defense countdown 75s default (60–90 by
> difficulty/variant)**, players may freely move/loot/fight away from LZ."*

45 is **outside the authored range entirely** — below the fastest variant by 15 s.

## Change, in the order that keeps the check honest

| step | change |
|---|---|
| 1 | `Constants.Mission.ExtractionCountdown = 45` — the value **moved unchanged** |
| 2 | `ExtractionService` reads it (`tonumber(...) or 45` fallback), so the constant is now the governing value |
| 3 | `CheckRunner` asserts it within **60–90** |

Because step 2 happened before step 3, the assertion points at the value that actually runs.

## Measured

```
boot ok=false  passed=638  failed=17
  spec drift: ExtractionCountdown = 45, spec 60-90
Constants.Mission.ExtractionCountdown=45
ExtractionService loads=true
```

`failed` moved 16 → 17 and `passed` is unchanged, which is the correct signature for a newly-asserted value that genuinely
fails. Behaviour is untouched — the countdown is still 45 s, because shortening or lengthening the extraction defence window is
a pacing decision.

## A three-way disagreement found on the way

While editing `Constants.Mission` I read the block:

```lua
DurationShort = 660,
DurationStandard = 990,
DurationExtended = 1350,
```

So mission length now has **three** values in play:

| source | value |
|---|---|
| `Constants.Mission.DurationStandard` | **990 s** (16.5 min) |
| `StationService.MISSION_SECONDS` | **1500 s** (25 min) — what the game actually runs |
| `GOAL_2026-11-24.md` | **900 s** (15 min) |

`Constants.Mission.Duration*` appears to be another unconsumed block of the same family as `InteractRange`, `DownedTimeout` and
`ReviveDuration`. It was **not** centralised here, because mission length is governed by `StationService` and moving it is a
larger change than this batch should carry. Recorded on `S09-017`.

## Limits

- The countdown value was not changed; only its location and its visibility.
- The 60–90 "by difficulty/variant" clause is unimplemented in any form — there is a single countdown, not a per-difficulty one,
  so the mapper cannot currently express the authored variation even after the value is fixed.
- No extraction was run this batch; boot parity plus module load is the whole verification.
