# 25 of 46 `Constants` keys have no consumer — and an in-game check for this is impossible (place 481)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`. Plugin-level scan in Edit mode; one Play cycle to prove a negative.

## First, a negative result worth having

I proposed last batch that `CheckRunner` could assert "every `Constants` key has at least one consumer", closing this class
permanently. **That is not possible.** A runtime `Script` cannot read `.Source`:

```
The current thread cannot read 'Source' (lacking capability PluginOrOpenCloud)
  Script 'ServerScriptService.GF_DeadKeyProbe', Line 6
```

So the consumer scan can only ever run at plugin level (the MCP tool VM), not inside the game. Recorded so nobody spends a
session trying to build it in-engine.

## Second, my first scan was wrong

The tool VM **caches required modules**. My first pass did `require(Constants)` and reported `Combat.InteractRange` as dead —
but that key was deleted three batches earlier at place 479. The scan was reading a stale module and would have published a
false inventory.

Corrected by **parsing the current `Source` text** instead of requiring the module. That is the reliable technique for
inspecting constants from the plugin side.

## The inventory

46 keys parsed, **25 with no consumer** anywhere in `ServerScriptService`, `ReplicatedStorage` or `StarterPlayer` outside
`Constants` and `CheckRunner`:

```
Combat.EnemyBudgetCap                Mission.DurationExtended            Progression.MasteryMaxLevel
Combat.MaxActiveEnemiesPerPlayer    Mission.DurationShort               Progression.MasteryXpPerLevel
Mission.DurationStandard            Mission.SoftLimitBoardWindow        Squad.AfkTimeout
Mission.SoftLimitWarning            Movement.AdsSpeed                   Squad.ExtractionGrace
Movement.RollDistance               Net.FireRateLimitPerSecond          Squad.ExtractionHold
Net.MaxRemoteBytesPerSecond         Progression.BossGuaranteedClearCount Squad.ExtractionVoteWindow
World.GenerationChunkStuds          World.MapMaxRouteDistance           Squad.MaxPlayers
World.MapMinRouteDistance           World.MapSizeStuds                  World.PoiMax
World.PoiMin
```

## This is a map of unimplemented systems, not just tidying

Three of these groups cross-link directly to ledger rows that were already recorded as unmet — and now have a second,
independent piece of evidence:

| dead constants | what it implies | ledger row |
|---|---|---|
| `Squad.ExtractionVoteWindow`, `ExtractionHold`, `ExtractionGrace`, `MaxPlayers` | extraction **voting** and squad-cap rules do not exist | `S09-002` |
| `Net.FireRateLimitPerSecond`, `MaxRemoteBytesPerSecond` | **rate limiting / token buckets** are not implemented | `S14-023` |
| `Progression.MasteryMaxLevel`, `MasteryXpPerLevel` | mastery ladder is driven by `ProfileService`'s own thresholds, so these are duplicates | `S10-037` |
| `World.MapSizeStuds`, `PoiMin/Max`, `GenerationChunkStuds`, route distances | procedural-world parameters unused | `S07-*` cluster |
| `Mission.Duration*`, `SoftLimit*` | mission length comes from `StationService.MISSION_SECONDS` instead | `S09-017` |
| `Combat.EnemyBudgetCap`, `MaxActiveEnemiesPerPlayer` | encounter budgeting is governed by `EncounterDirector.MAX_ACTIVE` | `S06-036` |
| `Movement.AdsSpeed`, `RollDistance` | movement may hardcode these — **needs checking**, because the conformance check asserts them | `S03-016`, `S03-018` |

The last row is the one that matters most and is the reason this scan was worth doing: I assert `Movement.AdsSpeed` is 12–14 and
`Movement.RollDistance` is 14–17 at every boot, but **neither has a consumer**. If `MovementService` hardcodes its own values,
those two assertions are certifying dead config — the same error as `DownedTimeout` last batch, still live in two rows.

## Confidence

`DEAD` here means "no `.KeyName` occurrence in any script source". Bracket access (`Constants.X["Key"]`) or a key read through
a computed name would be missed, so the list is a **lower bound** on unconsumed keys, not an exact census.

## Next action

Check `MovementService` for its own `AdsSpeed` / `RollDistance` literals. If it has them, centralise — exactly as `DownedService`
was centralised at place 480 — before trusting those two assertions.

## Resolved (place 482): `AdsSpeed` and `RollDistance` have zero consumers

Follow-up scan across `ServerScriptService`, `ReplicatedStorage` and `StarterPlayer`, case-insensitive:

```
case-insensitive WalkSpeed/AdsSpeed/aiming lines: 22
```

`AdsSpeed` appears **nowhere** outside `Constants` and `CheckRunner`. `RollDistance` likewise. WalkSpeed is only ever set from
`WalkSpeed` / `SprintSpeed` / `CrouchSpeed` (plus `ClassService`'s MoveSpeed modifier, and 0 when downed or dead).

So the two assertions added at place 476 were **certifying dead config** — the same error as `DownedTimeout` at place 480. Both
removed. Boot moved `passed 638 → 636`, `failed` unchanged at 17, confirming both were passing on values nothing reads.

### Two real defects this exposed

1. **Aiming does not slow movement.** `S03-016` requires *"ADS speed 0.8× walk"*. `Movement.AdsSpeed = 13` exists and is never
   read; no code sets `WalkSpeed` while aiming. A player strafes at full walk speed with sights up, which removes the tactical
   cost the spec intends.
2. **The `adsSpeed` augment key is inert.** `AugmentService` lists `adsSpeed` among its supported stat keys, so an augment can
   roll it — but with nothing consuming the stat, such an augment does nothing. A player can pay credits for a dead trait.
