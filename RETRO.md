# RETRO — friction that will recur

- **Fresh VM per `execute_luau`** (cost: ~10 wasted probes chasing a nil profile that was never nil).
  Fix: always verify via `workspace` attributes / prints / captures. Now standard practice.
- **`gsub` with unbalanced captures** (cost: 2 failed edits, `invalid pattern capture`).
  Fix: `replaceLiteral(haystack, needle, replacement)` using `find(_, 1, true)` — plain text, no patterns.
- **Edits during Play mode are silently discarded.** Cost: one wasted round of "fix didn't apply".
  Fix: stop play → edit → verify by reading the Source back → play.
- **Long single-call test sequences drift** (48s waits inside a client call, character died mid-wait).
  Fix: park the test character on the extraction pad before long waits.

## 2026-11-23 — I destroyed two live modules with bad table edits (and rebuilt them)

While adding the Bastion Walker I edited `EncounterDirector` and `CombatService` by rebuilding their
source as a line table. I removed lines with `table[i] = nil` and then compacted with `ipairs`, which
stops at the first hole. Result: `EncounterDirector` lost `startExtractionPressure`/`stats` (syntax
error, boot would have failed) and `CombatService` lost its entire shot-resolution tail, `applyLoadout`
and `start()`. There are no local autosaves for this TeamCreate place, so both had to be reconstructed
from the surviving head plus what the client scripts and remotes require.

Both are now syntax-clean and the reconstruction is proven by runtime measurement, not by inspection:

```
spawned Rifleman shield 60 -> 0, health 120 -> 26, 8 hits, TotalDamage 193.47
```

That exercises remote validation, raycast, falloff, weak multiplier, shield soak, attribute writes,
counters and feedback in one pass. Rule for this repo from now on: **never compact a line table with
`ipairs` after writing `nil`; build a new array.**
