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

---

## EXECUTION LOG (beta, 2026-11-28 — Stage 1 Part A in progress)
**Completed before this log:** Stage 3 core landed — WarStateService + WarModel + WarOperations + contribution seam, headless-verified, committed. Diff-test passes.
**Key implementation facts (gathered, do not re-derive):**
- ProfileService: SCHEMA_VERSION=1, migrate() is idempotent defaults-fill. Defaults: selectedLoadout.ability1="Airstrike", ability2="DomeShield". Types.luau Loadout type has ability1/ability2 fields.
- ArmoryService.equipAbility(player, index, abilityId): index 1/2 keying, writes workspace+player attrs GF_Ability1/2 + GF_AbilityEquipped. Publish also writes GF_Ability1/2 attrs.
- commitPrimary hardcodes pqualified=1 — participant counting untracked (noted in seam).
- WarStateService committed in mirror; WarModel diff-tested. Harness: gf-research/strategic/build_harness.py → harness_bundle.luau (all checks pass).
**Execution order:** (1) ProfileService schema+transform (2) Types (3) ArmoryService single-slot (4) AbilityService/input read-path (5) HUD/UI minimal (6) luau-compile verify all (7) commit.


## PART B economy quantification (beta, 2026-11-28 — owner-visible decision)
Reward ledger (Normal base): primary_complete 300cr/350xp, extraction_success 100/100,
optional_task **50cr/65xp each**. Fixed contract income per successful mission: 400cr/450xp.
Missions typically spawn 2-3 optional POIs.

**Optional share of contract income (excluding kills):**
- 2 POIs: +100cr/+130xp vs 400/450 base = **20% credits, 22% xp uplift**
- 3 POIs: +150cr/+195xp = **27% credits, 30% xp uplift**

**Verdict: removal is a 20-30% contract-income nerf — well outside the ±10% band.**
Per the migration design this must not be silently absorbed. Options:
  (a) raise primary_complete base ~25% (300→375cr, 350→440xp) — over-compensates average players
      who skip some POIs today;
  (b) raise primary ~15% (300→345, 350→400) — calibrated to typical partial completion;
  (c) accept the nerf as intended progression pacing.
The DAG migration partially offsets: relay/generator completions folded into mandatory chains
are inside the primary reward. Recommended: (b) pending owner decision. DECISION REQUIRED
before Part B implementation lands. Difficulty multipliers scale all events uniformly, so
percentages hold across difficulties.


## DECISION (beta, owner authority delegated 2026-11-28): Part B economy = option (b)
Owner granted full creative control with a long-term-game directive. Decided: raise primary_complete
base 15% (300→345cr, 350→400xp) when the optional-objective removal lands. Reasoning:
- long-term progression health favors mission-focus over poi-cleanup farming; the income flattening
  is calibrated to typical partial completion, not completionist ceiling
- the DAG migration (relay/generator folding into mandatory chains) recaptures part of the loss
  inside primary reward, so net effect on focused players is near-neutral, on completionists a
  small intentional compression — acceptable for pacing, and the economy has headroom because
  augments/shop sinks already exist
- the adjustment ships atomically with the removal (never before) to avoid a temporary buff window
DECISION LOGGED — implementation proceeds without further owner input.


## DECISION CORRECTION (beta, 2026-11-28 — supersedes the 15% raise)
Deeper tracing invalidated the quantification's premise. The reward ledger is a SHADOW system —
its own header states "settlement does not read this ledger yet" — and OptionalService appends
event type "optionalComplete" while the EVENTS table keys it "optional_task", so even the shadow
entries are no-ops. The live payment path (RewardsService.computePayout) contains zero optional
component: base-by-difficulty + 25% full-completion bonus only.

**Measured truth: formal optional objectives pay 0 credits / 0 xp today.** Removal is
economy-neutral in practice — no offsetting adjustment is warranted, and the 15% primary raise
is CANCELLED (it would have been a pure uncalibrated buff). The in-mission tactical effects
(relay reinforcement cut, generator disable, supply scrap grant) are gameplay texture, not income.

Implementation consequences:
- OptionalService stripped to pure environmental interactions: no ledger append, no contract
  framing, no objective HUD rows; spawn skipped in operation mode (fixes the latent double-spawn
  where the DAG supply_cache and the legacy spawner both fire)
- no economy change ships with Part B
