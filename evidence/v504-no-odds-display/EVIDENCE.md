# No cache-odds display exists anywhere (place 504)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, plugin-level scan of all `StarterPlayer` script sources. No place changes.

## Method

Two passes over every `LuaSourceContainer` under `StarterPlayer`:

1. keyword scan for `odds` / `chance` / `probability` / `%%` → 81 hits
2. the same scan excluding lines that are `string.format` calls → **0 hits**

Every one of the 81 was a format string (`"SHIELD %d"`, `"%.1fs"`, `"EXTRACTION VOTE %d/%d"`). **No UI anywhere shows a drop
probability.**

## The three rows

- **`S11-027`** (show true per-draw and whole-cache odds) — ABSENT. Nothing computes or displays it. The data required exists
  (`Caches.weights`, `rollRarity`), so the maths is available; it is simply never surfaced.
- **`S11-028`** (per-cache probability maths, e.g. `1-(1-p)^n` for at-least-one outcomes) — ABSENT. No such computation appears in any
  script, client or server.
- **`S11-029`** (do not imply guarantees unless they are real) — **vacuously satisfied**: with no odds shown, nothing can overstate them.
  But that is an accident of absence rather than compliance, and the row's real intent — honest disclosure — is unmet.

## Why this matters more than it looks

`S11-011`'s weight tables are verified to sum to 100, and the tier weights exist and are read. So the game has honest underlying numbers and
tells the player **nothing** about them. In a game whose economy is cache-driven, a player cannot distinguish a Common tier from Legendary
without opening dozens — and the authored distributions (which, per the earlier audit, do not even match the config) are invisible either
way.

The corresponding server-side observability exists: `GF_CacheOpened`, `GF_CacheHeld`, `GF_CacheBulk`, `GF_CacheBlocked` are all published.
Those are developer attributes, not player disclosure.

## What implementing it would take

Small and self-contained: the weights are already in config, `rollRarity` already consumes them, and a display needs only a normalised
percentage per tier (weight ÷ 100) plus the per-cache `1-(1-p)^n` for "at least one of n". No new state, no persistence, no architecture —
which makes it one of the few remaining rows that is pure presentation work on top of data that already exists.

## Confidence

High for the absence claim: exhaustive over all client sources with an exclusion that isolates genuine references. What I did not check is
whether the armory's cache section might be intended to show odds under a different vocabulary (`rate`, `rarity %`), though the second pass
would have caught `%` usage in prose too.
