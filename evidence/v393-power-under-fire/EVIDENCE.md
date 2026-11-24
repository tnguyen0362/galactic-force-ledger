# Defense | Power Under Fire — object HP, hostile structure fire, absence pause, failure (build 393)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client, attributes read from Server.

## What this variant adds that no other mission had
1. A defence object with **server HP** that enemies can actually destroy.
2. A **failure** terminal state (`GF_ObjectiveFailed`) instead of completion.
3. An **absence pause**: the 90 s timer only runs while a player is inside 55 studs.

## Measured
| Step | Result |
|---|---|
| Deploy Normal | `GF_PowerStage=1`, generator `GFIntegrityMax=600` (Easy 800, Hard/Extreme 650 by code path) |
| Restore generator (interact) | stage 2, timer started |
| Player present 20 s | integrity 549.5 → 476.5 (73 damage ≈ 3.65 HP/s; a 600 HP generator survives ~164 s of the 90 s window) |
| Player leaves (station), 18 s | integrity 476.5 → 471, `GF_DefensePaused=true`, `GF_DefenseEngaged=false`; the 5.5 residual is shots already in flight when engagement flipped |
| Timer while absent | 63 → 63 over 12 s (delta 0) in an earlier run |
| Timer resumes on return | 63 → 59 over 4 s |
| Destroy the generator | `GFIntegrity=0`, `GFDestroyed=true`, `GF_ObjectiveFailed=true`, `GF_ObjectiveComplete=false`, stage stays 2 |

## Defects found while building this (all fixed, all measured)
1. **`Instance` attributes come back as `InstanceHandle`.** Publishing the defence object as `workspace:SetAttribute("GF_DefenseStructure", part)` made every enemy tick die with `IsA is not a valid member of InstanceHandle` (`LogService` history showed seven repeats). Fixed by publishing the model and part **names** and resolving them on the enemy side.
2. **`lineOfSight` is wrong for large targets.** It rejects a hit that lands more than 3 studs from the aim point — correct for a humanoid, wrong for a 7×9×7 generator, so every hostile refused to shoot the objective it was standing in front of. Fixed with a direct raycast that accepts a hit on the structure or its own model.
3. **Un-gated structure fire is unfair.** With the gate absent, eight hostiles took a 600 HP generator from full to zero in **22 s**, outside any defend window. Fixed by requiring `GF_DefenseEngaged` (a player inside the radius) and scaling structure damage to `def.damage * 0.25`; measured drop afterwards was 3.65 HP/s.
4. Balance note: full damage (`def.damage`) killed the generator inside the window even with a player present; the 0.25 scale is what the measurements above reflect.

## Limits
- Failure sets `GF_ObjectiveFailed` and fires `ObjectiveComplete{success=false}`; the debrief/emergency-evac wiring for a failed primary has not been re-verified here.
- Only this variant publishes a defence structure; the beacon and uplink still cannot be attacked.
- `GF_DefenseEngaged` is per-mission state; a second simultaneous defence would need per-objective naming.
- Enemy kills still use the `Dead` attribute path; weapon→structure damage was verified at build 387.
- Solo only.
