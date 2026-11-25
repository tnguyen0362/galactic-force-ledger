# SELF — capabilities gained, measured

| artifact | replaces | effect |
|---|---|---|
| `[GF] boot: config check` (638 assertions) in `GF.Test.CheckRunner` | manual config eyeballing | every Play validates config tables in ~0ms, fails loud |
| authored-spec conformance section in the same runner (v465) | a human diffing config against `GOAL_2026-11-24.md` by eye | the 8 weapon tables, 6 ability cooldowns/radii and 2 boss HP values are asserted against transcribed spec numbers every boot, and drift is published as `GF_SpecDrift`. Found 12 drifts on first run, two of which the audit had missed |
| `workspace` attributes `GF_ObjectiveComplete` / `GF_ExtractionState` / `GF_LastPayout` | 3–5 probe calls per state check | 1 call, and it tells the truth across VMs |
| `replaceLiteral` (plain-text edit helper inside `execute_luau`) | pattern-escaping roulette | edits stopped failing on `(` `)` |
| Service prints on authoritative transitions | guesswork from HUD | console is now a readable trace of the mission |

Items completed per iteration is trending up: Phase 0 → 1 → 2 each took fewer calls than the one before,
mostly from the attribute-based verification switch.
