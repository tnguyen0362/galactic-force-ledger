# HUD reserve verified — and the previous batch had broken player state entirely (place 541)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 541**.

## Following the resume order found a fatal bug, not a cosmetic one

Step 1 was "confirm a fresh spawn produces `s.reserve = 168`". The answer was:

```
no state
still no state at +9s
```

**No player state existed at all.** The log gave the cause:

```
ServerScriptService.GF.Services.State:56: attempt to index nil with 'GF'
```

My catalogue-seeding expression in the previous batch used `ReplicatedStorage.GF.Shared.Configs.Weapons`, but `State` has **no top-level `ReplicatedStorage` local** — it calls
`game:GetService("ReplicatedStorage")` inline at line 39. So the expression threw during state construction, and `State.create` failed for **every player**.

That is the difference between "the HUD reserve display is unverified" (what I recorded) and the truth: **the build was unplayable.** Every system that calls
`State.get` — combat, vitals, movement, abilities — would have been dead. I did not detect it because the batch's own probes all set state fields via direct
`State.get` calls that returned nil and reported "no state", which I read as a probe problem.

## The fix

```lua
-- NB: this file has no top-level ReplicatedStorage local; use the service directly or the
-- expression throws 'attempt to index nil with GF' and NO player state is ever created.
local ok, Weapons = pcall(require, game:GetService("ReplicatedStorage").GF.Shared.Configs.Weapons)
```

## Verified after the fix

```
state ok: weaponId=AR01  ammo=28  reserve=168
ammo label after one client shot: 27 / 28  ·  168
```

Both resume steps pass: the fresh state carries the catalogue reserve, and the HUD shows ammo, magazine and reserve, with ammo decrementing on fire.

Suite unchanged: **`passed=657 failed=17 nonDrift=0`** — all failures still the catalogued spec drifts.

## What this batch should teach

1. **A "cosmetic" change can be fatal.** The HUD work was supposed to be display-only; the state-crash came from a one-line convenience default added to make it work.
2. **`no state` in a probe is not a probe problem by default.** Three separate batches treated "no state" as a harness issue. This time it was the game.
3. **The resume-order note paid for itself.** Writing "confirm a fresh spawn yields reserve 168" at the end of the last batch is what surfaced a build-breaking bug
   within one step, instead of shipping it into another feature.

## Still not done

- **Supply crates and drops do not replenish reserve** — there is still no supply-crate system, only comments referring to one.
- No cap on reserve accumulation.
- The reserve-limited and empty-reserve live cases remain unverified (arithmetic is unit-tested).
