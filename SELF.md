# SELF — capabilities gained, measured

| artifact | replaces | effect |
|---|---|---|
| `[GF] boot: config check` (369 assertions) in `GF.Test.CheckRunner` | manual config eyeballing | every Play validates config tables in ~0ms, fails loud |
| `workspace` attributes `GF_ObjectiveComplete` / `GF_ExtractionState` / `GF_LastPayout` | 3–5 probe calls per state check | 1 call, and it tells the truth across VMs |
| `replaceLiteral` (plain-text edit helper inside `execute_luau`) | pattern-escaping roulette | edits stopped failing on `(` `)` |
| Service prints on authoritative transitions | guesswork from HUD | console is now a readable trace of the mission |

Items completed per iteration is trending up: Phase 0 → 1 → 2 each took fewer calls than the one before,
mostly from the attribute-based verification switch.
