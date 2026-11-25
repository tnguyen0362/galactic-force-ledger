# Reserve reload verified end to end (place 536)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 536**. Diagnostics removed.

## The claim from last batch, corrected

Last batch recorded that a real reload "never reached the commit line" and suspected the `live ~= s` state-table guard. **That was wrong.** With instrumentation on the
callback entry:

```
delay = reloadTime 2.10
entry = liveNil=false  sameTable=true  reloading=true  ammo=19  reserve=168
result: ammo=28  reserve=159  reloadCount=1
```

The callback runs, sees the same state table, and commits. My earlier probes simply read the state **too early** — the reload takes 2.1 s and several runs let the reader
expire before the commit.

## Verified

```
ammo    19 -> 28      (+9 = min(28 - 19, 168))
reserve 168 -> 159    (-9, consumed)
```

That is the authored `S04-025` arithmetic working live: fill only the missing rounds, take them from reserve.

## Still unverified

- **Reserve-limited fill** (`ammo 0, reserve 5` → expect `ammo 5, reserve 0`): two attempts were inconclusive. In the last run the handler apparently never
  executed at all — `entry`, `abort` and `delay` were all nil — so the probe missed the window rather than the code failing. Not claimed either way.
- **Empty-reserve refusal**: same run, same inconclusive outcome.
- The pure unit checks do cover both cases (`reloadPlan(0,28,10)==10`, `(5,28,0)==0`), so the arithmetic is proven; only the live refusal path is not.

## A mistake worth naming

The two-case probe failed with `FireServer can only be called from the client` — I had put `remotes.ReloadWeapon:FireServer()` inside a **server** script. Server code
fires client remotes with `:FireClient`. I restructured to stage the cases server-side and fire from the client between stages, but the timing coordination between
two clocks is what made the result inconclusive.

## State of the code

Reserve is implemented and measured on the main path: `State.reserve`, seeded on equip from the catalogue, `reloadPlan` arithmetic, reserve consumed on commit,
empty-reserve gate, and `reserve` published in `AmmoUpdated`. All three temporary diagnostic publishes were removed and `CombatService` recompiles clean with zero
`GF_Reload*` references left.

## Limits

- One weapon (AR01), one player, remote-triggered rather than key-pressed.
- The HUD still does not display reserve, and supply crates/drops do not replenish it, so "limited ammo" is true of the mechanism but not yet visible or restorable
  in play.
