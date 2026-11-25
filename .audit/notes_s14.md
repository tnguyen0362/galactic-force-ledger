# S14 audit notes (durable working memory — update as batches progress)

## Mission context
- User directive 2026-11-25: finish ALL 533 UNKNOWN + 203 PARTIAL rows continuously, no stopping; severity order; graphics last.
- Spec authority: `.goal/GOAL_2026-11-24.md` ONLY (GOAL.md superseded). Audit scripts live in `.audit/`, idempotent, refuse to clobber non-UNKNOWN rows.
- Harness: `python3 ~/gf/gf_deploy.py <tgz|-> <probe.lua|-> <MARKER>`; optional NOSAVE=1. Tarball paths must start `playtest1_current/`, exclude macOS `._*` files. Harness cannot CREATE instances — new module shells need MCP execute_luau first.
- Studio id rediscover via list_roblox_studios (was e08db1e5-fdca-41c4-b603-85b73b777c92). Test userId 1889759131. Probes: temp server Script GF_TMP_PROBE, clean up after.

## S14-A findings (code audit, place 589 baseline)

### ProfileService.luau
- defaults() MISSING spec fields: revision, tutorialProgress, firstMissionBonusClaimed (written by CacheService:310 but never seeded), settledMissions (created lazily in RewardsService), ownedBlueprints, recentTransactionIds. Deviations with same info: rankXP→rank+xp; resources{scrap,cells,tech}→salvage{scrap,energyCells,militaryTechnology}; inventoryCapacity→augmentCapacity; lastSaveAt→lastSaveTime; bossPity→bossResearch[id].pity.
- migrate() clamps rank/xp/credits/warCredits but does NOT deep-validate nested tables (ownedWeapons types, salvage keys, augment inventory entries).
- load(): GetAsync failure sets store=nil GLOBALLY — one player's failure kills persistence for everyone. No overwrite of data though (memory mode doesn't write). Safe-ish but crude.
- save(): UpdateAsync transform ignores current stored value (blind overwrite). No revision check.
- Autosave 120s in non-Studio (spec says 60–90s — deviation). PlayerRemoving saves. BindToClose flushAll ✓ (S14-021 inspection-pass).
- ensure() has per-user loading serialization ✓.

### CombatService.luau fire() validation (S14-022)
- HAS: payload table check, weaponId string+match+known, shotId sequence, per-weapon RPM limit (60/rpm*0.9 slack), ammo, downed/character/life, origin/direction typeof Vector3, direction.Magnitude>=0.5, origin within 8 studs of root, server-side raycast, no client-supplied damage.
- GAP: NaN vectors pass! Vector3 with NaN components passes typeof check; NaN.Magnitude < 0.5 is FALSE so zero-direction doesn't catch it. Need finite checks (S14-016).
- GAP: no payload size limits, no per-action token bucket outer defense.

### Constants.Net (S14-023)
- FireRateLimitPerSecond=20, MaxRemoteBytesPerSecond=4096 declared with ZERO consumers — confirmed dead.

### RewardsService / RewardLedgerService (S14-017/018)
- RewardLedgerService: append-only per-session ledger, per-sourceId dedup, monotonic seq — RECORD ONLY, doesn't drive settlement.
- RewardsService.grant: idempotent via profile.settledMissions[missionKey], retention capped 30 evicting oldest — settled-only eviction is acceptable-ish; document.
- Server computes all payouts ✓ (S14-025 partial evidence exists v444).

### Remote attack surface (28 handlers)
FireWeapon, ReloadWeapon, EquipWeapon?, SetLoadout, RequestLoadout, UseAbility, ThrowGrenade, RequestDodge, AimChanged, CrouchChanged, SprintChanged, InteractRequest (DownedService revive + ObjectiveService + ExtractionService), HackAttempt, RequestDeploy, RequestQuickDeploy, RequestDispatchJoin, RequestExtractionVote, CastVote, RequestExtraction, ExtractionRequest, MarkIntroSeen, RequestIntroReplay, RequestSettings, SettingsChanged, ClaimStarter, RequestDeployOptions(inv), RequestDebrief(inv), RequestReturn, CacheService remote, ReportState (CHECK WHO CONSUMES), OpenArmoryPanel(server->client), MissionComplete(server->client).

## S14-A plan (implement then probe)
1. NEW NetGuard.luau (server-only): per-player per-action token buckets (fire 20, interact 5, purchase 2, equip 4, queue 1, stance 20, default 10), validators (finiteNumber/finiteVector3/stringId/shallowTable), aggregate reject reason logging to GFDebug attrs.
2. Wire buckets into all OnServerEvent handlers (map above).
3. fire(): NaN/finite validation on origin+direction.
4. Probe: malformed NaN/oversized/wrong-type payloads rejected with logged reasons; buckets enforce; boot PASS; legit fire still works.

## Mission-spine batch notes (in progress when written)

Deploy mechanics (StationService.deploy):
- deploy(player, difficulty?, template?) validates: VALID_TEMPLATES, DIFFICULTY_RANK rank gates, TEMPLATE_RANK gates
- resetMission for template; sets GF_InMission=true; zone[player]="Mission"; GF_LZ=spawnPoint; teleports player; GF_DeployGraceUntil=os.clock()+4
- Mission spawn derived from MISSION_SPAWN constant (groundPoint); station spawn separate
- ExtractionService.grant at line 270 = individual extraction payout; grantAll at 454 = squad settlement
- RewardsService.grant(player,difficulty,success,objectiveComplete,squadBonus) — dedup by settledMissions[missionKey]; missionKey from RewardLedgerService.missionId()

Probe-driving pattern: server probe requires services directly, calls StationService.deploy(player,"Normal","SABOTAGE_RELAY"), observes workspace attributes + ActiveActors folder. Evidence v388 shows missions driven this way successfully.

Rows targeted by this batch (measurement cluster): S14-025 (server-origin kill/loot/war), combat TTK/falloff rows (S04-*), enemy archetype rows (S06-*), mission objective rows (S07/S08-*), extraction rows (S09-*), economy settlement rows (S10-*). VERIFY AGAINST CSV before claiming - get exact row ids.

## Mission-spine progress (update as probes land)

SPINE1 PASS (place ~594 working copy): live deploy works; archetype spawn varies per seed (run1: Heavy2 Marksman2 Rifleman3 Officer2; run3: Rifleman5 Marksman1 Officer3); synthetic-target measurement inside live mission: 18 shots 18 hits 324 dmg vs synthetic Rifleman (240+80) through validated fire path = server-authoritative damage proven; TTK 18 shots EXACTLY matches spec S04-046 calibration (320 HP+shield at 100% accuracy); kill credited server-side; mastery accrued server-side. Enemy live targets use cover so are bad measurement subjects — use synthetic targets (pattern in probe_premium_weapons.lua: Model+GFEnemy attr+anchored CanQuery Torso part in workspace.ActiveActors).

Key mechanics learned: ObjectiveService.complete() directly callable (objective mechanics get own batch); war points commit server-side at completion via GalacticWarService.commitPrimary; ExtractionService.call needs objective complete first; GF_ExtractionCountdownOverride documented Studio hook; objective publishes GF_ObjectiveComplete/GF_ObjectiveFailed workspace attrs + ObjectiveProgress remote (NOT GF_ObjectiveProgress).

Row evidence mapping pending: S04-046 TTK anchor verified at 100% accuracy point; S14-025 kill+mastery server-origin proven (loot/war pending spine2); S04-018 shield-first ordering evidenced (324 = shield raw absorbed first).
