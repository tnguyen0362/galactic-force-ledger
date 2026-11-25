# v614 — Core-loop fix: station reseat yanked players out of missions

## Defect
`StationArt.buildShell` runs a one-time "reseat" pass when the station shell finishes building
(boot +~6 s via the Main safety net). It lifted **any** character below `deck - 10` (y < 750) onto the
deck at exactly (-8,765,40). The mission terrain is at y ≈ 31 — 700 studs below the deck — so every
player who reached a mission before the shell finished (or before any rebuild) was teleported back to
the station ~4 s after arrival, with no damage, no state change and zero velocity.

## Evidence chain (bisected live, ~15 probe rounds)
- Pure manual `PivotTo` with zero game state reproduced the snapback: positional, not mission logic.
- Free-fall at (500,*,500) never triggered it; standing grounded anywhere low did (probe-created platform).
- Streaming disabled: unchanged. Same-character identity: no respawn. Anchored: still moved — scripted CFrame write.
- `teleportTo` instrumentation: never fired at snapback. GF.Main disabled: no snapback → GF code.
- Service bisect (noop-stub halves): snapback requires StationService; dependents exonerated.
- Timing analysis: teleport at boot+2 → snapback at boot+~6; teleport at boot+9 → NO snapback. One-time boot event.
- Reading the build path: `StationArt.reseat` writes `root.CFrame = base * CFrame.new(-8, 5, 40)` = exactly (-8,765,40).

## Fix
`reseat` now exempts players whose `StationService.zoneOf` is `"Mission"`. The startup rescue still
protects players who genuinely spawn under the unbuilt shell (they are never in Mission zone).

## Verification
`[GF_FV] deploy=true yseq=31 x14 zone=Mission` — deployed at boot+2, player remained at the mission
terrain through the boot+6 reseat window and beyond. Place saved as v614.
