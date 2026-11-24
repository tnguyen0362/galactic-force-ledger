# Difficulty surface + failed-extraction cache skip (build 416)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## Three changes
1. **`Extreme` rank gate 10 → 14** per the spec (`DIFFICULTY_RANK`).
2. **All four difficulties advertised.** `RequestDeployOptions` returned `{ "Easy", "Normal" }`, so Hard and Extreme existed but were unreachable from the UI. Now `{ "Easy", "Normal", "Hard", "Extreme" }`.
3. **Defence object HP followed the wrong difficulty.** `buildPower` read `State.getMission().difficulty`, but `resetMission()` calls `ObjectiveService.setup` **before** `State.setMission`, so it saw the previous mission's difficulty. Measured: an Extreme deploy built a **600 HP** generator (Normal). It now reads `GF_OperationDifficulty`, which is set earlier in the same function.

## Measured
| Check | Result |
|---|---|
| `RequestDeployOptions` payload | `Easy, Normal, Hard, Extreme`; selected `Normal`, planet `Veyra-7` |
| Deploy `DEFENSE_POWER` on Extreme (rank 15) | accepted, no `GF_DeployRejected`; `GF_OperationDifficulty = "Extreme"` |
| Generator HP on Extreme | **650** (was 600 before the ordering fix) |
| Generator HP on Normal (earlier build) | 600 |
| Failed extraction after the mission cache moved | `GF_MissionCacheResult = "skipped success=false objective=false"`, `GF_ExtractionState = "failed"`, `GF_CarriedLost = true`, zero cache opens |

That last line closes the gap left at build 415: the mission cache is granted on a successful extraction and **skipped** on a failed one, both measured.

## Notes
- The Extreme gate itself was exercised in the passing direction only (rank 15 ≥ 14). The refusal path for a lower rank was verified earlier at build 398 with a temporary gate of 99 (`requires military rank 99`).
- `S08-029` now has two difficulties measured (Normal 600, Extreme 650); Easy 800 and Hard 650 remain code paths only.
- Easy was **not** deployed in this session.

## Limits
- One player, one difficulty per run, no co-op.
- No UI check that the war-table now renders four difficulty buttons; only the payload was read.
