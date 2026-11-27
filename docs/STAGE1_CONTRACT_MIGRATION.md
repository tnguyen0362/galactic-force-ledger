# STAGE 1 — MISSION/EQUIPMENT CONTRACT MIGRATION DESIGN
**Status:** design — pre-implementation | **Author:** beta | **Date:** 2026-11-28
**Mandate:** Counteroffensive sec. mission-contract revisions — remove formal optional objectives, one support ability slot. Preserves unrelated approved systems.

---

## PART A — Support ability: two slots → one

### Surface inventory (9 files)
`Types.luau` (profile type), `ProfileService.luau` (schema+migrations), `ArmoryService.luau` (single-writer loadout authority, deepest coupling — 6 refs), `AbilityService.luau` (execution), `SquadService.luau` (deploy snapshots), `Input.luau`, `Controller.luau`, `HUD.luau`, `StationArmoryUI.luau`, plus `TouchControls` bindings.

### Key design judgment: owned vs equipped
Owned abilities (unlocks/purchases) are player property — migration must NEVER delete them. Only the *equipment contract* changes: two equipped slots become one. Migration rule: `equippedAbility = ability1 if set else ability2`. Players who preferred their slot-2 pick re-equip in the Armory in seconds — zero permanent loss, zero need for a migration-choice UI. Document the reasoning in the migration note so support can answer player questions.

### Migration mechanics
1. **Schema**: profile version bump via existing ProfileService migration chain. Transform: `ability = ability1 ?? ability2 ?? "Airstrike"` (default preserved); delete `ability1/ability2`; `equippedSlots` array → single field. Saved loadouts: same transform per slot.
2. **Input**: `Input.luau` — collapse `Ability1`/`Ability2` semantic actions to `SupportAbility`. Bind to the current Ability1 key (KBM continuity for muscle memory). **The freed second key is reserved for Emergency Dispatch quick-response** (Stage 6 integration — note in code comment). Gamepad bindings likewise; glyph map updates automatically through the existing semantic-action abstraction — this is what the abstraction was built for.
3. **Attributes/cooldowns**: `GF_AbilityCooldown1/2` → `GF_AbilityCooldown`. Deploy snapshots in SquadService carry one ability. AbilityService execution path reads single slot.
4. **UI**: Armory two-slot picker → one slot (minimal change now — full redesign is Stage 8; do NOT redesign here). HUD/touch: remove second button, keep first in place; layout polish deferred to Stage 5.
5. **Order of work**: schema migration + server write-path first, then server execution, then input, then UI. Deployable at each step; no flag-day.

### Balance note
One slot is a buff-to-choice nerf: players lose simultaneous Airstrike+Shield. Mission difficulty was never tuned around two slots explicitly (per audit, abilities are force-multipliers). No retuning in this stage; flag for combat-balance successor review.

---

## PART B — Formal optional objectives removal

### Adjudication per audit (mandate: case-by-case, effects may migrate into mandatory DAGs)

| optional POI | current effect | adjudication |
|---|---|---|
| **Relay** (comms) | gameplay-relevant buff effect | **Migrate into mandatory prerequisite DAG** for missions where thematically central (SEVER_SIGNAL, BLACKOUT_PROTOCOL — sabotage family); drop elsewhere |
| **Generator** | powers/disables site systems | **Migrate into DAG** where the main objective logically needs power control (SILENT_ARCHIVE, FORWARD_DOMINION); drop elsewhere |
| **Supply cache** | resource/loot bonus | **Demote to informal environmental loot** — keep the spawn, remove ledger/objective framing, no contract status. Economy effect preserved at reduced salience |

### Economy quantification (required before removal)
Before implementation: measure the credit/xp contribution of optional completion in the current reward pipeline — read `RewardService`/`OptionalService` ledger coupling, compute share of per-mission income. If optional completion is a significant income fraction, the removal is a progression-economy nerf requiring offsetting adjustment to base mission rewards (keep total per-hour income within ±10% unless alpha's successor economy model says otherwise). **Owner-visible decision — document in validation report, do not silently absorb.**

### Mechanical changes
1. `Missions.luau`: remove `optionalPois` field; relocate relay/generator nodes into `requiresAny`/DAG structure per adjudication table. Fix the malformed `FIRST_SPEAR` constructor while editing (audit finding — it is currently dead content).
2. `OptionalService`: relay/generator spawn logic moves into MissionSites/ObjectiveService as DAG-gated spawns; supply cache spawn stays as ambient loot with no ledger events; service shrinks or is absorbed — decide by line count after edit, do not preserve empty shells.
3. `ObjectiveService`/`OperationService`: remove optional-objective contract states from HUD/debrief surfaces; DAG machinery already supports everything needed (audit confirmed diamond-dependency correctness).
4. Debrief screen: optional-completion rows removed (Stage 9 redesigns this screen anyway — minimal viable change now).

### Naming alignment (canonical roster — cheap, do in same pass)
SABOTAGE_RELAY→"Sever the Signal", RECOVER_TECH→"Alien Legacy", DEFEND_BEACON→"Hold the Line", plus the rest of the fifteen-variant canonical names from the mandate roster. Display strings only — ids unchanged (persistence keys must not break).

---

## PART C — What this stage explicitly does not touch
Lobby, matchmaking, teleport flow, war contribution routing, UI architecture, input architecture beyond the ability collapse. Those are Stages 3-9 with their own designs. Optional-objective *UI polish* and single-slot *presentation quality* are deliberately minimal here — the full redesign lands in the UI stages; this stage only makes the contracts correct.

## Sequencing with Stage 3
Independent — can proceed in parallel with war-service implementation. Both must land before the planetary UI (Stage 7) reads live contract shapes.
