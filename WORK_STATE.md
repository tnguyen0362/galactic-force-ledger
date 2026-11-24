# WORK_STATE — last verified 2026-11-24, place version 399

## Current build
- Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, place `Playtest1` (placeId 120646942844931), saved as **version 399**.
- Spec `.goal/GOAL_2026-11-24.md`; ledger `REQUIREMENT_COVERAGE.csv` **815 rows, 38 populated, 784 UNKNOWN**.
- Ledger state: PARTIAL 29 | VERIFIED 2 | VERIFIED 0 | OWNER_ACCEPTED 0.

## Verified this session
**Elimination family** (evidence/v383-elimination/EVIDENCE.md) — `Head of the Spear` 3 tagged (Officer + 2 Rifleman), `Siege Breaker` 1 tagged Bastion Walker, `Broken Talon` 3 tagged (Marksman + Heavy + Officer). Each completed only when its whole roster was down; 2/3 left the objective open.

**Conquest family** (evidence/v385-conquest/EVIDENCE.md) —
| Variant | Stage 1 | Stage 2 | Stage 3 |
|---|---|---|---|
| Forward Dominion | 4 defenders | console interaction | 45 s hold → complete |
| Iron Foundry | power interaction | control-point interaction | 60 s hold → complete |
| Thronefall | 3 guards | HighMarshalVeyr 3200 HP | command node → complete |

Rank gate verified by temporarily requiring rank 99: deployment refused with `requires military rank 99`, no mission started; restored to 10 and re-saved.

Counts: **5 of 5 families exist and are playable; all 15 variants are verified complete on Normal** (13 at builds 393-397, the last three re-run at 398).


## Verified at build 387
**Destructible objective structures** (`CombatService.damageStructure`): parts carrying `GFIntegrityMax` take the same falloff-adjusted weapon damage an enemy would, set `GFDestroyed`, and are polled by the objective machine.

**Sabotage | Shattered Aegis** (`SABOTAGE_AEGIS`), real weapon fire through `FireWeapon`:
- generators 300 HP each, destroyed in 13 and 14 AR01 shots;
- emitter shielded until both are down — six shots at it were deflected, integrity stayed 700;
- emitter 700 HP, destroyed in 56 shots across two reloads; `GF_ObjectiveComplete=true`, `GF_StructuresDestroyed=3`.

Shield leak found and fixed: `CanQuery=false` alone did not stop damage (700 → 568). Damage now gates on the `GFShielded` attribute and counts `GF_ShieldDeflected`.

Frame `ScreenCapture_AEGIS_SHIELDED` shows the new objective line `Destroy the shield generators (0 / 2)`.

Automation note: a camera-origin shot is rejected `origin-too-far`; fire from `root + (0, 2, 0)`. `workspace.GFDebug` reports `Accepted` / `Rejected` / `LastReject` / `LastStructure`, which separates a rejected shot from a miss.


## Verified at build 388
**Recovery | Fallen Convoy** (`RECOVERY_CONVOY`): crate A recovered (1/2, stage stays 1) → crate B → stage 2 with a tagged pursuit squad of Rifleman/Scout/Heavy → 2 of 3 dead left the objective open → 3rd kill completed it.

**Defense | Last Transmission** (`DEFENSE_UPLINK`): activate dish → stage 2 timer → at 78 s the stage moved to 3 and the terminal prompt changed to `Confirm uplink` → confirming set `GF_ObjectiveComplete=true`. The defend uses its own 75 s timer, not the beacon's 60 s.

Both reuse existing machinery only: tagged rosters and the 0.5 s timer.


## Verified at build 393 — Defense | Power Under Fire
First defence object that can actually be lost: 600 HP on Normal, hostiles shoot it when no player is visible, the 90 s timer pauses when nobody is inside 55 studs, and destroying it sets `GF_ObjectiveFailed` instead of completing.
- player present 20 s: 549.5 → 476.5 integrity (~3.65 HP/s, survives the 90 s window);
- player absent 12 s: timer 63 → 63, `GF_DefensePaused=true`; returning resumed 63 → 59 in 4 s;
- generator destroyed: `GFIntegrity=0`, `GFDestroyed=true`, `GF_ObjectiveFailed=true`, `GF_ObjectiveComplete=false`.

Three defects found and fixed while building it:
1. **Instance attributes return an `InstanceHandle`** — publishing the structure as an Instance killed every enemy tick with `IsA is not a valid member of InstanceHandle` (seven logged repeats). Names are published and resolved instead.
2. **`lineOfSight` rejects large targets** (3-stud tolerance), so hostiles refused to shoot a 7×9×7 generator they were standing in front of. Replaced with a direct raycast that accepts the structure's own model.
3. **Un-gated structure fire is unfair** — eight hostiles destroyed 600 HP in 22 s. Gated on `GF_DefenseEngaged` and scaled to `def.damage * 0.25`.


## Verified at build 397 — the last two variants and the hacking subsystem
**Hacking** (`HackingService` + `HackState`/`HackAttempt` + MissionHUD overlay) is server-authoritative: the client presses, the server derives the needle angle from `workspace:GetServerTimeNow()` and decides hit or miss. Normal = 95° arc, 1.3 s rotation. Measured 3 hits → complete, and a deliberate out-of-arc press at stage 1 dropped the stage to 0 with `GF_HackMisses=1` (spec floor is 0).

**Sabotage | Burn the Arsenal**: pad A armed (1/2), pad B → warning; stage 2 at +2 s, stage 3 at +9 s, so the 8 s warning is real; stockpile removed, objective complete.

**Recovery | Silent Archive**: approach auto-advanced to stage 2, interaction started the hack, 3 in-arc presses → stage 3 with the intel case revealed, interaction completed the objective.

Defects fixed: the HUD kept the previous mission's green `PRIMARY OBJECTIVE COMPLETE` on a fresh deployment (verified by scanning `PlayerGui`: `COMPLETE` → `PRIMARY OBJECTIVE` after redeploy); the revealed intel case was faded by the Neon completion flourish (now Metal); the hacking miss floor was 1 instead of 0; and six `StationUI` table entries were missing commas, which killed the whole client script until fixed.

Lesson: syntax-check every edited script with `loadstring` before a playtest — the StationUI parse error only surfaced as a client log line.


## Verified at build 398 — the variant table is closed
- `RECOVER_TECH`: black box → `CarriedCase` on the character → delivered at the LZ → complete.
- `DEFEND_BEACON`: 60 s hold completed.
- `DEFENSE_POWER`: restore → 90 s survived at 520/600 HP → stage 3 → stabilise → complete.
- Hacking cancel: watchdog on range/downed/disconnect; observed release with reason `downed`, stage reset, console unlocked for retry.

Ledger now has **2 VERIFIED rows** (`COUNT-VARIANT`, `S08-003`) — 15 of 15 variants played to completion. Owner acceptance is still pending and is not mine to grant.

**Harness lesson:** `StationService.deploy` sets `GF_DeployGraceUntil = os.clock() + 4`, so grace armed before a deploy is overwritten. The player then dies, respawns at the station, and the defence timer pauses — which reads as a stuck objective. Re-arm grace after deploying, and re-assert it during long timers.


## Verified at build 399 — objective markers (`S08-033`, was the only MISSING row)
A diamond plus distance label, projected with `WorldToViewportPoint`, clamped to a 46 px margin when off-screen or behind the camera. Server picks the position per template (living elimination target, otherwise the objective) and sends it inside `ObjectiveProgress`; it is nil once complete.

Measured: `TARGET 45 m` with three tagged Talons alive, live update to `TARGET 87 m` when the player moved ~75 studs, marker hidden after the objective completed.

**Defect fixed:** the marker function, defined near the top of `ObjectiveService`, captured a *global* `elimTargets` because the local of that name was declared 600 lines further down — so it silently fell back to `OBJECTIVE (behind) 752 m` and never updated. Forward declaration fixed it. `loadstring` cannot catch this class of bug; reading the rendered value did.

## Defects fixed this session
1. `ObjectiveService` had no elimination builder at all — elimination deploys fell through to `buildRelay`. This was the `targets=0` null result recorded at pause time.
2. Elimination tracker started before `objective` was assigned, so it exited on its first iteration; now started from `setup` with a generation counter.
3. Bosses leaked across deployments because `EncounterDirector.reset` only swept models with a `Humanoid`; measured five `BastionWalker` models after five deployments. Reset now spares `GF_ObjectiveTarget` and `setup` destroys stale tagged targets; `beginMission` skips the optional field boss for `ELIM_WALKER`.
4. `conqEnterStage(4)` did nothing, so Thronefall's command-node capture advanced the counter without completing (measured `stage=4 complete=false`). Fixed and re-verified.

## Known gaps in the new content
- Hold/defend stages have **no failure condition** and do not pause when the squad leaves (`S08-029`, `S08-031`).
- No target marker system anywhere (`S08-033` MISSING).
- Thronefall's "breach" is a three-guard clear, not a fortification with HP.
- Missing authored stages: commander's optional relay, Walker's "secure battlefield", Talon's "linked encounter", Foundry's turret dependency.
- Kills in all tests were applied via the `Dead` attribute that `CombatService` writes; weapon → damage → kill was not re-exercised. Solo only.

## Next highest-value work

1. **Hacking cancel extras** (`S08-040`): explicit exit input and a terminal mutex for two players on one console.
3. **Target markers** (`S08-033`) remain MISSING across every mission.
2. **Hacking subsystem** (`S08-036`–`S08-043`) — referenced by every authored variant that says "hack console"; nothing exists yet.
3. **Target markers** (`S08-033`) — affects every mission.
4. Defense object HP + absence pause (`S08-029`, `S08-031`).

## Environment
`.goal/PAUSE` absent. Studio in Edit mode, place saved at 385, HEAD includes this batch after commit.
