# Encounter Program Milestone — Ascendancy Elite Infantry, Mechanized Warfare & Boss Encounters

Program: expand the Ascendancy into a complete military civilization — elite infantry (Spectre/Revenant),
armored vehicles (Bastion family), major mechanized boss (Leviathan), rare encounter generation,
component-driven damage model. Design influences: Helldivers 2 ~45%, The First Descendant ~30%,
Halo ~15%, Warframe ~10%.

Status: **core framework built and live-validated**. 12 commits on main (local, unpushed).
This document is the honest accounting: what exists, what is empirically proven, what remains.

---

## 1. What was built (2,700+ lines of new encounter-system code)

### Shared architecture
- **EncounterHierarchy.luau** (212 lines, ReplicatedStorage) — the authoritative definition surface:
  encounter classes with rarity/duration/pressure costs, per-difficulty occurrence probabilities,
  Spectre/Revenant role tables with capability vectors, Bastion component definitions
  (health/eta/protection/enables), Bastion variant parameters.
- **ComponentService.luau** (376 lines) — authoritative destructible-component framework:
  explicit hitbox registry, per-component health pools, protection redirection, eta hull-transfer
  arithmetic, dependency-graph validation (protection cycles broken), capability mapping,
  exactly-once destruction events, explosion budget allocation across multiple components.
- **AttackScheduler.luau** (203 lines) — attack lifecycle framework:
  Ready→Telegraph→Active→Recovery lifecycle states, encounter-level pressure budget,
  feasibility filtering first (never selects attacks that cannot execute), softmax selection with
  exponential recency penalty, health-scaled aggression that compresses cooldowns/recovery but
  **never telegraph windows** (survival-critical tells stay honest).
- **VehicleLocomotion.luau** (183 lines) — hull movement controller:
  bounded acceleration/braking with speed convergence, hull yaw rate caps with turn-bleed,
  multi-sample terrain alignment, slope limits, stuck detection/recovery, independent turret
  articulation with bounded angular convergence.
- **ShellService.luau** (95 lines) — deterministic projectile flight:
  anchored step-integrated shells with raycast impact detection. Replaced physics shells after
  live measurement showed gravity drop + incidental contact detonation made cannon fire inaccurate
  (blast landing 54 studs from a stationary target).

### Encounter implementations
- **BastionTank.luau** (515 lines) — standard heavy armored vehicle:
  modular construction (hull/glacis/propulsion/turret/cannon/sensor/core), 7 destructible
  components with dependency graph (FrontArmor protects EnergyCore), hull + independent turret
  articulation, attack portfolio (HeavyCannonAttack telegraphed projectile, SecondaryFire pressure
  pulses), legitimate perception with 7-second memory decay — no omniscient tracking.
  Variants config-complete: Standard/Vanguard/Bulwark/Siege (speed/armor/geometry parameters differ).
- **LeviathanWalker.luau** (568 lines) — the reference major war machine:
  monumental quadruped (~55×38×36 studs), four articulated legs with diagonal-pair gait phasing,
  hull-sag defeat sequence, 6+ components with protection graph (CoreArmorPanel protects the
  amplified-damage ventral core), 4-attack portfolio (HeavyCannon, AreaDenial pattern, SecondaryFire,
  close-range Shockwave), 26,000 hull health, aggression scaling to 1.65× at low health.
- **EliteOperations.luau** (405 lines) — elite infantry encounter layer:
  Spectre composition rolls (3-5 operators weighted by role), Revenant fixed five-role squads,
  capability vector tracking (eliminating an operator removes its contribution), defensive barrier
  equipment (bounded: 6s duration, 110° arc, 260 HP, 22s cooldown, visible activation/shutdown),
  encounter lifecycle Dormant→Discovered→Engaged→Disengaged→Reengaged→Defeated,
  role-signaling visual equipment (command vane, mobility pack, heavy barrel, optic mast,
  barrier projector) applied post-spawn — zero EnemyService internals touched (alpha's lane intact).
- **RareEncounters.luau** (146 lines) — seeded operation-level generation:
  per-difficulty occurrence rates (Spectre uncommon → Leviathan very rare, Hard+ only),
  deployment-plausibility positioning (stronghold approach/perimeter/corridor), legible seed
  attribution, integration at operation activation after garrison spawn.
- **Enemies.luau** — 13 new configs: 5 Spectre + 5 Revenant operators (compatible variants of
  established roles per spec — same AI machinery, next-level competence parameters) +
  BastionTank/BastionSiege/LeviathanWalker loot entries.

### Integration
- **CombatService.damageEnemy** routes component-entity hits through
  `ComponentService.resolveComponentDamage` — component pools burn, eta-scaled transfer continues
  through the established shield/armor pipeline. Legacy ComponentHP path preserved for the old
  BastionWalker; no double-counting.
- **CacheService** identifies enemies EnemyId-attribute-first — vehicle/boss loot resolves.
- **OperationService** binds the new services and invokes RareEncounters after garrison generation.
- **EncounterTestHarness** — game-VM validation entry points through workspace attributes
  (probes run in a separate VM and cannot mutate game-VM module state — hard-won lesson applied).

---

## 2. What is empirically proven (live validation, play-mode, real mission)

### Component damage arithmetic — exact-verified
Measured against config formulas, every number matching precisely:
- FrontArmor hit 100 raw: pool 900→800 (burn ×1.0), hull transfer 5 (eta 0.05) ✓
- Chassis hit (no component): full 100 to hull ✓
- Protected core hit while armor lives: redirect 50 to armor at half rate, hull transfer 5 ✓
- Armor burn-down: destruction at exactly 0, `GF_ComponentDestroyed=FrontArmor` fired once ✓
- Exposed core hit: amplified burn (mult 2.0 → pool 700→500), amplified transfer (400 hull) ✓

### Damage-driven capability loss — confirmed live
MainCannon destroyed → scheduler rejects `HeavyCannonAttack:cap` permanently → cannon fire count
frozen → vehicle continues fighting with secondary. The spec's central mechanized-warfare
requirement works end-to-end.

### Vehicle combat effectiveness — confirmed live in-mission
Over 35s engagement: cannon damage 213.9 applied + secondary 36 applied through VitalsService
(shield-first absorption — damage returns nonzero through the real pipeline; player Humanoid.Health
correctly stays 100 while shields absorb).

### Vehicle locomotion — confirmed live
Spawn at 130 studs: tank closes 130→105→87→85 with correct yaw convergence (2.28→3.34 rad turning
toward target), speed convergence (peak 10 studs/s), then holds in the 40-95 engagement band.
Bounded acceleration observed — no instant starts.

### Walker gait — confirmed live
Leviathan foot FL tracked articulating (−297,−2102 → −300,−2085) independently of hull motion
(−274,−2106 → −290,−2108): legs cycle with diagonal phasing while the hull advances. No errors
in the step loop.

### Elite squads — confirmed live
- Revenant: all five roles spawned (Leader/Assault/Weapons/Precision/Defense) with role-signaling
  equipment verified present (CommandVane, MantlePlate, MobilityPack, BarrierProjector).
- Spectre: 3-operator composition spawn confirmed; division armor treatment applied.

### Mission lifecycle integration — confirmed correct
Encounter entities (Bastion/Revenant/Spectre/Leviathan) are destroyed by EncounterDirector.reset()
at mission end — verified after a natural mission timeout (inMission=false, all counts zero).
The Leviathan "disappearance" observed mid-testing was correct cleanup, not a defect.

### Performance — measured acceptable
Heartbeat 1.25–1.34 ms with simultaneous Bastion + Leviathan + Revenant squad + Spectre squad +
mission garrison active. Physics step 0.03 ms. Far within budget.

---

## 3. Honest limitations and remaining work

### Not yet validated
1. **Rare encounter statistics** — planAndSpawn is wired into operation activation and every spawn
   path it uses is individually validated, but the seeded rolling itself has not been statistically
   validated across multiple operations (rare=nil in two Hard test deploys; within probability but
   unconfirmed). Needs a 20-operation sampling run.
2. **Leviathan attack delivery** — spawn/gait/movement/perception validated, but cannon/area-denial
   damage on players not yet confirmed in-mission (the walker closes slowly at 6.5 max speed;
   validation sessions ended before sustained attack range).
3. **Revenant barrier in combat** — equipment visually present; deployment trigger (health < 85%)
   untested in live combat.
4. **1-4 player scaling** — all validation was single-player.

### Known design gaps
5. **Bastion variants visually similar** — Vanguard/Bulwark/Siege differ in stats/dimensions but
   share the same primitive construction language. Siege should be visibly larger with artillery
   silhouette. Mesh production would resolve; primitive differentiation is achievable sooner.
6. **Primitive geometry everywhere** — vehicles/walkers are part-built placeholders with correct
   attachment semantics. The architecture supports mesh-shell swap-in without logic changes, but
   the hard-surface art production pass has not happened. This is the largest visual limitation.
7. **Pacing director integration (stage 10) not started** — encounter pressure costs are defined
   in the hierarchy but EncounterDirector does not yet budget encounter composition against them.
   Alpha owns EncounterDirector — this is a coordination item, not a solo task.
8. **Augment-system readiness** — rewardSource ids exist in the hierarchy but the Augment-service
   interfaces are not yet wired.

### Coordination state
- Alpha's kit-installation patch reviewed (verdict: approve with 4 conditions, posted to bus).
  Key integration constraint noted: kit buildings have roofs — walker-class spawns must reject
  positions with solid overhead within 30 studs (not yet implemented in RareEncounters).
- Elite visual layer deliberately uses post-spawn augmentation so alpha's EnemyService internals
  stay untouched. If alpha restructures model construction, the augmentation anchor points
  (Torso etc.) need re-verification.

---

## 4. Validation methodology notes (for future encounter work)

- execute_luau probes run in a separate VM: game-VM module state is invisible. All telemetry
  flows through workspace attributes written by the services themselves (heartbeat pattern).
- VitalsService.applyDamage returns the amount actually dealt — nonzero return through the real
  pipeline is authoritative evidence even though shield absorption keeps Humanoid.Health at 100.
- Player damage is zeroed outside missions (`GF_InMission` guard) — combat validation REQUIRES
  a deployed operation, deploy fired through the Client VM (`FireServer` is client-only).
- The scheduler's alternating cooldown rejections (`HeavyCannonAttack:cd` / `SecondaryFire:cd`)
  are positive evidence of continuous attack cycling — feasibility failures carry reason tokens.

## 5. Commit inventory (local main, unpushed)

```
acad913 validation round evidence
0e1c540 ShellService deterministic projectile flight
1cb437e vehicle root-part hull-frame fix + loop protection + telemetry
5e46c5b encounter test harness
141806c elite visual production
a637b78 rewards integration (EnemyId-first loot resolution)
f159c33 stage 9 rare encounter generation
94afc90 stage 4 elite configs + squad encounter layer
(+ earlier: hierarchy/component framework/scheduler/locomotion/leviathan commits)
```
