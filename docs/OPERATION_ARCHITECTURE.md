# OPERATION ARCHITECTURE — mission integration design (owner directive 2026-11-26)

## Core architectural judgment
The existing services are substantial and refined (ObjectiveService 1755 lines,
ExtractionService 804, EncounterDirector 617, EnemyService 1899). This is an
INTEGRATION assignment: the operation layer ORCHESTRATES existing systems through
their interfaces. No rewrites of combat, AI, extraction, rewards, or terrain.

## Layer model
    OperationService (new — authoritative operation state)
        generates: OperationDefinition manifest (versioned, seed-reproducible)
        orchestrates:
            GeographyService — terrain foundation (DONE, validated)
            InstallationBuilder (new) — strongholds/depots/relays placed on real terrain
            ObjectiveGraph (new) — dependency DAG over reusable mechanics
            ObjectiveService — existing interaction/hacking/terminal mechanics
            EncounterDirector — existing enemy composition/patrols/reinforcements
            ExtractionService — existing voting/transport/defense
            GalacticWarService — existing war contribution
            RewardLedger (new thin layer) — authoritative events, idempotent finalization

## OperationDefinition (directive-specified)
    OperationId, OperationSeed, GeneratorVersion, GeographyId, TerritoryId,
    MissionFamily, MissionVariant, Difficulty, DeploymentRegion, PrimaryObjective,
    PrerequisiteObjectives, OptionalObjectives, InstallationAssignments,
    EncounterRegions, ReinforcementPermissions, ExtractionRegion,
    MissionTimeLimit, RewardConfiguration, OperationalConditions

## Objective dependency DAG
    Ready(j) = AND over P_j, or OR-of-ANDs for alternative prerequisite sets
    Validation: topological sort (cycles), reachability probes, solo-completable check
    States: Locked -> Available -> Active -> Completed (+Failed/Suspended/Cancelled)
    Idempotent event processing: ProcessedEvents[e] guard, server-authoritative

## Reusable mechanics library (compose, don't duplicate)
    Destroy, Recover, Defend, Eliminate, Capture, Restore, Disable, Locate
    Combat-first: destruction by weapons/explosives, not hold-E terminals everywhere
    Hacking stays rare/brief (existing rotating-needle skill check preserved)

## Operational circumstances (variant x config matrix)
    Fortified / Operational / Compromised configurations change actual decisions
    Circumstance selection: bounded deterministic, P(z) weighted by compatibility

## Reference operation (first milestone)
    Conquest - Stronghold on fv1/fv2 mountain valley:
    deploy ~1km from stronghold -> patrol encounter -> traversal ->
    optional installation -> prereq: disable comms relay (reduces reinforcements)
    + destroy shield generator (visibly drops stronghold shield) ->
    defended approach -> assault + capture -> extraction defense -> rewards -> return

## Consequence events (explicit, no arbitrary internals mutation)
    ObjectiveCompleted, InstallationCaptured, DefensiveSystemDisabled,
    ReinforcementPermissionChanged, TargetRevealed, PrimaryObjectiveUnlocked

## Pacing targets (provisional)
    deploy->first contact 1-3min, prereqs 3-6min, primary approach 1-3min,
    primary engagement 3-5min, extraction 2-3min. Standard op 15-20min.
    Timers provide margin beyond intended completion, not artificial padding.
