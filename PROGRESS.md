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
