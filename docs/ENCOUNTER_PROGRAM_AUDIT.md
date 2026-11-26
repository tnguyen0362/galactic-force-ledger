# ASCENDANCY ENCOUNTER PROGRAM — STAGE 1 AUDIT (2026-11-27)

## Existing foundations (build on, do not rewrite)

### Enemy AI (alpha-owned, actively refined)
- EnemyService (1927 lines): archetype system — Rifleman/Scout(Vanguard)/Marksman/Heavy/Officer(Commander)
  with per-archetype TACTICAL profiles (preferredRange, repositionUrgency, coverCommit, flankArc,
  suppressionShrug, retreatHpFrac). NPCLocomotion integrated (velocity convergence, bounded turning).
  Fire slots, threat memory (noteThreat), hearing (hearGunfire), spawn() ground-snapped, difficulty
  scaling at spawn (hp/damage/cadence).
- NPCSquads: blackboard coordination — squads form by proximity (55 studs, max 6), shared target
  reports with timestamps+confidence, cover reservations, role assignment, commander influence radius
  60, flanker limits, loss tracking. THE elite extension point: Spectre/Revenant consume this.
- NPCPerception/NPCNavigation/SpatialGrid/PathThrottle exist as separate modules.

### Enemy definitions (config extension path)
- Enemies.luau: flat stat blocks — tier (Standard/Specialist/Elite/Boss), health/shield/damage/range/
  cooldown/speed/sight/loot/behavior/weakPointMultiplier/hitProb/burst. Armor mitigation via
  armorFactor attribute. Spectre/Revenant extend this exact pattern with behavior extensions.

### Boss implementations
- BastionWalker (572 lines): functional primitive-built quadruped — mortar (3-round telegraphed),
  sweeping laser, stomp AOE; telegraph ring/beam markers; phased aggression 1+0.45*(1-h) cadence
  scaling (tells never shortened); weighted attack selection no-immediate-repeat; component HP pools
  (MortarRack 600, Emitter 450) with ComponentDestroyed state; rear joint weakpoints (2x);
  squad-shared loot on death. MECHANICALLY REAL but primitive visuals, direct CFrame rotation,
  no vehicle-grade locomotion.
- HighMarshalVeyr: boss module present, alpha reports broken AI (their lane).

### Damage architecture (CombatService)
- damageEnemy: hitMultiplier/weakpoint/armor factor applied to health-only post-shield; per-part
  WeakPoint attributes override; headshots use model WeakPointMultiplier; armor penetration
  bypasses armor fractionally. COMPONENT DAMAGE EXISTS embryonically: hits on parts with
  ComponentHP burn the component pool while damaging core exactly once; destruction sets
  ComponentDestroyed + darkens the part + publishes GF_ComponentDestroyed.
- damageStructure: GFIntegrity pool for structures, GFShielded gate, destruction visuals.

### Mission integration (beta-owned, validated)
- Operations: armEliminate boss-routes BastionWalker/HighMarshalVeyr to bespoke modules,
  others to EnemyService.spawn; elimination death-watch; 15/15 templates live.
- Rewards: CacheService.onEnemyKilled per-def drop chances, mission cap, boss drops squad-ledgered,
  extraction-dependent settlement (17/17 validated).

### Art pipeline
- GenerateModelAsync works in Edit datamodel directly (alpha-proven); meshes embed and persist.
- Alpha owns GFArtKit (installation assets). Beta will use GFAscendancyKit (new, enemy/vehicle/boss).

## Gaps to close (this program)

1. No elite infantry: Spectre/Revenant configs, behavior extensions, visual armor — all absent.
2. No vehicle architecture: no hull locomotion, no turret articulation, no vehicle nav/clearance.
3. Component system embryonic: no dependency graph, no exposure chains (armor protects core),
   no capability mapping, no authoritative destruction events, no explosion-overlap allocation.
4. No attack scheduling framework: no pressure budget, no lifecycle state machine, no anti-repetition
   beyond BastionWalker's simple version.
5. Enemy visuals are primitive blocks: no mesh armor/equipment assets exist for any enemy.
6. No rare encounter generation: operations spawn fixed garrisons/patrols only.
7. No director pressure model or encounter combination budgets.
8. No reward-source differentiation (single loot pipeline per enemy def).
9. NAMING: existing "BastionWalker" is a quadruped mini-boss — mechanically a PROTO-Leviathan.
   Spec "Bastion" is a tracked TANK family. Resolution: evolve BastionWalker's mechanics toward
   Leviathan lineage; build the tank family new as spec-Bastion.

## Coordination constraints
- Alpha owns: EnemyService/NPC* rewrite, installations, GFArtKit. Beta consumes public APIs only.
- Studio serializes through STUDIO-YOURS/STUDIO-FREE bus protocol.
- Mesh generation in Edit-mode windows only, never during live missions.
