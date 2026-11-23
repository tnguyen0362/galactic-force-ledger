# RETRO — friction that will recur

- **Fresh VM per `execute_luau`** (cost: ~10 wasted probes chasing a nil profile that was never nil).
  Fix: always verify via `workspace` attributes / prints / captures. Now standard practice.
- **`gsub` with unbalanced captures** (cost: 2 failed edits, `invalid pattern capture`).
  Fix: `replaceLiteral(haystack, needle, replacement)` using `find(_, 1, true)` — plain text, no patterns.
- **Edits during Play mode are silently discarded.** Cost: one wasted round of "fix didn't apply".
  Fix: stop play → edit → verify by reading the Source back → play.
- **Long single-call test sequences drift** (48s waits inside a client call, character died mid-wait).
  Fix: park the test character on the extraction pad before long waits.
