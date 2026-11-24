# WORK_STATE — last verified 2026-11-24, place version 435

## Current build
- Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, place `Playtest1` (placeId 120646942844931), saved as **version 435**.
- Spec `.goal/GOAL_2026-11-24.md`; ledger `REQUIREMENT_COVERAGE.csv` **815 rows, 81 populated, 748 UNKNOWN**.
- Ledger state: PARTIAL 52 | VERIFIED 14 | IMPLEMENTED_UNVERIFIED 1 | VERIFIED 0 | OWNER_ACCEPTED 0.

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
