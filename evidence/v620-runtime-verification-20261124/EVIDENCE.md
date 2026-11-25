# Runtime Verification Evidence — 2026-11-24 session

Methodology: live Studio play sessions, server-driven probes + genuine screen captures.
No config-file or script-presence claims. Harness assistance is labeled where used.

## VERIFIED WITH RUNTIME EVIDENCE

1. **Full mission loop end-to-end** — deploy → objective channel (proximity hold) →
   "PRIMARY OBJECTIVE COMPLETE — Extraction authorized" → extraction call →
   "EXTRACTION INBOUND — 54s" → "TRANSPORT LANDED — BOARD NOW" → boarding → departure →
   debrief with +312 credits / +412 XP / rank progression. Captures at every stage.
2. **Failure path** — "OPERATION FAILED" debrief, zero payout, honest incomplete-objective
   economics. Capture: operation_failed panel.
3. **Enemy roster** — 5 archetypes (Rifleman/Scout/Marksman/Heavy/Officer) visually confirmed
   in distinct armored rigs with glowing visors, advancing in tactical spread (AI live).
   Bastion Walker large mech silhouette confirmed in distance. Captures: v2026_roster_lineup,
   v2026_enemy_engagement. Combat lethal: shield 100→62→death in organic play.
4. **Death/redeploy flow** — player died twice; second death returned to station with
   participation cleared (mission cascade verified by probe).
5. **Armory transactions** — RECON purchase: credits 2000→1500 exactly, GF_ArmorBought=RECON:500;
   duplicate purchase rejected (credits unchanged); rank gate enforced (rank-1 attempt no-op);
   equip applied live (GF_ArmorEquipped=RECON:true, selection switched, dress ran).
6. **Tutorial opening** — "OPERATION FIRST SPEAR 1/5" UI live with step instructions.
   Server-validated anti-skip design confirmed in code (position/damage/ammo/dodge/ability
   observation, not client self-report). Full 5-step completion NOT yet verified.
7. **Progression gating** — non-Easy deploy rejected: "requires military rank 3".
8. **Mission timer HUD** — absent in station, present in-mission (leak fixed + capture-verified).
9. **Armor legs** — thigh/knee/shin plating visible in-mission (fixed + capture-verified).
10. **Station starfield** — black starfield tiles + stars + planet limb render correctly from
    external direct view; right/center window bays good; FAR-LEFT oblique bays still leak
    residual purple (substantially fixed, not closed).
11. **Mission environment palette — VERIFIED CONFORMANT** — root cause found: empty skybox
    texture strings do NOT clear the renderer (it keeps the last valid texture); destroying the
    Sky object is required. Fix deployed (v680). Captures v2026_sky_delete_test +
    v2026_sky_final_verify2: pale blue-green sky with clouds, sage highlands (#7D8C79), warm
    rock (#9A8876), cyan alien flora, bronze/amber-lit Ascendancy installation — spec S27/S04
    Veyra-7 achieved. Bonus: TRANSIT IN PROGRESS deployment loading screen capture-verified.

## KEY DEFECTS FOUND+FIXED THIS SESSION
- 3 live syntax errors (Weapon.luau, VFX.luau, DownedService.luau) — boot now clean, 816 assertions.
- Boss attribute hygiene: stale BossHealth=3600 in non-boss missions fixed on cleanup path.
- Nebula skybox cannot be blanked by empty strings — must destroy Sky object (renderer keeps
  last valid texture otherwise).

12. **DEFEND_BEACON template — VERIFIED** — correct objective chain ("Activate the beacon,
    then hold the position"), activation interaction works, "Holding beacon: 50s" holdout timer
    live, enemy pressure engages during hold (shield 100→34), defense site architecture matches
    spec (graphite enclosure, cyan guide strips, amber equipment lights). Captures:
    v2026_beacon_site, v2026_beacon_defense.
13. **Deployment transit screen** — "GALACTIC FORCE — TRANSIT IN PROGRESS" loading overlay
    capture-verified during deploy transition.

## AI CONFORMANCE BATCH (deployed v684, boot 816 PASS) — structural implementation
1. **Formal 13-state FSM vocabulary** — resolveSpecState() derives and publishes the spec's exact
   state names (Idle/Patrol/Suspicious/Investigate/TakeCover/Advance/Suppress/Flank/Attack/
   Retreat/CallReinforcements/Stunned/Dead) on every live hostile every tick. GFState is never
   nil on a live enemy anymore. NOTE: structurally implemented, runtime state-transition
   evidence not yet captured.
2. **Named threat tiers** — Unaware/Investigating/Mobilizing/Lockdown published as GF_ThreatLevel
   with GF_ThreatAlert numeric; scout-transmit escalation (+30 alert) wired to beacon completions;
   relay-destruction reinforcement reduction already present via GF_ReinforcementCut.
3. **Scout reinforcement beacon** — FlankBeacon hostiles channel a 4s visible transmission
   (TransmissionUntil attribute) when holding partial knowledge without LOS; damage or being
   challenged cancels (GF_BeaconCancels); completion spawns reinforcement + escalates threat.
4. **Suppress behavior** — ranged hostiles with confident knowledge fire denial-lane tracer
   suppression at last-known positions while closing (no free damage — readable threat lanes).
5. **Marksman warning conformance** — chargeTime raised 0.8→1.1s (spec requires >=1s visible).
6. **Telegraph beam renderer** — client renders visible targeting beams for the full windup;
   charged/heavy attacks (>=0.9s) get thick red beams with end-of-windup brightness spike.
7. **Heavy weak point** — exposed visible power core (WeakPoint attribute = config multiplier)
   welded to high-back plate on all archetypes with weakPointMultiplier > 1.
8. **Officer energy sweep** — 1.6s telegraphed radial burst, 30-stud radius, 14-20s cooldown,
   damage routed through VitalsService (correct shield-first path).

## OBSERVED BUGS / ANOMALIES (owner-reported + probe-observed, NEED INVESTIGATION)
- Owner reports spawn bugs in play (unverified specifics — reproduce first)
- Enemies held at LZ platform edge without firing — possible pathing/LOS deadlock on elevated geometry
- Enemy positions jumped ~200m between probes — respawn relocation or duplicate confusion
- Bastion Walker despawn cascade on player death is abrupt (correct in principle, harsh in practice)
- Military rank displayed 15 in a failure debrief during a memory-mode session — possible XP inflation or display bug
- v684 AI batch itself is unverified — new bugs possible in FSM resolver/beacon/sweep paths

## TERRAIN MATH — EPISTEMIC STATUS (owner framing, endorsed)
- Generative noise math implements the spec's APPROACH faithfully (verified by reading)
- Measurable constraint enforcement is half-built: no 300-650 stud objective distance targeting,
  no slope checks in placement despite comments claiming them, no connectivity validation,
  silent overlap fallback after 40 attempts
- OUTCOME PROOF is limited to existence proof: one full mission completed on generated terrain
  (one seed). No statistical confidence across the seed space exists
- THE FIX: extend the offline seed harness to measure traversability, slope distribution,
  objective distances, and footprint validity across thousands of seeds — converts "unknown"
  into a measured acceptance rate with named failing seed families (spec stage-8 intent)
- Tuning constants (octave scales, terrace 4.5, spine blend 0.62, corridor 55) were never
  validated against outcomes — treat as unproven hypotheses until the harness measures them

## OWNER NOTES FOR FUTURE PASSES (not yet scoped as work items)
- Graphics polish pass needed broadly — visual quality uneven across station/mission surfaces
- UI/UX polish pass needed — owner flagged without specifics; audit screens against spec S12/S26
  (HUD legibility minimums, restrained military slate/cyan/amber system, no clutter)
- These are quality observations, not conformance failures — schedule after correctness bugs
- PERFORMANCE/OPTIMIZATION is a founding requirement (owner emphasis since project start).
  Current state: architectural discipline exists (throttled staggered AI ticks, spatial grid
  broad-phase perception, pooled VFX, streaming modes, corpse caps, fire-slot fairness) but
  real measurement is entirely absent — the S15 benchmark rows are BLOCKED on hardware.
  Known cost hotspots spotted this session: the officer relay-call loop runs a full
  workspace:GetDescendants() scan (spec forbids per-tick global scans); AI v684 batch adds
  per-tick attribute writes on every hostile (cheap individually, unaudited at scale);
  probe harnesses used GetDescendants heavily (test-only, not production). No frame-rate
  numbers exist for ANY configuration — first optimization pass must measure before tuning.

## HONESTLY UNVERIFIED / OPEN
- Tutorial steps 2-5 end-to-end (shoot/reload/dodge/ability validation)
- Other mission templates: RECOVER_TECH carry, ELIM/CONQUEST variants (DEFEND_BEACON now verified)
- High Marshal Veyr boss fight visuals/phases
- Crew NPC animation (one NPC confirmed standing at window; animation unverified)
- Cinematic play/skip/replay
- Multiplayer rows (single-player Studio limitation)
- DataStore persistence (Studio is memory-mode by design)
- Input-level verification (server-driven, not literal keypresses)
- AI conformance batch: implemented+deployed but runtime behavior evidence NOT yet captured
  (state transitions, beam visuals, sweep telegraph, weak-core hits all need captures)
- Residual purple in far-left window bays
- Military rank 15 display anomaly seen in one debrief (possibly XP inflation or display bug)
