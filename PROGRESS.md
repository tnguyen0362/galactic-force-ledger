# PROGRESS

**Moved.** The single source of truth is `.goal/PROGRESS.md` — the ledger the goal supervisor reads.
The earlier Phase 0-2 tables live on at `.goal/legacy-PROGRESS.md` (frozen, historical).

Do not append here; split ledgers are how verified work gets lost.

## Iteration 21 — armory becomes playable (v104–v106)
- `RequestLoadout`/`SetLoadout` had **zero server listeners** before today: the armory was unprovable no matter what the UI looked like. New `ServerScriptService.GF.Services.ArmoryService` now owns `ownedWeapons`, `selectedLoadout`, `selectedClass`, with rank + credit gating and a state push back to the client.
- New client `StarterPlayerScripts.StationArmoryUI`: proximity prompt at the racks (46 studs), panel with 6 weapons (name, category, damage, magazine, fire mode), BUY/EQUIP/EQUIPPED, live credits/rank, and the four soft classes.
- Closed an economy hole: `CombatService.equip` accepted any weapon id from the client, so a 3000-credit weapon was free via `EquipWeapon`. It now requires `profile.ownedWeapons[id]`.
- `CombatService.applyLoadout` applies the armory primary to session state on equip and on `CharacterAdded`, so the mission actually carries it.
- Proven live: MR-07 purchase (2700→1850) and SG-04 equip, with the mission HUD reading `SG04 6/6` (capture `V106_01`).

## 2026-11-23 — three playable mission templates (v112-v113)
Booted relay-only objective was replaced with a template-driven `ObjectiveService` (`SABOTAGE_RELAY`,
`RECOVER_TECH`, `DEFEND_BEACON`); `StationService.resetMission`/`deploy` now carry the chosen template,
`RequestDeployOptions` advertises all three, and the war-table card has a mission chip row.
Verified in play: RECOVER_TECH builds `ScientificTransport` + terminal and completes on a 7 s hold
(`GF_ObjectiveComplete=true`); DEFEND_BEACON builds `CommBeacon`, activation publishes
`Holding beacon: 57 s` ticking progress and completes at 60 s (`GF_ObjectiveComplete=true`).

## Station interior art — armoury (MICRO-008) and dispatch alcove (MICRO-009), v143–v149

Both alcoves had signs and nothing under them, which is what a player reads as unfinished. Built
in `StationArt`: armoury rack walls with weapon silhouettes under cyan header strips, bench and
lockers; dispatch counter with hood, two terminals, comms mast and dish, and a nine-bar waveform
that moves while the game runs.

- Armoury (v143–v145): rack posts + six rifles per side + cyan headers so the bays read from the
  concourse. First capture (V143_01) showed the rack was only visible from inside the bay, so the
  bays were pulled toward the corridor mouth.
- Dispatch (v146–v149): first capture (V146_01) showed the waveform merged into one blown cyan
  slab and the neon screen bezel reading as a light fixture; the signal was then mounted on the
  operator side where no player ever sees it (V147_01). Moved to the queue-facing counter face
  (v148), then the queue caps, which were 0.7 stud neon cubes a stud from the camera and filled
  the whole frame (V148_01), became metal caps with a small lamp (v149).
- Live behaviour asserted rather than assumed: the signal bars change height between two samples
  0.6 s apart (`bars=1.58,2.58,2.49 -> 2.23,2.24,3.01`), and 371 checks still pass.
- Version note: ArmouryStation rack drop lies inside the camo-clone spawned after SendClaim(...)
  so it was unparented by the armory's delayed re-parent — that was fixed in the war-table branch
  (`84950fa`, sanity report `6/6`). The `Humanoid` skin complaint on the generic clone remains
  unfixed and still prints on self-test.

Honest limit: V149_01 is a wide corridor frame, not an alcove frame — it proves no regression at
the queue end, not the alcove's readability. No frame yet shows a player standing at the counter
reading the signal shield to shield.
