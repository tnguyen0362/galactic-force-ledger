# WORK_STATE — last verified 2026-11-24, place version 448

## Audit pass 2026-11-24 (repo-only — Studio was not connected)

**Why this pass happened.** The goal loop had reported `ABSENT 0 | PARTIAL 68` for 33 iterations while the ledger actually held
**732 UNKNOWN rows with zero implementation paths, zero evidence refs and zero verified builds**. `ledgerLine()` counted five
statuses and omitted `UNKNOWN`, so the progress line could not show the unaudited majority. That is fixed in the loop; this pass
starts populating those rows from evidence already on disk.

**Batch: Combat / weapons conformance — 14 rows.**

| result | rows |
|---|---|
| UNKNOWN -> VERIFIED | `COUNT-DIFF`, `COUNT-SECONDARY`, `S04-034` |
| UNKNOWN -> PARTIAL | `S04-008`, `S04-014`, `S04-025`, `S04-026`, `S04-030`, `S04-035`, `S04-036`, `S04-046`, `S04-047`, `S04-048` |
| UNKNOWN -> IMPLEMENTED_UNVERIFIED | `COUNT-CLASS` |

Ledger moved 732 -> **718 UNKNOWN**, 68 -> 78 PARTIAL, 14 -> 17 VERIFIED. Script: `.audit/audit_batch_combat.py`
(idempotent, and it asserts every targeted row exists before writing).

**CORRECTION — one recorded "spec conflict" was my error and is withdrawn.**

**Which document is the specification.** `.goal/GOAL.md` (304 KB, 1476 lines) is **superseded**; a
`.goal/GOAL.md.superseded-25line-summary` file marks it so. The authoritative specification is
`.goal/GOAL_2026-11-24.md` (98 KB, 279 lines), **byte-identical** to the owner's `Downloads/GOAL (1).md`
(sha256 `1a1d440d4d60ad109dbf2de9967778dd24847a6533ff4b41db472572b4f66a9d`). Batch 1 below was audited against
the superseded document by mistake. Audit against `GOAL_2026-11-24.md` only.

1. **ER-16 vs SMG-03 — WITHDRAWN, not a conflict.** `GOAL_2026-11-24.md` L54 lists **SMG-03 Jackal** in the weapon
table; ER-16 appears **nowhere** in the authoritative document. The implementation was right and my "conflict" was an
artifact of reading `GOAL.md`. `S04-034` corrects this in the ledger.
2. **Stale pointer that caused the error — still open.** The goal text itself says *"use GOAL.md as the authoritative
specification"*. Every batch that follows that instruction audits against a superseded 1476-line document. This needs
an owner edit to the goal string; it is not something an agent should silently rewrite.
3. **Weakpoint multiplier — still open.** `GOAL_2026-11-24.md` L47 requires head/marked weakpoint **x1.5**. The note in
v461 records the function reading **x2**. Neither value was fired, so which is live is unconfirmed. On `S04-014`.

**Defects promoted out of prose into the ledger** (all were known, none were tracked): aimed spread missing from the
weapon data table (`S04-036`); GL-22 blast radius 9 vs spec 13 and RL-09 12 vs spec 10, and both launchers are
hitscan-with-blast so there is no projectile speed, gravity or fuse (`S04-047`, `S04-048`); reserve subtraction on
reload unmeasured (`S04-025`); empty-auto-reload and swap-cancel unmeasured (`S04-026`).

**Batch 2: Caches / Augments — 7 rows.**

| result | rows |
|---|---|
| UNKNOWN -> VERIFIED | `S11-004` (32 archetypes, >=3 per category), `S11-022` (1/2/3/4 draws per tier, 300-1200 draws each) |
| UNKNOWN -> PARTIAL | `S11-003` (no armory category selector), `S11-038` (rarity changes cost/weight only, not magnitude range), `S11-039` (in-range rolls yes, quantized 0..1000 + gold max unverified) |
| UNKNOWN -> ABSENT | `S11-031` (no cache UID/timestamp/source), `S11-032` (no inventory capacity limit at all) |

Script: `.audit/audit_batch_caches.py`. It refuses to overwrite a row that is no longer UNKNOWN, so batches cannot clobber each other.
`S11-033` and `S11-035` are blocked behind `S11-032` (a full-inventory rule needs a capacity limit to exist first).

**Running totals after both batches:** UNKNOWN 732 -> **711**, PARTIAL 68 -> 81, VERIFIED 14 -> 19, ABSENT 0 -> 2, IMPLEMENTED_UNVERIFIED 2.

**Batch 4: Economy / mastery — 6 rows, all PARTIAL.** Script `.audit/audit_batch_economy.py`.

`S10-004`, `S10-006`, `S10-021`, `S10-025`, `S10-031`, `S10-040`, mapped from v430 (persistence), v438 (base/bonus
split) and v439 (salvage bonus). Mastery rows `S10-037`, `S10-038` and `S10-039` have **no evidence anywhere in
`evidence/`** and were left UNKNOWN rather than guessed.

**One number is off and it is consistent across two rows:** a Normal solo success pays **450 Credits and 600 XP**.
Credits are inside the intended 450-600 band; XP is **50 below the 650-900 band's floor**. Recorded on `S10-006` and
`S10-025`, which must be reconciled together. It is a balance question, not a bug — the arithmetic does what it is told.

Also measured and now recorded: lifetime rank survives two full server restarts (rank 15 / 123,700 XP), flooring happens
once at settlement for squad bonuses (25% of 450 -> 112), and 36 owned augments persisted with the loadout socket intact.

**Batch 5: Engineering / QA — 16 rows (8 beta test-matrix, 8 acceptance-gate).** Script `.audit/audit_batch_qa.py`.

These rows are process requirements, so what they describe IS reporting discipline; evidence is repo state rather than a
place measurement. Five acceptance rows verified (`S16-100`, `S16-107`, `S16-110`, `S16-112`, `S16-115`) — the build has
never self-certified, never published, never claimed beta, and `owner_acceptance` is empty on all 815 rows.

The device/squad `TEST_MATRIX` rows are recorded PARTIAL with an **external** blocker, not ABSENT: they are not
unimplemented, they are untestable here, and `S16-103` requires such blockers stay visible rather than turn green.

**Correction to an earlier claim.** `WORK_STATE` previously asserted "all 15 variants verified complete on Normal". Only
**8 of 15** have a per-variant `EVIDENCE.md` (3 elimination v383, 3 conquest v385, 2 recovery/defense v388). The remaining 7
rest on an aggregate sentence here and no evidence file, so `BETA-OPS-SOLO` is PARTIAL at observed_count 8. An aggregate
claim in WORK_STATE is not evidence.

Also recorded: `S16-111` was being actively violated until this session — the loop reported `ABSENT 0 | PARTIAL 68` while
732 rows were unaudited.

**Batch 6: Enemy AI / bosses — 14 rows (2 VERIFIED, 12 PARTIAL) plus a refinement to `S04-046`.** Script `.audit/audit_batch_enemy.py`.

Verified: `COUNT-BOSS` (both bosses are real Workspace objects) and `S06-020` (the LOS gate is instrumented and reports
entry / los-fail / los-pass / hit).

**Two boss numbers do not meet the spec:**

1. **Veyr HP.** Measured `Health 3200` in Thronefall against spec base **7200** (`GOAL_2026-11-24.md` L102). At Normal,
   solo, the scaling formula gives 7200 exactly, so 3200 is under half. The reading is from build 385 and predates the
   build-441 stat realignment, so the *current* value is unknown rather than proven wrong — recorded on `S06-052` and
   `S06-065` as a defect to re-measure, not as a confirmed regression.
2. **Blueprint pity.** Spec L102 requires **5** qualifying extracted boss kills at 15%/kill before. `HANDOFF.md` records the
   implementation at **3** "(was 5)". Deterministic under `GF_ForceNoBlueprintChance`, but 3 is a spec deviation with no
   decision record authorising it. Recorded on `S06-072`.

**Refinement:** `S04-046` previously said Normal infantry 320 was unmeasured. It is now confirmed as authored and configured
— v441 realigned Rifleman to 240 HP + 80 shield = 320 exactly. Only the 18-shot / 1.7 s TTK is still missing.

Also recorded: distinct per-archetype burst patterns are real and measured (13/8×3, 18/6×4, 11/38×1, 8/32×1, 12/12×2), and
the Heavy's 1.4 s telegraph-then-32-damage path is proven.

**Batch 7: Data / security — 9 rows, all PARTIAL.** Script `.audit/audit_batch_data.py`.

Mapped from BLOCKED.md #1 (DataStore proven live, `schema=1` round-trips), v430 (two full restarts), v441/v444
(server-applied damage), v438/v439 (server-computed rewards), v422 (guarded cache open), v457 (client sends direction
only), v412 (server-published countdown).

None are VERIFIED, and that is deliberate: for durability and rate-limiting the untested half is the failure path, which
is the half that matters. What *is* proven: the profile round-trips `credits/xp/rank/schema` and survives two full server
restarts including a post-restart write; a held cache, 36 augments and the loadout all survive; cache open is guarded; the
client holds no damage authority.

**Security note worth a look — `S14-029`.** `GOAL_2026-11-24.md` L224 requires debug affordances to be gated by Studio or an
explicit private allowlist, with no live arbitrary reward commands. Six switches are documented in `HANDOFF.md` and two of
them grant state directly: `GF_TestHooks` enables `grantTestAugment` and `bossRewardTest`, and `GF_ForceRankUps` forces
rank-ups. They are read from **workspace attributes**. No gate to Studio or an allowlist was found, and none was verified,
so whether a client can set one is **unknown, not proven safe**. That needs reading the guard before beta.

Also recorded: sensitive reward/profile/cache logic is server-side, but every balance table lives in
`ReplicatedStorage.GF.Shared.Configs` and is client-readable — acceptable for prediction, but never audited module by
module (`S14-004`).

**Batch 8: Studio reconnected — first live measurements of the audit (build 462).**

Studio came back in Edit mode, so this pass stopped auditing documents and tested them. Evidence: `evidence/v462-testhook-gate/EVIDENCE.md`.

**`S14-029` is now VERIFIED — by attack, not by reading.** A client set `GF_TestHooks = true` on its own `Workspace` copy
(succeeded locally), fired `SetLoadout{grantTestAugment}` at the server, and the server read **`nil`** and refused with
`GF_ArmoryRejected = "test hooks disabled"`, granting nothing. Attributes set by a LocalScript do not replicate, and the
guard reads the server's copy. Two caveats recorded: the mechanism is a server-only attribute rather than the
Studio-or-allowlist gate the spec names, and `GF_ForceRankUps` has **no** guard at all, resting on the same property.

**Boss HP measured live from config, replacing a stale build-385 reading:**

| boss | config (health + shield) | spec base | gap |
|---|---|---|---|
| Bastion Walker | 1200 + 400 = **1600** | **3600** | -2000 |
| High Marshal Veyr | 4000 + 1500 = **5500** | **7200** | -1700 |

Both under spec. **Not changed** — raising them roughly doubles both fights and would move the solo clear targets in
`S06-064`/`S06-074`, which is owner judgement (`S16-113`). The Walker config also carries none of the spec's component HP
(two 400 HP leg actuators, 550 HP cannon housing), so that system is either absent or configured elsewhere.

**FIRST IMPLEMENTATION FIX OF THE AUDIT — `S09-035` war points, place 463.** Evidence `evidence/v463-war-commit-at-primary/EVIDENCE.md`.

The defect was inverted in both directions: `ExtractionService.finish(success)` passed the **extraction** outcome to
`recordMission()`, so a completed primary followed by a failed evac was recorded as a **loss**, and a lost primary
followed by an emergency evac was recorded as a **win**.

Fixed with four edits: new `GalacticWarService.commitPrimary(template)` guarded by `GF_WarCommitted`; the marker cleared in
`ObjectiveService.setup`; the commit called from `ObjectiveService.complete` (which already had a once-only guard); and
`ExtractionService.finish` now records a loss **only** when the primary never completed. All three modules pass `loadstring`.

Verified in a temporary `Script` parented to `ServerScriptService` so it shared the live module instances — a tool-VM
`require` gets its own copies and would have proved nothing. Script deleted after the run.

```
before                      [w=13 l=7  c=false]
afterComplete               [w=14 l=7  c=true ]  committed AT PRIMARY
afterComplete2              [w=14 l=7  c=true ]  idempotent
afterFail_primaryDone       [w=14 l=7  c=true ]  failed evac did NOT touch the campaign
afterFail_primaryIncomplete [w=14 l=8  c=false]  loss only for an incomplete primary
```

**Place version is now 463.** That resolves the contradiction below: WORK_STATE 448, HANDOFF 318, BLOCKED 232 and commits
461 were all stale. 463 is the authoritative saved version.

**Side effect, stated plainly:** testing the real path wrote one win and one loss into `GalacticWarService`'s DataStore
(`missionsWon` 13 → 14, `missionsLost` 7 → 8). The war score is cosmetic, but the counters are no longer the pre-test
values.

**BLOCKED.md ability item CLOSED — it was never a game defect (place 463).** Evidence `evidence/v463-ability-cast-verified/EVIDENCE.md`.

The "unresolved" v260 blocker had two causes, neither a broken pipeline:

1. `State.get(player) == nil` was the **tool-VM trap** — a tool-VM `require` gets its own module instance, so `states[player]`
   is empty there regardless of game state. Read from a real `Script` in the game: `State.get(player)` is non-nil with
   `shield = 100`. The false negative was reproduced deliberately to prove it.
2. `AbilityService.cast` already self-heals via `State.ensure` at lines 638-650.

Proven live: client-fired `UseAbility{abilityId="DomeShield"}` → `AbilityCastRequests=1`, `LastCastRejected=nil`, and the
world gained **`Workspace.DomeShield`, `DomeShieldRim` and 14 `DomePost` parts**.

**Ability config measured against spec — two mismatches, NOT changed (balance levers, owner call):**

| ability | spec CD | config CD | spec radius | config radius |
|---|---|---|---|---|
| **Orbital Lance** | **165s** | 180 | 6 | 6 |
| **Reflective Barrier** | **85s** | 95 | **10** | 12 |

`GOAL_2026-11-24.md` L77 also specifies Orbital Lance as "total 420 over 3 pulses" (config: `damage = 550`, single value,
no pulse split) and L78 sets Reflective Barrier duration "immediate/7s" (config: 6). Airstrike, Dome Shield, Sentry and
Orbital Strike all match. Recorded on `S05-015` and `S05-016`.

**Diagnostic pass: payout branches, missing event ledger, blueprint + mastery defects (place 463).** Evidence `evidence/v463-reward-branches-and-mastery/EVIDENCE.md`.

**`compute` payout table measured** (Normal, squad 1): extracted+primary 450/600 · **failed evac+primary complete 450/600** ·
extracted+primary FAILED 0/0 · failed evac+primary FAILED 0/0. This corrects an earlier note — a failed *extraction* after a
completed primary still pays full base with salvage withheld. The zero case is an **objective failure**.

**`S09-025` ABSENT — the rewards event ledger does not exist.** Scanned every `LuaSourceContainer` under
`ServerScriptService.GF` for `eventType` / `resourceDelta` / `appendEvent`: none. `RewardsService` is 150 lines, three
functions, no event list, no kill-XP table. **This is the missing subsystem under `S09-033`, `S09-040`, `S10-015`–`S10-019`
and `S10-037`** — which is why `S09-033` cannot be fixed as a one-liner.

**`S06-072` — the pity comment is false.** `ProfileService:82-85` reads *"The spec requires the blueprint to be guaranteed on
the third qualifying clear. It was set to 5, so a..."* then `BOSS_PITY = 3`. `GOAL_2026-11-24.md` L102 says **5**, and
`BOSS_BLUEPRINT_CHANCE = 0.34` against the authored **15%**. So 5 → 3 was a **misreading, not a decision** — the justification
in the file cannot be trusted as a record. Both recorded, neither changed (drop rate is a gameplay lever).

**`S10-037` / `S09-034` / `S10-039` — mastery exists, its ladder and its gate do not.** `weaponMastery = {}` and
`ProfileService.addMastery` exist, called from `CombatService:231` with **+1 per hit** and `ArmoryService:503` (+5 test hook).
But the five levels with thresholds `[0,100,240,420,650]` appear **nowhere** in the project, and accrual happens per hit
mid-mission — so a player who fails the primary keeps all mastery, the exact opposite of the settlement rule.

**MASTERY LADDER FIXED — it was unreachable by construction (place 464).** Evidence `evidence/v464-mastery-ladder/EVIDENCE.md`.

First, a correction to my own previous note: mastery is awarded **+1 per kill**, not per hit. The award sits inside the
`if newHealth <= 0` branch, and the spec also forbids per-hit credit. The structure was right; the arithmetic was not.

```lua
local updated = math.min(10, current + math.floor(amount))
```

The spec sets five levels at `[0, 100, 240, 420, 650]` and caps XP at level 5. **A cap of 10 sits below level 2's 100, so no
weapon could ever leave level 1**, and the level-5 augment socket was unreachable by construction. The thresholds existed
nowhere in the project.

Fixed: cap 10 → 650; new `MASTERY_THRESHOLDS` + `ProfileService.masteryLevel`; and `CombatService` now awards the authored
per-archetype value (Rifleman/Scout/Marksman 10, Heavy 20, Officer 35, Walker 100, Veyr 250) instead of a flat 1 — a flat 1
could not reach 100 either, so rate and cap had to move together.

Measured with a real loaded profile:

```
thresholds=0,100,240,420,650
after +10    xp=15  lvl=1
after +90    xp=105 lvl=2
after +140   xp=245 lvl=3
after +10000 xp=650 lvl=5
```

**A process slip, caught:** my first insertion was spliced with an off-by-one and produced `Expected identifier when parsing
expression, got '}'`. `loadstring` caught it before Play and it was repaired. This is the silent-edit hazard HANDOFF records —
every edit this session is compile-checked before running.

**Still open:** `S09-034` settlement is untouched — mastery still writes to the profile per kill, so a player who fails the
primary keeps it. That needs an in-mission bucket, not a constant change.

**SPEC CONFORMANCE IS NOW AUTOMATED (place 465).** Evidence `evidence/v465-spec-conformance-check/EVIDENCE.md`.

Seven defects in this audit were one shape: a config number silently disagreeing with the specification. All were found by
a human reading a ledger, which is not a control. `CheckRunner` now transcribes the authored tables and asserts config
against them every boot — 8 weapons (damage/RPM/mag/reserve/reload/falloff/radius), 6 ability cooldowns and radii, 2 boss HP
values — publishing `GF_SpecDrift`.

Result in a fresh Play VM: **passed=625 failed=13**.

```
Augments: duplicate id FastHands
RL09.radius 12 (spec 10)      GL22.radius 9 (spec 13)
OrbitalStrike.radius 12 (spec 13)   OrbitalStrike.damage 400 (spec 390)
Sentry.radius 60 (spec 65)          Sentry.damage 12 (spec 10)
ReflectiveBarrier.cooldown 95 (spec 85)  .radius 12 (spec 10)
OrbitalLance.cooldown 180 (spec 165)     .damage 550 (spec 420)
HighMarshalVeyr.health 4000 (spec 7200)  BastionWalker.health 1200 (spec 3600)
```

**Two drifts were new** — `OrbitalStrike` radius/damage and `Sentry` radius/damage had never been recorded by the audit.

**One pre-existing failure surfaced:** `Augments: duplicate id FastHands`. Two archetypes share that id, which is exactly what
`S11-054` requires to be impossible. The check always computed this; nothing acted on the result.

**Rank and cost are deliberately not asserted.** The authored weapon table (L52-L59) and the prose arsenal list (L393-L397)
contradict each other on rank and cost for AR-01, SG-04, MR-07 and LMG-12 (the table gives LMG-12 rank 1 / 750cr, the prose
rank 7 / ~1,400cr). Config follows the prose. Asserting those would have produced four false positives.

Drift is reported but not fatal: `Main` warns and continues. Making it fatal is a one-line change once this list is clear.

**Duplicate augment id fixed, boot check clears to 12 drifts (place 466).** Evidence `evidence/v466-duplicate-augment-id/EVIDENCE.md`.

`CheckRunner` reported `Augments: duplicate id FastHands` — two archetypes declared the same id, both created in the
32-archetype rebuild at build 408. Not cosmetic: `Augments.ById` is keyed by id, so one entry overwrote the other and a
Pistol-category roll could resolve to the SMG archetype's effects and cost.

Renamed the Pistol entry to `PistolFastHands` (display label unchanged). Verified first that only two places in the entire
project mention `FastHands`, both the config definitions, so no reference or saved key could break.

`ok=false passed=625 failed=13` → **`ok=false passed=625 failed=12`**. `passed` does not rise because the duplicate check has
no clean-path assertion; the failing one is simply gone.

The remaining 12 failures are all **balance drift** and are the owner's to rule on.

**MASTERY SETTLEMENT GATE FIXED — `S09-034` now VERIFIED (place 467).** Evidence `evidence/v467-mastery-settlement-gate/EVIDENCE.md`.

The spec settles mastery on mission completion and not on an incomplete primary. The build did the opposite: `CombatService`
called `addMastery` on every kill, and `addMastery` writes the profile immediately — so a player could farm kills, fail the
primary and keep every point.

Fixed structurally: kills credit a per-player `State.pendingMastery` bucket, and `ExtractionService.finish` settles it through
`addMastery` only when the primary completed, clearing it either way.

```
case1 (primary NEVER completed)  mastery 0 -> 0   settled=0   50 earned, 0 credited
case2 (primary completed, failed evac)  mastery 0 -> 50  settled=50
```

Case 2 is the requirement's other half: mastery is independent of the way out, so a squad that wins the primary and loses the
dropship keeps what it earned.

**Also added to `.goal/HANDOFF.md` as a known trap:** a tool-VM `require` is **cached across calls**, so after editing a
module's `Source` the tool VM can return the *previous* compiled version with no error. It produced a phantom "ability missing
from config" twice this session and made a working fix look broken. Verify edits in a fresh Play VM or from a temp
`Script` in `ServerScriptService`.

**Path correction:** earlier evidence during this audit cited `HANDOFF.md` at the repo root; it lives at `.goal/HANDOFF.md`.

**Kill-to-bucket path fired, closing the gap stated last batch (place 467).** Evidence `evidence/v467-kill-credits-bucket/EVIDENCE.md`.

A real `EnemyService.spawn("Rifleman", ...)` + `CombatService.damageEnemy(...)` kill through the real damage path:

```
weapon=SMG03  profile=0 pending=0
afterKill        profile=0  pending=10  dead=true
afterFailFinish  profile=0  pending=0   settled=0
```

Confirms three things: the kill credits the authored **10** XP to the bucket, the **profile is untouched** on the kill (before
place 467 the same kill called `addMastery` and moved it), and a failed primary discards the bucket.

**Open question, recorded not dismissed:** the previous batch's settlement test wrote 50 XP to SMG03 on this account, and this
server read SMG03 as **0**. Either the write missed the spec's ~60–90 s autosave window (previous server stopped quickly), or
`weaponMastery` does not survive the DataStore round-trip — which would make mastery session-only. Not called a defect: the
autosave explanation is at least as likely. To settle it: award mastery, wait past autosave, stop the server, start a new one,
read the same weapon.

**Mastery persistence SETTLED — it persists; the attribute was lying (place 469).** Evidence `evidence/v469-mastery-persist-publish/EVIDENCE.md`.

Last batch left this open: 50 XP written to SMG03, a later server read 0. Answer: **the XP persisted the whole time.** `GF_Mastery_<weapon>` was written in exactly one place — inside `addMastery` — so on a fresh server it read nil until the player earned more.

The disproof of my own hypothesis: `addMastery(plr, "SMG03", 10)` returned **60**, therefore `current` was 50. Then a full
stop/start read `ProfileService.get(plr).weaponMastery.SMG03 = 60` while the attribute was still **nil**.

Fixed in `ProfileService.load` (the single choke point, which already syncs `IntroSeen`): mastery is published for every weapon
on join. Verified in a fresh server — `attrXP=60` on join with no award that session.

This is the **seventh** false-negative mechanism in this project and the same shape as the rest: an instrument disagreeing with
real state. Any HUD reading that attribute would show nothing for a returning player, which reads as lost progress.

**SECOND AUGMENT SOCKET GATE FIXED — `S10-037` now VERIFIED (place 470).** Evidence `evidence/v470-socket-gate-level5/EVIDENCE.md`.

Spec: *"starter one Augment socket, level5 second permanent socket"*. `AugmentService.socketsFor` compared **raw XP** against a
constant named `SECOND_SOCKET_MASTERY = 5` — the name said level 5, the comparison used XP.

**And my own change made it worse.** At the old 1-XP-per-kill rate with a cap of 10, `XP >= 5` happened to act like "five kills".
After I rescaled mastery to the authored 10 XP per kill with a 650 cap two batches ago, it unlocked the second socket on the
**first kill**. A latent naming bug became a visible exploit because of my fix.

Now `SECOND_SOCKET_XP = 650` (the level-5 threshold), with the refusal message saying so. Verified at the boundary:

```
xp=0/10/100/500/649 -> 1 socket      xp=650/900 -> 2 sockets      unowned -> 0
equip slot2 @500xp -> ok=false "requires mastery level 5 (650 XP)"
equip slot2 @650xp -> ok=true
```

`xp=10 -> 1 socket` is the assertion that matters: one kill under the authored rate, which previously returned 2.

**My own test errored first:** the probe called `A.assign(...)`, which does not exist, threw at line 14 *after* the sweep but
*before* publishing its result, so the attribute read `nil` and looked like the fix had failed. The console named the cause in
one line. Second instrument failure this session that briefly impersonated a code fault.

**MASTERY NOW VISIBLE IN THE DEBRIEF (place 471).** Evidence `evidence/v471-mastery-debrief-display/EVIDENCE.md`.

Rendered client debrief after a mission that settled 25 XP:

```
Credits  base 450  +  squad bonus 0
Military XP  base 600  +  squad bonus 0
Mastery  SMG03  level 1  (85 XP)
```

**An ordering bug nearly made this lie.** Mastery settles in `ExtractionService.finish`, and the debrief payload is built in
`RewardsService.grant`, which `finish` called *before* the settle ran. A naive payload field would have reported the
pre-mission value — the player earns 25 XP and the debrief says nothing changed. Fixed by moving the settle above the
`grantAll` call. `(85 XP)` rather than `(60 XP)` in the capture is the proof.

**Process note:** my first edit corrupted `ExtractionService` with a stray `-` because I built the replacement with
`string.gsub` and the *pattern* contained `-`, which Lua treats as a lazy quantifier. `loadstring` caught it in the same call.
`gsub` is not a plain-text replace; this project has already lost one edit to text matching (`v439`).

**Still open:** the Armory half of the spec's "debrief/Armory" requirement — `ArmoryService.state` exposes sockets but not
mastery XP or level, and no armory row renders progress.

**MASTERY DISPLAY COMPLETE — `S10-039` VERIFIED (place 472).** Evidence `evidence/v472-armory-mastery-display/EVIDENCE.md`.

The Armory half. `ArmoryService.state` already built a raw-XP `masteries` table that nothing rendered, so the change is a
`masteryLevel` map (via `ProfileService.masteryLevel`) plus one line in `StationArmoryUI`. Measured on all eight rows:

```
Rifle · 18 DMG · 28 MAG · Auto · MASTERY 5 (650 XP)
LMG · 17 DMG · 75 MAG · Auto · MASTERY 1 (5 XP)
SMG · 13 DMG · 36 MAG · Auto · MASTERY 5 (650 XP)
... six more, all correct
```

The whole mastery chain is now observable end to end: earn → bucket → settle on a completed primary → persist → publish on join
→ level → socket → debrief → armory. It took six batches, and two of the defects in it were introduced by fixes earlier in the
same session.

**Side effect:** SMG03 is now at 650 XP / level 5 on the test account (the probe pushed it), which also unlocks its second
augment socket. The Rifle was already there from the ladder test.

**REWARDS LEDGER EXISTS — record-only, no payout changed (place 473).** Evidence `evidence/v473-rewards-ledger-record-only/EVIDENCE.md`.

`S09-025` was deferred four times on the grounds that shaping it wrong would be expensive to unwind. That was true and also an
excuse. Resolution: build the **recording** half only — `RewardsService` still pays exactly what it did, so nothing about the
economy moves until a later batch deliberately makes settlement read from the ledger.

New `RewardLedgerService`: `begin`, `append`, `isClaimed`, `snapshot`. Invariants: `seq` monotonic per mission, and a
`sourceId` claimable exactly once so a retry cannot pay twice. Wired at three sites, all `pcall`-wrapped so a ledger fault
cannot break gameplay.

Measured: setup → seq 0; primary completion → `#1 primary_complete`; duplicate source refused with a reason; extraction →
`#2 extraction_success`; next mission restarts at seq 0 with old claims cleared.

**Still PARTIAL, deliberately:** no `eligibleUserIds` (single `userId` only), not durable (in-memory, lost on restart), and
every `resourceDelta` is 0 because no per-event deltas are computed yet (`S10-012`–`S10-019`). Durability ownership is the next
real design decision.

**AUTHORED PER-EVENT TABLE + FRACTIONAL TOTALS (place 474).** Evidence `evidence/v474-event-reward-table/EVIDENCE.md`.

`RewardLedgerService` now carries the L150-L157 event table and the L161 difficulty multipliers, and computes each event
fractionally — no rounding per event, one floor at settlement.

```
value primary_complete@Normal   cr=300.00  xp=437.50
value primary_complete@Extreme  cr=495.00  xp=875.00      (300x1.65, 350x2.5)
value kill_Heavy@Normal         cr=3.00    xp=25.00  m=25.00

real mission: #1 primary_complete 300/437.5 · #2 extraction_success 100/125
totals 400.00 cr / 562.50 xp      floored once -> 400 cr / 562 xp
```

Still **record-only**: `RewardsService` pays its own way, so these values do not yet decide a payout.

**Eighth instance of the instrument pattern, and I wrote this one.** The first measurement printed `cr=-1.00 xp=-1.00` while
`totals()` returned the correct 400/562.5 — `snapshot()` copied events through a fixed field list that omitted `credits`,
`xp`, `mastery` and `difficulty`. Stored data was right; the view dropped it. Fixed with the reason commented in place.

`S10-012`–`S10-021` are now PARTIAL rather than ABSENT.

**LEDGER `eligibleUserIds` ADDED (place 475).** Evidence `evidence/v475-ledger-eligible-users/EVIDENCE.md`.

`S09-025` names `eligibleUserIds`; `SquadService` has no eligibility notion (`join, leave, add, snapshot, total, reset`), so the
set is derived from live session state — a player with a runtime `State` entry is present and owed.

```
#1 primary_complete   eligible=1889759131
#2 extraction_success eligible=1889759131
eligible with state=1, after State.clear=0     <- removed player correctly excluded
```

Every field the spec names now exists on each event. **Durability is the only missing input**: the journal is in-memory, so it
cannot provide the retention or idempotent recovery `S09-025` also asks for. Wiring settlement into a journal that evaporates
on restart would produce something that looks implemented and loses money on the first server bounce.

Untested eligibility states: **downed**, **pending-redeploy**, **co-op** (one client only), and **disconnect grace** (no restore
path exists).

**DURABILITY DECISION RECORDED (no code) — `.goal/DECISIONS.md`.** Also: `HANDOFF.md` claimed *"Place version at handoff:
318"*, stale by 157 saves; corrected to **475**.

Two shapes for `S09-025` durability were written up with trade-offs: a **per-user journal inside the profile** (rides the
DataStore, serialisation, retry and dirty-marking already proven surviving two restarts at build 430; cost is one mission
spread across N records) versus a **per-mission DataStore journal** keyed by `missionId` (matches the spec schema literally;
cost is a second durability surface with its own retention and idempotency). **Recommendation: per-user journal**, because the
proven machinery already exists and option 2 duplicates it with a second silent-failure point. Recorded as a recommendation,
not a decision — and settlement must NOT read the ledger until durability exists.

**Downed eligibility answered by source, not runtime:** `DownedService` sets `state.downed` and never calls `State.clear`, so a
downed soldier keeps their state and stays eligible, which is what `S09-027` requires. Stated as a read, not a test.

**DOWNED ELIGIBILITY RUNTIME-VERIFIED (place 475, no source change).** Evidence `evidence/v475-downed-eligibility-runtime/EVIDENCE.md`.

The previous batch recorded the downed case as *"source reading, not a runtime downing test"*. Now tested with real
`VitalsService` calls:

```
before down   state=true  downed=false  eligible=1[1889759131]
after down    state=true  downed=true   eligible=1[1889759131]     <- downed stays eligible
after revive  state=true  downed=false  eligible=1[1889759131]     <- clean round trip
```

`S09-027` requires shared credits and salvage to reach each eligible **active/downed/pending-life** participant, so a downed
soldier silently dropping out would under-pay the player who most needs it. They do not drop out.

Still unproven: **pending-redeploy** (no distinct State representation exists, so genuinely unknown), **co-op** (one client),
**disconnect grace** (no restore path), and the down was applied via `downPlayer` rather than lethal combat damage.

**INPUT/PLAYER/HUD CONSTANTS AUDIT — two real drifts, two row-text errors (place 475, no source change).** Evidence `evidence/v475-input-constants-audit/EVIDENCE.md`.

`Constants` read whole and compared against the spec (L384/L921/L145), **not** against the ledger's own paraphrases:

| constant | value | spec | verdict |
|---|---|---|---|
| `Combat.DownedTimeout` | **45s** | **60s bleedout** | **defect** — dies 15s early |
| `Combat.ReviveDuration` | **3.5s** | **"hold revive 3s"** | **defect** — every revive costs +0.5s |
| `Movement.WalkSpeed` | 17.5 | ~17–18 | conforms |
| `Movement.AdsSpeed` | 13 | ~12–14 | conforms |
| `Movement.RollDistance` | 15.5 | ~14–17 | conforms |
| `Vitals.HealthMax/ShieldMax` | 100 / 100 | 100 / 100 | conforms |
| `ShieldRegenDelay` / `HealthRegenDelay` | 4 / 9 | 4 / 9 | conforms |

**Two ledger rows were themselves wrong, and I nearly filed false defects because of it.** `S03-016` says "Walk 17" (spec says
~17–18) and `S03-018` says "roll ~13 studs" (spec says ~14–17) — in both cases the *config was right and the row text was the
paraphrase error*. Same failure mode as the ER-16 conflict and the pity comment: a secondary description treated as the spec.

`Constants` is not a `Configs` module, so `CheckRunner`'s spec section does not cover these values — that is why both drifts
survived.

**CONFORMANCE CHECK NOW COVERS `Constants` (place 476).** Evidence `evidence/v476-constants-conformance-check/EVIDENCE.md`.

The bleedout (45 vs 60) and revive (3.5 vs 3) drifts survived because `CheckRunner` only asserted **`Configs`** modules —
`Constants` was never compared to the spec. A tenth section now asserts WalkSpeed/SprintSpeed/AdsSpeed, RollCharges/Duration/
Distance, HealthMax/ShieldMax, both regen delays, DownedTimeout and ReviveDuration, with ranges where the spec gives ranges.

```
before:  passed=625  failed=12   (config drifts only)
after:   passed=635  failed=14   +10 conforming constants, +2 real drifts
         CONST DRIFT: DownedTimeout = 45, spec 60-60
         CONST DRIFT: ReviveDuration = 3.5, spec 3-3
```

Fixing the two values is four characters and changes how the game feels, so it stays the owner's call. Closing the **detection
gap** is not an owner call: it is additive, changes no behaviour, and converts a defect class that needed a human to notice
into a boot failure. Two batches ago the same work found OrbitalStrike and Sentry drifts that twelve manual passes missed.

Not yet covered: `Combat.EnemyBudgetCap`, `MaxActiveEnemiesPerPlayer`, `InteractRange`, `RollRecharge`, and the regen **rates**
(only delays are asserted). `BOSS_PITY`/`BOSS_BLUEPRINT_CHANCE` remain unassertable locals.

**PITY VALUES MADE ASSERTABLE (place 477).** Evidence `evidence/v477-pity-values-assertable/EVIDENCE.md`.

`ProfileService` held pity as two file-local constants (`BOSS_PITY = 3`, `BOSS_BLUEPRINT_CHANCE = 0.34`) that no check could
reach, under a comment claiming *"the spec requires the blueprint to be guaranteed on the third qualifying clear"* — which
L102 does not say. Moved to `Constants.Pity` (**values unchanged**) and asserted:

```
ok=false passed=635 failed=16
  spec drift: Pity.Target = 3, spec 5-5
  spec drift: Pity.Chance = 0.34, spec 0.15-0.15
Constants.Pity Target=3 Chance=0.34      <- behaviour preserved, moved not retuned
```

The deviation is now visible at every boot, and a future session cannot quietly inherit the false comment — the check argues
with it. Fixing it is now a one-line change in one obvious place.

**The false comment is left in place deliberately** so the record of why the value moved survives, but it is contradicted by a
failing assertion rather than standing unchallenged.

**REGEN RATES + ROLL RECHARGE ASSERTED — all three conform (place 478).** Evidence `evidence/v478-regen-rate-assertions/EVIDENCE.md`.

Closing the gap the constants batch named: `ShieldRegenRate 25`, `HealthRegenRate 8` and `RollRecharge 3.5` are all pinned in
the spec and are now asserted.

```
before:  passed=635  failed=16
after:   passed=638  failed=16   new-section drifts: 0
```

`+3` passing, no new drifts — a check that grew without finding a defect. Worth recording that not every batch finds one.

**Two deliberately left unasserted:**

- `Combat.InteractRange` = **10**, while `v388`'s evidence mentions `INTERACT_RANGE (16 studs)`. Possible discrepancy, but no
  authored value exists to assert against, so it stays an open question rather than a green tick built on evidence prose.
- `EnemyBudgetCap` / `MaxActiveEnemiesPerPlayer` — the spec gives a *formula* (`round(4+2*(P-1))` × difficulty factor), not
  constants. Asserting 12 or 3 would mean inventing the mapping.

**INTERACT RANGE: 16 vs AUTHORED 9, AND A DEAD CONSTANT (place 478, no source change).** Evidence `evidence/v478-interact-range-9-vs-16/EVIDENCE.md`.

Resolving the open question from the previous batch. There are **two separate things**, not a conflict:

| symbol | value | referenced by |
|---|---|---|
| `ObjectiveService` local `INTERACT_RANGE` | **16** | 7 call sites (crates, terminals, pads; one at +4 = 20) |
| `Constants.Combat.InteractRange` | **10** | **nothing — dead configuration** |

So `v388`'s "16 studs" was right and `Constants` is simply unused.

**But 16 is wrong against the spec**, verbatim: *"Interact instant on valid range **<=9 studs**/LOS except hacking/revive"*. The
build allows 16, and one terminal path 20 — between 1.8× and 2.2× authored. A player can trigger objectives from nearly twice
the intended distance, and the hacking/revive carve-out is not implemented either way.

**Not changed** (feel parameter: pacing and combat pressure). Also deliberately NOT wired the dead `Constants` value in — 10 is
also wrong against 9, so connecting it would put a second wrong number in a live path while looking like a tidy-up.

Note `v388` measured the code's number rather than the spec's: behaviour was measured and still wrong.

**DEAD CONFIG REMOVED: `Constants.Combat.InteractRange` (place 479).** Evidence `evidence/v479-remove-dead-interact-constant/EVIDENCE.md`.

Scanned every `LuaSourceContainer` under `ServerScriptService`, `ReplicatedStorage`, `ServerStorage`, `StarterPlayer` and
`StarterGui` for `interactrange`: **one hit, the definition itself.** Zero consumers. Removed.

```
Combat.InteractRange = nil
Combat keys = DownedTimeout, EnemyBudgetCap, MaxActiveEnemiesPerPlayer, ReviveDuration, ReviveRange
boot: ok=false passed=638 failed=16     <- identical to before, so nothing read it
```

Boot parity is the proof: had any consumer read the key it would now be `nil` and something would have failed.

**Why remove rather than leave it:** a dead constant reads as authoritative and sits beside live values. This one produced a
false lead that cost part of a batch — 10-vs-16 looked like a contradiction when only 16 was ever live.

**Still wrong:** `ObjectiveService.INTERACT_RANGE = 16` against the spec's **<=9**. But there is now exactly one interact range
in the project, so the question is unambiguous. When the owner sets it, the clean order is: move to `Constants.Combat` at 9 →
have `ObjectiveService` read it → assert in `CheckRunner`. Doing it in that order means the check never goes red against a
constant nothing uses.

**MY OWN CONFORMANCE CHECK WAS CERTIFYING DEAD CONFIG (place 480).** Evidence `evidence/v480-downed-reads-constants/EVIDENCE.md`.

Scanning the 64 service-local numeric tunables found two alarms in the first ten lines.

**1. `DownedService` never requires `Constants`.** It had its own `BLEEDOUT = 45`, `REVIVE_TIME = 3.5`, `REVIVE_RANGE = 12`,
while `Constants.Combat` carried the same three names with — verified by consumer scan — **no consumers at all**. So my
"CONST DRIFT: DownedTimeout = 45" and "ReviveDuration = 3.5" assertions were certifying values nothing reads. That is exactly the
failure mode I warned about one batch earlier when refusing to centralise `INTERACT_RANGE` — and I had already committed it two
batches before saying so. The numbers happened to agree, so the drift was still true of behaviour; the **method** was wrong. A
check pointed at an unused copy proves nothing: had DownedService said 30 while Constants said 45, the check would have passed
while the game bled players out in 30 seconds.

Fixed by centralisation, not retuning: `DownedService` now reads `Constants.Combat` (45 / 3.5 / 12 unchanged). Boot parity
`passed=638 failed=16` proves no behaviour changed, and the two drift assertions now cover the governing value.

**2. The mission clock is 25 minutes, not 15.** `StationService.MISSION_SECONDS = 1500` against the spec's *"15min standard
active clock"*. `v433` recorded a fresh deploy showing `MISSION 24:52` — measured correctly, never compared to the spec.
Recorded, not changed: a 40% shorter mission changes the whole game's pacing.

**Consumer-scan results worth keeping:** `RollRecharge` → MovementService, `ShieldRegenRate`/`HealthRegenRate` → VitalsService,
`Pity` → ProfileService (all sound). `DownedTimeout`/`ReviveDuration`/`ReviveRange` → none (now centralised).

**The rule this proves:** assert the value at its consumer, or centralise so the consumer cannot disagree.

**EXTRACTION COUNTDOWN CENTRALISED THEN ASSERTED (place 481).** Evidence `evidence/v481-countdown-centralised/EVIDENCE.md`.

Applying last batch's rule in the right order — centralise **first**, assert **second**, so the check points at the value that
runs:

1. `Constants.Mission.ExtractionCountdown = 45` (moved unchanged)
2. `ExtractionService` reads it
3. `CheckRunner` asserts it within the authored **60–90**

```
boot ok=false  passed=638  failed=17
  spec drift: ExtractionCountdown = 45, spec 60-90
Constants.Mission.ExtractionCountdown=45
ExtractionService loads=true
```

`failed` 16 → 17 with `passed` unchanged is the correct signature for a newly-asserted genuine failure. Behaviour untouched: the
window is still 45s, because 45 vs 75 is a pacing decision.

**Spec verbatim:** *"defense countdown 75s default (60–90 by difficulty/variant)"*. 45 is below the fastest variant by 15s, and
the "by difficulty/variant" clause is unimplemented — there is one countdown, not a table.

**A three-way disagreement found while editing:** mission length has `Constants.Mission.DurationStandard = 990` (apparently
unconsumed), `StationService.MISSION_SECONDS = 1500` (what runs), and a spec value of **900**. Not centralised here — mission
length is governed by `StationService` and moving it is too large for this batch.

**DEAD-CONSTANT INVENTORY; ADS IS UNIMPLEMENTED (place 482).** Evidence `evidence/v481-dead-constant-inventory/EVIDENCE.md`.

46 `Constants` keys parsed from current Source: **25 have no consumer**. Two findings:

1. **`AdsSpeed` and `RollDistance` have zero consumers** — so the assertions added at place 476 were certifying dead config, the
   `DownedTimeout` mistake repeated. Both removed (`passed 638 → 636`, `failed` unchanged).
2. **Aiming does not slow movement.** Spec requires ADS 0.8× walk; `Movement.AdsSpeed = 13` is never read and no code changes
   `WalkSpeed` while aiming. Consequence: `AugmentService`'s `adsSpeed` stat key is inert, so an augment can roll it and do
   nothing — a paid dead trait.

**Negative result:** an in-game "every key has a consumer" check is **impossible** — a runtime `Script` cannot read `.Source`
(`lacking capability PluginOrOpenCloud`). It can only run plugin-side.

**The dead-key list is a map of unimplemented systems:** `Squad.Extraction*`/`MaxPlayers` → no voting (`S09-002`);
`Net.FireRateLimitPerSecond`/`MaxRemoteBytesPerSecond` → no rate limiting (`S14-023`); `Progression.Mastery*` → duplicate of
ProfileService's thresholds; `World.*` → procedural params unused; `Mission.Duration*` → `StationService.MISSION_SECONDS` rules.

**ADS IMPLEMENTED — three missing links, not one wrong number (place 484).** Evidence `evidence/v484-ads-implemented/EVIDENCE.md`.

`S03-016` needs ADS at 0.8× walk and `S03-003` needs RMB ADS. The gap was structural: `Movement.AdsSpeed` was read by **nothing**,
**nothing set the `Aiming` attribute** (so `GF_CharacterAnimator`'s aim pose could never fire), and **no aim remote existed**. RMB
was only a camera-look toggle.

Wired end to end: `AimChanged` added to the single remote registry; `MovementService` gained `applyStance()` (the one place
WalkSpeed is decided: aim → crouch → sprint → walk) and an `AimChanged` handler; `Controller` fires it on RMB down/up; the
`AdsSpeed` assertion is restored now that the value has a consumer.

```
aim on  -> GF_AimState "true:13"   Aiming attribute = true
aim off -> GF_AimState "false:17.5"
check: passed=639 failed=17
```

`Aiming=true` also revives the animator's dead aim branch — two defects closed by one wiring.

Open: AdsSpeed 13 is 0.74× walk, not 0.8× (14); aim-over-crouch precedence is unspecified and my choice; RMB still toggles camera
look as well; LT/L2 and touch aim are not wired; no FOV/camera shift or crosshair tightening.

**ADS RATIO + AUGMENT WIRED (place 485).** Evidence `evidence/v485-ads-ratio-and-augment/EVIDENCE.md`.

`AdsSpeed` 13 → **14**: the spec gives a ratio ("0.8× walk") and 0.8 × 17.5 = 14, so 13 was 0.74×. Measured `aim on → true:14`.

The `adsSpeed` augment stat was inert and now applies. **Correction to place 482:** my scan said "0 augments use adsSpeed" — a
false negative from reading `e.stats` when the field is `e.effect`. Exactly one augment rolls it,
`StabilityCompensator = -0.08`. Real key census: `recoil 8 · weakPoint 8 · healthDamage 7 · armorDamage 5 · blastRadius 4 ·
reloadSpeed 4 · swapSpeed 4 · cooldown 3 · magazine 3 · adsRecovery 2 · followUpSpeed 2 · movingAccuracy 2 · sentryAmmo 2 ·
adsSpeed 1`.

**Sign convention is a judgement, documented as one.** A negative value on a "compensator" must make aiming *less* restrictive,
so the formula is `AdsSpeed * (1 - bonus)`. Measured with the augment equipped: `true:15.12` = 14 × 1.08. If the author meant the
opposite, it is one line to flip.

**12 OF 36 AUGMENTS ARE PLACEBO (place 485, no code change).** Evidence `evidence/v485-placebo-augments/EVIDENCE.md`.

The allow-list declares 14 stat keys; only **7** are ever read: `weakPoint`/`healthDamage`/`armorDamage`/`shieldDamage`
(CombatService), `magazine`/`reloadSpeed` (via AugmentService helpers), `adsSpeed` (MovementService, added at 485).

**Never applied:** `recoil`(8 augments), `blastRadius`(4), `swapSpeed`(4), `cooldown`(3), `adsRecovery`(2), `followUpSpeed`(2),
`movingAccuracy`(2), `sentryAmmo`(2). Each appears exactly once in `AugmentService` — inside the allow-list literal.

Result: **12 of 36 augments do nothing at all** — Bipod, BorePolish, CoolantLoop, ExtendedSentryMagazine, FastHands, HeatSink,
LightBolt, OverclockedCore, QuickDraw, ReflexSear, StableStock, WideCharge. A third of the catalog is purchasable placebo.
`FastHands` was doubly broken: the duplicate id fixed at place 466 *and* an inert effect.

Also: **no cross-slot clamp** (`S11-055`) — per-application floors only, so two same-stat augments stack unbounded with no
negative floor.

**Two false negatives corrected first:** `e.stats` is actually `e.effect` (third field-name error this session), and excluding
`AugmentService` from the consumer scan wrongly made `magazine`/`reloadSpeed` look dead — a key's consumer may be its owning module.

**Why invisible:** every check validates augments *exist*. None asks whether a trait *does anything*. 639 passing assertions, none
of them about effect.

**`cooldown` AUGMENT WIRED — 8 of 14 keys now live (place 487).** Evidence `evidence/v487-cooldown-augment-applied/EVIDENCE.md`.

`AbilityService` set cooldowns inline at four identical sites; all four now route through one `beginCooldown(player, s, ability)`
that applies `ability.cooldown * math.max(0.25, 1 - bonus)`. Measured: Airstrike **90s → 46.1s** at bonus 0.4785
(`90 × 0.5215 = 46.94`, sampled 0.8s after the cast). Before this batch the same cast read ~90.

Now live (8): weakPoint, healthDamage, armorDamage, shieldDamage, magazine, reloadSpeed, adsSpeed, **cooldown**.
Still dead (7 keys, 9 augments): recoil(8), blastRadius(4), swapSpeed(4), adsRecovery(2), followUpSpeed(2), movingAccuracy(2),
sentryAmmo(2). Fully-placebo augments down from 12 to **9**.

**The stacking defect now has a number:** bonus **0.4785 = 47.85% cooldown reduction**, where the spec caps support cooldown at
**+20%**. `forProfile` sums additively with no clamp, so this is `S11-055` demonstrated rather than theorised.

**Mistake caught in-batch:** my replacement loop counted 5 substitutions instead of 4 — it also matched the line inside the helper
it had just inserted, yielding a syntax error at line 26. `loadstring` caught it before running. Rule: when inserting code that
contains the string you are about to replace, insert *after* the replacements or anchor on surrounding context.

**Authoring oddity for the owner:** `ExtendedSentryMagazine` carries `cooldown = 0.2` despite the name saying magazine — looks like
a config slip.

**`blastRadius` WIRED — 9 of 14 keys live, first authored clamp honoured (place 489).** Evidence `evidence/v489-blastradius-applied/EVIDENCE.md`.

Four augments rolled `blastRadius` into nothing. Now applied in `CombatService.detonate`:

```
base (no augment) -> radius 9.00   bonus 0
+ SiegePayload    -> radius 11.25  bonus 0.8514
```

`9 × 1.25 = 11.25` — **clamped at the spec's +25%**, the first augment stat in the project to honour its authored cap. Unclamped the
same stack would have given 16.66 (+85%). Signs are data-driven (positive widens, negative tightens); the 0.4 floor is mine.

The 0.8514 bonus is well above one `SiegePayload` (+0.45) — the test account accumulated several blastRadius augments across this
session's probes, so the stacking defect is **reproducible on demand** and the clamp is demonstrated necessary and sufficient for
this stat.

Live keys (9): weakPoint, healthDamage, armorDamage, shieldDamage, magazine, reloadSpeed, adsSpeed, cooldown, **blastRadius**.
Still dead (6 keys, 5 augments): recoil(8), swapSpeed(4), adsRecovery(2), followUpSpeed(2), movingAccuracy(2), sentryAmmo(2).

**PER-STAT CLAMPS IMPLEMENTED + ABILITY-TRAIT BUG FIXED (place 490).** Evidence `evidence/v490-augment-clamp-table/EVIDENCE.md`.

`AugmentService.forProfile` now clamps the summed bonus per stat to the authored caps and floors negatives at 0 — the requirement
in `S11-055` that previously existed nowhere:

```
before: cooldown 0.4785  -> Airstrike 46.1s
after:  cooldown 0.200   -> Airstrike 71.9s   (90 x 0.8 = 72)
blastRadius: WideCharge +0.3 -> 0.250         (clamped to the +25% cap)
```

**Real bug found on the way:** the ability augment's trait was *never* applied — `applyTrait(out, profile, id)` used `id`, an
out-of-scope weapon-slot loop variable, instead of `ability`. Fixed.

**Two false leads ruled out before they became claims.** `blastRadius` read `0`, which looked like the clamp zeroing a value; it
was simply not equipped (the persisted loadout held only `CoolantLoop`). Chasing that found `AugmentService` has **zero**
`markDirty` calls vs `ArmoryService`'s fourteen — which looked like "augment changes never persist". They do: my probes called
`AugmentService.equipAugment` directly, bypassing the only caller that marks dirty. Probe artifact, product path intact — but the
fragility is real for future code. It also means the place-489 `blastRadius 11.25` was measured on state that never persisted.

**NO SPREAD MODEL EXISTS — every weapon is perfectly accurate (place 490, no code change).** Evidence `evidence/v490-no-spread-model/EVIDENCE.md`.

Chasing the two remaining big augment keys led to the real gap. `Configs/Weapons` declares `spreadBase`, `spreadPerShot` and `recoil`
on every weapon (AR-01 0.6/0.35/1.0, LMG-12 3.2/0.2/2.0, SG-04 0.15/0.6/1.6 …) and a scan of `ServerScriptService` + `StarterPlayer`
returns **zero consumers**.

So: **no bloom, no per-shot growth, no aim penalty** — every shot lands exactly where the ray points, and the spec's ADS spread
column is unimplemented. This re-reads `S04-036`: the spread values are not *missing from the table*, they are present and unused,
which looks done and isn't.

**This is why `recoil` (8 augments) and `movingAccuracy` (2) cannot be wired** — 10 of 36 augments sit behind one absent system.
`swapSpeed` (4) is blocked differently: switching is instantaneous, so there is no delay to scale.

**Not implemented on purpose.** Spread changes hit registration, and every exact-shot measurement in the ledger (18-shot TTK, the
90/240 falloff curve, v461 falloff, arc-of-fire) was taken in a perfectly accurate world. Adding jitter would make that evidence
irreproducible and move TTK, so it needs an owner call plus a `GF_ForceNoSpread` determinism switch — the same pattern as
`GF_ForceNoBlueprintChance`.

**SPREAD MODEL IMPLEMENTED (place 492).** Evidence `evidence/v492-spread-model/EVIDENCE.md`.

I implemented what I deferred last batch: spread is an authored functional requirement with explicit spec values, and the config
fields already existed — the intended design was clear.

- **Data:** `adsSpread` did not exist on ANY weapon (the spec's ADS column was never transcribed). Added all eight from L53-L60.
- **Model** in `CombatService.fire`: bloom +`spreadPerShot` per shot, decays 1.0/s, capped 6; hip uses `spreadBase`, aiming uses
  `adsSpread`; `recoil` augment cuts the remainder; jitter rotates the unit direction; **`GF_ForceNoSpread`** disables all of it so
  the existing TTK/falloff evidence stays reproducible.

```
6 shots at 600 RPM: 0.600 0.817 1.026 1.250 1.467 1.682   (bloom building)
GF_ForceNoSpread=true: "disabled"                          (truthful, not stale)
hip 0.600  vs  ads 0.550                                   (authored AR-01 adsSpread)
```

**Two self-inflicted bugs fixed mid-batch:** with the switch on I never wrote the attribute, so a disabled run reported the previous
value — the fourth stale-attribute trap this session, in code I had written minutes earlier. And decay 2.5/s nearly cancelled
per-shot growth (`0.600 → 0.667` over six shots); 1.0/s makes it meaningful.

**Mine, not the spec's:** decay 1.0/s, bloom cap 6, recoil floor 0.4, uniform (not gaussian) jitter.

**Not verified:** scatter as hit geometry (only the angle was measured), `recoil` (no such augment equipped), and TTK/falloff were
not recaptured — those rows are now valid only under `GF_ForceNoSpread`.

**`recoil` + `movingAccuracy` WIRED — 11 of 14 keys live, and two sign bugs fixed (place 493).** Evidence `evidence/v493-recoil-movingaccuracy/EVIDENCE.md`.

The augment data settled the sign, and I had it backwards twice:

1. **My place-492 formula was inverted.** Every recoil augment is negative (StabilityCompensator −0.15 … MasterworkBore −0.25) and
   negative means *less* dispersion, so `1 - recoilCut` was **increasing** spread by up to 25% for augments whose purpose is to
   reduce it. Now `1 + recoilCut`.
2. **My own place-490 clamp deleted the stat.** `math.clamp(v, 0, cap)` floors at 0, and with every recoil value negative that
   **zeroed all eight recoil augments**. The spec's "negative floor 0" cannot apply to a stat whose benefit *is* negative. Added a
   `SIGNED = { recoil, adsSpeed, movingAccuracy }` set clamping to `[-cap, cap]`; everything else still floors at 0.
   `movingAccuracy` carries both signs in the data (Bipod +0.2, LongBarrel −0.05), so symmetric is the only safe treatment.

`movingAccuracy` implemented: moving (`> 2` studs/s) adds a **1.5°** penalty reduced by a positive value. The 1.5° and the
threshold are my invention — the spec names the stat but authors no magnitude.

```
stand 0.600  |  moving 2.100 (= 0.600 + 1.5)  |  + MasterworkBore 0.450 (= 0.600 x 0.75)
recoil attribute −0.25 survived the signed clamp (floor-0 would have zeroed it)
```

Under the old formula that augment would have produced `0.750` — a 25% penalty on a "recoil reduction" stat.

Live keys (11): weakPoint, healthDamage, armorDamage, shieldDamage, magazine, reloadSpeed, adsSpeed, cooldown, blastRadius,
**recoil**, **movingAccuracy**. Still dead (5 augments): swapSpeed(4, needs a swap delay to exist), adsRecovery(2),
followUpSpeed(2), sentryAmmo(2).

**`adsRecovery` + `followUpSpeed` WIRED BUT NOT VERIFIED — two unexplained anomalies (place 495).** Evidence
`evidence/v495-adsrecovery-followup-unverified/EVIDENCE.md`.

Signs were read from the data first this time: `adsRecovery` positive helps (FastHands 0.15, ReflexSear 0.25), `followUpSpeed`
negative helps (TargetDiscipline/PrecisionChamber -0.15) — opposite conventions, both fit `1 - bonus`. Wired as bloom-decay
multiplier and per-shot growth scaling while aiming.

**Verification failed and is recorded as such:**

```
slot1 ReflexSear=true  slot2 TargetDiscipline=true
adsRecovery=0.25  followUp=-0.15  swap=0.8000590953796903
hip3 = 0.600:bloom=0.35      ads3 = 0.550:bloom=0.35
```

- `bloom=0.35` after three shots, where a control run reached `0.82` — shots 2 and 3 did not accumulate, though no rejection was
  reported. Cause unproven.
- `swap=0.8` where only ReflexSear (0.4) carries `swapSpeed` — a slot looks **double-counted** after a session of repeated probe
  equips.

Proven: both keys are read correctly off a real loadout (the previously-dead plumbing works), and ADS spread still works with two
augments equipped. Not proven: that either stat changes behaviour.

**Next batch must start by instrumenting the reject path** (rejects, lastShotAt, ammo, lastShotId) and dumping
`selectedLoadout.weaponAugments` to find the duplicated slot — before wiring any further key.

**BOTH ANOMALIES DIAGNOSED — they were my probes, not the code (place 495, no source change).** Evidence
`evidence/v495-anomalies-diagnosed-adsrecovery-verified/EVIDENCE.md`.

A clean 4-shot run with per-shot instrumentation behaved perfectly (`bloom 0.35 → 0.51 → 0.67 → 0.83`, ammo decrementing, no
rejects). The earlier "bloom=0.35 after three shots" was **not** a firing fault: **each of my probes mutated the persisted loadout**
by equipping a different augment into slot 1, so "baseline" and "with augment" were different loadouts. Dumping the slots next to
the measurement is what exposed it — that should have been in every probe from the start.

**Third finding:** `unequipAugment(profile, slot)` takes **two** parameters. My probe passed three (`profile, "AR01", i`), so `slot`
got the string `"AR01"` and the call silently no-opped. Slot numbers are one table per loadout, not per weapon.

**`adsRecovery` VERIFIED** with a same-session A/B: 3 ADS shots gave `bloom=0.69` without it and `0.41` with `adsRecovery=0.25`,
matching the predicted `0.35 × 0.75` per-shot with 1.15× decay. **`followUpSpeed` supported but NOT isolated** — TargetDiscipline was
in both arms, so no control; the decay matches 1.15× baseline but that is arithmetic agreement, not an A/B.

13 of 14 keys wired. Never applied: **swapSpeed** (no swap delay exists) and **sentryAmmo** (sentry has no ammo pool).

**The hard lesson:** a wrong harness looks exactly like a passing test. Every reading taken without dumping the loadout alongside it
is suspect — including the place-495 "failure", where the code was probably right and the measurement was wrong.

**`followUpSpeed` ISOLATED AND VERIFIED — 13 of 14 keys now wired AND measured (place 495, no source change).** Evidence
`evidence/v495-followupspeed-verified/EVIDENCE.md`.

The previous run could not isolate it (TargetDiscipline was in both arms) and failed to clear the loadout because `unequipAugment`
takes two parameters. This run cleared correctly and confirmed `EMPTY` before the baseline burst:

```
baseline              [EMPTY]               fu=0      bloom=0.92  (4 shots)
withTargetDiscipline  [1=TargetDiscipline]  fu=-0.15  bloom=0.84  (4 shots)
```

Predicted: decay 1.00/s → `0.35 0.55 0.75 0.95` (observed 0.92); decay 1.15/s → `0.35 0.5275 0.705 0.8825` (observed 0.84). Both arms
match and differ by exactly the stat's effect.

**Census: 13 of 14 keys wired and measured.** Never applied (2 keys, needing a new system rather than a hook): `swapSpeed`
(switching is instantaneous) and `sentryAmmo` (sentry has no ammo pool). Either add the systems or remove the keys from the
allow-list so the catalog stops advertising them.

**Method that resolved both discrepancies: dump the mutated state next to the measurement.** Any probe touching persistent state
must print that state on every arm, or it silently compares the wrong things.

**`S11-037` CORRECTED TO ABSENT — there is no per-instance augment generation (place 495).** Evidence
`evidence/v495-augment-instances-absent/EVIDENCE.md`.

The row was labelled IMPLEMENTED_UNVERIFIED, implying a generator existed to test. It does not:

```lua
if profile.ownedAugments[augmentId] == true then return false end
profile.ownedAugments[augmentId] = true
```

Ownership is a **boolean set**. Each archetype carries exactly **one** trait definition of shape `{key,min,max}` — e.g.
`{key=recoil, max=-0.12, min=-0.17}` — and `forProfile` sums the fixed `def.effect`, so the authored min/max range is **never
sampled**. Rarity does not change trait count; every rarity has the same shape. So there is nothing for a "1/2/3/4 traits by rarity"
rule to apply to, and two copies of one augment are identical rather than two rolls.

**A measurement trap recorded:** counting `#e.trait` per rarity returns **3 for all four rarities**, which reads like "the 1/2/3/4
rule is missing" but actually counts the **3 keys of one definition**. That number must not be used as evidence.

**`S11-031` and `S11-037` are one missing subsystem, not two gaps** — a UID has nothing to attach to without instances, and
instances have nothing to identify without a UID. An augment instance model also touches persistence, cache opening, dismantle/fusion
protection and the UI, so it belongs with the same durability decision pending for the rewards ledger.

Ledger: ABSENT 2 → 3, IMPLEMENTED_UNVERIFIED 2 → 1.

**`COUNT-CLASS` VERIFIED — four classes, both passives, values conform (place 495, no source change).**
Evidence `evidence/v495-classes-verified/EVIDENCE.md`.

Config values match `GOAL_2026-11-24.md` L66 verbatim for all eight numbers. Runtime, applying each class on a real profile:

```
Assault  move=0.00  reload=0.15  shield=0.00  regen=0.00
Heavy    move=0.00  reload=0.00  shield=0.20  regen=0.00
Recon    move=0.05  reload=0.00  shield=0.00  regen=0.00
Support  move=0.00  reload=0.00  shield=0.00  regen=0.10
```

All four apply with **no gate**; personal + team both land on the owner (Assault `0.15 = 0.10 + 0.05`, Heavy `0.20 = 0.15 + 0.05`),
which is the spec's "solo is its own squad" rule; each class produces a distinct effect. Recon's personal `DodgeRecharge` and
Support's personal `ReviveSpeed` are not in the published attribute, so those two readings show only the team component — that is
consistent with the config, not evidence of a missing bonus.

**Unproven (needs a second client):** aura reaching a squad-mate, duplicate-stack prevention, and the +25% movement/reload/shield
caps. Also unverified: max-shield applied without free healing.

Ledger: IMPLEMENTED_UNVERIFIED 1 → 0, VERIFIED 31 → 32.

**AUGMENT INVENTORY CAPACITY IMPLEMENTED — `S11-032` ABSENT → PARTIAL (place 497).** Evidence `evidence/v497-augment-capacity/EVIDENCE.md`.

Spec: 200 baseline, +50 per expansion for 10 Cells + 3 Tech + 1000 Credits, max 400. None of it existed.

`AugmentService` gained the constants, a capacity count in `grantAugment` (publishing `GF_AugmentCapacity`) and
`expandCapacity(profile)`; `ArmoryService` gained an `expandAugmentInventory` action that marks the profile dirty — through the armory,
so the write persists.

```
capacity=1 owned=1  grant=false  marker "full 1/1"      capacity=2  grant=true  marker "2/2"
expand: cap 37 -> 87 (+50); credits 5000->4000, cells 40->30, tech 10->7
baseline with unset field: default=200
```

**Not verified:** the 400 clamp and its "already at max" refusal (needs 400 owned), every insufficient-funds branch, and **no armory
UI button exists** — the action works when invoked but a player cannot buy an expansion through the interface. Capacity also relies on
`or BASELINE_CAPACITY` rather than being written into the load-time schema.

**Disclosed:** the probe temporarily swapped `ownedAugments` for a one-entry table to make the blocking rule reachable, restored it,
and left `augmentCapacity` at 87 on the test profile.

Ledger: ABSENT 3 → 2, PARTIAL 155 → 156.

**CAPACITY RULES FULLY VERIFIED — `S11-032` VERIFIED (place 498).** Evidence `evidence/v498-capacity-branches-verified/EVIDENCE.md`.

`ProfileService.defaults` now writes `augmentCapacity = 200` explicitly instead of relying on `or BASELINE_CAPACITY`, and every branch
was exercised:

```
default on a real profile = 200
noCells   = false (not enough energy cells)          cells 9
noTech    = false (not enough military technology)   tech 2
noCredits = false (not enough credits)               999
funded    = true  (250)                              exactly 1000 / 10 / 3
atMax400  = false (already at max capacity)
from380   = true  cap = 400                          380 + 50 clamped, not 430
```

Each refusal names the specific shortfall, all three resource checks are independently reachable, the spec's exact cost boundary is both
sufficient and required, and the ceiling clamps rather than overshoots.

**Still open elsewhere:** no armory UI button for the expansion (action works via the remote); and `grantAugment` is the only guarded
path — any future code writing `ownedAugments[id] = true` directly would bypass the cap, the same shape as the `markDirty` bypass found
earlier.

**Disclosed:** the probe wrote credits/salvage/augmentCapacity on the test profile across six trials, leaving `augmentCapacity = 400`.

Ledger: PARTIAL 156 → 155, VERIFIED 32 → 33.

**CACHE OPENING NOW RESPECTS CAPACITY — and my place-495 ABSENT verdict was wrong (place 499).** Evidence
`evidence/v499-cache-capacity-gate/EVIDENCE.md`.

`CacheService.open` granted unconditionally and **ignored `grantAugment`'s return**, so a full inventory could open a cache, watch it
roll, and receive nothing silently. Added the fit-only gate:

```
full capacity (1/1):  returned=0  owned 1->1  blocked "full 1/1 needs 1"
room for one (2/1):   returned=1  owned 1->2  blocked nil
```

Deployment and cache rewards are **confirmed ungated by reference**: `augmentCapacity` appears in only three modules
(ProfileService default, AugmentService cap, CacheService gate) — no deployment/squad/dispatch path reads it, and
`grantToInventory`/`grantMission` have no capacity check.

**Correction:** I marked `S11-037` ABSENT at place 495, concluding nothing rolled traits. That was too strong, and the evidence was in a
file I had open: `CacheService.open` calls `Augments.rollTrait` and stores the sampled `{key,value}` in `profile.augmentTraits`. So the
authored min/max range **is** sampled; my claim that it "is never sampled" was wrong. What is genuinely missing is the **rarity rule** —
every augment rolls exactly one trait regardless of Common/Rare/Epic/Legendary. `S11-037` is now **PARTIAL**. The UID gap stands
(S11-031): traits are keyed by augment id, so two copies of one archetype can never differ.

**Still open:** `S11-035` bulk opening (no bulk path exists), and `S11-033`'s fusion clause (fusion does not exist).

Ledger: ABSENT 2 → 1, PARTIAL 155 → 156.

**CACHE INSTANCES HAVE IDENTITY + my place-499 bug fixed (place 500).** Evidence `evidence/v500-cache-instances/EVIDENCE.md`.

**Bug first:** place 499 put the capacity gate inside `CacheService.open`, which returns early, but `openFromInventory` decremented the
held count *before* calling it. With a full inventory, opening a cache would have **eaten it**. Fixed by checking capacity before
consuming: measured `rolled=0  held 1->1  rejected="inventory full 1/1"` — the cache survives. A guard at the wrong layer, which is
this project's recurring failure.

**Then `S11-031`:** `profile.caches` was counts-per-tier only. Each grant now records
`{uid="Common-1795574978-1", tier="Common", source="mission:test", obtainedAt=...}` in `profile.cacheInstances`, and
`openFromInventory` consumes the oldest matching instance, passing its **uid as the draw source**:

```
granted 2 instances; first uid=Common-1795574978-1 tier=Common src=mission:test ts=1795574978
opened: rolled=1 held=1 instances left=1   GF_CacheOpened="Common:1:Common-1795574978-1"
```

**Still PARTIAL:** no crash-atomic transaction or journal — consume-before-open is at-most-once but a crash between removing the instance
and granting the augment loses the cache with no record. The 50-instance cap is my invention, and pre-existing profiles have counts with
no instances (source falls back to "unknown").

**Ledger: ABSENT 1 → 0.** That means every missing thing is now understood and recorded — not that nothing is missing.

**BULK CACHE OPENING IMPLEMENTED — `S11-035` both clauses verified (place 502).** Evidence `evidence/v502-bulk-open/EVIDENCE.md`.

A project-wide search for bulk/openAll/openMulti returned 22 hits, **all station bulkheads** — there was no bulk path at all, so the
authored limit had nothing to constrain. Implemented `CacheService.openMany`, with three bounds applied up front (cap 10, caches held,
free space) precisely so a partially-fitting batch stops instead of consuming caches it cannot use:

```
held before = 20
openMany(50) -> wanted=10 opened=10 held 20->10 space=200     per-action cap
space-limited-> wanted=10 opened=2  held 10->8  space=2       space bound, 8 left held
```

**Not done:** no UI calls it (unreachable in play), no rate limit between bulk actions, no per-item success list on partial failure,
and untested against a nearly-exhausted tier.

**Disclosed:** the probe replaced and restored ownedAugments, augmentCapacity, caches and cacheInstances.

**ORPHANED ACTIONS NOW HAVE BUTTONS — `S11-032` and `S11-035` VERIFIED (place 503).** Evidence
`evidence/v503-armory-action-buttons/EVIDENCE.md`.

Two features implemented in the previous three batches were unreachable in play. The armory now renders:

```
EXPAND +50 | OPEN 10 · Rare x14
```

with the bulk label reading the real held tier and count. `ArmoryService.state` exposes `caches`, a `bulkOpenCache` action wraps
`openMany`, and both buttons fire the existing actions.

Client-fired results:

```
expandResult = "false:already at max capacity"    (profile capacity is 400 from an earlier probe)
GF_CacheHeld = "Rare:13"                           (was 14)
GF_CacheBulk = "Rare wanted=10 opened=1 held=13 space=364"
```

`opened=1` with `space=364` is correct: the batch stopped because **no unowned Rare augments remained** — the nearly-exhausted-tier case
I had listed as untested, degrading cleanly. `source=unknown` is the documented fallback for caches granted before instance records
existed.

**Feedback gap remains:** both results go to workspace attributes, not to an on-screen message, so a player still learns nothing from
clicking; `EXPAND +50` shows no cost preview; and the held count does not refresh until the panel reopens.

**ARMORY NOW REPORTS ACTION RESULTS ON SCREEN (place 504).** Evidence `evidence/v504-armory-status-line/EVIDENCE.md`.

Place 503 made both actions reachable but left the caveat that results only went to workspace attributes. A status row now mirrors those
attributes via `GetAttributeChangedSignal`, so no new remote was needed:

```
before firing:  READY | READY | READY
after firing:   READY | READY | OPENED 0 CACHE(S)
```

`OPENED 0` is correct — every unowned Rare augment had already been granted by earlier probes, so the roll had nothing to give. Third
time that exhausted-tier path has degraded cleanly.

**Two limits:** a single shared line means messages overwrite (the expansion result appeared then was replaced by the bulk result), so the
expansion message was not captured in isolation; and three `READY` labels exist, suggesting the panel list is rebuilt without destroying
stale instances.

**Still missing:** `EXPAND +50` shows no cost preview (10 Cells + 3 Tech + 1000 Credits) before pressing.

**CACHE DISTRIBUTION CONFORMANCE AUDITED — sums conform, per-difficulty table does not (place 504, no code change).**
Evidence `evidence/v504-cache-distribution-conformance/EVIDENCE.md`.

`Configs/Caches` holds one weight table per **tier**, and difficulty names a tier (`Easy→Common, Normal→Rare, Hard→Epic,
Extreme→Legendary`):

| difficulty | config C/R/E/L | spec C/R/E/L | verdict |
|---|---|---|---|
| Easy | 82/16/1.9/0.1 | 80/18/2/0 | close, not equal |
| Normal | 48/43/8/1 | 65/29/5.5/0.5 | substantially off |
| Hard | 18/48/30/4 | 40/43/15/2 | substantially off |
| Extreme | 0/30/55/15 | 20/43/30/7 | **wrong shape** |

Three findings: **Extreme cannot drop a Common** (spec keeps 20%, config has 0); the drift is **progressive**, the signature of hand-tuned
tier weights standing in for an authored per-source table; and the **structure differs** — the spec models source→distribution (four
difficulties plus four enemy classes), the build models tier→distribution with all enemies sharing one table.

`S11-011` VERIFIED (all four tables sum to exactly 100; content counts 1/2/3/4 by tier). `S11-012`–`S11-015` → PARTIAL with the exact
numbers recorded. **Not retuned** — this changes loot pacing for every difficulty and belongs with the pending owner balance decisions
(boss HP, ability cooldowns, mission length, ADS ratio).

Ledger: UNKNOWN 625 → 620, PARTIAL 156 → 161, VERIFIED 34 → 35.

**ENEMY DROPS AUDITED — chance exists, per-class distributions and difficulty scaling do not (place 504, no code change).**
Evidence `evidence/v504-enemy-drop-distributions/EVIDENCE.md`.

`Caches` gives each tier a per-class **drop chance** (Common: infantry 0.01, heavy 0.04, commander 0.07) and then one rarity weight
table. So an enemy decides *whether* to drop by class, and the tier supplies rarity. The authored **per-class distributions** (infantry
85/14/1/0, elite 55/35/9/1, Walker 0/70/28/2, Veyr 0/40/50/10) do not exist — an infantryman and a commander produce identical rarity
odds once a cache drops.

**Two rules absent outright:**

- `S11-020` — *"multiply non-Common weights by Easy .65, Hard 1.35, Extreme 1.7 and renormalize"*. Tier weights are static; no code path
  scales or renormalises by difficulty. Enemy drops are therefore identical on Easy and Extreme.
- `S11-021` — first-mission Rare guarantee. A search for `firstMission`/`guarantee` finds only the blueprint-pity comment and the
  mission-cache guarantee, neither of which grants it.

Notable consequence: the Legendary tier has `Common = 0` and commander `enemyChance = 0`, so "boss never Common" holds by accident and the
highest-value enemy can currently drop **nothing**.

`S11-016`–`S11-019` → PARTIAL (system exists, distribution doesn't); `S11-020`, `S11-021` → ABSENT. Not retuned — same owner balance
queue (mission distributions, boss HP, cooldowns, mission length, ADS ratio).

Ledger: UNKNOWN 620 → 614, PARTIAL 160 → 164, ABSENT 0 → 2.

**`S11-005` VERIFIED; ENTIRE REROLL/DISMANTLE/FUSION CLUSTER ABSENT (place 504, no code change).** Evidence
`evidence/v504-item-lifecycle-absent/EVIDENCE.md`.

**No class lock — verified.** `ArmoryService` touches `selectedClass` in four places (a comment, the class list, the state payload, and
the setter at line 473). No lock check exists, and all four classes were applied in sequence on one profile at place 495.

**`S11-057`–`S11-067` are ABSENT — one missing subsystem, not eleven gaps:**

```
reroll     both hits are "preRolled" (substring)
dismantle  NO references
fuse       only inside "refused"
fusion     NO references
```

Reroll, dismantle and fusion have no entry point at all. Every row in the cluster needs per-instance augment records that can hold a
pending offer, a lock flag and a protected flag — the same instance model blocked on `S11-031`.

**Two consequences worth noting:** dismantle is the only sink that would make the now-verified 200-slot capacity meaningful (with no
dismantle, a full inventory can only be expanded, never cleaned); and because `Augments.rollTrait` already samples the authored range,
reroll would be cheap to add once instances exist — the blocker is identity, not the roll.

**Process note:** my first pass silently updated nothing because `f"S11-{n}"` produced `S11-57`, not `S11-057`. Caught by checking the
status counter rather than trusting the loop.

Ledger: UNKNOWN 613 → 602, ABSENT 2 → 13, VERIFIED 35 → 36.

**TRAIT MAGNITUDES ARE 3–8× THE AUTHORED BANDS (place 504, no code change).** Evidence `evidence/v504-trait-magnitude-inflation/EVIDENCE.md`.

Authored per-rarity bands (S11-042) against the config:

| stat | config Common | authored Common | ratio |
|---|---|---|---|
| recoil | 7–17 | 3–6 | ~2.5× |
| magazine | 20–32 | 3–6 | ~5× |
| weakpoint | 16–25 | 2–3 | **~8×** |
| reload (Rare) | 10–26 | 3–6 | ~3× |

Rarity ordering is not respected either: a **Common** `StabilityCompensator` rolls recoil `12–17`, overlapping the authored **Legendary**
band `10–17`, and a **Common** weakpoint augment `16–24` is roughly four times the authored Legendary ceiling `6–10`.

**This is the root cause of three earlier findings.** It explains the measured 47.85% cooldown reduction and +85% stacked blast radius
(two augments overshoot a 20–25% cap immediately at this scale); it explains why the clamp table I added at place 490 makes augments feel
far weaker than their displayed ranges; and it explains why `StabilityCompensator`'s rolled −0.08 disagrees with its declared 12–17% band.

**Recommendation:** rescale the bands **before** revisiting the clamps — the caps only make sense once the magnitudes are authorised. This
probably belongs first in the owner balance pass.

`S11-042` → PARTIAL. Not retuned: rescaling all 36 augments is economy-wide.

**TRAIT-BAND RESCALE IS BLOCKED ON FOUR UNMAPPED KEYS (place 504, no code change).** Evidence
`evidence/v504-trait-band-mapping/EVIDENCE.md`.

The obvious fix for the 3–8× inflation is to transcribe S11-042's bands. It **cannot be done cleanly**: the spec gives 12 bands, the config
uses 14 keys.

**Mapped (10):** `recoil`, `reloadSpeed`, `magazine`, `adsSpeed`, `healthDamage`, `weakPoint`, `shieldDamage`/`armorDamage`, `blastRadius`,
`cooldown`, and `swapSpeed` (via S11-051 *"universal swap reduction ranges same as reload"*).

**Unmapped (4):** `sentryAmmo` (the spec specifies sentry **HP**, not ammo — deliberately not treated as equivalent), `movingAccuracy`,
`adsRecovery`, `followUpSpeed`.

Rescaling only the 10 would leave those four at 3–8× the others, so a Common augment would be weak on recoil and overwhelming on follow-up
speed. **Mixed scales are worse than one wrong scale**, because rarity would then mean different things per stat.

Also found: *"range extension"* has an authored band but **no config key consumes it** — specified and unimplemented.

**Ask for the owner:** supply bands for those four keys, or authorise "match the nearest equivalent" for each, then rescale the catalog in
one pass — before any further clamp tuning.

`S11-051` → PARTIAL (`swapSpeed` runs 20–46% against the authored reload bands 2–4/3–6/5–9/7–12).

**RNG IS `math.random`; DOME DURATION IS 20s AGAINST A GUARANTEED 10s (place 504, no code change).** Evidence
`evidence/v504-rng-and-dome-duration/EVIDENCE.md`.

- `S11-030` — every cache outcome (rarity, category, archetype, trait value) and the enemy drop check resolve through
  `math.random()`, Luau's process PRNG. That is not "cryptographically appropriate unpredictable randomness"; `Random.new()` seeded per
  session would at least be distinct. The picker **is** injectable (`roll(tier, owned, rng)`), which is good for reproducible tests and is what
  let this audit reason about odds without gambling — but it does not make production unpredictable.
- `S11-043` — `DomeShield duration = 20` against the spec's *"remains guaranteed 10s"*. A 20s bubble on a 70s cooldown is 29% uptime where
  the authored intent is 14%. The other half of the clause (*"shield radius eligible"*) is unmet in the opposite direction: `blastRadius`
  acts only in `CombatService.detonate`, so the dome's 18-stud radius never scales with augments.

Both → PARTIAL with exact values. Duration belongs with the ability-cooldown drifts already recorded (OrbitalStrike, OrbitalLance,
ReflectiveBarrier, Sentry).

**CATALOG IS SINGLE-TRAIT: no tradeoff pairing, no signature variants (place 504, no code change).** Evidence
`evidence/v504-single-trait-catalog/EVIDENCE.md`.

All 36 archetypes carry exactly these fields: `applies, category, cost, displayName, effect, id, rarity, slot, trait`. **No `variant`,
`signature` or `tier` field exists**, and trait sign splits **30 positive / 6 negative** — one trait per archetype.

- `S11-044` → PARTIAL: negative tradeoff *data* exists (6 of 36), but several of those are **benefits expressed as negative numbers** (the
  recoil group), not tradeoffs. No augment pairs a positive entry with a negative one, and rarity does not govern the count.
- `S11-045`, `S11-046` → ABSENT: with one trait slot and no variant field there is nowhere to express *"strong signature variants as 1.25×
  ordinary defining range"*. All 36 are ordinary by construction.

**Three separate spec features collapse into one absence** — multi-trait generation, tradeoff pairing and signature variants all need an
augment that can hold N traits, which is the same instance model blocking `S11-031` and the 11-row reroll/dismantle/fusion cluster.

The fair characterisation: the catalog is **not broken, it is simpler than specified** — 36 working single-trait augments rather than 36
multi-trait items with variants. Playable; roughly a third of the authored depth.

Ledger: UNKNOWN 598 → 595, PARTIAL 168 → 169, ABSENT 13 → 15.

**NO CACHE-ODDS DISPLAY EXISTS (place 504, no code change).** Evidence `evidence/v504-no-odds-display/EVIDENCE.md`.

Keyword scan of every `StarterPlayer` script for odds/chance/probability returned **81 hits — all of them `string.format` calls**. Excluding
format lines leaves **zero** genuine references. So `S11-027` (show per-draw and whole-cache odds), `S11-028` (per-cache `1-(1-p)^n` maths)
and `S11-029` (do not imply guarantees) are all ABSENT — `S11-029` only vacuously, since with nothing shown nothing can be overstated.

**Why it matters:** the underlying numbers are honest (`Caches.weights` verified summing to 100 and consumed by `rollRarity`), but the game
tells the player nothing. In a cache-driven economy a player cannot distinguish Common from Legendary except by opening dozens. Server-side
observability exists (`GF_CacheOpened`/`Held`/`Bulk`/`Blocked`) but those are developer attributes, not disclosure.

**This is one of the few remaining rows that is pure presentation on existing data** — normalise weights to percentages, add the n-draw
rate, no new state or persistence. Cheapest meaningful player-facing win left on this ledger.

Ledger: UNKNOWN 595 → 592, ABSENT 15 → 18.

**CACHE ODDS DISCLOSED — `S11-027` and `S11-028` VERIFIED (place 506).** Evidence `evidence/v506-cache-odds-disclosed/EVIDENCE.md`.

`CacheService.oddsFor(tierId)` computes from the **same weight table `rollRarity` consumes**: `perDraw = w/total*100` and
`atLeastOne = (1-(1-p)^draws)*100` with `draws = tier.augments`. `ArmoryService.state.cacheOdds` supplies it for the most-held tier and the
armory renders a dedicated row:

```
Rare x2  ·  Common 48.0% · Rare 43.0% · Epic 8.0% · Legendary 1.0%  ·  Legendary in this cache 2.0%
```

Rare weights are 48/43/8/1 so the per-draw shares match exactly, and `1-(0.99)² = 1.99%` renders as 2.0%. **The numbers shown are the numbers
used** — derived live, not hardcoded.

**My measurement error, recorded:** the first verification said `ODDS=0` and I nearly filed the feature broken. The scan looked for the
substring `"ODDS"`, which only appears in the empty state (`"ODDS  no cache held"`); the live text begins `"Rare x2 …"`. Third false negative
this session from a probe encoding an assumption about output *format* instead of the property under test.

**Still open:** only the most-held tier is disclosed; enemy drop chances (0.01/0.04/0.07) are not shown; and the disclosed weights are the
config ones, which the earlier audit showed disagree with the authored table — so the disclosure is honest about an off-spec distribution.

`S11-029` → PARTIAL (this surface names a probability, but shop/pity/bundle copy is unaudited).

Ledger: UNKNOWN 592 → 590, VERIFIED 36 → 38, ABSENT 18 → 17.

**ODDS DISCLOSURE COMPLETED — every held tier + enemy drop chances (place 507).** Evidence `evidence/v507-odds-all-tiers-and-drops/EVIDENCE.md`.

Closing both gaps named at place 506: `oddsFor` now also returns `dropChance` (same `tier.enemyChance` table `onEnemyKilled` rolls
against), `state.cacheOdds` returns a **list** of every held tier sorted most-held first, and the UI renders all of them plus a drop line.

```
Rare x2 held 13  ·  Common 48.0% · Rare 43.0% · Epic 8.0% · Legendary 1.0%  ·  Leg 2.0%
  ||  Common x1 held 1  ·  Common 82.0% · Rare 16.0% · Epic 1.9% · Legendary 0.1%  ·  Leg 0.1%
DROP Rare  ·  infantry 1% · heavy 5% · commander 9%
```

Every figure checked against config by hand: weights 48/43/8/1 and 82/16/1.9/0.1 match; `1-(0.99)²=1.99%` and `1-(0.999)¹=0.1%` match; Rare
`enemyChance 0.01/0.05/0.09` matches.

**Honest limitation:** the whole-cache figure is `1-(1-p)^n` **with replacement**, not the exact conditional probability given what the player
already owns — so it is not literally "true whole-cache odds" in the strict sense. Standard reading, but an approximation. The disclosed
weights also remain the config's, which disagree with the authored table.

**Method note:** verification scanned for `"Leg "` and `"DROP "` — substrings only the real display produces. After three false negatives from
scanning placeholder text like `"ODDS"`, matching on content unique to live output is now the default.

**WEAPON STATS CONFORM EXCEPT RELOAD, WHICH IS UNIFORMLY LONGER (place 507, no code change).** Evidence
`evidence/v507-weapon-reload-drift/EVIDENCE.md`.

**Two misreadings caught before reporting them:** the authored table's last column is **reload seconds**, not unlock rank (AR-01 shows `2` but
is rank 1, and reloads in 2.1 s) — reading it as rank would have produced five false rank-drift findings. And GL-22 is **not** drifted: spec
`110 | 50 | 4/16` matches config exactly; the `40 | 1 | 1/8 | 2` row belongs to a different launcher.

**Conforms exactly:** AR-01 18/600/28-168, SMG-03 13/850/36-216, LMG-12 17/660/75-225, SG-04 96=8×12/72/6-42, MR-07 51/150/12-72,
GL-22 110/50/4-16, P-01 22/300/12-72.

**Drifts:** every reload is longer, never shorter — AR-01 2.1 vs 2, MR-07 2.4 vs 2, SMG-03 1.7 vs 1, LMG-12 3.7 vs 3, SG-04 2.8 vs 2. A
uniform upward bias is a tuning choice, not a transcription slip. Sustained DPS is therefore below authored for every weapon, worst for SMG-03
and SG-04 — the close-quarters throughput classes, where SMG-03's authored 1 s reload is the fastest in the game.

Not changed: reload is core feel and interacts with the verified `reloadSpeed` augment stat. Owner queue.

**THE SHOTGUN FIRES ONE RAY, NOT EIGHT PELLETS (place 507, no code change).** Evidence `evidence/v507-no-pellets/EVIDENCE.md`.

A scan for **`pellet`** across `ServerScriptService` and `StarterPlayer` returns **zero references**. `SG-04 damage = 96` is exactly `8 × 12`, so
the *data* was transcribed correctly — but `CombatService.fire` resolves one ray and applies 96 as a single hit.

| authored | build |
|---|---|
| 8 rays, 12 each | 1 ray, 96 |
| graded damage at range | all-or-nothing |
| per-pellet falloff | one falloff on the total |
| shotgun pattern | single-ray spread |

Affects `S04-022` (*"shotgun per pellet"*) and `S04-WPN-SG04` (*"8 pellets; D: 12/pellet"*).

**Why this was easy to miss:** one batch ago I recorded SG-04 as `96 = 8 × 12 ✓` — correct about the arithmetic, wrong about the mechanic. Same
class of error as asserting a dead constant: the number agrees, the behaviour does not.

Not built: pellets change the combat model (8 raycasts per pull, per-pellet falloff, damage accumulation) and alter every shotgun TTK
measurement, so it needs a decision about whether partial hits stack.

**SG-04 NOW FIRES EIGHT PELLETS (place 508).** Evidence `evidence/v508-shotgun-pellets/EVIDENCE.md`.

The spec settled the stacking question by arithmetic: authored `12/pellet × 8 = 96` and the config already carried `damage = 96`, so all
pellet eight must stack on one target at point blank. `damagePerPellet = damage / pellets` reproduces the authored total exactly while making
each pellet independent.

`Configs/Weapons`: `SG04.pellets = 8`. `CombatService.fire`: the raycast-and-damage section is now a loop — pellet 1 uses the spread direction,
pellets 2..N scatter around it using the weapon's own `adsSpread`/`spreadBase`, each resolving its own enemy/structure and falloff. Non-pellet
weapons have `pellets = 1`, so their path is behaviourally identical.

```
SG04 pellets field=8  damage=96
pellet markers observed=8   first=8/8 dmgEach=12.00   last=8/8 dmgEach=12.00
```

Eight independent rays per trigger pull at exactly 12.00 each.

**Mistake caught in-batch:** the splice inserted five lines with a literal `[[` prefix, leaving `CombatService` unparseable
(`got malformed string` at line 424). `loadstring` caught it before anything ran; prefixes stripped and recompiled. And the first verification
reported `observed=0` because my marker lived inside the `enemyModel` branch — instrumentation, not the loop.

**Not verified:** no enemy was in front of the muzzle, so 8 rays *emitted* is proven but 96 *received* is not; per-pellet weak-point and
penetration interaction untested. **Shotgun TTK evidence from earlier in this project is now stale** — it was measured when one ray dealt 96.

**PELLETS VERIFIED ON A REAL TARGET — 196.8 is headshots, not a bug (place 508, verification only).**
Evidence `evidence/v508-pellets-on-target/EVIDENCE.md`.

```
12 studs: shield 60->0  health 210->73  totalDelta=196.8
70 studs: shield 60->60 health 210->210 totalDelta=0.0
```

`weakMultiplier` returns **2 for Head**, so a headshot pellet does `12×2=24` and eight all-head pellets is 192 — 196.8 is that plus routing.
`damageEnemy` was read end-to-end: shield absorbs, remainder hits health, one call per pellet, **no double application**. So the total is correct
for a point-blank pattern that scattered several pellets onto the head.

**Consequence for the owner:** the authored `12/pellet` and config `96` describe *body* damage. With the existing 2× weak-point rule, a full-head
pellet pattern now reaches ~192, so this weapon's effective ceiling roughly doubled when pellets went in.

**Unresolved:** at 70 studs the same shot did **0.0**. Scatter plausibly misses, but pellet 1 uses the aimed direction and should connect — either
the probe's direct `root.CFrame` teleport did not take effect or the aim used a stale position. Range behaviour is therefore **not verified either
way**, and the exact body-hit 96 remains unconfirmed because every landed test included headshots.

**Useful discovery:** `ActiveActors` enemies have **no Humanoid** — health/shield/armor are model attributes (`Health`, `Shield`, `ArmorFactor`,
`Dead`). Two probes failed before that was noticed.

**THE 70-STUD MYSTERY WAS A BUG IN MY OWN PELLET CODE (place 510).** Evidence `evidence/v510-pellet-scatter-stance-bug/EVIDENCE.md`.

Two causes, both real:

1. **Probe artifact:** the first shot of a range sweep used a stale root position (`dist=750.7`), because aim was computed immediately after
   writing `root.CFrame`. Waiting for physics and recomputing fixed the measurement.
2. **Place-508 bug:** pellet scatter used `tonumber(weapon.adsSpread) or ...` **even when hip-firing** — 4.5° instead of SG-04's 0.15° base, a 30×
   wider cone, so most pellets sailed past a torso beyond ~30 studs. Fixed by hoisting `isAiming` and applying the same stance rule as the primary
   spread.

After the fix:

```
12 studs: delta=96.0  (h 210->174, sh 60->0)   dist=6.4     <- authored 8 x 12, CONFIRMED
40 studs: delta=22.1                            dist=37.7
70 studs: delta=0.0                             dist=69.0
```

**`96.0` confirms the authored figure for the first time.** It also retro-explains the previous batch's 196.8: that reading was a headshot pattern
through the 4.5° cone, so the explanation was right about that measurement but the measurement itself was distorted by my bug.

**Still unexplained:** mid-range damage is partial and inconsistent — only ~2 of 8 pellets land at 38 studs although a 0.15° cone there is under 0.1
studs wide. Something in the scatter maths remains wrong, and I did not guess at it.

**NO SCATTER BUG — SG-04's `spreadBase` IS 3.2°, NOT 0.15° (place 510).** Evidence `evidence/v510-spreadbase-3-2-no-bug/EVIDENCE.md`.

Retracting my own claim from the previous batch. I wrote that a 0.15° cone at 38 studs should land all eight pellets and therefore "something in the
scatter maths is still wrong". Instrumenting the value at fire time:

```
aiming=false  angle=3.200  ads=4.5  base=3.2
```

**The hip base is 3.2°**, so at 38 studs only 4–5 of 8 pellets land a ~2-stud torso (measured 56.9 and 22.1 across runs, varying with random
jitter). Mid-range behaviour is **correct**. I had asserted a config value I never read for this weapon.

The stance bug fixed at 510 was real but **an order of magnitude less severe than I claimed** — 4.5° instead of 3.2°, not 4.5° instead of 0.15°.

**Fourth time this session** a wrong premise produced a wrong conclusion from correct measurements (`e.stats` vs `e.effect`; `#e.trait`; searching
`"ODDS"`; recalling `spreadBase 0.15`). Every fix was to print the value instead of recalling it — that belongs in the method, not the epilogue.

**State:** point-blank 96.0 confirmed against the authored 8 × 12; mid-range explained by configuration; reload 2.8 vs authored 2 is the one open
SG-04 issue.

**CATEGORY COMPATIBILITY IS NEVER ENFORCED (place 510, no code change).** Evidence `evidence/v510-category-compat-unenforced/EVIDENCE.md`.

Every augment carries `applies` ∈ {`Ability` (4), `Category` (28), `Universal` (4)}. `AugmentService` has **zero** checks involving `applies` or
`incompatible`; the field's only consumer is cosmetic (`description = def.applies or ""` in ArmoryService), and `CheckRunner` only validates it is a
legal string.

Verified by repro, not inference:

```
aug=Choke  applies=Category  cat=Shotgun
weapon=AR01  cat=Rifle
equipAccepted=true   why=nil   effectsInForce=1
```

A shotgun weak-point augment equipped onto an assault rifle **and its effect took force**. 28 of 36 archetypes are Category augments, so the majority
behave as Universal.

**Why it matters:** weapon identity collapses; and it is the mirror of the placebo-augment problem — augments doing something they were explicitly
not meant to. Worse, the UI *displays* the restriction while the server accepts it anywhere.

**Not implemented deliberately:** enforcing it removes power from every existing mismatched loadout (including the test profile, which now carries a
shotgun `Choke` on `AR01` from this probe). Belongs with the balance pass.

`S11-052` → PARTIAL.

**AUGMENT COMPATIBILITY ENFORCED — `S11-052` VERIFIED (place 512).** Evidence `evidence/v512-augment-compatibility-enforced/EVIDENCE.md`.

`applies` (Ability 4 / Category 28 / Universal 4) was decorative: it only fed the armory description, while the server accepted any augment in any
socket. Added the check at the single equip choke point in `AugmentService.equipAugment`:

```
Choke on AR01 slot1  -> false ("fits Shotgun weapons only")
Choke on SG04 slot1  -> true  (nil)
StabilityCompensator on AR01 slot2 -> true (nil)   (Universal unaffected)
```

The refusal names the required category rather than failing generically.

**Why done without an owner ruling:** it removes power from mismatched loadouts, which normally means balance — but the alternative is a UI that
promises a restriction the server ignores. That is a correctness bug with a balance side effect, not the reverse, and `Universal` still means
universal.

**Consequences to expect:** the test profile's `Choke` on `AR01` is now invalid (left in place, not silently stripped); saved loadouts holding a
mismatched augment keep its effect until unequipped because nothing validates slots on load; and the armory still prints the raw `"Category"` string
instead of naming the category.

**SAVED LOADOUTS REPAIRED ON JOIN (place 514).** Evidence `evidence/v514-loadout-sanitised-on-join/EVIDENCE.md`.

Place 512 enforced compatibility at equip time, but a loadout saved before that kept its effect until unequipped. `AugmentService.sanitiseLoadout`
now clears mismatched slots, called from `ArmoryService.PlayerAdded` before serving the loadout.

Three placement decisions: it lives in `AugmentService` because `ProfileService` would create a circular require (AugmentService already requires it);
slots are one table per loadout so the equipped **primary** is what a slot is judged against; and it only removes, never reassigns.

```
before: 1=Choke,2=StabilityCompensator  (primary=SMG03)
cleared=1   after: 2=StabilityCompensator   secondRunCleared=0
```

**Not verified:** the `PlayerAdded` path itself — the probe called the sanitiser directly, so a real rejoin is untested. Removal is also silent to the
player (only `GF_AugmentSanitised*` attributes record it), `loadout.abilityAugment` is not validated, and a missing primary weapon in config would
clear every Category augment.

**JOIN REPAIR VERIFIED ACROSS A REAL RESTART (place 514, no code change).** Evidence `evidence/v514-join-repair-restart-verified/EVIDENCE.md`.

Closing the gap declared at place 514 ("the `PlayerAdded` path itself was not exercised"). Three steps, the middle one easy to forget:

1. Plant `Choke` (shotgun-only) into slot 1 with `primary = SMG03`, then `ProfileService.save` → `save=true`, `mode=datastore`.
2. **Remove the planting probe before restarting** — left in place it would have re-planted the mismatch and made a passing test meaningless.
3. Restart Play and read the observable from a fresh server.

```
sanitisedCount  = 1
sanitisedDetail = "Choke from SMG03"
```

A new server loaded the persisted bad loadout, the `PlayerAdded` hook ran the repair, and the profile was dirty-marked so the repair persists. This is
the first end-to-end test in the project exercising **DataStore round-trip + join hook together** rather than either half alone.

**Still open on this row:** the player is not told anything was removed; `loadout.abilityAugment` is not validated; and nothing repairs a mismatch made
while the player stays connected.

**Self-correction:** my first draft of this evidence claimed a new `GF_AugmentSanitisedDetail` attribute had been added. It had not — the existing
attributes were sufficient. Corrected before committing.

**ABILITY SOCKET NOW VALIDATED TOO (place 515).** Evidence `evidence/v515-ability-socket-validated/EVIDENCE.md`.

Place 514's sanitiser repaired weapon slots only, so a Category augment parked in `loadout.abilityAugment` survived every join. Added four lines to
`sanitiseLoadout`; cleared items also count toward `GF_AugmentSanitisedCount`, so a double repair reports 2 rather than 1.

```
planted abilityAugment=Choke (Category)  cleared=1  after=nil  detail="Choke from ability socket"
valid ExtendedSentryMagazine kept=true   cleared=0   (applies = Ability)
```

The Category augment was discarded and the valid Ability augment survived, so the check discriminates rather than emptying the socket.

**Only `Category` is refused** — `Ability` belongs there and `Universal` is permitted to fit anything; refusing Universal would invent a restriction
the data does not express.

**Still open:** the player is not told anything was removed (now on both sockets); Universal on the ability socket may be under-enforced if the design
intends it weapon-only; mismatches made while connected are not repaired; and this branch's `PlayerAdded` path was not re-run across a restart (the
weapon-slot equivalent was, at place 514).

**NO REQUISITION SYSTEM — AND THE SPEC'S CATALOG WEAPONS DON'T EXIST (place 515, no code change).** Evidence
`evidence/v515-no-requisition-system/EVIDENCE.md`.

A search for `requisition` across server, replicated and client code returns **one** module — `Configs.Armor` — where it is merely an armour tier
label (`TROPHY` rank 12, `BLACKSTAR` rank 16). No requisition config module exists, and there is no catalog, tier structure, spend threshold,
premium unlock or progress display.

**Worse:** the spec's catalog contents name `GF-02`, `GF-05` and `GF-06`. The entire weapon set is `AR01, GL22, LMG12, MR07, P01, RL09, SG04, SMG03` —
**no `GF-*` weapon exists at all**. So `S12-011` and `S12-013` cannot be implemented as written; one number does line up (`GL-22` costs exactly
1200, the premium tier1 price).

Ten rows moved: `COUNT-REQ`, `COUNT-REQ-TIERS` and `S12-003`–`S12-008` → ABSENT; `S12-011` and `S12-013` → PARTIAL with the missing-weapon detail.

**This is a scope question, not a bug.** The requisition catalog is a store feature with tiered spend, premium access and a contents preview — a
build-vs-spec decision for the owner, not something to infer from one armour string.

Ledger: UNKNOWN 591 → 581, ABSENT 15 → 23, PARTIAL 170 → 172.

**CORRECTION: `GF-*` ARE ARMOUR KITS, NOT WEAPONS (place 515).** Appended to `evidence/v515-no-requisition-system/EVIDENCE.md`.

I reported that the spec's requisition contents named weapons that don't exist. **Wrong** — the `GF-` prefix misled me. `GF-01`–`GF-06` are armour:

```
STANDARD "GF Standard Kit" r1 free | RECON "GF-02 Recon Weave" r3 500 | SIEGE "GF-03 Siege Plate" r5 850
VANGUARD "GF-04 Vanguard Seal" r8 1200 | TROPHY r12 2200 | BLACKSTAR r16 3200
```

`GF-02`, `GF-03` and `GF-04` **exist and match the spec's ranks and costs exactly**. Genuinely missing: **`GF-05` (Ash Sentinel) and `GF-06` (Frost
Warden)** — the armour list ends at four numbered kits.

Requisition conclusion unchanged (no catalog, tiers, thresholds or premium unlock), but `S12-011` is PARTIAL for the *free* condition rather than for a
missing item, and `S12-013` is missing only `GF-05`/`GF-06`.

**Fifth time this session a prefix-shaped assumption produced a false finding.** The rule: when a requirement names an id, resolve it in the config
**before** concluding it is absent.

**PAUSED AT OWNER REQUEST (continuation 81).** Evidence `evidence/v515-buy-no-double-charge/EVIDENCE.md`. Place **515** is the last saved version;
this batch made no source changes and did not save.

`S12-010` → PARTIAL. Repeated purchases of owned items **do not double-charge** (three calls with SG04 ×2 and AR01 left credits unchanged at 10000),
but a **first purchase was not exercised** because the account already owned both items, so every call took the already-owned path. Also observed:
`ArmoryService.buy` returns `nil` for both success and refusal with no reason string — unlike `equipAugment`'s `(ok, why)`.

**Resume here:** buy an unowned item (Sentry ability, 900) and confirm the exact catalogue price is deducted and ownership added, then re-buy to
confirm refusal.

Test profile left with `credits = 10000`.

**FIRST PURCHASE CHARGES EXACTLY; `S12-010` VERIFIED (place 515).** Evidence `evidence/v515-first-purchase-charges-exactly/EVIDENCE.md`.

The pause point was that every priced item was already owned, so only the "already owned" branch was reachable. Re-listing confirmed it: `Sentry 900`,
`OrbitalStrike 1800`, all weapons owned; the only unowned item was `ReflectiveBarrier` at **cost 0**.

Made testable by un-owning `SG04` (500) and re-buying:

```
un-owned SG04; credits=5000
FIRST  buy  credits 5000 -> 4500   delta=500   owned=true
SECOND buy  credits 4500 -> 4500   owned=true
```

Exact catalogue price deducted, ownership granted, second purchase charged nothing — so both halves now hold **on the same item**, and the earlier
no-double-charge finding is confirmed rather than assumed.

**Separate API-quality finding:** `ArmoryService.buy` returns `nil` for **both** success and refusal with no reason string, unlike `equipAugment`'s
`(ok, why)`. The UI must be inferring success from profile state.

**Limits:** weapons only — `buyAbility`/`buyGrenade`/`buyArmor` were not charged-path tested (`buyAbility` granted a free item and returned nothing);
insufficient-credit refusal untested; ownership was manipulated directly rather than through a supported flow. Profile left at `credits = 4500`,
`SG04` owned. All probe scripts removed.

**CORRECTION: ARMORY REFUSALS ARE REPORTED, WITH PRECISE REASONS (place 515).** Evidence `evidence/v515-armory-refusals-reported/EVIDENCE.md`.

I recorded that `buy` returned no reason and that the UI "must be inferring success from profile state". **Wrong on the substance.** `buy` returns
`nil`, but every failure branch calls:

```lua
fail(player, reason)  ->  workspace:SetAttribute("GF_ArmoryRejected", reason)
                          push(player, { ok = false, reason = reason })
```

Measured through that attribute:

```
SG04 with 10 credits  -> "needs 500 credits"
AR01 (owned)          -> "already owned"
NOPE (unknown id)     -> "unknown weapon"
```

Each names the exact shortfall rather than a generic refusal. I had read `buy`'s body, seen `return fail(...)` with no value, and concluded no reason was
reported — without reading `fail`. **Sixth instance of reasoning from an unread name.**

**Still untested:** the rank gate, because this profile is rank **15** while the highest weapon requirement is rank **7**; `buyAbility`/`buyGrenade`/
`buyArmor` refusals; and the success path returns no value by design (`ok=true` is pushed).

**The "silent refusal" defect I recorded does not exist.**

**RANK GATES ENFORCED ON ALL FOUR PURCHASE PATHS (place 515, no source change).** Evidence `evidence/v515-rank-gates-enforced/EVIDENCE.md`.

The profile is rank **15** while the highest requirement is rank 7 (weapons) / 12 (armour), so no refusal was reachable. Lowering `profile.rank` to 1
and restoring it afterwards made all four testable.

**Ordering detail that mattered:** ownership is checked *before* rank, so an owned item refuses as `"already owned"` regardless of rank — `Sentry` and
`TROPHY` had to be un-owned before their gates could be reached.

```
weapon  MR07   (r4)  at rank 1 -> "requires rank 4"
ability Sentry (r4)  at rank 1 -> "requires rank 4"
armour  TROPHY (r12) at rank 1 -> "requires rank 12"
grenade EMP    (r4)  at rank 1 -> "requires rank 4"   owned=false
grenade Frag   (r1)  at rank 1 -> no rejection (control: permitted)
```

A refused purchase grants nothing, and the control case shows the gate discriminates rather than blocking everything.

`S12-012` → PARTIAL (first clause verified; the requisition half has nothing to open). `S05-013`/`S05-014` unlock data confirmed live
(`Sentry rank4/900`, `OrbitalStrike rank8/1800`).

**Not covered:** rank was manipulated rather than earned, so the gate logic is proven, not the progression feeding it; and how locked items are
*presented* in the armory was not checked.

Ledger: UNKNOWN 580 → 579, PARTIAL 172 → 173.

**TUTORIAL REWARD IS 200/400, SPEC SAYS 350/410 PLUS A CACHE AND STARTER ITEMS (place 515, no code change).** Evidence
`evidence/v515-tutorial-reward-drift/EVIDENCE.md`.

`TutorialService.finish` sets `tutorialCompleted`, marks dirty, and calls `ProfileService.award(player, 200, 400)` → **200 credits, 400 XP**.

| | spec (`S10-009`) | build |
|---|---|---|
| Credits | 350 | **200** |
| XP | 410 | **400** |
| Common cache | 1 | none |
| Starter items | yes | none |

**The completion flag has no consumer.** A search for `tutorialCompleted`/`Tutorial_Complete` returns 10 hits, all writers or UI displays — nothing
gates a difficulty, grants a cache or offers a weapon pick. So `S01-027`'s three outcomes are all unimplemented (and "unlocks Easy/Normal" may be
vacuous if those are never locked).

Free starter items **do** exist as priced-zero catalogue entries (`AR01`, `P01`, `Airstrike`, `DomeShield`); what is missing is the tutorial's
*"first-time choose AR/SMG/LMG free"* pick, which is how a player would get `SMG-03` (600) or `LMG-12` (1400) for nothing.

**No monetisation exists at all** — zero references to `MarketplaceService`, `DeveloperProduct`, `GamePass`, `PromptPurchase` or `robux`. So
`S12-016`/`S12-017` are VERIFIED **vacuously** (nothing can be bought), and the spec's premium requisition cannot exist as written.

`S01-027`, `S10-009`, `S12-009` → PARTIAL. Ledger: UNKNOWN 579 → 574, PARTIAL 173 → 176, VERIFIED 40 → 42.

**Method note:** my first pass searched `TutorialService` for `grant|credits|reward|ownedWeapons` and got zero, reading as "grants nothing". The award
is spelled `ProfileService.award(...)` — **wrong vocabulary produced a false negative for the seventh time this session.**

**TUTORIAL AWARD CORRECTED TO 350/410 + 1 COMMON CACHE (place 516).** Evidence `evidence/v516-tutorial-award-corrected/EVIDENCE.md`.

`TutorialService.finish` now calls `ProfileService.award(player, 350, 410)` and grants one Common cache, replacing `award(200, 400)` with no cache. This
is spec conformance (`S10-009` names the figures explicitly), not balance tuning.

A test hook `TutorialService.finishForTest(player)` was added on the same pattern as the existing `resetForTest` — `finish` is a local function, so the
completion path was otherwise unreachable without playing the whole tutorial, which is why the reward had only ever been code-read.

```
credits 1000 -> 1350 (+350)   xp 0 -> 410 (+410)   Common cache 0 -> 1   completed=true
```

**Deliberately not implemented:** the fourth component — *"first-time choose AR/SMG/LMG free"* — needs a choice UI and grant flow, so `SMG-03` (600)
and `LMG-12` (1400) stay unaffordable for a new player who did not pick them. And `tutorialCompleted` remains unread, so "unlocks Easy/Normal" has no
mechanism; whether those difficulties should even be locked is a design call I did not invent.

**Verification limit:** measured via `finishForTest`, so everything downstream of `finish` is proven, but the step-tracking that decides *when* `finish`
runs is unexercised. The hook also ships in the place — harmless, but test-support surface that should be removed or gated before private beta.

`S10-009` → PARTIAL (3 of 4 components verified), `S01-027` → PARTIAL (first cache now granted).

**STARTER PICK IMPLEMENTED AND VERIFIED END TO END — `S10-009` VERIFIED (place 518).**
Evidence `evidence/v518-starter-pick-implemented/EVIDENCE.md`.

Closes the fourth reward component (*"first-time choose AR/SMG/LMG free"*), which was why `S01-027`'s starter-equipment half was unmet.

**Server:** `TutorialService.claimStarter` validates in order — profile → `tutorialCompleted` → `starterClaimed` → id ∈ {AR01, SMG03, LMG12} — then
grants ownership, sets the flag, marks dirty and publishes `GF_StarterClaimState`. **Profile:** `starterClaimed = false` added to defaults.
**Transport:** new `ClaimStarter` RemoteEvent wired in `TutorialService.start()`. **UI:** `TutorialUI` renders a `STARTER PICK` frame with AR/SMG/LMG
buttons once complete and unclaimed.

```
before completion:  ok=false "tutorial not complete"    claim SMG03: ok=true owned=true claimed=true
second claim:       ok=false "starter already claimed"  illegal MR07: ok=false "not a starter option"
UI: StarterPick present | label=STARTER PICK | buttons=AR,SMG,LMG | visible=true
end-to-end: LMG12 owned=true claimed=true state=claimed:LMG12
```

**Two bugs fixed inside the batch:** the frame was parented to `script.Parent` (resolving to StarterPlayerScripts, not a UI container) so it never
appeared; and a frame under `gui` would have been hidden by the 4-second `gui.Enabled = false` timer after completion. **One measurement error:** the
first end-to-end reader's `task.wait(11)` expired before the client fired, reporting `owned=false` when the grant had simply not happened yet.

**Limits:** the physical `Activated` click was not exercised (the client fired the same remote), `starterClaimed` migration from an older save was not
tested, `TutorialService.finishForTest` still ships, and the pick shows whenever `Tutorial_Complete` is true with no claim — not a designed rule.

`S10-009` → VERIFIED (4/4). `S01-027` → PARTIAL (2 of 3; only Easy/Normal gating remains, a design call).

Ledger: VERIFIED 42 → 43, PARTIAL 176 → 175.

**DIFFICULTY IS COSMETIC: NO LETHALITY SCALING, REWARDS INVERTED (place 518, no code change).**
Evidence `evidence/v518-difficulty-not-scaling/EVIDENCE.md`.

`S06-032` asks for `(HP, damage, attack cadence, reinforcement pressure)` = `(.70,.60,.85,.65) / (1,1,1,1) / (1.50,1.30,1.10,1.25) / (2,1.60,1.20,1.50)`.
**None of the four fields exists** in `Configs.Difficulties`, and `EnemyService`/`CombatService` have **zero** difficulty references — the only consumers
are `StationService`/`StationWarTable` for tickets, payout and spawn budget. So Hard/Extreme are not harder to *fight*: budget rises (8/12/16/18) and
payout rises, nothing else. `S06-032` → ABSENT.

`S06-009` — reaction delay is a per-enemy-type constant (`def.chargeTime or def.telegraph or 0.55`), identical on every difficulty;
`Difficulties.reactionMultiplier` (1.4/1/0.8/0.65) is **read by nothing** (another dead field). → PARTIAL.

`S10-020` — measured drifts:

| | spec credits | config `rewardMultiplier` |
|---|---|---|
| Easy | 0.8 | 1 |
| Normal | 1 | 1.7 |
| Hard | 1.35 | 2.6 |
| Extreme | 1.65 | **3.5** |

and tickets run **inverted**: solo Easy 5 / Normal 4 / Hard 2 / Extreme 1 against the specified 1 / 1.25 / 1.75 / 2.5 — paid most for the easiest content.

`S06-033` (cadence must not shorten heavy/marksman warning below 0.9s) is satisfied **vacuously** — cadence does not vary at all.

**Misread caught before writing:** the alphabetical config dump put `reactionMultiplier=1.4 rewardMultiplier=1` on Easy; I nearly recorded Easy paying
1.4×. It pays 1×.

Ledger: UNKNOWN 574 → 573, ABSENT 23 → 24.

**CORRECTION: MY TICKET AND CREDITS CLAIMS WERE WRONG (place 518).** Amendment appended to
`evidence/v518-difficulty-not-scaling/EVIDENCE.md`.

**Retracted:** *"tickets run inverted against spec 1/1.25/1.75/2.5"*. Those figures are **XP/mastery multipliers** (`S10-020`), not tickets — and the spec
specifies **no ticket counts at all** (one unrelated "ticket" hit, about TeleportService reserved servers). I compared a ticket curve against the XP column.

**Retracted:** *"credits multiplier 1/1.7/2.6/3.5 against a specified 0.8/1/1.35/1.65"*. Wrong target. The multipliers that compute rewards are
`RewardLedgerService.CREDIT_MULT` / `XP_MULT` and they **match the spec exactly**:

```lua
CREDIT_MULT = { Easy = 0.8, Normal = 1, Hard = 1.35, Extreme = 1.65 }
XP_MULT     = { Easy = 1,   Normal = 1.25, Hard = 1.75, Extreme = 2.5 }
```

`Difficulties.rewardMultiplier` (1/1.7/2.6/3.5) is a **different field** read only by `StationWarTable` — the pre-deploy **reward estimate**.

**The corrected, narrower findings:**
1. Reward maths conforms (`S10-019` × `S10-020` → Veyr kill on Extreme = 165cr / 625xp).
2. The **war-table estimate is wrong** — it previews from `rewardMultiplier` instead of `CREDIT_MULT`, so Easy shows 1× while paying 0.8×.
3. **Settlement uses a third path** — `RewardsService.compute` reads `Economy.PayoutByDifficulty` (Easy 250cr/330xp … Extreme 950cr/1350xp), which
   `RewardLedgerService` documents as transitional. `S10-020` → PARTIAL.

Also recorded: `Configs/Difficulties` line 30 cites *"spec: Easy 3+2P…"* for tickets — **that text is not in the spec**, so a code comment asserts a
conformance basis that does not exist.

**Survives unchanged:** `S06-032` ABSENT (no HP/damage/cadence/pressure scaling anywhere) — the load-bearing finding; `S06-009` PARTIAL; `S06-033`
vacuously satisfied.

**Pattern:** eighth wrong conclusion this session, third from comparing a spec number to the **wrong field** rather than a missing one. The discipline:
find the field that *feeds the behaviour*, not the one whose name resembles it.

**DIFFICULTY COMBAT SCALING IMPLEMENTED; HP VERIFIED, DAMAGE UNPROVEN LIVE (place 522).**
Evidence `evidence/v522-difficulty-combat-scaling/EVIDENCE.md`.

`Configs.Difficulties.modifiersFor` now carries the authored `S06-032` table, and `EnemyService.spawn` applies it from the live `GF_OperationDifficulty`:
health × hp, plus `DamageMultiplier` / `CadenceRate` attributes consumed by the attack interval (divided by rate) and player damage (× multiplier).
Applied **at spawn** so a mid-mission difficulty change cannot retroactively buff enemies already on the field.

```
Easy hp=168 (0.70) | Normal hp=240 (1) | Hard hp=360 (1.50) | Extreme hp=480 (2.00)   base 240
```

**Damage and cadence are wired but NOT proven live.** An enemy 6–8 studs from the player produced zero shield/hp loss and `charges=0` over 8 s with
`GF_InMission=false` — hostiles never entered their attack cycle outside a mission. Worth recording: if hostiles will not engage a player who is not in a
mission, an out-of-mission test world can never exercise enemy combat.

**Not implemented:** `pressure` (budget/eliteFrequency are a different mechanism; applying both would double-count) and shield scaling (spec says "HP").

**Interpretation flagged:** `cadence` is treated as a **rate** multiplier, so Easy's 0.85 lengthens the interval. The alternative reading would make Easy
attack 15% *faster* than Normal, contradicting every other column. Recorded as a reading, not a certainty.

`S06-032` → PARTIAL.

**DAMAGE AND CADENCE SCALING VERIFIED LIVE — the earlier "unproven" was a test artifact (place 522).**
Evidence `evidence/v522-difficulty-scaling-verified-live/EVIDENCE.md`.

**My previous diagnosis was wrong.** I recorded that hostiles "never entered their attack cycle". A probe watching the counters returned
`tracked=1 engaged=1 tickErrors=0` — the enemy acquires and fires. The damage was swallowed deliberately:

```lua
-- VitalsService.applyDamage
if workspace:GetAttribute("GF_InMission") == false then return 0 end
```

My test world had `GF_InMission = false`. No AI failure; a gate.

```
Normal:  shield 100 -> 28   hits=9  sizes=[8.0 ×9]
Extreme: shield 100 -> 0    hits=8  sizes=[12.8 ×7, 10.4]     (12.8 = 8 × 1.60; 10.4 = clamped remainder)
cadence: Normal gaps=[0.20,0.17,1.30,0.20]  Extreme gaps=[1.10,0.20,0.17,1.07]
```

The post-burst gap shrinks 1.30 s → ~1.08 s (ratio 1.20 = authored cadence) while intra-burst spacing is unchanged — cadence scales the **cycle**, not
the burst, which also confirms the rate-not-interval reading.

**Still open on `S06-032`:** the `pressure` multiplier (budget/eliteFrequency are a separate mechanism; applying both double-counts) and shield
scaling (spec says "HP"). Stays PARTIAL.

**Method lesson (inverse of the session's usual error):** I asserted *absence of behaviour* and was wrong because **an intended gate looks identical to a
broken system from outside**. Before recording "X does not work", check whether something upstream deliberately suppresses it — `GF_InMission`, deploy
grace and console mitigation are all silencers on this path.

**HEADSHOTS ARE ×2, NOT THE AUTHORED ×1.5 (place 522, no code change).** Evidence `evidence/v522-head-multiplier-drift/EVIDENCE.md`.

Measured by calling `CombatService.weakMultiplier` against a live `Rifleman`:

```
Head[1]=2.00  Head[2]=2.00  Torso=1.00   heads=2  torsos=1  markedWeakPoints=none
```

- **Head ×2.00 vs authored ×1.5** — every headshot 33% stronger than specified (240 HP Rifleman dies in 6 headshots, not 7).
- Body ×1.00 conforms.
- **"Marked weakpoint" is unimplemented** — the code reads `part:GetAttribute("WeakPoint")`, but no part on any rig carries it, so only the name-based
  Head branch ever fires.
- The rig has **two parts named `Head`**, both ×2 — `FindFirstChild("Head")` picks arbitrarily.

**Near-miss:** this is the same ×2 behind the puzzling `196.8` shotgun total. I explained that figure as "several headshots at mult 2" — arithmetically
right, but I filed it as expected without noticing 2 is not the authored value.

**Unresolved anomaly:** a live shot into a spawned enemy returns **0 damage with no rejection reason** (empty `GF_LastReject`), from origins inside the
8-stud limit with ammo set. `fire` accepts and nothing lands; causes not distinguished (rig part not mapped by `resolveEnemy`, ray miss never checked via
`LastMiss`, or scoping). The fire path's ability to damage a spawned test enemy is therefore itself unverified.

Not changed: the head constant is a damage-tuning value; flipping 2 → 1.5 invalidates every TTK measurement, so it goes in the owner's balance pass.

**FIRE PATH IS FINE — THREE OF MY PROBES WERE MISBUILT (place 522).** Evidence `evidence/v522-fire-path-probe-corrections/EVIDENCE.md`.

Chased the previous batch's "0 damage with no rejection" anomaly to ground. The code was correct each time; all three defects were in the probes.

1. **Wrong attribute container.** `note()` writes to `workspace.GFDebug` (`debug():SetAttribute(...)`), not `workspace`. Every "no rejection reason" I read was
   nil because I looked in the wrong folder — a rejection looked like silence.
2. **My own stale shot sequence.** `fire` rejects `shotId <= s.lastShotId`. An earlier probe fired with `math.random(1e6)`, so a later test passing `4242` was
   silently rejected. Using `s.lastShotId + 1` made every shot land.
3. **Misread parameter semantics.** I called `damageEnemy(model, 18, plr, "Head", 2)` and measured 18, concluding the multiplier was ignored. `mult` there is only
   a flag for augment bonuses; the **caller** applies it (`fire` does `base * falloff * mult`). My test bypassed the only place it is applied.

Established with fixed probes: torso shot through `fire` = **18.0 exact** (AR01 base); `weakMultiplier("Head")` = **2.00**, `("Torso")` = **1.00**; a ray aimed
at the `Head` part does hit `Head`, while a ray aimed at `Torso` hits **`ChestPlate`**; no rig part carries a `WeakPoint` attribute.

**Still unmeasured:** an end-to-end headshot, because the moving enemy's ray hits `ChestPlate` as often as `Head`. Needs a stationary target. The ×2 is a proven
multiplier on a proven caller path, not a measured in-play headshot.

**HEADSHOTS MEASURED END TO END: ×2.00 vs authored ×1.50 (place 522, no code change).**
Evidence `evidence/v522-headshot-measured-end-to-end/EVIDENCE.md`.

```
torso = 18.0 (AR01 base)      head = 36.0 = base × 2.00      authored 1.50
```

The drift is now measured through the real `fire` path with a frozen rig, not inferred from `weakMultiplier`.

**Why three earlier attempts failed** — none was the game: wrong attribute container (`workspace.GFDebug`, not `workspace`); a poisoned shot sequence from a
prior `math.random(1e6)` id; `origin-too-far` because candidate origins sat 6–18 studs away against `MAX_ORIGIN_OFFSET` **8**; and chest-plate occlusion —
even a correct line to `Torso` hits `ChestPlate`.

**Reusable combat-test recipe (all four are required):**
1. `workspace:SetAttribute("GF_InMission", true)` + clear `GF_DeployGraceUntil`, or every hit is swallowed.
2. Anchor the rig's parts so aim and raycast see one pose.
3. Stand within 8 studs of the target.
4. Choose an aim origin whose **first** raycast hit is the intended part — aiming at a part does not mean hitting it.

`S04-014` stays PARTIAL: body ×1 conformance and head ×2 drift both measured; *marked weakpoint* still unimplemented (no `WeakPoint` attribute on any rig part).

**SHIELD ROUTING CORRECT, BUT TWO AUTHORED SHIELD RULES ARE VIOLATED (place 522, no code change).**
Evidence `evidence/v522-shield-rules-violated/EVIDENCE.md`.

Measured on one `Rifleman` with the combat harness (mission active, rig anchored, origin chosen where the first raycast hit is the intended part):

```
overflow(shield 10):   shield 10 -> 0    health 5000 -> 4992   (-8 exactly = 18 - 10)
shieldOnly(shield 40): shield 40 -> 22   health 5000 -> 5000   (-18, health untouched)
noShield(shield 0):    health 5000 -> 4982                     (-18)
```

**Correct:** shield absorbs first, overflow is exact, no double-charging.

**Violation 1 — head bonus applies to shields.** A headshot drained shield **36**, not 18. Spec: *"no ordinary head bonus on shield"*. `fire` pre-multiplies
before `damageEnemy`'s shield branch, so it cannot be excluded without restructuring.

**Violation 2 — armour applies to shield damage.** With `ArmorFactor 0.5`, a body shot drained **9** from shield (18 × 0.5). Spec line 47: *"armor multiplier
on health only"*. Cause is ordering in `damageEnemy`: `amount = amount * armorFactor` sits **before** the shield branch. Consequence: a shielded Heavy
(`ArmorFactor 0.75`) has shields 25% tougher than authored — the shield-break phase is slower than designed.

**Violation 3 — no `shieldFactor` exists.** `S04-018`'s raw-versus-mention split (`shieldBefore/shieldFactor`) is unimplemented in structure, not merely
mistuned.

`S04-015`, `S04-018`, `S04-021` → PARTIAL. (`S04-021`'s *behaviour* is verified exact, but the row asks for **unit tests** and no CombatService damage test
harness exists — `CheckRunner` asserts configs and constants only.)

Not changed: fixing this reorders the damage maths and changes every shielded TTK figure, including ones already recorded. Owner's balance pass.

Ledger: UNKNOWN 572 → 570, PARTIAL 176 → 179.

## Current build
- Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, place `Playtest1` (placeId 120646942844931), saved as **version 522**.
- Spec `.goal/GOAL_2026-11-24.md`; ledger `REQUIREMENT_COVERAGE.csv` **815 rows, 168 populated, 648 UNKNOWN**.
- Ledger state: PARTIAL 126 | VERIFIED 26 | ABSENT 2 | IMPLEMENTED_UNVERIFIED 2 | OWNER_ACCEPTED 0.
- Place version **522** is authoritative (saved this session). Earlier documents claiming 448, 318, 232
  or 461 are all stale; 461 was the last commit-labelled build, 463 is the saved place version.

## Verified this session
**Elimination family** (evidence/v383-elimination/EVIDENCE.md) — `Head of the Spear` 3 tagged (Officer + 2 Rifleman), `Siege Breaker` 1 tagged Bastion Walker, `Broken Talon` 3 tagged (Marksman + Heavy + Officer). Each completed only when its whole roster was down; 2/3 left the objective open.

**Conquest family** (evidence/v385-conquest/EVIDENCE.md) —
| Variant | Stage 1 | Stage 2 | Stage 3 |
|---|---|---|---|
| Forward Dominion | 4 defenders | console interaction | 45 s hold → complete |
| Iron Foundry | power interaction | control-point interaction | 60 s hold → complete |
| Thronefall | 3 guards | HighMarshalVeyr 3200 HP | command node → complete |

Rank gate verified by temporarily requiring rank 99: deployment refused with `requires military rank 99`, no mission started; restored to 10 and re-saved.

Counts: **5 of 5 families exist and are playable; all 15 variants are verified complete on Normal** (13 at builds 393-397, the last three re-run at 398).


## Verified at build 387
**Destructible objective structures** (`CombatService.damageStructure`): parts carrying `GFIntegrityMax` take the same falloff-adjusted weapon damage an enemy would, set `GFDestroyed`, and are polled by the objective machine.

**Sabotage | Shattered Aegis** (`SABOTAGE_AEGIS`), real weapon fire through `FireWeapon`:
- generators 300 HP each, destroyed in 13 and 14 AR01 shots;
- emitter shielded until both are down — six shots at it were deflected, integrity stayed 700;
- emitter 700 HP, destroyed in 56 shots across two reloads; `GF_ObjectiveComplete=true`, `GF_StructuresDestroyed=3`.

Shield leak found and fixed: `CanQuery=false` alone did not stop damage (700 → 568). Damage now gates on the `GFShielded` attribute and counts `GF_ShieldDeflected`.

Frame `ScreenCapture_AEGIS_SHIELDED` shows the new objective line `Destroy the shield generators (0 / 2)`.

Automation note: a camera-origin shot is rejected `origin-too-far`; fire from `root + (0, 2, 0)`. `workspace.GFDebug` reports `Accepted` / `Rejected` / `LastReject` / `LastStructure`, which separates a rejected shot from a miss.


## Verified at build 388
**Recovery | Fallen Convoy** (`RECOVERY_CONVOY`): crate A recovered (1/2, stage stays 1) → crate B → stage 2 with a tagged pursuit squad of Rifleman/Scout/Heavy → 2 of 3 dead left the objective open → 3rd kill completed it.

**Defense | Last Transmission** (`DEFENSE_UPLINK`): activate dish → stage 2 timer → at 78 s the stage moved to 3 and the terminal prompt changed to `Confirm uplink` → confirming set `GF_ObjectiveComplete=true`. The defend uses its own 75 s timer, not the beacon's 60 s.

Both reuse existing machinery only: tagged rosters and the 0.5 s timer.


## Verified at build 393 — Defense | Power Under Fire
First defence object that can actually be lost: 600 HP on Normal, hostiles shoot it when no player is visible, the 90 s timer pauses when nobody is inside 55 studs, and destroying it sets `GF_ObjectiveFailed` instead of completing.
- player present 20 s: 549.5 → 476.5 integrity (~3.65 HP/s, survives the 90 s window);
- player absent 12 s: timer 63 → 63, `GF_DefensePaused=true`; returning resumed 63 → 59 in 4 s;
- generator destroyed: `GFIntegrity=0`, `GFDestroyed=true`, `GF_ObjectiveFailed=true`, `GF_ObjectiveComplete=false`.

Three defects found and fixed while building it:
1. **Instance attributes return an `InstanceHandle`** — publishing the structure as an Instance killed every enemy tick with `IsA is not a valid member of InstanceHandle` (seven logged repeats). Names are published and resolved instead.
2. **`lineOfSight` rejects large targets** (3-stud tolerance), so hostiles refused to shoot a 7×9×7 generator they were standing in front of. Replaced with a direct raycast that accepts the structure's own model.
3. **Un-gated structure fire is unfair** — eight hostiles destroyed 600 HP in 22 s. Gated on `GF_DefenseEngaged` and scaled to `def.damage * 0.25`.


## Verified at build 397 — the last two variants and the hacking subsystem
**Hacking** (`HackingService` + `HackState`/`HackAttempt` + MissionHUD overlay) is server-authoritative: the client presses, the server derives the needle angle from `workspace:GetServerTimeNow()` and decides hit or miss. Normal = 95° arc, 1.3 s rotation. Measured 3 hits → complete, and a deliberate out-of-arc press at stage 1 dropped the stage to 0 with `GF_HackMisses=1` (spec floor is 0).

**Sabotage | Burn the Arsenal**: pad A armed (1/2), pad B → warning; stage 2 at +2 s, stage 3 at +9 s, so the 8 s warning is real; stockpile removed, objective complete.

**Recovery | Silent Archive**: approach auto-advanced to stage 2, interaction started the hack, 3 in-arc presses → stage 3 with the intel case revealed, interaction completed the objective.

Defects fixed: the HUD kept the previous mission's green `PRIMARY OBJECTIVE COMPLETE` on a fresh deployment (verified by scanning `PlayerGui`: `COMPLETE` → `PRIMARY OBJECTIVE` after redeploy); the revealed intel case was faded by the Neon completion flourish (now Metal); the hacking miss floor was 1 instead of 0; and six `StationUI` table entries were missing commas, which killed the whole client script until fixed.

Lesson: syntax-check every edited script with `loadstring` before a playtest — the StationUI parse error only surfaced as a client log line.


## Verified at build 398 — the variant table is closed
- `RECOVER_TECH`: black box → `CarriedCase` on the character → delivered at the LZ → complete.
- `DEFEND_BEACON`: 60 s hold completed.
- `DEFENSE_POWER`: restore → 90 s survived at 520/600 HP → stage 3 → stabilise → complete.
- Hacking cancel: watchdog on range/downed/disconnect; observed release with reason `downed`, stage reset, console unlocked for retry.

Ledger now has **2 VERIFIED rows** (`COUNT-VARIANT`, `S08-003`) — 15 of 15 variants played to completion. Owner acceptance is still pending and is not mine to grant.

**Harness lesson:** `StationService.deploy` sets `GF_DeployGraceUntil = os.clock() + 4`, so grace armed before a deploy is overwritten. The player then dies, respawns at the station, and the defence timer pauses — which reads as a stuck objective. Re-arm grace after deploying, and re-assert it during long timers.


## Verified at build 399 — objective markers (`S08-033`, was the only MISSING row)
A diamond plus distance label, projected with `WorldToViewportPoint`, clamped to a 46 px margin when off-screen or behind the camera. Server picks the position per template (living elimination target, otherwise the objective) and sends it inside `ObjectiveProgress`; it is nil once complete.

Measured: `TARGET 45 m` with three tagged Talons alive, live update to `TARGET 87 m` when the player moved ~75 studs, marker hidden after the objective completed.

**Defect fixed:** the marker function, defined near the top of `ObjectiveService`, captured a *global* `elimTargets` because the local of that name was declared 600 lines further down — so it silently fell back to `OBJECTIVE (behind) 752 m` and never updated. Forward declaration fixed it. `loadstring` cannot catch this class of bug; reading the rendered value did.


## Verified at build 402 — weapon roster to spec
8 weapons: AR01, **SMG03**, SG04, MR07, LMG12 (standard) + **GL22**, **RL09** (requisition launchers) + P01. `ER16` removed — human energy weapons are future-only and it was never authored.

**Defect fixed:** `CombatService.applyLoadout` called `ArmoryService.selection`, which did not exist; the `pcall` swallowed it, so equipping changed the menu and the profile but never the live weapon (measured `ok=true` then `weapon-mismatch:AR01!=SMG05`). After adding `selection`, the same equip produced accepted shots.

Launchers use `CombatService.detonate`: radius damage to enemies and destructible structures with distance falloff. GL22 measured 33 damage into a shielded target (shield 30 → 7); RL09 fired and registered a blast. **Multi-target coverage was not demonstrated** — authored rosters spawn 18–20 studs apart, wider than the 9-stud radius.


## Verified at build 404 — augment catalogue rebuild
9 category pools x 3 archetypes = 27 augments, each with category, rarity (Common/Rare/Epic), cost and a trait range. `Augments.roll(category, owned)` is rarity-weighted and skips owned ids; `rollTrait` produced `blastRadius=0.344` on `WideCharge`. `ArmoryService.buyAugment` now accepts a category and rolls an unowned archetype: measured `Launcher:ShapedWarhead:660` and `Marksman:StableStock:430`. Rolled traits are stored per player in `profile.augmentTraits` and applied by `AugmentService.forProfile`.

**Retraction (build 406):** the "repeat purchases fail" note above was an instrumentation error — `GF_AugmentBought` records only the last buy. Measured ownership shows the loop works and the roll excludes owned archetypes (10 owned across five categories, no duplicates).

Two real fixes at build 406: every armory refusal now records `GF_ArmoryRejected` (measured `"no augment left in that category"` on an exhausted pool), and `WeaponEquipped.magazine` now carries the augmented capacity instead of the catalog value (measured `ammo=116, magazine=116` for LMG-12).

**Also learned:** a `string.find` anchor that exists twice (`s.ammo = require(...).magazine(...)` is in both `fire()` and `applyLoadout`) patched the wrong one and left the payload field nil.


## Verified at build 408 — cache system (previously absent)
There was no cache code at all: no config, no roll, no grant. Now `Configs/Caches` defines four tiers and `CacheService` rolls/opens/grants them. A tier's rarity weights actually restrict the draw (before they were dead data), and opening grants the augments plus a rolled trait.

Measured over 300 caches per tier — Common cache 81.7/16.0/2.3/0.0 vs spec 82/16/1.9/0.1; Rare 48.5/42.3/8.0/1.2 vs 48/43/8/1; Epic 17.4/49.7/29.0/3.9 vs 18/48/30/4; Legendary 0/26.0/58.5/15.5 vs 0/30/55/15. Counts per cache are 1/2/3/4 as authored.

Completing SABOTAGE_RELAY on Normal granted `Rare:2:mission` and the profile went from 10 to 13 owned augments.

Five Legendary archetypes had to be added: the Legendary tier's 15% weighting had nothing of that rarity to roll (120 draws produced 0 Legendary).

**Open:** enemy cache drops are configured but never rolled; the mission cache is granted at primary completion rather than extraction; no cache inventory/UID/bulk/fusion; Legendary-tier Rare share is 26% because only five Legendary archetypes exist.


## Verified at build 410 — enemy cache drops and the mission cap
Chance ladder implemented (boss 100%, Officer 7%, Elite 4%, infantry 1%). Per-mission cap of 3 excludes bosses, measured: 3 forced drops then `GF_CacheDropCapped` with the count stuck at 3; a boss kill bypassed the cap and produced two caches (boss + guaranteed mission, `GF_CacheOpens` 0 -> 2).

Legendary odds improved by adding one Legendary archetype per category: 0 / 29.5 / 57.5 / 13.0 over 400 draws against the spec's 0/30/55/15.

**Instrumentation lesson (third time):** a single attribute records only the newest write. Drops looked absent because the weapon-kill hook never ran for an attribute kill, and the boss cache looked absent because the mission cache overwrote it one line later. `GF_CacheOpens` is now a counter.


## Verified at build 412 — failed primary offers emergency extraction
`powerFail` used to set `GF_ObjectiveFailed` and stop there: no evac, no way out. It now calls `ExtractionService.emergency()`. Measured with a 6 s grace override: at generator destruction `failed=true, emergency=true, called=true, remaining=6, landed=false`; after the grace `landed=true, remaining=0`.

Added server-side mirrors (`GF_ExtractionCalled/Landed/Remaining/Emergency`) because the live state sits in the module, and a tool VM `require` returns a separate instance — every `isLanded()` read from a test was false regardless of reality.

**Still open:** boarding a failed-mission dropship, the failed debrief and reward withholding were not exercised. Only `DEFENSE_POWER` can fail.


## Verified at build 413 — a lost mission now settles as a loss
`ExtractionService.board()` called `finish(true)` unconditionally, so boarding the emergency dropship after a **failed** primary was paid as a success. It now passes `ObjectiveService.isComplete()`.

Measured full failed round trip: generator destroyed → failed + emergency offer → dropship landed → boarded → settlement `{success=false, credits=0, xp=0, salvage 0}`, `GF_CarriedLost=true`, `GF_ExtractionState="failed"`, no success departure.

**Still open:** only one player and one difficulty; squad bonus and per-player split untested; war-credit contribution on a loss not inspected.


## Verified at build 415 — mission cache paid at extraction, not completion
Completing the primary now opens **no** cache (measured 0 opens). Boarding after a successful extraction opens exactly one: `GF_MissionCacheResult=granted`, `GF_CacheOpens=1`, source `mission`, alongside credits 450 / xp 600.

**A no-op edit happened here and is worth remembering:** the patch computed the new `CacheService` source and `loadstring`'d it but never assigned `C.Source`, so `tierForDifficulty` did not exist and a `pcall` swallowed "attempt to call a nil value". Every other failure this session at least threw; this one silently did nothing. Recording the pcall error into `GF_MissionCacheResult` found it in one step.

**Still open:** the failure→skip branch (`GF_MissionCacheResult = skipped ...`) has never been observed.


## Verified at build 416 — difficulty surface and the failed-cache skip
- `Extreme` rank gate corrected to 14; `RequestDeployOptions` now advertises all four difficulties (payload measured: Easy, Normal, Hard, Extreme). Hard and Extreme were previously unreachable from the UI.
- **Ordering bug fixed:** `buildPower` read `State.getMission().difficulty`, but `resetMission` calls `ObjectiveService.setup` *before* `State.setMission`, so an Extreme deploy built a **600 HP** generator. It now reads `GF_OperationDifficulty`; Extreme measures **650**.
- **Failed extraction skips the mission cache** — the gap left at build 415 is closed: `GF_MissionCacheResult = "skipped success=false objective=false"`, zero opens, `GF_CarriedLost=true`.

**Still open:** Easy (800) and Hard (650) defence HP are code paths only; the difficulty refusal path was last verified at build 398 with a temporary gate.


## Verified at build 417 — three saved loadouts
`profile.savedLoadouts` was a dead field: nothing wrote it. Added `ArmoryService.saveLoadout/loadLoadout` (slots 1-3, reachable as `SetLoadout` actions). Measured: save slot 1 holding SMG03 → equip AR01 → load slot 1 restores **SMG03**; slot 2 stays independent; `loadout slot is empty` and `loadout slot must be 1-3` both refuse correctly.

**Still open:** the Armory UI has no slot buttons, so this is remote-only. Persistence across a rejoin was not tested.


## Build 418 — loadout slot buttons in the Armory
`StationArmoryUI` now renders three SAVE/LOAD rows (`Loadout1.Save` … `Loadout3.Load`) wired to the verified server actions. Six buttons exist with distinct paths.

**Retraction (same build, retest):** the armory was never broken. `StationArmoryUI` closes the panel every Heartbeat when the player is more than 46 studs from the rack, and my unanchored teleport dropped the character to `y=30` against a `y=768` deck — a 738-stud gap. With the root **anchored** at 14 studs, the panel opened and real mouse clicks worked: `Loadout1.Save` → `GF_LoadoutSaved=1`; equip SMG03, `Loadout2.Save`, equip AR01, `Loadout2.Load` → `GF_LoadoutLoaded=2` and profile primary became **SMG03**.

**Harness rule:** anchor the character before any station teleport. There is no floor under the armory approach, and every proximity check fails silently 738 studs below the deck.


## Build 420 — six armour suits, and a real armory anchor bug
Armour did not exist: no config, one hardcoded kit, and a profile field nothing read. Now `Configs/Armor` holds six suits (4 standard, 2 requisition), `AppearanceService.dress(character, suitId)` is palette-driven and strips the previous kit, and `ArmoryService.buyArmor/equipArmor` buy and wear them. Measured: SIEGE → 12 kit parts, chest plate RGB 206/190/158; TROPHY → RGB 120/84/96, still 12 parts (no stacking); BLACKSTAR refused at rank 15 with `requires rank 16`.

**Real bug fixed:** the station has three armory racks and `findAnchor()` returned an arbitrary one, so a player at another rack measured 66 studs away (limit 46) and the panel closed every frame. It now returns the nearest rack — `Panel.Visible` stayed true across 8 samples afterwards.

**Not verified:** the armour WEAR/BUY buttons were never clicked (they sit below the scroll viewport); RECON and VANGUARD were never worn; armour prices do not match the authored GF-02/03/04 table (`S10-035`).


## Verified at build 421 — all six armour suits
Prices corrected to the authored table (GF-02 r3/500, GF-03 r5/850, GF-04 r8/1200) and all six suits worn with correct chest-plate colours: STANDARD 222/222/214, RECON 176/190/172, SIEGE 206/190/158, VANGUARD 198/206/224, TROPHY 120/84/96, BLACKSTAR 48/52/62 — 12 kit parts each, no stacking. BLACKSTAR's rank 16 gate was temporarily lowered to 14 for the run and restored.

**Harness limit found:** this client click tool cannot reach buttons inside a scrolled ScrollingFrame. Scrolling to an armour row made it visible (Y 87) but the synthetic click did nothing. Top-of-list loadout buttons were click-verified at build 418.


## Verified at build 422 — caches are earned, held, then opened
Awards used to roll instantly. Now `profile.caches[tier]` stacks unopened caches, the armory shows `Rare Cache · 1 held` with an `OPEN` button, and opening is an explicit action. Measured: mission completion → `GF_CacheHeld = "Rare:1"` with zero opens; `openCache Rare` → 2 augments, augments 34 → 36, held 0; second open refused `no Rare cache held`.

Fixed an instrumentation split: the grant wrote `GF_CacheHeld` while the open wrote `GF_CachesHeld`, so a stale grant value looked like a failed decrement.

**Still open:** the OPEN button was not clicked (below the scroll viewport); no inventory capacity check; no bulk open; no cache UID/timestamps.


## Verified at build 423 — armory clicks land, and a cache no longer burns for nothing
Reordered the armory list (loadouts → caches → armour → weapons) and discovered the real click constraint: the list viewport is **286 px tall starting at y=167**, so a row outside that band cannot be clicked. With rows inside it, `ArmorRECON.Wear` equipped RECON and `CacheRare.Open` consumed the cache — both click-verified.

**Defect the click exposed:** opening a cache whose archetype pool was exhausted produced **0 augments** and still consumed the cache. Fixed: roll first, refuse `nothing left to roll`, keep the cache (verified held stayed at 1).

**Still open:** the armory shows an OPEN button even when the pool is exhausted; no inventory capacity model; no Abilities/Grenades sections or tabs.


## Verified at build 424 — abilities and grenades are selectable, and the client obeys
Two defects fixed together: the armory had no ability/grenade surface, **and** the client hardcoded `Ability1 → "Airstrike"`, `Ability2 → "DomeShield"` — `profile.ability1/ability2` were read by no script, so selection could not have mattered.

Now `equipAbility`/`equipGrenade` write the loadout and publish `GF_Ability1/2` + `GF_GrenadeEquipped`; HUD and Controller read those attributes with the old literal as fallback. Measured: `Sentry` refused (`ability not owned`), `DomeShield` equipped (`GF_Ability1=DomeShield`), `EMP` selected, and casting the published id produced `AbilityCastRequests=1` plus a spawned dome.

**Still open:** no duplicate-slot guard (both slots can hold the same ability); four of six abilities unobtainable; armory buttons not clicked; grenade effects untested.


## Verified at build 426 — abilities: purchase, duplicate guard, clickable rows
- Duplicate slots refused: `ability already in the other slot`.
- `buyAbility` charges rank/cost: Sentry (900) and OrbitalStrike (1800) bought; the bought Sentry then equipped.
- **Four alternatives rendered at the same coordinates** in the Ability row — invisible stacked buttons, only the last clickable. Replaced with one cycling alternative per row; clicking `Ability1.UseAbility` moved the slot to DomeShield (`GF_Ability1=DomeShield`).

**Still open:** OrbitalLance/ReflectiveBarrier cost 0 in config (free unlocks); grenade rows not clicked; rank gate for the rank-10 abilities untested.


## Verified at build 427 — grenades do different things
| Throw | Measured |
|---|---|
| EMP at a shielded Heavy | 100 shield drained, 1 hostile stunned, no health damage |
| Frag at the same Heavy | 57 damage to 1 target, landing on shields first (HP unchanged) |

The spec's "Frag kills, EMP opens" distinction is real and now measured in play.

**Layout bug fixed:** grenade rows rendered at **y = 1313** because their `LayoutOrder` was `6 + order` and `order` had already climbed past 300 — present in the list, completely unreachable. Now sorts at 7–8; clicking `GrenadeFrag.Equip` after an 80 px scroll set `GF_GrenadeEquipped = "Frag"`.

**Still open:** Frag max-3 charges, EMP rank-4/550-credit unlock, fuse timing, throw preview — none verified.


## Verified at build 428 — grenade ownership and the charge cap
Throwing EMP **unowned** was free; `toss` now refuses it (`grenade not owned`). `buyGrenade` charges rank/cost: EMP is rank 4 / 550 credits as specced (was rank 5, no cost). Charges default to 3 (was 2), measured 3 → 2 → 1 → 0 across three throws with the fourth refused `no charges`.

**Still open:** charges never refill per mission — three grenades and you are done for the session. No armory BUY button for grenades, so a player cannot purchase EMP from the UI. Frag's cap not re-measured.


## Verified at build 429 — grenade supply is per deployment
`refill` restocks `GrenadeCharges` to the equipped type's `count` on every deploy: measured 3 → 0 after three throws, then **3** again after deploying (`GFDebug.LastGrenadeRefill = 3`). Armory grenade rows now show BUY for unowned types and EQUIP for owned.

**Still open:** the BUY branch has never rendered (both types owned on this profile); refill fires only on deploy, not on return to station; the refill is reached through a `_G` handoff inside a `pcall`, so a failure would be silent.


## Verified at build 430 — progression survives a server restart
Snapshot before/after a stop-start cycle: credits 39,590 · rank 15 · XP 123,700 · 36 augments · all six armour suits · four abilities · loadout (SMG03/P01, DomeShield/Airstrike, Frag, BeltFeed socket) · Rare cache ×1 — **identical**. A change made before the restart (equip VANGUARD) also persisted.

**Bug the restart exposed:** the character spawned in **STANDARD** while the profile said VANGUARD, because AppearanceService dresses at spawn before the DataStore profile arrives and never re-dressed. Fixed with a bounded 20×0.5 s retry; measured `GF_ArmorSuit = "VANGUARD"` with the correct palette on a fresh server.

**Still open:** no crash/reconnect mid-mission test, no receipt idempotency, war credits and settings not read back.


## Build 431 — minimap HUD (first pass)
`TacticalMapService` published `GF_MapMeta`/`GF_MapHeights`/`GF_MapMarkers` and **nothing read them**. New `StarterPlayerScripts.Minimap` draws 256 terrain cells and colour-coded blips (objective amber, LZ green, squad blue, down red) in a 156×156 top-right frame with an N tick. Measured `GF_MinimapCells=256`, `GF_MinimapBlips=2`, capture `ScreenCapture_MINIMAP`.

**Fixed at build 432** (evidence `v432-minimap-disc`): the map is now a **disc** — `UICorner` and `CanvasGroup` both failed to clip children, so the circle is drawn explicitly with a rounded disc backdrop plus radius culling (capture `ScreenCapture_MINIMAP_DISC` shows no corners). Heading now comes from the **character's** `LookVector` (camera writes were inert): character yaw 90° → `heading = -90`, `field.Rotation = 90`. Cells re-place every 0.2 s, so the map re-centres as the player moves (measured after a +20 stud move).

**Still open:** heading follows the character, not the camera; squad/downed blips never exercised; no zoom or POI discovery.


## Verified at build 433 — mission clock and grenade counter
Neither existed: the mission deadline lived only in mission state (never published) and grenade charges were an invisible attribute. `StationService` now publishes `GF_MissionRemaining` each second and `StarterPlayerScripts.StatusStrip` draws `MISSION m:ss` plus `GRENADE xN`.

Measured: 1492 s → `MISSION 24:52` normal (220,230,240); override 200 s → `MISSION 3:20` **amber (255,200,90)**; override 30 s → `MISSION 0:30` **red (255,110,100)**; charges 3 → `GRENADE x3`.

**Still missing from `S03-037`:** squad status, compact loot feed, Voss portrait/subtitles, nearby-enemy blips.


## Verified at build 435 — loot feed stacks, squad count
`SquadService.broadcast` now emits a **delta** on `LootCollected`; `StatusStrip` renders a four-line feed that stacks identical consecutive pickups. Measured: three 25-scrap grants → **`+75 scrap x3`** in one line, salvage total 75, `SQUAD 1`.

**Regression I caused and fixed in the same batch:** the delta code was placed above `local RS = game:GetService("ReplicatedStorage")` inside `broadcast`, so `RS` was nil and **every salvage pickup errored for two builds**. Fixed by hoisting `RS`; re-verified with three real broadcasts.

**Harness mistake, twice in a row:** setting `GF_TestHooks` from the **Client** datamodel (writes do not replicate) made the hook look broken. From the Server it works immediately.

**`S03-037` still missing:** Voss portrait/subtitles, nearby-enemy blips, multi-member squad reading (only one client exists).


## Verified at build 436 — Voss speaks
`DialogueEvent` was a declared remote with **no sender and no receiver**. New `DialogueService.say` fires `{speaker="VOSS", text}` and is wired to deploy briefing, primary complete and primary failed. `StarterPlayerScripts.Voss` renders a bottom-left panel with a shape-built helmet portrait and queued subtitles (6 s each).

Measured: deploy → `Sabotage Relay on Normal. Get in, finish the job, get out.`; completion → `Primary objective complete. Wrap it up and get to the ship.` (`GF_VossLines` 1 → 2). Capture `ScreenCapture_VOSS` shows the panel together with the circular minimap, `MISSION 24:40`, `GRENADE x3`, `SQUAD 1`.

**Known wart:** `DialogueService.start()` is never called (dead intro line and a stale `hook.onStage` check) — delete or wire it.
**`S03-037` still missing:** nearby-enemy blips with the observed/audible fade.


## Resumed — minimap hostile blips verified (build 437)
`.goal/PAUSE` removed by the owner. Hostile blips measured: **8** shown while standing 22 studs from a tagged Marksman with line of sight, **0** after moving ~700 studs away and waiting 4.5 s. Seen/audible rule implemented client-side (raycast + `EnemyFired` linger), so the map cannot learn about an enemy the client cannot see.

**Still unmeasured:** occlusion (cover) and the audible-only path; no cap on simultaneous blips.

## Earlier pause note (resolved)
`.goal/PAUSE` written; goal loop will not continue until it is removed.

**In flight, unverified:** minimap hostile blips (`StarterPlayerScripts.Minimap`). Design is "observed or audible only, never a wallhack" — a client-side raycast from the player's head plus `EnemyFired` as the audible channel, three-second linger with a transparency fade. The code compiles and the place is saved at **version 437**, but no frame or count has been read yet, so it is **not** claimed to work. Next step is to deploy an elimination mission, stand with line of sight and read `GF_MinimapHostiles`, then break line of sight and confirm the blips fade to zero.


## Verified at build 438 — debrief breakdown and the full-squad bonus
`RewardsService` had **no** full-squad bonus; now `compute(difficulty, success, objective, squadSize)` returns base/bonus splits. Measured arithmetic: solo 450 credits / 600 XP with 0 bonus; four players 450+112 / 600+150 (562 / 750, floored).

The debrief now renders base vs bonus for credits and XP, primary COMPLETE/INCOMPLETE, extraction SUCCESSFUL/FAILED and "Carried salvage secured/lost", measured after a real solo extraction.

**Still open:** the bonus has never paid out live (one client only); salvage is not multiplied; no rank-up animation; the lost-salvage branch has not rendered.


## Verified at build 439 — salvage bonus, and a payload bug of mine
**My own defect:** at build 438 the split fields went into the **late-join branch** payload, because `objectiveComplete = objectiveComplete,` exists twice and my text anchor hit the wrong one. The client therefore never received base/bonus/`carriedLost` — which is why a failed run still said "Carried salvage secured". Rewrote the real payload block by line range.

Salvage bonus implemented (+25% per resource, floored): measured 40/40/40 → **50/50/50** with 10 each at four players, unchanged at one. Credits 450 → 562 and XP 600 → 750 already measured at 438.

Failed-run debrief now reads: `base 0`, `Primary objective: INCOMPLETE`, `Extraction: FAILED`, **`Carried salvage LOST`**. Both settlement outcomes are observed in a real run; only the rank-up animation remains from `S09-041`.


## Verified at build 440 — debrief rank-up flourish
`MissionHUD` shows a rank-up label when `rankUps > 0`, growing 14→22 px and fading after 2.6 s. First attempt printed **`RANK UP 11 → 15 (x2)`** because the formatter subtracted the delta twice; fixed to **`RANK UP 13 → 15 (x2)`**. The salvage-bonus line from build 439 also rendered (`+0 scrap +0 cells +0 tech` on a solo run).

**Not observed:** the tween/hold/fade itself, and a real earned rank-up (forced via `GF_ForceRankUps`).


## Audited at build 440 — archetype combat behaviour
Deployed, put the player at the centroid of 3 Rifleman + 3 Marksman + 2 Scout, watched `EnemyFired` and model movement for 12 s.

| Archetype | Shots / 12 s at ~40 studs | Furthest move |
|---|---|---|
| Rifleman | 5 | 56 |
| Marksman | 8 | 59 |
| Scout | **0** | 45 |

Then 6 studs from a Scout: **13 shots in 8 s**. So the Scout was never broken — its authored range is 46 studs and it spent the first window closing. Had I recorded Result 1 alone, "Scout never fires" would have been a false defect.

**Not verified:** any authored statistic in `S06-023`–`S06-027` (HP, shields, damage, accuracy, armour); no cover/peek/flank/investigate state was observed.


## Verified at build 441 — enemy stats realigned and burst fire implemented
Every archetype ignored its authored stat block, and every attack was a **single instantaneous hit** — the spec's 8x3 / 6x4 / 12x2 patterns did not exist.

Realigned: Rifleman 240/80 (was 120/60), Scout 210/60 (80/30), Marksman 210/60 (100/40), Heavy 620/180 (260/150), Officer 420/160 (180/100), with move speeds and per-shot damage to match, plus a `burst` field per archetype. `EnemyService` now fires `count` hits `interval` apart, aborting on death, lost target or out-of-range.

Measured: Scout spawns at 210/60 and dealt **10 separate `amount=6.0 source=Scout`** events at 4 studs — a burst, not one 24-damage spike.

**Mistake to remember:** my first config edit was string splicing that produced `burst = burst = {...}` and broke compilation with no backup. Recovered by reconstructing the lines; verify compile after every config splice.

**Still open:** only the Scout was observed; Heavy telegraph, Officer aura/call, armour factors and cover/peek are all unimplemented.


## Verified at build 442 — armour factors and the Commander aura
**Armour** is now per archetype and applied after shields: a 40-damage hit lands **30** on the Heavy (0.75) and **36** on the Officer (0.9), measured on shield values with `GF_LastArmorMitigated` recording the result.

**Commander aura**: allies within 45 studs of a live Officer attack at 0.9× cooldown (10% faster) — measured `AuraRate = 0.9` on Marksman/Heavy/Scout/Rifleman — and return to **1** the moment the Officer dies, which satisfies "death clears aura" without any bookkeeping.

**Still open:** Heavy charged-blast telegraph and 4 s recovery; Officer relay call; the cadence difference (1.6 s → 1.44 s) was not timed shot-to-shot.


## RESOLVED at build 444 — the build-443 "no damage" alarm was my own grace flag
The Heavy does fire. Measured with `GF_DeployGraceUntil` cleared: `GF_LastAttackAttempt = "hit"`, **32.0 damage twice** in 9 s, `GF_LastCharge = "Heavy:1.4"` and `ChargingUntil` set then expiring — the authored 1.4 s charge and 32 damage are real.

Two artefacts had masked it: deploy grace absorbs every hit, and earlier runs had the player at y≈767 (station) while the Heavy was at y≈37 (mission) — a 746-stud gap, which a raycast confirmed.

`GF_LastAttackAttempt` (entry / los-fail / los-pass / hit) is now a permanent diagnostic.

**Still open:** the 4 s recovery interval was not timed; no visible charge tell beyond `EnemyTelegraph`.

## Superseded note (build 443)
Added Heavy `chargeTime = 1.4, recovery = 4.0` and wired `windUp` through `EnemyService`. Config verified (Heavy 620/180, armour 0.75, charge 1.4, recovery 4.0).

**But no enemy dealt damage in either run**: `GF_EnemiesTracked = 10`, `GF_EnemiesEngaged` was **0** with the player anchored 12 studs away and **6** after repositioning unanchored — and damage events were **0** in both. `ChargingUntil` and `GF_LastCharge` never set.

Two builds ago the same mission produced 32-damage Heavy blasts and 6-damage Scout bursts, so this is either a **regression from this batch's three edits to the attack path** or a positional artefact. Not separated.

**Next action:** instrument the delayed attack callback — write `GF_LastAttackAttempt` at entry, after the LOS test, and after `applyDamage` — then read all three in one run. Do not touch anything else until that reads true.

**Repeat mistake:** the `ChargingUntil` writes first landed in a *different* function that shares the same telegraph code (line ~326 vs ~412). Same "anchor exists twice" failure as the build-438 payload edit.


## Verified at build 445 — Commander relay call
New `EnemyService.startCalls` loop (outside `tickActor`, so the attack path is untouched): an Officer within 70 studs of a live relay starts a 2 s call, then spawns **2 Riflemen**; dying mid-call cancels it.

Measured: `GF_CallState = "Officer:pending"` → `GF_Reinforcements = 2` with Riflemen 2 → 4; killing the Officer during a call gave `GF_CallCancelled = 1` and **zero** reinforcements (`Officer:cancelled`).

**Corrected at build 446:** the sabotage roster *does* include Officer — it is a random patrol pick, and two sample missions happened to roll none. The real issue was reliability, so `beginMission` now guarantees **one Officer at the relay** for `SABOTAGE_RELAY`. Measured in plain play (no scaffolding): Officer 11 studs from the relay, `GF_CallState = Officer:pending`, then `GF_Reinforcements = 6` and Riflemen → 7.

**Balance risk:** three Officers each called once, adding 6 hostiles to a mission with no cap. Needs a one-call-per-mission (or per-relay) limit before it is tuned.


## Build 447 — relay call cap attempted, NOT airtight
Added `relayCallUsed` with both a start guard and a completion guard, reset from `beginMission`. Result: reinforcements fell from **6 → 4**, but two calls still resolve and I cannot say why. Two candidates not separated:

1. `GF_Reinforcements` is a running counter never reset per mission — 4 may include carry-over.
2. Two calls resolving inside the same 0.5 s tick.

**Resolved at build 448:** the 4 was carry-over, not two calls. `beginMission` now resets `GF_Reinforcements`/`GF_CallCompletedBy`/`GF_LastCall`, and each completion appends `Officer@<clock>;` so completions are countable. Two consecutive missions each gave **2 reinforcements** and **one** `Officer@…` entry — the cap works and does not accumulate.

**Process note:** fifth time a running counter or last-value attribute gave an ambiguous reading. Counters must be reset where their mission peers are.


## Verified at build 449 — burst cadence and Heavy recovery timed
Inter-arrival times from `EnemyFired` over 18 s:

| Archetype | Gaps (s) | Reading |
|---|---|---|
| Rifleman | 0.17, 1.10, 0.20, 0.18, 0.17 | 3-shot bursts at ~0.18 s (authored 8x3/0.18) |
| Officer | 1.55-2.03 (x6), 5.27 | 2-shot volleys 2 s apart (authored 12x2/2 s) |
| Heavy | **6.10, 6.05** | cooldown 2.6 + recovery 4.0 = 6.6, observed ~6.1 |

So the Heavy's 4 s recovery is no longer just config, and the burst loop is confirmed at the authored interval rather than merely "more than one hit".

**Two harness facts learned:** moving the character from the **Client** datamodel does not replicate (the server still saw the player at the station — that is why fire looked dead), and `GF_EnemiesEngaged` reads **0 during active fire**, so it is not a usable "is anyone attacking" signal.


## Verified at build 450 — "engaged" means shooting now
`GF_EnemiesEngaged` counted a `target` pointer that ticks clear, so it read **0 while 12 hits landed** (that was the build-449 false alarm). Every shot now stamps `actor.lastFiredAt` and the counter means "fired within 3 s": measured **2** under fire and **0** five seconds after leaving.

Marksman also gained `chargeTime = 0.8` through the shared telegraph path (unobserved so far).

**Bug introduced and fixed same batch:** routing the shot through a `local function` declared *below* its first use gave `EnemyService:450: attempt to call a nil value` twelve times and stopped all hostile fire — while `loadstring` compiled clean. Inlined; re-verified zero errors.

**Still stale:** `GF_EnemiesTracked` stayed at 13 with the player at the station — `actor.target` is never cleared, so it means "ever acquired", not "has a live target".


## Verified at build 452 — both enemy diagnostics honest
`GF_EnemiesTracked` was still lying (13 at the station) because dormant actors never tick and `actor.target` was never cleared. `tickActor` now clears it, and the counter requires a live in-range target (character present, within 260 studs).

Measured: under fire **engaged 5 / tracked 10**; six seconds after leaving, **0 / 0**. Either counter can now be trusted.

**Two runtime-only bugs of mine this batch:** a `local function` used before its declaration (`attempt to call a nil value`, all hostile fire stopped) and a loop-variable mismatch (`model` vs `_`) that threw inside the Heartbeat and pinned both counters at 0. Both compiled clean. **`loadstring` is not a test** — the runtime error log is.


## Verified at build 453 — full-loop regression pass
Deploy → hold relay → extract → board → debrief on `SABOTAGE_RELAY`/Normal: objective complete, ship landed, debrief `base 450 + bonus 0`, `xp 600`, `COMPLETE`, `SUCCESSFUL`, `Carried salvage secured`. Server errors: **1**, the Roblox plugin (`Game is not a valid member of ReplicatedStorage`), no game code.

**Client break found and fixed:** `StationUI:472: attempt to call a nil value` — `showDebrief` called `setFocus` declared 8 lines *below* it as a `local function`, so the focus hand-back threw on every debrief. Made it a global; re-ran the loop and the error is gone.

**Third forward-reference bug this session** (two of mine in `EnemyService`, this one pre-existing). Luau compiles it and fails at runtime — `loadstring` is not a test.


## PAUSED by owner — 2026-11-24T22:35Z
`.goal/PAUSE` written; the loop will not continue until it is removed.

**In flight — 15-template deploy sweep (place 453, unchanged by the sweep).** Each template was deployed on Normal for ~3 s and `GF_DeployRejected` read:

| Verdict | Result |
|---|---|
| Rejections | **none** — all 15 templates accepted |
| `GF_ObjectiveComplete` | `false` on all 15, as expected right after deploy |

**Suspicious artefact, not yet investigated:** `GF_ElimTargets` read **3** for templates that are not elimination missions (Conquest, Defense, Recovery, Sabotage-Aegis/Arsenal), and `1` for `ELIM_WALKER`. Either it is a stale attribute left by the previous mission, or elimination tagging is leaking into other templates. One run with the attribute cleared before each deploy would settle it. Do not trust that counter until then.

**Next actions when resumed**
1. Clear `GF_ElimTargets` before each deploy and re-read it per template to prove or kill the leak hypothesis.
2. Finish the sweep by driving each variant to completion (teleport + interact/objective per template) rather than only deploying.
3. Check the client and server logs once at the end; the sweep only covered deploy, not play.


## PAUSED by owner — 2026-11-24T22:40Z (place 455)
`.goal/PAUSE` written. Nothing is mid-edit; the tree is committed and the place saved.

### What was resolved before the pause
**`GF_ElimTargets` was never leaking.** Clearing the attribute before each deploy proved it: across five consecutive deploys only `ELIM_COMMANDER` set `GF_ElimTargets = 3`; `SABOTAGE_RELAY`, `CONQUEST_DOMINION`, `DEFENSE_POWER` and `RECOVERY_CONVOY` all left it `nil`. The earlier "3 everywhere" was a stale attribute read across deploys.

**Elimination tagging verified:** `ELIM_COMMANDER` marks an **Officer + 2 Riflemen** (`elim = 3`, `tagged = 3`, names `Officer,Rifleman,Rifleman`).

### A change I made and reverted in this batch
I added `EnemyService.clearAll()` to `EncounterDirector.beginMission` to stop hostiles accumulating across redeploys. It **destroyed the elimination targets** (`tagged = 0` on every elimination deploy) because `ObjectiveService.setup` spawns and tags them *before* `beginMission` runs. Reverted; tagging re-verified at 3.

### The real defect that remains
**Redeploying without extracting never clears the previous mission's hostiles.** `EnemyService.clearAll()` exists but is only called from `ExtractionService`. After several deploys the mission contained 9 hostiles and counts read high.

The fix has to run **before** `ObjectiveService.setup(RELAY, template)` in `StationService` (not in `EncounterDirector`), and it must be verified with the attribute and world state cleared between deploys — my sweep this batch did not clear between runs, so it proved nothing.

### Next actions when resumed
1. Move the clear to just before `ObjectiveService.setup` and verify: deploy ELIM → kill nothing → redeploy ELIM → still exactly 3 tagged, and total hostiles equal one mission's roster.
2. Finish the 15-template sweep **playing each to completion**, not just deploying.
3. `S06-023/024/026` still lack cover/peek behaviour and the Marksman telegraph is unobserved.


## Verified at build 456 — elimination family works; redeploy no longer stacks missions
**Root cause of the old "targets=0":** `StationService` called `EnemyService.clearAll()` without ever requiring EnemyService, so deploy threw `attempt to index nil with 'clearAll'` **before** `ObjectiveService.setup` and every elimination mission came up patrols-only. Adding `local EnemyService = require(script.Parent.EnemyService)` fixed it.

`clearAll()` now runs immediately before `ObjectiveService.setup`, so a redeploy replaces the roster instead of stacking two missions in `ActiveActors`.

Measured: fresh deploy → `elim=3`, tagged 3 (`Officer, Rifleman, Rifleman`), 8 hostiles; redeploy without killing anything → still `elim=3`, tagged 3, **8 hostiles**. Killing all three → `stillAlive=0`, `GF_ObjectiveComplete=true`.

**Still open:** only `ELIM_COMMANDER` was played to completion; `ELIM_WALKER` and `ELIM_TALON` tag correctly but were not completed. `S08-033` approximate-then-reveal markers still do not exist.


## Verified at build 457 — all three elimination variants complete
| Variant | Targets | Outcome |
|---|---|---|
| `ELIM_COMMANDER` | Officer + 2 Riflemen | `complete = true` (build 456) |
| `ELIM_WALKER` | Bastion Walker, 4200 HP | 4200 → 0, `Dead = true`, `complete = true` |
| `ELIM_TALON` | Heavy, Marksman, Officer | 3 killed, 0 alive, `complete = true` |

**Harness error repeated:** the Walker scan looked only in `ActiveActors` and read zero while `GF_ElimTargets = 1` — the Walker lives at `Workspace.BastionWalker`. Count targets with a **workspace** walk, never an `ActiveActors` walk.

**Not proven:** kills went through `CombatService.damageEnemy`, so aim/spread/time-to-kill are untested, and Walker/Talon extraction settlement was not re-run.


## Verified at build 457 — weapon fire end to end
Six client `FireWeapon` shots at a 21-stud clear line on an Officer: **6 DamageFeedback events**, shield **160 → 120.4**, **6.6 damage per shot**. That is AR-01 base 8 × Officer armour 0.9 × falloff ~0.92 — three systems compounding as designed. A shot into a wall 5 studs away consumed ammo and dealt nothing, which is correct hitscan.

**Config mismatch found:** the ledger specifies AR-01 damage **18**; observed damage is consistent with a base near **8**. Recorded on `S04-WPN-AR01`, not yet reconciled.

**Harness errors, both repeated again:**
- `GF_DeployGraceUntil` set from the **Client** does not replicate — the player respawned at the station and shots went into the deck 748 studs from the target.
- Line of sight must be **found**, not assumed: a 15-stud target sat behind `AscendancyOutpostWall`. Target selection now requires an enemy whose own raycast is the first hit.


## Verified at build 457 — weapon stats aligned to spec
Five of eight weapons disagreed with their authored rows; nobody had compared them. Aligned: AR-01 (18 dmg / 2.1 reload, was 22/2.2), P-01 (22 / 300 rpm / 72 reserve / 1.5), SG-04 (72 rpm / 42 reserve), MR-07 (51 / 150 / 12 / 72 / 2.4), LMG-12 (17 / 660 / 225 / 3.7). SMG-03, GL-22 and RL-09 already matched.

**AR-01 verified by firing:** `GFDebug.LastDamage = 18`, 5 accepted hits, `TotalDamage = 81` = 5 × 18 × 0.9 armour, shield 160 → 79.

**Behaviour worth deciding:** `damageEnemy` applies `armorFactor` **before** shields, so a Heavy's 0.75 reduces damage landing on its shield. The spec calls armour a *health* factor. Recorded, not changed.

**Unchanged:** every weapon's falloff window still differs from spec (AR-01 120/320 vs 90/240, MR-07 250/600 vs 150/350, LMG-12 130/420 vs 85/230, P-01 60/250 vs 55/170, SG-04 25/90 vs 22/75). Reload path unverified; SG-04 is one 96-damage hit, not eight pellets.


## Build 459 — falloff aligned, long-range damage not decomposed
Every weapon's falloff window and minimum now matches spec (AR-01 90/240 min 0.55, P-01 55/170/.50, SG-04 22/75/.25, MR-07 150/350/.70, LMG-12 85/230/.50, SMG-03 45/150/.40). Previously all five carried wider windows and no `falloffMin` at all, so the code silently used its 0.6 default.

Measured: at 12 studs `LastDamage = 18` (16.2 after the 0.9 armour factor). At **199 studs a hit dealt 30.32** — above the base 18, so a weak-point multiplier outweighs the falloff loss. The two were **not** decomposed; which part was struck and what `weakMultiplier` returned were never read.

**Harness:** teleporting the player without `Anchored = true` put them back at the station mid-measurement (744 studs). Anchor both the player and the target before any ranged test, and search eight directions to find a clear line — the compound has no straight 60-stud sightline.

**Still unmeasured:** falloff *behaviour* at 60/240/300 studs, any shot past the floor, and every reload.


## Verified at build 460 — falloffEnd was dead config; reload works
**The 30.32 is explained.** `weakMultiplier("Head")` is 2.0 and torso 1.0, so 30.32 / (18 x 2) = 0.842 falloff at 199 studs. Neither the new window (0.673) nor the old one matched — because `CombatService.fire` computed `span = weapon.range - falloffStart`, i.e. **400 - 90 = 310**, not the authored `240 - 90 = 150`. Recomputed with the real span: **0.8418**. Three decimals of agreement.

So `falloffEnd` was never read: every weapon's curve was silently stretched to `range`, ~2.5x wider than authored, and aligning `falloffEnd` at build 459 changed nothing. Fixed to use `falloffEnd` with a `range` fallback.

**Reload verified:** ammo `27 -> 26 -> 25 -> 28`, one AmmoUpdated at completion, elapsed 1.88 s against 2.1 s configured (class/augment factor, not decomposed).

**Not verified:** the corrected curve at range — two 200-stud shots missed because origin/aim drift between the positioning call and the client fire. Build an open lane before claiming falloff.


## Verified at build 461 — falloff confirmed; bosses were blocking sightlines
The "missing" long shots of build 460 were not missing: a **Bastion Walker** left over from an elimination mission was standing in the lane (`firstHit = BastionWalker`). `EnemyService.clearAll()` only cleared `actors`, and bosses live at the workspace root, so they survived every mission change. `clearAll` now destroys `Workspace.BastionWalker` and `Workspace.HighMarshalVeyr` too (verified: present → destroyed).

**Falloff measured:** one shot at **226 studs** gave `LastDamage = 10.674` against a predicted **10.66** for window 90/240 min 0.55 on a base of 18. Two-decimal agreement, which confirms the `falloffEnd` fix, the authored window and the curve shape.

**Client/server position agreement:** player z = −7, target z = −107, both sides read 99–100 studs — teleport replication is fine; the earlier misses were obstruction.

**Unmeasured:** the 0.55 floor beyond 240 studs — there is no clear line past 270 in the relay compound.


## Verified at build 461 — falloff window, curve and floor
AR-01 through the real fire path: **18** at 12 studs, **10.674** at 226 (predicted 10.66), **9.90** at 299 = exactly `18 x 0.55`. The clamp holds, so start, slope, end and floor are all measured.

**Technique that unblocked it:** the compound has no ground sightline past ~226 studs (every 260–320-stud attempt hit `Workspace.Terrain`, and lifting 10–100 studs made the ray start inside terrain). Moving **both** target and shooter to `lz.Y + 220` in open air gave a clean 299-stud line — first hit `ActiveActors.Rifleman.Torso`.

**Harness fact:** `TerrainService.groundSurface(x, z)` returns a **number** (height), not a Vector3; `ground + Vector3.new(...)` throws.

**Still untested:** shotgun pellets, launcher radial falloff, beyond-max-range rejection, the 2x head multiplier in practice, and the other five ballistic weapons.


## PAUSED by owner for a PC restart — 2026-11-24T23:05Z (place 461)
`.goal/PAUSE` written. No code edits are in flight; playtest stopped and the place saved.

### Found this batch, not yet recorded in the ledger
**Many "misses" were unqueryable parts.** Enemy models contain two `Head` parts — one `CanQuery = true`, one `false` — and the `Root` (the model's PrimaryPart) is `CanQuery = false`. Aiming at `PrimaryPart` sends the ray straight through the enemy. Aim at `Torso`, `ChestPlate` or the queryable `Head` instead.

**Weak multiplier is name-based, not geometric.** `weakMultiplier` returns **2 for the part literally named `Head`**, and **1 for `Visor`, `Torso` and everything else**. A shot at the head silhouette usually lands on `Visor` (in front of the head), which is a 1× hit — measured 17.58 at 98 studs, exactly the torso value.

### Measured before the pause
| Shot | Distance | `LastDamage` | Predicted |
|---|---|---|---|
| Torso | 99 | **17.532** | 17.51 |
| Visor (aimed at Head height) | 98 | **17.582** | 17.5-ish |
| Head-part ray, from 56 studs above/behind | — | not fired yet | — |

The last line is where I stopped: the raycast from above **does** reach the named `Head` part at 56 studs (`firstHit = …Rifleman.Head`), but the shot was never fired.

### Next action when resumed
1. Fire from that above-the-head position and confirm `LastDamage ≈ 36` (18 × 2 with falloff 1 inside 90 studs). That closes the 2× weak-point claim for `S04-WPN-AR01` / `S04-022`.
2. Then test beyond-max-range rejection (fire at 400+ studs in the aerial lane) and SG-04 pellet behaviour.

## Defects fixed this session
1. `ObjectiveService` had no elimination builder at all — elimination deploys fell through to `buildRelay`. This was the `targets=0` null result recorded at pause time.
2. Elimination tracker started before `objective` was assigned, so it exited on its first iteration; now started from `setup` with a generation counter.
3. Bosses leaked across deployments because `EncounterDirector.reset` only swept models with a `Humanoid`; measured five `BastionWalker` models after five deployments. Reset now spares `GF_ObjectiveTarget` and `setup` destroys stale tagged targets; `beginMission` skips the optional field boss for `ELIM_WALKER`.
4. `conqEnterStage(4)` did nothing, so Thronefall's command-node capture advanced the counter without completing (measured `stage=4 complete=false`). Fixed and re-verified.

## Known gaps in the new content
- Hold/defend stages have **no failure condition** and do not pause when the squad leaves (`S08-029`, `S08-031`).
- No target marker system anywhere (`S08-033` MISSING).
- Thronefall's "breach" is a three-guard clear, not a fortification with HP.
- Missing authored stages: commander's optional relay, Walker's "secure battlefield", Talon's "linked encounter", Foundry's turret dependency.
- Kills in all tests were applied via the `Dead` attribute that `CombatService` writes; weapon → damage → kill was not re-exercised. Solo only.

## Next highest-value work

1. **Hacking cancel extras** (`S08-040`): explicit exit input and a terminal mutex for two players on one console.
3. **Target markers** (`S08-033`) remain MISSING across every mission.
2. **Hacking subsystem** (`S08-036`–`S08-043`) — referenced by every authored variant that says "hack console"; nothing exists yet.
3. **Target markers** (`S08-033`) — affects every mission.
4. Defense object HP + absence pause (`S08-029`, `S08-031`).

## Environment
`.goal/PAUSE` absent. Studio in Edit mode, place saved at 385, HEAD includes this batch after commit.
