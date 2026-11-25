# S06 enemy AI — gap analysis and implementation plan (2026-11-25)

## Discovery: architecture largely absent

EnemyService.luau (809 lines) implements basic behavior-driven enemies:
- behavior tags in config: GuardCover/FlankBeacon/ChargedShot/AreaBurst/CommandSquad/WalkerPhases/CommanderPhases
- cover usage exists; single central heartbeat (good); enemies use cover in live tests (observed spine1)
- NO hierarchical FSM states (Dormant/Patrol/Investigate/Acquire/Engage/Search/Return) — only "Guard" string found
- NO confidence model exp(-age/4), NO lastSeen tracking, NO radio knowledge sharing
- NO spatial grid, NO token-bucket pathfinding, NO threat-cost reinforcement economy
- NO hitProb config (S06-028 spec values absent), NO threatCost table (S06-039 absent)
- EncounterDirector.luau is only 238 lines — minimal spawn control

Enemies config (78 lines): solid per-archetype hp/shield/damage/speed/sight/burst but no hitProb/threatCost.

## Spec targets (from rows S06-003..044)

FSM states, central staggered scheduler (no per-NPC heartbeat — currently central single heartbeat: partial credit),
LOS raycasts bounded (2 max per check), sight 110 studs/110 deg cone, near-proximity 14, hearing 90,
confidence exp(-age/4), radio within 100 studs same group delay .5s, target scoring formula,
downed-not-targeted, cover node reservation TTL, pathfinding token bucket 8/s, stuck recovery 2s/6s,
hit probabilities rifleman .42 Vanguard .38 etc, suppressive-fire intentional misses, elite frequency 0/10/20/30%,
active cap round(4+2*(P-1)) scaled, Normal solo 3-5 active, threat costs, reinforcement token formula,
off-screen spawn validation 65-140 studs.

## Implementation plan (sub-batches)

S06-A perception/FSM core: implement state machine (Dormant/Patrol/Investigate/Acquire/Engage/Search/Return),
  LOS cone+distance checks, hearing on gunfire events, lastSeen+confidence, target scoring, downed exclusion.
  Verify: probe observes state transitions via attributes when player exposes/hides.
S06-B reinforcement economy: threat costs config, active caps by player count, token refill formula,
  off-screen spawn validation. Verify: probe counts actives over a mission, spawn positions outside LOS.
S06-C attack patterns: hitProb config per archetype, suppressive-fire zones, telegraph avoidance windows.
  Verify: statistical probe on synthetic engagements.
S06-D stuck recovery + cover reservation TTL + radio sharing.

Each sub-batch: implement -> deploy -> probe -> ledger update -> commit. Estimate multiple sessions.

## Row triage note
Config-checkable rows can be verified as implementation lands. Do NOT mark behavioral rows verified
without live probes. S06-012 (footstep sound not needed) is a negative-requirement: verifiable by absence.
