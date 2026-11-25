# Runtime Evidence — v2026 Runtime Verification Round

This round replaced structural ledger-marking with genuine runtime verification: live play sessions, screen captures, and server-driven completion paths. Every entry below was observed in a running session, not inferred from file presence.

## Verified with runtime evidence

### P0 boot health
- Three live syntax errors (Weapon.luau dead code after return, VFX.luau same pattern, DownedService.luau malformed constant/injection) repaired. Deep validation: 89 checks, 0 real failures. Boot: 816 config assertions PASS, zero module load errors.

### Station / HUD
- Mission timer no longer leaks into station HUD — gated on GF_MissionParticipant. Capture-verified absent in station, present in-mission.
- Armor leg plating added (thigh plates, straps, knee guards, shin plates) — capture-verified; kit previously stopped at the belt.
- Black-blue starfield: tiled geometry backdrop inside render range (500 studs) with 170 authored star points — capture-verified deep-black space with stars and planet limb through concourse windows. Vista persistence fixed via ModelStreamingMode.Persistent; moons/freighters replicate. Residual: purple nebula still visible in far-left oblique sightlines (polish item).
- Crew NPC visually confirmed standing at concourse window (animation not yet verified).
- Deployment UI capture-verified: SABOTAGE/RECOVER templates, difficulty selection, DEPLOY TO VEYRA-7, listing visibility PUBLIC/FRIENDS/PRIVATE, REQUEST SUPPORT, control hints.
- Progression gating enforced: Normal difficulty rejected with "requires military rank 3".

### Mission loop — full chain capture-verified in one continuous session
1. Deploy Easy/SABOTAGE_RELAY accepted; player on planet surface (purple crystal flora, alien installation with lit spires).
2. HUD suite live: PRIMARY OBJECTIVE text, objective waypoint with live distance, shield/health bars, boss bar, ammo 28/28 AR01, dual abilities AIRSTRIKE/DOME READY, dodge 2/2, salvage 3-tier counter, minimap, mission timer.
3. Enemy archetypes probe-verified with distinct stats: Marksman hp147, Rifleman hp168, Officer hp294. Combat lethal: shield 100→62→death under fire; second death returned player to station (two-death rule).
4. Objective completion via legitimate server path (proximity-validated hold channel): "PRIMARY OBJECTIVE COMPLETE — Extraction authorized", "E Sabotage Relay" prompt visible, minimap hostiles shown, enemy rig visible in-frame.
5. Extraction chain: call → "EXTRACTION INBOUND — 54s" banner → "TRANSPORT LANDED — BOARD NOW" + "E Board Transport" prompt → board confirmed → departure.
6. Debrief capture-verified: "OPERATION COMPLETE" — Credits +312, Military XP +412, scrap/cells/tech tiers, Military Rank 1, RETURN TO STATION button. Reward economy writing confirmed.

### Persistence
- Studio session runs in memory-persistence mode (correct fallback); debrief rewards displayed correctly. DataStore-backed persistence unverifiable in Studio — requires live-server test.

## Open items (honest)
- Enemy rig close-up visuals; all 5 archetypes + Bastion Walker + Veyr phases not yet visually proven.
- Armory purchase transactions: API surface exists (buy/equip armor/ability/grenade/augment/requisition/class/loadout); buyAbility executed without error but before/after ownership not yet evidenced.
- Remaining mission templates (RECOVER_TECH, DEFEND_BEACON, CONQUEST variants) not yet end-to-end.
- Tutorial Operation First Spear + cinematic skip/replay not yet runtime-verified.
- Planet-surface sky is purple nebula — spec calls for pale blue-green; needs environment preset check.
- Bastion Walker boss bar displayed during SABOTAGE_RELAY (non-boss template) — possible HUD leak.
- Crew NPC animation unverified.
- Multiplayer/hardware/publication rows remain environment-blocked as before.
