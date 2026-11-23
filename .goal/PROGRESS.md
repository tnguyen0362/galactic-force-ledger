# GALACTIC FORCE — Progress Ledger

Place: `Playtest1` (placeId 120646942844931), Studio `586a4e54-321f-4609-aee4-e09dbc1e269c`
Saved: version 56 (TeamCreate). Boot: `config check PASS (369 assertions)`.
Eval: `.goal/evals/mission_geometry.luau` → **10/10 passing** (paste into `execute_luau`, edit mode).

## 2026-11-22 (resume) — preflight + harness trap

- Tools answer: `list_roblox_studios` -> 1 Edit instance `Playtest1`; `execute_luau` (Edit) returns values;
  `get_console_output`, `start_stop_play` loaded. Studio `586a4e54-...`, mode Edit, persistedToCloud true.
- World present: `GF` = 30 source containers (25 services incl. `SectorBuilder`, `OutpostService`,
  `EnvironmentDressing`, `EnemyAnimation`; `Test/CheckRunner`; `Main`; `Mission`).
- **NEW harness trap (F4): edit-mode `require` cache is stale and cannot be busted.** In one call,
  `ReplicatedStorage.GF.Shared.Remotes.Source` contains 44 names incl. `InteractRequest`, but
  `#require(...).Names == 24` (stops at `DialogueEvent`). Rewriting `m.Source` (noop, append, restore)
  leaves the cached instance at 24. So `require` in edit mode serves the *first* version loaded this
  session; only `Source` text and fresh play-session VMs are truthful. Verification rule change:
  authoritative checks run in a **play session**, never via edit-mode `require`.
- Consequence: edit-mode `CheckRunner.run()` = `{ok=false, passed=329, failed=8}` with 8
  `unregistered remote in folder` errors — an artefact of the stale cache (registry really has them).
  Re-verified in play session: 369 assertions PASS, so the 8 failures were **not** a real bug.

## CHECK-BOOT — PASS (re-verified play session, fresh VM)

- `start_stop_play(true)` -> console: `[GF] boot: config check PASS (369 assertions)`,
  `[GF] boot: services online (persistence=datastore)`, `[GF] boot: 12 remotes ensured`
  (12 = only the missing ones; registry holds 44 names + 2 functions).
- No `[GF]` errors/warnings. The only red lines are from a third-party cloud plugin
  (`cloud_12199271470.weapon system plugin`, `Game is not a valid member of ReplicatedStorage`), not GF code.
- Bonus: `[GF] profile ready 1889759131 credits=2250` — profile read back across sessions (was 900 after
  the last ledger entry), so persistence keeps accumulating.

## Open

- [x] Combat VFX pass: muzzle flash, impact sparks/decals by surface material, shield-break.
      Built + unit-verified (pool of 40 emitters, no leak over 200 impacts).
- [x] Audio pass: spatialised weapon/impact/shield/ambient cues. Zero uploads — engine
      `rbxasset://` sounds re-pitched, 14-voice pool, per-event audit counters.
      Live-verified cues: `ambient_wind` loop, `land`, `ui_confirm`, `enemy_death`,
      `player_hurt`, `objective_done`.
- [x] Verify rewards persist: credits 2250 before a run → 2700 after a completed run, read back
      by a fresh server (`[GF] profile ready ... credits=2700`).
- [ ] Input-path cues still unobserved: `rifle_fire`, `hit_flesh`, `hit_shield`, `reload`,
      `reload_start`, `ui_click`, `footstep`, `mission_fail`, `extraction_hum`, `relay_hum`.
      Tooling cannot inject input (a fresh `Input` module instance is not the live one), so these
      need either a test seam or a human run. Counters exist: `SoundService.GFAudioVoices` attrs.
- [ ] Device/perf pass vs 30 FPS Xbox One target; instance streaming settings.
- [ ] `.goal/DONE` only after a human-visible quality review — `screen_capture` cannot judge art.

## Done — full mission loop verified live (client remote → server → attributes)

- [x] Deploy → walk 228 studs → arrive **3.8 studs** from terminal (was stuck at 24).
- [x] `InteractRequest("Relay")` → `GF_ObjectiveComplete = true`, health 100.
- [x] `ExtractionRequest` → 45 s countdown → ship lands at LZ → board →
      `GF_ExtractionState = "complete"`, `GF_InMission = false`.
- [x] `TerrainService.groundSurface` raycast authority; relay seated on terrain
      (terrain 26.0 / relay pivot 27.4 / terminal 28.5, was 26 studs underground).
- [x] `GF_LZ` published at deploy; ship lands at mission site (was spawning at station, Y≈824).
- [x] Corridor grading in the terrain sampler: 11-stud spine corridor easing over 30 studs.
- [x] `INTERACT_RANGE` 14 → 16 so the terminal clears the tower collision envelope.
- [x] Authored R15 rigs with 15 joints; `HipHeight` −0.2528 → 3.21; locomotion verified
      (foot swept −1.63 → +1.64 studs).
- [x] Enemies clone `AscendancyTrooper`, 4/4 rigged, feet gap 0.00, walk phase advances.
- [x] Outpost: 11 wall bays + gate gaps at ±Z, 4 watchtowers, causeway, barricades, crates.
- [x] Palette unification: `ArtService.reskin` clears `TextureID` and strips baked
      `SurfaceAppearance`/`Decal` children, so one authored palette governs every imported mesh.
      Ascendancy energy moved to cold cyan (96,214,232), was saturated orange (255,150,60).
- [x] Outpost compound levelled: terrain plateau (`FillCylinder` air + rock) under the ring; all
      30 wall modules and 4 towers placed at one Y. Wall Y spread **0.0 studs**, was 13.0.
- [x] Cliff dressing clustered: **56 pieces in 16 outcrops** of 2-4 sharing an orientation
      (scale 0.16-0.38 of the mesh), replacing 46 uniformly scattered singles at 0.5-0.95.
- [x] Distant ridge ring: 9 ridges, tops **57-89 studs** at 576-650 studs from centre. Was a
      214-stud-wide mesh reading as a dome that filled the sky behind the outpost.
- [x] Boot guard: `Main` creates `workspace.ActiveActors` before any service runs. A missing
      container made `ArtService.place` throw and abort the entire world build.

## Harness notes that cost time

- **`screen_capture` cannot judge colour.** It drops Lighting post-effects (proven: a pure-red
  `ColorCorrection` control rendered grey) and stamps a cyan cast that survived a full lighting
  rewrite. Use it for geometry/composition only; verify palette values numerically instead.
- **Re-patching a module by string surgery duplicates code.** Inserted multi-line Luau with
  literal `\t` escapes produced a second `ArtService.reskin` body and a syntax error at line 81.
  Always `pcall(require, module)` in the same call as the patch.

- **Script edits made while a play session is running are discarded when it stops.** Patch in
  edit mode, `save_place`, then play. This silently ate four patches once.
- `execute_luau` in a play session gets a fresh VM per call, so `require`d module state there is
  a *different instance* — inspect live state through workspace attributes or remotes.
- `ServerScriptService` is not visible from the `Client` datamodel.
- Dead remote names exist alongside live ones: `RequestExtraction` (nothing listens) vs
  `ExtractionRequest` (the real one); `RequestFire` vs `FireWeapon`.

## 2026-11-22 — perf audit + VFX verification (play session)

Pre-commit: verify VFX via pooled-emitter counts + beam state; falsifier = 0 emitters created or
count grows linearly with emissions.

- **Perf headroom measured** (`execute_luau` edit mode): 93 BaseParts total of which **84 MeshParts**
  (9 primitive Parts), 4767 instances, 60 `SurfaceAppearance` (stripped at runtime by `reskin`),
  4 Humanoids, **0 PointLights, 0 ParticleEmitters, 0 Beams, 0 Trails** in authored content.
  Streaming on, minRadius 64, targetRadius 1024. Geometry is nowhere near a 30 FPS risk.
- **Correction — the VFX module is not broken.** My first probe reported 5 failures; the fault was
  my call signature (the module's API is `muzzle(pos: Vector3, dir: Vector3)`,
  `impact(pos, normal, materialName, shielded)`, `shieldBreak(pos, normal)`, `death(pos)`),
  not the code. Re-ran with correct args: 10 hosts, 14 beams, 40 pooled emitters, **0 errors**,
  tracer enables exactly 1 beam, muzzle lights 4 host PointLights, 200 impacts leave the emitter
  count at 40 → pool does not leak.
- **Verification level: unit + static, NOT live.** `tryFire` is a module-local function and
  `execute_luau` cannot inject input, so firing the `FireWeapon` remote directly exercises the
  server only, not the client VFX path (`Weapon` lines 124-130). Live trigger remains unverified.

## 2026-11-22 — audio layer (v61, verified live)

Pre-commit: verify by listening through a client probe — voices observed in `GFAudioVoices` /
`GFAudioAnchors` / `Loop_*` while the real gameplay code runs; falsifier = event fires in code but
no `Sound.IsPlaying` is observable.

- [x] `StarterPlayerScripts.GFAudio` built (ModuleScript, 165 lines): 15 events + 3 loops, 14-voice
      round-robin pool with per-voice spatial anchors, 0 uploaded assets (engine `rbxasset://`
      sounds re-pitched). Syntax-clean under `loadstring`, loads with **0 errors**.
- [x] `StarterPlayerScripts.GFAudioRuntime` built (LocalScript, 122 lines): ambient loop, footsteps,
      jump/land, hurt, death → `mission_fail`, mission start confirm → `objective_done`, UI clicks.
- [x] Wired into gameplay: `Weapon` emits `rifle_fire` on shot, `hit_shield`/`hit_flesh` on impact,
      `reload_start`/`reload`; `VFX.death` emits `enemy_death`. All 4 modules `require` clean.
- [x] Live play, deployed mission, audible through the client probe: `Loop_ambient_wind`,
      `snap.wav` (footsteps), `action_get_up.mp3` (land), `electronicpingshort.wav` (mission confirm).
      Weapon path: 13 shots in 1.2 s with `metal.ogg` + `impact_water.mp3` observed. 0 GF errors.
- [x] Bug: footsteps never fired — `Humanoid.MoveDirection` is permanently 0 here (212 frames,
      19 studs travelled, 0 moving). Gait now integrates `AssemblyLinearVelocity`, stride 3.0 studs.
      Verified 5 steps/17 studs, 6 steps/20 studs.
- [x] Bug: duplicate `GFAudioVoices` folders when the module is instantiated twice (tooling context
      vs game context) split the pool and hid voices from probes. Module reuses an existing folder.
      Verified: 1 folder in `SoundService`.
- [ ] Gap, not claimed done: UI-click cue, `enemy_death`, and `objective_done`/`mission_fail`
      transitions are wired and syntax-clean but were **not** observed live (no real kill, no
      win/loss executed). Needs a start-to-finish playthrough.

## 2026-11-22 — live run: close the 3 unobserved cues + persist check

Pre-commit: drive one complete operation from a Client VM and read three things at once —
(a) server attributes `GF_ObjectiveComplete` / `GF_ExtractionState` / `GF_LastPayout`,
(b) `SoundService.GFAudioVoices` children with `TimePosition > 0`, matched to the cue ids
`enemy_death`, `objective_done`, `mission_end`,
(c) stored profile credits before vs after the run.
Falsifier: the gameplay event happens (enemy dies / objective flips / extraction completes) but the
matching Sound never advances past `TimePosition 0` → the client wiring is broken in the live path and
the cue stays unverified, reported as a bug rather than a pass.

## 2026-11-22 — live run result (play session, real remotes, real server)

Commands: `start_stop_play(true)` → Client-VM `execute_luau` driving `RequestDeploy`,
`EquipWeapon`, `FireWeapon`, `InteractRequest`, `ExtractionRequest` → read `workspace` attrs +
`SoundService.GFAudioVoices` audit attributes.

- **Kill verified.** Rifleman 120 hp → **0** in **6 shots** (22 dmg each, AR01).
  `workspace.GFDebug` → `Received=6 Accepted=6 Hits=6 TotalDamage=132 LastKill=Rifleman`.
- **`enemy_death` cue fired** — `count_enemy_death=1` for exactly 1 kill (was the unobserved gap).
- **`objective_done` cue fired** — `count_objective_done=1` when `GF_InMission` went true→false.
- **Combat hurt path live** — `count_player_hurt=14` from hostile fire while standing in the open.
- **Full loop closed**: `GF_ObjectiveComplete=true`, `GF_ExtractionState=complete`,
  `GF_InMission=false`, `GF_LastPayout=ROBLOXISUS101:450`.
- **Persistence verified across a server restart**: boot read `credits=2250`, run paid +450,
  stop → start → `[GF] profile ready 1889759131 credits=2700`.
- Cue counters observed this run: `ambient_wind=1 loop_ambient_wind=1 land=5 ui_confirm=1
  enemy_death=1 objective_done=1 player_hurt=14`.

### Corrections to my own probes (three bad readings, all mine, no code bug)
1. I probed `AscendancyTrooper` (the art mesh child) for `Health` and concluded enemies were
   unkillable. The enemy root is the `Rifleman` **Model** carrying `GFEnemy`/`Health`; the art mesh
   is a child. `CombatService.damageEnemy` correctly returned `false` for the child.
2. I read `GFAudioVoices` **children** and reported "audio never played". The audit counters are
   **folder attributes** (`count_<event>`), which the module has had all along.
3. I treated `GF_ExtractionState` as a countdown source. It is only ever `idle`/`complete`/`failed`;
   `publish()` fires the `ExtractionState` remote instead. Countdown lives in that payload.
Also: `DataStoreService:ListKeysAsync()` returned 0 keys while the profile demonstrably persisted —
treat ListKeys as unusable here and verify persistence through the boot line instead.

### Still unverified (do not claim)
`rifle_fire`, `hit_flesh`, `hit_shield`, `reload`, `reload_start`, `ui_click`, `footstep`,
`mission_fail`, `extraction_hum`, `relay_hum`. All are reached only from the client input path
(`tryFire` under `RunService.RenderStepped`). A tool VM cannot drive it: `require(Input)` returns an
instance whose `setHeld("Fire", true)` leaves `Weapon.getState().firing == false`, i.e. not the live
module. Static check passes (each `Audio.play` call site exists in `Weapon`/`GFAudioRuntime`), but
static is not live.

## 2026-11-22 — CRITICAL: the player could not move at all (fixed, v65)

Pre-commit: press W through real injected input and require a position delta; falsifier = the
humanoid stays put while `UserInputService:IsKeyDown(W)` is true.

- **Bug:** `StarterPlayer.StarterPlayerScripts` had no `PlayerModule`, so the place ran with **no
  ControlModule and no CameraModule** — no WASD, no mouse-look, no jump. Evidence: `PlayerScripts`
  contained only GF scripts + `RbxCharacterSounds`; `game:GetDescendants()` in Edit mode has **no
  PlayerModule anywhere**; 2 s of held W produced `AssemblyLinearVelocity = 0,0,0` and
  `gf_moving = 0`. This is also the true root cause of the old "footsteps never fire" bug: with no
  controls, `Humanoid.MoveDirection` could never be anything but 0.
- **Fix:** new `StarterPlayerScripts.Controller` (LocalScript, 7.3 KB) — camera-relative movement
  (WASD/arrows, gamepad `Thumbstick1`, touch stick), orbit camera (RMB or touch drag, right stick,
  wheel zoom 8-12), and the action bindings that had **no listener at all**: `Jump`, `Sprint`,
  `Dodge`, `Ability1`, `Ability2`. Bindings go through the shared `Input` module
  (`Input.onPress/onRelease`), so keyboard, gamepad and the HUD's existing touch buttons all reach
  one code path. `Fire`/`Reload`/`SwapWeapon` stay owned by `Weapon`; `Interact` stays owned by
  `MissionHUD`; the HUD already had Fire/Aim/Jump/Dodge/Reload/Ability touch buttons, so the only
  UI added here is the movement stick the HUD lacked.
- **Verified live (v65 save = v64 + v2):** W held → `z 26.1 → -45.4` in 4 s (≈17.5 studs/s =
  WalkSpeed), `gf_steps = 197`, `count_footstep = 197`; E at the relay (5.8 studs) →
  `GF_ObjectiveComplete = true`; mouse click → `count_rifle_fire = 28`, `count_hit_flesh = 28`.
- **Harness finding (cost 3 false negatives):** injected input only advances the game **between**
  tool calls. A `keyDown` + `wait` + `keyUp` inside one `user_keyboard_input` call produces no
  frames, so nothing moves. Pattern that works: `keyDown` in one call → do work (a `task.wait` in a
  later call) → `keyUp`. `IsKeyDown` is true during the whole hold.

### Still open after this
Dodge/ability/jump bindings were written in v2 and **not yet exercised live**; `hit_shield`,
`mission_fail`, `ui_click`, `extraction_hum`, `relay_hum` cues still unobserved.

## 2026-11-22 — input actions completed (v69-v70)

- **`Dodge` needed a payload.** `MovementService.doDodge` returns early unless `payload.direction`
  is a Vector3 with a horizontal component; the first binding sent nothing, so dodge silently did
  nothing. `Controller` now sends camera-flat direction (or the movement vector when moving).
  Verified: `[GF] dodge dir=0.00,0.00,-1.00 remote=ReplicatedStorage.GF.Remotes.RequestDodge
  ok=true` in the console, and the identical payload fired from a VM takes the HUD from
  `DODGE 2/2` → `DODGE 1/2` inside 0.6 s, then recharges to 2/2 at 3.5 s.
- **Abilities needed a position.** `AbilityService.cast` returns early unless `payload.position` is a
  Vector3. `Controller` now raycasts the camera look direction (220 studs) for `Airstrike` and uses
  the player's own position for `DomeShield`. Verified live: `AIRSTRIKE [Z] READY` → `74.8s`,
  `DOME [X] READY` → `54.9s`.
- **Sprint verified**: WalkSpeed `17.5 → 24.0` while `LeftShift` is held (server-authoritative
  `SprintChanged`), back to 17.5 on release.
- **Jump verified**: `[GF] action jump` and Humanoid state transitions on `Space`.

### Fixed: a downed player with no tickets left froze forever
`DownedService.redeploy` returns early when `(mission.tickets or 0) <= 0`, and the tick called
redeploy unconditionally, so at zero tickets the player stayed `downed` forever — which also blocked
dodge, abilities and any damage-based progression. New `DownedService.reinforceOrFail` redeploys while
tickets remain and calls `DownedService.failMission` at zero: resets vitals, announces
`MissionEvent{kind="fail"}`, calls `ExtractionService.finish(false)` (which sets
`GF_ExtractionState="failed"`, clears hostiles, grants the failure payout) and returns the player to
the station. `GFAudioRuntime` now plays the `mission_fail` cue on that event.
**Verification level: static + syntax only.** The branch could not be exercised live because tickets
live in the *live* `State` module, and a tool VM gets a fresh module instance (`State.getMission()`
returned `nil` while `GF_InMission` was true), so tickets cannot be set for a test. Recipe for a human
run: deploy, get downed 6 times without redeploying (tickets start at 6), the 6th must return to
station with `GF_ExtractionState="failed"` and one `mission_fail` cue.

## 2026-11-22 — shields existed only in config (fixed, v73)

- **Enemy shields were never instantiated.** Every archetype has `shield` in `Configs/Enemies`
  (Scout 30 … Bastion Walker 400), but `EnemyService.buildModel` only set `Health`/`MaxHealth`, so
  models carried no `Shield`. Consequence: `Weapon`'s `shielded` test
  (`model:GetAttribute("Shield") or 0 > 0`) was always false, which made the `hit_shield` cue and the
  shield-break VFX unreachable. Verified before the fix: a live Scout had
  `Health=80 MaxHealth=80` and no Shield attribute.
- **Fix:** `buildModel` sets `Shield`/`MaxShield` from the def; `CombatService.damageEnemy` now soaks
  damage into the shield first, records `ShieldBrokenAt` at zero, and only then touches health.
  Verified after: live Scout reports `Shield=30 MaxShield=30`; `play("hit_shield")` increments
  `count_hit_shield`; `VFX.impact(pos, n, "Metal", true)` and `VFX.shieldBreak(pos, n)` both return
  clean with the pool at 38 hosts / 40 emitters.
- **`extraction_hum` / `relay_hum` were dead cues** — defined in `GFAudio`, never started by anything
  (`startLoop` was only called for `ambient_wind`). `GFAudioRuntime` now starts/stops `relay_hum`
  within 26 studs of a `GFInteract="Relay"` part and `extraction_hum` while an `ExtractionDropship`
  exists, with transition guards so the loop is not restarted every tick.
  Verified live: standing at the terminal → `Loop_relay_hum IsPlaying=true`, `count_loop_relay_hum=1`.
  `extraction_hum` not yet observed (needs a dropship in the same session).
- **Solo redeploy dropped the player on the orbital station.** `DownedService.redeploy` anchors to
  another player when one exists; solo it had no anchor, so `LoadCharacter()` spawned at the station
  750 studs away while the mission stayed live. Now falls back to `workspace.GF_LZ`.
  Verified live: after a down, hp 100 at `z≈114` (the LZ) instead of `y≈765`.

### Cue ledger after this run (live unless marked)
Verified live: `ambient_wind`, `relay_hum`, `land`, `jump`, `footstep`, `ui_confirm`, `rifle_fire`,
`hit_flesh`, `reload`, `reload_start`, `enemy_death`, `player_hurt`, `objective_done`.
Verified at module level only: `hit_shield` (trigger needs a shielded enemy in front of the camera).
Still unobserved: `ui_click`, `mission_fail`, `extraction_hum`.

### Probe error #4 (mine, again)
`VFX.impact(..., true)` reported `attempt to index nil with 'CFrame'` and I nearly logged it as a
shield-VFX bug. Cause: a fresh module instance in a tool VM has no pools until `VFX.init()` runs, so
`hostFor()` returned nil. After `init()` all three VFX paths return clean. Rule: call `init()` before
probing any pooled module.
## 2026-06-14 12:10 — in-mission HUD proven; three lighting/build defects fixed (v103)

- `StationArt.buildShell` threw on `ceilingY` (undefined) at the lamp anchors and aborted the shell build on every
  call — this is why the war table was missing from the built station. Replaced with `WALL_H - 3`.
- Mission sky: blanking `Skybox*` textures yields a magenta nothing-skybox; mission preset now destroys the Sky.
- Mission atmosphere 0.34/0.6 cyan-washed everything; now 0.14/0.28 again with warmer colour.
- Mission ambient raised 96/92/84 -> 122/116/104 so the avatar is not a silhouette.
- Crosshair 6x6 dot -> 4-tick reticle; vitals block got a dark plate because the shield label sat on sky.
- Proof: V100_01, V101_01 (ammo 28->20), V103_01. LC-024 PARTIAL -> PROVEN.
- Captures taken with the place saved at v103; next blocking item is the missing objective waypoint.

## 2026-06-14 13:05 — station interior pass + a real gate failure fixed (v126–v131)

- Window bays were holes with nothing behind them. Added `OrbitVista` (built from the averaged
  `WindowBay` normal, so it follows the shell if the bay moves): planet, moon, three freighter
  silhouettes. `SmoothPlastic` at ClockTime 0.2 rendered the planet as a black disc, so the bodies are
  `Enum.Material.Neon`, which reads from inside regardless of sun angle.
- Windows had no glazing: added `WindowGlass` (SmoothPlastic 0.93 — real `Glass` at 0.88 darkened the
  starfield to nothing) plus three mullions and a transom per bay.
- The hangar was too dark to read: fixtures were 15 PointLights at 0.95 brightness / 46 range. Now
  2.6 / 85, and station ambient 134 -> 206. Walls (graphite 58,64,72 albedo) finally render as surfaces
  instead of silhouettes (V130_01, V131_01).
- `ServicePanel` used `CorrodedMetal` at steel grey, which renders as red-black rust blotches on the
  side walls and read as noise/magma in every capture since V120. Now DiamondPlate at 96,102,112.
- `Sky.StarCount` 2600 showed roughly one star through a 6-stud bay; raised to 20000.
- **Gate failure found and fixed**: `RequestReturn` was created ad hoc inside `StationService.start`
  instead of coming from the shared registry, so `GF.Check` failed with `unregistered remote in folder:
  RequestReturn` (369 passed / 1 failed). Registered it in `Shared.Remotes.Names`, deleted the ad-hoc
  creation block, and the debrief RETURN TO STATION button now fires a registered remote.
  After: **371 passed / 0 failed**.
- Lesson: instance/Source edits made while Play is running are discarded when Play stops. Two of the
  edits above were silently reverted this way before I noticed; always stop Play before editing.

## Iteration 22 — the player is not a grey doll any more, and the deck is not a checkerboard (v132–v135)
- **Player rig had no textures at all.** Runtime check: `GF_Rigged=true`, every body part is a
  `MeshPart`, and `texturedParts = 0` — no `TextureID` on any of the 15 parts, colour flat 0.64 grey.
  So the authored soldier rendered as an untextured mannequin (V132_01). `AppearanceService.dress`
  skipped it because `GF_Rigged` was set, which is only correct while a rig carries its own armour art.
  `dress` now skips a rigged character **only if it has at least one textured MeshPart**, and treats a
  texture-less rig as one that needs the kit.
- **The kit was authored for classic R15 proportions** (head 2 studs wide) but the shipped rig head is
  **2.27** and its torso 2.23. Added a module-local `kitScale`, set in `dress` from `head.Size.X / 2`,
  applied to every plate size and offset (offsets are translation-only `CFrame.new`, checked: 0
  `CFrame.Angles` in the file). Result: 12 plates fitted at 1.13× (V133_01_dressed_trooper).
- **Deck read as holes.** `FloorPlate` used `STEEL`/`GRAPHITE` — 0.53 vs 0.23 albedo — so two thirds of
  the deck was near-black and at eye level it looked punched through. Floor-specific shades
  `DECK_DARK 0.38` / `DECK_LIGHT 0.56` now vary 1 plate in 3: 70 plates, 33% light share, seams visible
  (V133_02_deck_contrast).
- **War table was a black silhouette.** Every part of it sat at 0.08–0.22 albedo, so the room's focal
  point read as a slab with a blue ball. Base 0.08→0.34, top 0.22→0.51, hologram navy→cyan
  (96,214,255) at 0.8 transparency, globe teal, and one 1.6-brightness / 36-range `PointLight` inside
  the hologram (V135_02).
- **`WindowGlow` blew out.** A 52-stud neon sill strip at 0.3 transparency bloomed into a pale green
  slab across the whole window bay (V135_01). Now 0.2 thick at 0.62 transparency.
- **Source control exists now.** The project directory had no git repository — `git` was resolving to
  `C:/Users/tnguy`, whose history is unrelated trading code. `git init` here, initial commit `4427aa7`,
  so build ledgers and evidence manifests are auditable per V3-03.
- **Self-check unchanged and green after all of it: 371 passed / 0 failed / 0 errors** (`GF.Test.CheckRunner.run`).
- Place versions: v132 (appearance), v133 (deck), v134 (war table), v135 (window glow).

**What still looks wrong in V135_02** (see VISUAL_REVIEW.md): the window bays are still black rectangles —
no stars are visible through the Sky despite `StarCount = 20000`; the war table has no floor ring and its
planet is a featureless ball; the far console area is still a dark slab with unreadable text; the trooper
has no glove or boot geometry.
