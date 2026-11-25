# Both remaining reserve cases verified live (place 542)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. No source changes; probes removed and place re-saved.

## Cases closed

**Reserve-limited fill** — `ammo = 0, reserve = 5`, reload fired through the client remote:

```
ammo 0 -> 5      reserve 5 -> 0      reloadCount 1
```

The magazine fills to **5**, not 28, and the reserve is exhausted exactly. That is `n = min(capacity - ammo, reserve)` behaving as authored when the reserve, not the magazine, is the limit.

**Empty-reserve refusal** — `ammo = 5, reserve = 0`, reload fired:

```
ammo 5 (unchanged)   reserve 0 (unchanged)   reloadCount 0
```

`reloadCount` staying at **0** is the important part: the reload never *starts*, so no animation plays and no time is wasted. The gate is before the state change, not after it.

## Why the previous batch couldn't get these

Two batches ago I recorded both cases as "inconclusive" with the handler apparently never running. The cause was **my read windows, not the code**: the commit lands later than I assumed, and my readers expired first. With a 22-second reader the results are unambiguous.

The intermediate attempt in this batch also produced a false negative — an instrumented attribute came back `nil`, which I initially read as "callback never runs". I had inserted the instrumentation after the **first** `local live = State.get(player)` in the file rather than the one inside the reload callback. Same probe-error family as the rest of the session.

## Cumulative evidence for the reserve feature

| case | measurement |
|---|---|
| normal refill | ammo 19 → 28, reserve 168 → 159 |
| reserve-limited | ammo 0 → 5, reserve 5 → 0 |
| empty reserve | refused — reloadCount stays 0 |
| HUD display | `27 / 28  ·  168` |
| pure arithmetic | 4 unit checks in `CheckRunner` |

The mechanism is now verified from every direction I can reach without a second player.

## What `S04-027` still lacks

The row reads *"Limited ammo/reserve **and supply**; no paid ammo advantages."*

- **Limited ammo/reserve** — verified above.
- **No paid ammo advantages** — verified earlier (zero monetisation references anywhere).
- **Supply** — **absent.** There is no supply-crate or drop system in the project at all; the only occurrences of "supply" are comments describing one. So reserve is finite but **not restorable** in play, which makes the current design strictly harsher than authored.

That keeps the row PARTIAL, but for one missing system rather than an unverified mechanism.

## Limits

- One weapon (AR01), one player; reloads triggered by remote rather than by key press.
- No test of reserve behaviour across a weapon *swap* (the swap path resets `ammo` and seeds reserve from the new weapon, which is code-read only).
