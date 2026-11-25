# v594 — Data/security batch (S14 core) — place versions 591-594

## What changed

**NetGuard (new server-only module `ServerScriptService/GF/Services/NetGuard.luau`).** Centralized network
input defense: per-player per-action token buckets, payload validators, aggregate rejection logging.
- Bucket rates per GOAL L224: interaction 5/s, purchases 2/s, equip 4/s, queue 1/s; fire outer 20/s
  (per-weapon RPM inside `fire()` stays authoritative); stance 20/s; ability/throw/reload moderate.
- Wired into every client-facing handler: FireWeapon, ReloadWeapon, UseAbility, SetLoadout, RequestLoadout,
  ThrowGrenade, RequestDodge, Aim/Crouch/Sprint, HackAttempt, all extraction remotes, InteractRequest
  (all three listeners, tokens spent only by the owning listener after target filtering), RequestDeploy
  (exactly one listener spends - StationService; DispatchService hears the same physical request),
  RequestQuickDeploy, RequestDispatchJoin, RequestReturn, RequestSettings, ClaimStarter.
- Oversized payloads (>8KB) refused before work; cost scales with byte size.
- `SetLoadout` splits buckets by action: economy-mutating actions 2/s, equip/loadout actions 4/s.
- Validators catch what typeof() cannot: NaN/infinity vectors and numbers, control-char ids, wide tables.

**Input validation hardening.** `fire()` rejects non-finite origin/direction vectors
(`non-finite-vector`); grenade throw rejects non-finite aim. Previously a NaN vector passed typeof()
and every magnitude check (NaN comparisons are false).

**ProfileService data layer.**
- Schema completion (L222): added `revision`, `tutorialProgress`, `firstMissionBonusClaimed`,
  `settledMissions`, `ownedBlueprints`, `recentTransactionIds` to defaults.
- Deep migration validation: ownership maps scrubbed of non-boolean/non-string entries, augment
  inventory entries must carry archetypeId+category or are dropped, numeric fields pass through a
  finite-or-fallback coercion (math.max/clamp cannot stop NaN), mastery/rank/capacity clamped to range.
- Load-failure fencing: a failed GetAsync flags the player unpersisted - session-only safe mode,
  save() refuses for the session, the durable document can never be overwritten by defaults.
  Removed the old global `store=nil` downgrade that dropped everyone's persistence on one failure.
- Session lease + optimistic concurrency: every load issues a fresh lease token; save() increments
  `revision` and aborts (UpdateAsync nil) when the durable document carries a newer revision under a
  different token (teleport-handoff/double-session fencing). Decision logic exported pure as
  `ProfileService.leaseConflict`; migration exported as `ProfileService.validateAndMigrate`.
- Autosave interval corrected into the authored 60-90s band (was 120s, now 75s).
- `saveWithRetry`: bounded exponential backoff (1/2/4s + jitter, 3 retries) for critical writes.
- `recordTransaction`: umbrella dedup journal write-through (ring 64); wired into mission settlement
  (`settle:<missionId>`) and receipt processing (`receipt:<purchaseId>`); settlement save upgraded
  to retry path; receipts already persisted before final success.

**TutorialService.** tutorialProgress persisted per validated step; resume starts at the persisted
stage; completion resets the field. First Spear no longer restarts from zero after a disconnect.

**Remotes contract** pinned at `Remotes.ContractVersion = 1`.

## Live verification (server playtests, test userId 1889759131)

`[GF_NET] PASS buckets+validators+malformed+endtoend` (place 591):
- Token bucket mechanics exact: interact capacity 5, purchase capacity 2, queue 1/s, refill over time,
  per-player and per-action independence.
- Validators: NaN/infinity rejected in vectors and numbers, oversized/control-char/empty ids rejected,
  wide tables rejected, oversized payloads refused pre-work.
- fire() malformed abuse: NaN direction rejected (x2 for origin+direction), oversized weapon id rejected,
  valid shot still accepted (ammo decremented).
- End-to-end: a real client probe flooding InteractRequest with 10 rapid fires was throttled server-side
  (5 accepted, 5 dropped), proving the wiring live, not just the module.

`[GF_PROF] PASS schema+migration+lease+concurrency` (place 593):
- All L222 schema fields present in defaults.
- Malformed document: negative credits clamped, NaN xp scrubbed, rank 999 clamped into range, infinite
  warCredits scrubbed, non-boolean ownership entries dropped, shapeless augment entries dropped,
  capacity/mastery clamped; non-table document replaced by defaults.
- Lease fence decision table exact across 5 cases (no doc, same token, newer-different, older-different,
  legacy no-lease).
- Same-tick reroll double-fire: second refused "already pending", cost charged exactly once.
- Same-mission settlement double-fire: second pays nothing, flagged duplicate.
- Revision increments on save; lease token issued.

`[GF_JRN] PASS journal+mode` (place 594): transaction journal records op ids, ring cap 64 enforced,
datastore mode active, healthy load not unpersisted.

Boot: config check PASS (701 assertions) at every version. Test profiles restored after each probe.

## Row dispositions (see REQUIREMENT_COVERAGE.csv)

- S14-016 VERIFIED - NaN/infinite/malformed rejected on fire+throw; currencies clamped at migration and
  award time; purchase costs server-config only; no client-supplied amounts anywhere (grep-negative).
- S14-022 VERIFIED - abuse-tested exactly as the row's next action demanded, plus element survey.
- S14-023 VERIFIED - buckets implemented, wired, probed end-to-end.
- S14-024 PARTIAL - aggregate rejection logging+throttling yes; plausible-displacement movement
  validation (anti-teleport) not yet implemented.
- S14-012 PARTIAL -> advanced - schema fields complete incl. journal; restart read-back of remaining
  fields (warCredits/settings/journal) still owed.
- S14-013 PARTIAL -> advanced - malformed/out-of-range validation proven; overwrite-on-load-failure
  fencing implemented, failure-injection test still owed.
- S14-014 PARTIAL - lease token+revision fencing implemented and pure-verified; live teleport handoff
  untestable in single-place Studio.
- S14-015 PARTIAL -> advanced - settlement dedup proven exact-once; note single-threaded Luau
  serializes same-tick mutations inherently; UpdateAsync transform still blind-merge for non-lease
  conflicts by design (single-writer-per-key semantics).
- S14-017 PARTIAL - critical settlements persist before success with bounded backoff; autosave band
  corrected; retry path implemented.
- S14-018 PARTIAL - journals exist (receipts, settledMissions, cacheOpenJournal, umbrella ring);
  retention policy documented.
- S14-019 PARTIAL - cache-open journal reuses committed draws (existing); crash-mid-settlement test owed.
- S14-020 PARTIAL - session-only safe mode implemented + attribute surfaced; no player-facing retry UI yet.
- S14-021 VERIFIED - BindToClose flushAll present and inspected.
- S14-026 PARTIAL -> advanced - reroll/settlement exact-once proven; revive/objective/squad guards
  inspected (holding[] guard, seat decrement); cache-open same-tick test owed.
