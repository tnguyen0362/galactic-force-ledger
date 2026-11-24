# VISUAL REVIEW — GALACTIC FORCE: COUNTEROFFENSIVE

Session: 2026-11-23, Studio `Playtest1` (placeId 120646942844931), saved **v73**, PC viewport 1100×680.
Captures were produced by the Studio MCP `screen_capture` tool during this session. That tool returns
the image inline to the agent and **does not write a file to disk**, so each capture is identified by
its capture id rather than a path. This is recorded as an evidence-storage limitation, not a claim of
a stored artefact.

| capture id | when | what it shows |
|---|---|---|
| `AUDIT_01_station_spawn` | station, default player camera at spawn | the first five seconds of the hub |
| `AUDIT_02_station_wide` | station, requested wide camera | request returned the identical frame — the `Controller` script owns the camera every frame, so the requested camera position was ignored. Recorded as a tool/architecture limitation. |
| `AUDIT_03_mission_landing` | mission, player at insertion pad | planet vista + HUD |
| `AUDIT_04_outpost_relay` | mission, player teleported 34 studs from relay | outpost, enemies, relay |

---

## 1. `AUDIT_01_station_spawn`

- **Scene / camera**: player camera at spawn, `pos ≈ (0, 766, 52)`, war-table panel open, character at frame centre-left.
- **Goal aesthetic**: "interior of a real military spacecraft with windows into space and a planet outside" (V2-23); first five seconds must frame a panoramic window with a curved planet and atmospheric limb (MICRO-001..003).
- **What looks wrong**:
  1. There is **no window and no planet**. The background is a black void with cyan emissive strips.
  2. The floor is one flat saturated-blue surface with a single cyan light band; no plates, seams, deck markings, rails or ribs.
  3. The character is a **default-avatar part stack** in blue/white — not a Galactic Force soldier with helmet, chest plate, gloves, boots and energy module.
  4. The war table is a **text panel floating in the void**, not a physical dais with a holographic planet.
  5. Everything is one hue (cyan/blue). No value hierarchy, no graphite/steel/off-white palette from the art bible.
  6. No signage, no crew, no hangar, no deployment bay, no armory racks — the space is empty.
- **Severity**: blocking (fails MICRO-001..005, 008..016, LC-014).
- **Action to repair**: author the `GFS VANGUARD` concourse: three contiguous angled window bays with mullions and rail, layered starfield + planet limb, plate/seam/rib architecture, signage, weapon racks, dispatch alcove, hangar bulkhead, 4–8 animated crew.
- **Retest screenshot**: pending (must be a new capture after the rebuild).
- **Owner disposition**: PENDING — owner has already stated the UI and graphics are unacceptable.

## 2. `AUDIT_02_station_wide`

- **Scene / camera**: requested elevated wide shot at `(70, 806, 130)` looking at `(0, 768, 30)`.
- **Goal aesthetic**: whole-hub readability, destination silhouettes for War Table / Armory / Dispatch / Bay.
- **What looks wrong**: the returned frame is **identical to capture 1**. The `Controller` LocalScript rewrites `Camera.CFrame` every `RenderStepped`, so an external camera override cannot take effect. This also means no cinematic camera or menu camera angle is currently possible without changing the control layer.
- **Severity**: high (blocks visual review of the hub as a whole, and blocks V2-23's "camera traversal" evidence).
- **Action to repair**: give the camera a state machine (gameplay / cinematic / menu) instead of a single unconditional override, then re-capture.
- **Retest screenshot**: pending.
- **Owner disposition**: PENDING.

## 3. `AUDIT_03_mission_landing`

- **Scene / camera**: player camera at the insertion pad, mission `SABOTAGE_RELAY`, `pos ≈ (0, 31, 118)`.
- **Goal aesthetic**: premium stylized low-poly Veyra-7 highland; pale dusty sky, atmospheric depth, faceted cliffs, sparse alien flora, readable outpost silhouette at 100+ studs.
- **What looks wrong**:
  1. Sky is **saturated cyan** with a **giant pale sphere** intruding at the top-left — a sky/planet dome intersecting the view. Reads as a rendering artefact, not a planet.
  2. Terrain is smooth native voxel with **green grass material**, not slate highland; boulders are **bright blue meshes** that read as plastic.
  3. The insertion pad is a **flat untextured dark-blue part** with no scuff, deck marking or drop-pod scar.
  4. The outpost is a silhouette of dark blue blocks; the relay reads as **three vertical cylinders**, not a split-spire uplink with emitter core, conduit and warning antenna.
  5. HUD is thin text with no frames or icons; "DODGE 2/2" is clipped by the bottom edge.
  6. Character is again a default-avatar part stack.
- **Severity**: blocking (fails MICRO-046..053, LC-029).
- **Action to repair**: author the planet palette and skybox, faceted cliff kit, proper landing pad, relay split-spire kit, and rebuild the HUD to V2-34 zones with iconography.
- **Retest screenshot**: pending.
- **Owner disposition**: PENDING.

## 4. `AUDIT_04_outpost_relay`

- **Scene / camera**: player 34 studs from the relay, outpost walls and four Riflemen in view.
- **Goal aesthetic**: Ascendancy compound — angular offset-chevron architecture, obsidian/bronze/ivory palette, amber-violet energy seams, tall split-spire relay, readable alien silhouettes.
- **What looks wrong**:
  1. **Colour collapse**: player, enemies, walls, relay, crates, ground glow and sky are all the same blue/cyan. Faction identity is impossible to read; a player cannot tell human from alien at a glance.
  2. Relay is a **cluster of cylinders** with a pale core — no spire geometry, no cable, no console, no warning antenna.
  3. Enemies are **blocky humanoid avatars** with a blue torso and no helmet crest, shoulder mass, alien hands or plasma weapon.
  4. Wall modules are plain boxes at varying heights with **gaps that do not meet at corners**.
  5. Ground is a **glowing cyan plate**; no terrain transition, no wear, no hazard markings.
  6. Sky dome artefact visible again as a grey sphere edge at frame top.
- **Severity**: blocking (fails MICRO-021..023, 052..053, LC-029).
- **Action to repair**: split the palette by faction per art bible (human graphite/steel/off-white/cyan; Ascendancy obsidian/bronze/ivory/violet), rebuild relay and wall kit to grid with corner modules, replace both character rigs with authored meshes.
- **Retest screenshot**: pending.
- **Owner disposition**: PENDING.

---

## Cross-cutting defects (all four captures)

| # | Defect | Severity | Requirement |
|---|---|---|---|
| D1 | Every surface is one blue/cyan hue; no value or material hierarchy | blocking | V2-26 palette, MICRO-015 |
| D2 | Default-avatar part stacks for player and enemies | blocking | MICRO-021..023 |
| D3 | Sky dome sphere artefact intrudes into every exterior frame | high | MICRO-047 |
| D4 | No station windows, planet or space vista | blocking | V2-23, MICRO-001..005 |
| D5 | HUD is unframed text; one label clipped at 1100×680 | high | V2-34, MICRO-024 |
| D6 | Camera is single-mode; no cinematic or menu angle possible | high | V2-30, V2-23 |
| D7 | No armory, dispatch, hangar or archive geometry exists to review | blocking | MICRO-008..010 |

**Reviewer note (harness):** this is a blockout, not a production scene. `screen_capture` also drops
Lighting post-effects and adds a cyan cast (recorded earlier), so absolute colour readings are
approximate — but the single-hue collapse and the sky artefact are geometry/material facts, not
post-effect artefacts, and they are visible in the frames above.

---

## V87 — Station concourse, first real interior (2026-11-22 23:4x)

**Captures:** `V87_01_station_spawn` (spawn view, bays + war table card), `V85_02_planet_probe` (planet probe), `V86_01` (glass probe).
**Built:** `ServerScriptService.GF.Services.StationArt` — concourse shell (raised deck plates, side bulkheads,
ceiling ribs, three 56-stud angled view bays with mullions/pier/spandrel, waist rail, light coffer fixtures),
hull signage (`STATION ORION`, `OPERATIONS`, `HANGAR`), orbital body `Veyra7` + `Veyra7Atmo`, transport tube.
`GF.Services.Environment` gained a `Sky` with `StarCount = 2600` for the station preset.

### Root causes found this iteration (each one produced a "the art is broken" symptom)
1. **150/150 lights were Neon at brightness 0.42** and the ceiling/floor panels were wide emitters: the whole
   room saturated to one blue-cyan hue. Fixed by dropping emissive density and moving accents to thin strips.
2. **`Lighting.Ambient` barely applies under `LightingStyle = Future`**; the room's only real light was sky IBL,
   which is why every wall read flat. Fixed with a ceiling `PointLight` rig + brighter `OutdoorAmbient`.
3. **`FogEnd = 4000`** with the planet at 8000 studs: the planet was 100% fog colour = invisible black. Fixed by
   `FogEnd = 24000` in the station preset.
4. **The place has streaming on.** A planet 8000 studs out existed on the server (423 parts verified) but was
   *never replicated to the client* — the client's `Station` folder had no `Veyra7` at all. Any vista element
   must live inside streaming range. Planet now at 900 studs, radius 420, limb crossing the window sightline.
5. **`Enum.Material.Glass` renders as a dark reflective pane from inside**, so the bays read as black panels
   even with the planet in view. Switched to `ForceField` at 0.94 transparency.
6. **`panel()` anchors centre, not top-left**: the war table card at `x = 0` rendered half off-screen. Fixed.

### What still looks wrong (V87 frame)
1. `Veyra7` is a **pale cream/yellow disc** — Neon at that scale reads as a sun, not a dusty planet. Needs a
   darker body colour, a terminator, and the atmosphere shell doing the rim light.
2. **No stars visible** in the bays — `Sky.StarCount` was set but the skybox textures may be overridden by the
   existing `Sky` instance; unverified.
3. **Blown white patch** on the deck at frame left (the light coffer strip reflecting on steel at grazing angle).
4. Player is still the **stock Roblox avatar** (purple) — MICRO-010/021 blocking.
5. War table card is a flat rectangle: no proximity gating, no holographic treatment, no crew NPCs at it.
6. Concourse is empty of people and props; no bay door, no hangar silhouette, no scale reference.
7. Character spawns facing the table with the table card covering the right third of the frame.

---

## V91 — Concourse lit, planet in frame, mission HUD leaking (2026-11-23 00:1x)

**Captures:** `V91_02_concourse` (concourse from the deck, planet in right bay), `V91_01` (accidental mission frame),
`V90_01` (planet over-scaled, room black), `V89_01` (planet as a hill behind the rail).

### Two more root causes
7. **The space skybox kills sky IBL.** The station preset swaps in a black space `Sky`, and under
   `LightingStyle = Future` the concourse was being lit almost entirely by sky image-based lighting.
   The moment the skybox textures loaded the room went to near-black with only Neon strips glowing
   (`V90_01`). Fixed with 12 ceiling `PointLight` fixtures (Range 92, Brightness 3.2) plus
   `Brightness 1.45 → 2.15`, `Ambient (118,122,128) → (158,166,182)`, `Exposure −0.15 → 0.12`.
8. **Planet scale is bounded by the bay's angular height.** The bays subtend ~12.7° from the rail, so a
   420-stud planet at 900 studs (25°) filled the aperture edge to edge and read as a green wall
   (`V90_01`). At 160 studs (≈10°) it reads as a body (`V91_02`).

### What still looks wrong (V91_02)
1. **Overexposed**: ceiling and deck are blown white again — 2.15 brightness + 12 fixtures is too much;
   target ~1.6 brightness and 8 fixtures at Range 70.
2. **No stars in the bays.** `Sky.StarCount = 2600` is set and the Sky exists (verified on the client),
   but the bays read as flat black — star size/brightness too low at this exposure.
3. **Mission HUD renders at the station**: SHIELD/PRIMARY OBJECTIVE/SALVAGE/abilities are visible on the
   concourse. Station should show station UI only (V2-34, V3-07 item 2).
4. **War table card still a flat panel** overlapping the right third; no proximity gating, no hologram.
5. **Spawn is behind the station**: `SpawnLocation` sits at `(0, 1.5, 120)` — outside the hull, z = +120 vs
   hull z ∈ [−76, +76]. Player must spawn on the concourse deck.
6. Character remains the stock avatar; no crew NPCs; bays empty of traffic.

---

## V94 — Spawn on the deck, mission HUD gated off the concourse (2026-11-23 00:41)

**Capture:** `V94_01_spawn` (first frame after join, no teleport).

### Fixed
- **Spawn was on the baseplate 760 studs below the station.** `StationService.build` (which holds the old
  `SpawnLocation` handling) is *dead code* — the live builder is `StationArt.buildShell`, and it never created
  a spawn. The only `SpawnLocation` in the place sat at `(0, 1.5, 120)`, outside the hull and below it.
  `buildShell` now defers a `StationSpawn` at `(-8, 761, 40)` on the deck, disables the legacy spawn, and
  reseats any character that spawns below the deck (character spawns at `PlayerAdded`, before the shell exists).
- **Mission HUD rendered at the station.** `StarterPlayerScripts.GFUIGate` toggles `GF_HUD` and `GFMissionHUD`
  from `GF_EnvironmentPreset`; `V92_01` shows the concourse with no vitals, `V94_01` confirms at spawn.
- Exposure dial-down from V91 landed: `brightness 2.15 → 1.62`, `ambient (158,166,182) → (138,146,162)`,
  fixtures 12 → 9 at Range 70.

### What still looks wrong (V94_01)
1. **Planet is a flat pale-green disc** with no terminator, no cloud band, no ring — reads as a UI sphere.
2. **Bays are otherwise black**: no stars, no traffic, no debris layer. Star field exists (`Sky.StarCount`) but
   is invisible at this exposure.
3. **War table card covers the right third of frame** and floats over the world with no anchor to the table.
4. Ceiling still brighter than the deck; the value hierarchy is inverted (ceiling lit, floor mid).
5. Stock avatar, no crew, empty concourse.

---

## V95–V98 — War table exists, card gated by proximity (2026-11-23 01:0x)

**Captures:** `V95_01_spawn_clear` (unobstructed spawn frame), `V96_02_war_table` (first table build, blown out),
`V97_01_war_table`, `V98_01_war_table` (current).

### Findings
- **The "GALACTIC WAR TABLE" UI described an object that did not exist.** `StationUI` drew a full deploy card for
  a table whose only builder (`StationService.build`) is dead code — a raycast and a part scan of the live
  `Station` folder both returned zero table parts. The card floated over an empty deck. The table is now built by
  `StationArt.buildShell` (base, diamond-plate top, holo plane, 6 pins, globe, rim strips, light rig).
- **Card was pinned to the screen** at 420×404 bottom-right, covering a third of every concourse frame, including
  when the player stood 70 studs away. Now gated to within 36 studs of `WarTableBase` (the table's own half-width
  is 17, so a 26-stud gate excluded standing at its edge).
- **Third lighting blow-out in three iterations, same cause:** the table `SpotLight` + cyan `PointLight` + Neon
  materials on a 9-stud `Slate` globe rendered as a white ball occluding the bays (`V96_02`). Dialled to spot 0.35/30,
  point 0.9/26, globe 6 studs `SmoothPlastic` `(34,48,62)`, holo 0.86 transparency (`V98_01`).
- **Character could not walk after the spawn reseat**: teleporting to `base * CFrame.new(-8, 5, 40)` left the
  Humanoid inside the deck (root y 760.0, `Subfloor` top 760.0). Reseat offset needs ≥ 3.5 studs above deck top.

### What still looks wrong (V98_01)
1. Table top reads as a **milky white slab** — `DiamondPlate` under the spot at this exposure has no value range.
2. **Holo globe is a flat blue ball**; no wireframe/scanline treatment, no planet texture, no pin labels.
3. **No crew, no chairs, no wall screens** — the "war table" has no one at it and nothing on the walls.
4. Bays still black: no stars, no traffic, no debris layer behind the glass.
5. Stock avatar, no faction palette on the player (MICRO-010, MICRO-021..023 still blocking).
6. Signage is tiny relative to the 200-stud hall; `OPERATIONS` is unreadable at 8 studs tall from 60 studs away.


---

## V103 — In-mission HUD live, and three defects behind the first real mission frame

Captures: `V100_01_mission_hud` (first deploy), `V101_01_firing` (three clicks), `V103_01_mission_combat` (78 studs from a hostile, facing the relay). Place version 103.

### What is proven now
- `RequestDeploy:FireServer` flips `GF_EnvironmentPreset` station -> mission and the club/combat HUD gate opens in
  the same frame: `GF_HUD` and `GFMissionHUD` both enabled, shield/objective/salvage/ability/ammo/dodge/prompt all
  populated. The gate works in both directions and is not a static layout.
- Firing works end to end: three left clicks took AR01 28 -> 20 and the reticle stayed at the aim point.

### Findings
- **`ceilingY` did not exist, and it aborted the whole station build.** `StationArt.buildShell` line 301 used
  `ceilingY - 3` for the lamp anchors; `ceilingY` is not defined anywhere in that function. Every build threw
  `attempt to perform arithmetic (sub) on nil and number`, so the shell stopped at the ceiling and the war table —
  built in the same function — never appeared. Fixed to `WALL_H - 3`. `[GF] station online` now prints, which it
  never had.
- **Blanking a Sky's six textures does not restore the default sky.** The mission branch set every `Skybox*` to `""`
  and `StarCount = 0`; at runtime all six were empty and the frame still rendered a magenta/red nebula over a black
  void (`V100_01`). The engine default only exists while there is no `Sky` instance, so the mission preset now
  destroys it. Sky went from magenta void to blue with cloud (`V102_01`).
- **0.34 atmosphere density at 0.6 haze turned the entire mission cyan.** Sky, deck, hills and rock all read as one
  teal wash. Halved density to 0.14, haze 0.28, warmed colour/decay, exposure 0.1 -> 0.0.
- **Mission ambient 96/92/84 made the player a black silhouette** against the compound deck. Raised to 122/116/104
  with outdoor 142/136/122; the avatar now reads as armour with a white chest plate.
- **The 6x6 crosshair dot was invisible** on a 1100px frame. Replaced with a 4-tick reticle + centre dot.
- **The shield label sat directly on the sky** and disappeared against the pale horizon. Vitals block now has a
  35%-transparent dark plate and a near-white label.

### What still looks wrong (V103_01)
1. **Nothing tells the player where to go.** The objective card names the relay, the relay is 200+ studs away, and
   there is no waypoint, arrow, distance readout or compass. A player who looks away once cannot find it.
2. **The hostile at 78 studs is a dark unmarked figure** — no faction colour, no silhouette read, no health or threat
   cue until it shoots. It does not stand out from the terrain shadow.
3. **Terrain grass is flat neon green** with hard black shadow wedges; no texture breakup, no ground detail near the
   player, and the cacti read as black spikes.
4. **The relay itself is an ambiguous stack of towers** — blue crystal, turrets and stanchions all similar value, so
   the "sabotage target" is not identifiable from the approach.
5. **Over-saturated cyan horizon** survives near the sun; the top-left sky still clips to pure cyan.
6. **White thighs on the stock avatar** clash with the navy armour palette (MICRO-010/021 still open).
7. SALVAGE reads `0  0  0` — three bare numbers with no labels, so it is not obvious what the three pools are.

### Next
Waypoint/distance marker for the objective (row LC-021 class), then hostile silhouette read, then terrain detail
near the player.

## V106 — Armory (station) + mission weapon readout
Frames: `V104_01_armory`, `V105_01_armory_open`, `V105_03_armory_equipped`, `V106_01_sg04_in_mission`

Right: the panel reads clearly — credits/rank header, per-weapon stats, BUY/EQUIP/EQUIPPED states. Buying MR-07 Ranger took credits 2700 → 1850 and flipped that row to EQUIPPED, so the server transaction is real, not a label. Equipping SG-04 Breacher then changed the in-mission readout to `SG04  6 / 6`, which proves the armory selection reaches gameplay instead of dying in the menu.

Still wrong:
- The station interior left of the armory is blown out — an orange-white flare plus neon-white wall wash that erases the rack silhouettes (`V105_01`). Same over-bright interior family as the concourse report; there is still no light budget for interior props.
- ER-16 Pulse Rifle row is clipped by the panel's bottom edge and the class selector sits entirely below the fold, so a player opening the armory cannot see class choice without scrolling.
- Rack geometry reads as plain boxes; the rifles on the racks are bars, not silhouettes.
- No augment sockets or inspect view exist yet, so two of the V3 armory columns have no visible surface at all.

## V108–V111 — station lighting, war-table dressing, and a capture blocker (unreviewed by owner)

**Built this pass (v107→v111)**
- `StationWarTable` service: 4 crew figures at the table (Assault/Heavy/Recon/Support accent plates) with a 20 Hz idle sway, two 16×9 wall intel screens (operation intel + live squad status), and 4 squad slots with name billboards on the table.
- `ArmoryService` + `StationArmoryUI`: full purchase/equip/class loop wired to the profile; `CombatService` ownership check closed a free-weapon hole through `EquipWeapon`.

**What still looks wrong — station concourse**
1. Exposure is not settled. V107_01 was a pure-white void (fixture brightness 3.2 × 9 + 36 lights + ambient 138). V108_01 over-corrected into a navy cave. V109_01/V111 sat between those but the deck and table top still read as pale cyan sheets rather than steel plating.
2. The room is lit almost entirely by fixtures — the hull blocks all sky/outdoor contribution, so lamp brightness is the whole exposure budget. No single value has been validated by the owner.
3. `WarHolo` (23×23 emissive plane) still dominates the table; the holo globe is now cyan but reads as a sticker, not a hologram (no scanline/parallax).
4. Crew figures are six-part primitives with no faces, weapons, or gestures. At 13 studs from camera they read as coloured boxes.
5. `GFS VANGUARD` signage overlaps the observation bay line and the planet limb sits behind it.

**Capture blocker (real, quoted)**
Every `screen_capture` after v109 returns a frame where the 3D viewport is black and only ScreenGui content draws — including a capture with the tool's own `camera_position`/`look_at_position` and one aimed straight up at a ceiling that a raycast confirmed at Y=795 (`frontHit=clear`, `ceiling at 795`). Edit mode returns an empty dark viewport with only the axis gizmo. So v109+ frames are NOT usable as visual evidence; the last trustworthy frames are **V108_01** and **V109_01**.

## V122–V123 — station hangar: the "black viewport" was a minimised window, and the player fell out of the station

**Correction to earlier entries.** Every capture between roughly v104 and v121 was recorded as "the Studio viewport renders black". That diagnosis was wrong. `screen_capture` returned a stale surface because the RobloxStudioBeta window was minimised (`IsIconic = True`). Restoring and foregrounding the window made captures work immediately with no code change. Any conclusion in `REQUIREMENT_COVERAGE.csv` that rests on "viewport renders black" must be re-tested before it is repeated.

**Player-facing defect found and fixed.** With captures working, the first real frame showed the character floating in blackness with a few cyan bars far away. The character was at Y=26 while the station mass spans Y=648–1102: the player spawned and fell ~620 studs out of the station, because no `BasePart` floor existed under the spawn point. `StationConcourse.build` now lays one 200x190 diamond-plate deck under the bay, and `StationService` deletes every `SpawnLocation` that is not `ConcourseSpawn` (via `workspace.DescendantAdded`, because `StationArt.buildShell` re-creates `StationSpawn` mid-build and a one-shot sweep lost that race).

**Second defect fixed.** The station had `Light instances = 0`. At `Lighting.ClockTime = 0.2` the interior was lit only by ambient, which is why every frame was either black or a flat blue wash. Fifteen warm ceiling fixtures with `PointLight` (brightness 1.05, range 46) now light the bay.

**Third defect fixed.** The `station` preset in `Environment` used `ambient = (120,126,138)` with `atmoDecay = (40,46,60)`, which tinted ceilings, walls and every distant surface blue — the hangar read as a nightclub. It is now `ambient = (134,132,128)`, `atmoDecay = (122,120,116)`, `brightness = 1.6`, `exposure = 0.02`.

**What still looks wrong (V123_01_hangar_tuned).**
- Ceiling fixtures clip to pure white Neon slabs; the room's brightest surface has no shape.
- Walls and window bays read black, so the "panoramic windows" look like holes punched into nothing. No planet, stars or traffic is visible through them.
- The bay between the deploy pad and the OPERATIONS terminal is empty at player scale — no crates, terminals, crew, or vehicles, so it reads as a corridor rather than a command station.
- `OPERATIONS` and `EMPTY` labels overlap and are unreadable at gameplay distance.
- The character is bright blue-violet with white gauntlets, far more saturated than the muted hangar palette.

A second `Concourse` room was built during this round and then deleted: `StationArt` already builds 374 parts of hangar (BayDoor, DeployPad, Dropship, FloorPlate, pad rings) and a duplicated shell was occluding the real station. Only the floor, lights and spawn pad were genuinely missing.

## V132–V135 — player armour, deck contrast, war table, window glow (place v135)

All captures below are Play-mode Studio captures of the shipped station, taken in the same session as
the changes (`GF.Test.CheckRunner.run` = 371 passed / 0 failed immediately after the last of them).
The `screen_capture` camera override is ignored during Play, so every frame is the real follow camera
at spawn — that is the camera the player actually loads into.

### V132_01_preflight — spawn, before any fix
- **Scene / camera:** play test, spawn pad, follow camera behind the player, station bay at ClockTime 0.2.
- **Goal aesthetic:** a lit command-bay interior with a recognisable armoured soldier and a steel deck.
- **What looks wrong:** the player is an untextured grey mannequin with peach-coloured limbs; the deck
  alternates near-black (0.23 albedo) and white plates and the dark ones read as holes; the far wall is
  a solid black band; the war table area is a black slab with a blue ball on it.
- **Severity:** blocker. The player character is the most-viewed asset in the game, and it was a default
  -looking mannequin; the deck made the ground plane ambiguous.
- **Action to repair:** texture-test the rig and dress texture-less rigs (`AppearanceService.dress`),
  scale the kit to the rig head, replace deck shades with floor-specific values, light the war table.
- **Retest screenshot:** V133_01_dressed_trooper, V133_02_deck_contrast, V135_02_station_complete.
- **Owner disposition:** PENDING.

### V133_01_dressed_trooper — player armour applied
- **Scene / camera:** same spawn camera, immediately after the appearance fix (v132).
- **Goal aesthetic:** human soldier with helmet, visor, chest armour, belt, backpack, shoulder and
  forearm plates, muted navy/steel with a cyan accent — matching the station palette.
- **What looks wrong:** the silhouette now reads correctly, but there is no glove or boot geometry —
  bare grey hands and feet stick out from the plates; the chest plate is a flat white slab with a
  printed-looking seam; the character's legs still show untextured grey between the thigh and shin
  plates.
- **Severity:** major for MICRO-022 (needs gloves/boots/energy module), cosmetic elsewhere.
- **Action to repair:** add glove and boot plates, give the chest energy module real depth (lit
  canister with a bezel) instead of a flat neon strip.
- **Retest screenshot:** V133_02_deck_contrast (same rig, wider frame).
- **Owner disposition:** PENDING.

### V133_02_deck_contrast — deck shades corrected
- **Scene / camera:** spawn camera after the deck fix (v133).
- **Goal aesthetic:** a steel hangar deck with visible plate seams and a centre line, not a checkerboard.
- **What looks wrong:** the checkerboard is gone and seams read, but bright ceiling fixtures still blow
  two bands of deck to paper white, and the plate grid is regular enough to read as tiling rather than
  deck plating. The window bays behind the barrier are pure black.
- **Severity:** minor (deck), major (windows still unreadable as space).
- **Action to repair:** reduce fixture bloom on the deck, add a floor ring around the war table, and
  give the windows something to see.
- **Retest screenshot:** V135_02_station_complete.
- **Owner disposition:** PENDING.

### V135_01_war_table — war table lit (intermediate)
- **Scene / camera:** spawn camera after the war-table light and colour pass (v134).
- **Goal aesthetic:** the War Table as the room's focal point, with a readable holographic planet.
- **What looks wrong:** the table now reads as a lit object with a cyan globe, but a **pale green slab**
  spans the whole window bay at sill height — that was `WindowGlow`, a 52-stud neon strip at 0.3
  transparency blooming out. The planet is still a featureless ball and the pins are cubes.
- **Severity:** major (the blown-out glow reads as a rendering bug).
- **Action to repair:** thin and dim `WindowGlow`; give the planet a surface treatment.
- **Retest screenshot:** V135_02_station_complete.
- **Owner disposition:** PENDING.

### V135_02_station_complete — the frame that has to be judged
- **Scene / camera:** spawn camera, place v135, 7 s after load, `371 passed / 0 failed`.
- **Goal aesthetic:** a military orbital command station: lit steel deck, armoured trooper, physical war
  table under the OPERATIONS sign, space visible through the bay windows.
- **What looks wrong (exhaustive, not a compliment list):**
  1. **Window bays remain black rectangles.** `Sky.StarCount = 20000` with the space skybox produces no
     visible stars from inside — the only "space" the player can see is the small cyan planet peeking
     over the barrier. The vista parts exist; they are not where the camera can see them.
  2. **The OPERATIONS sign text is mirrored/upside down** at this distance and half-occluded by the
     war-table rim — reads as "GEFV…" rather than "OPERATIONS".
  3. **The war table is still mostly edge-on.** From spawn you see its lit top edge and the hologram
     plane; the hologram plane reads as a white bar, not a projection.
  4. **No floor ring or deck marking around the table**, so it floats on the plate grid.
  5. **The trooper has no gloves or boots**, and the chest plate is a flat slab.
  6. **Nothing moves.** No crew, no traffic behind the glass, no flicker on the terminals.
- **Severity:** windows + signage are blocker for LC-014/MICRO-006; the rest major.
- **Action to repair:** (a) find why the Sky starfield is invisible from inside and fix or replace with
  visible vista bodies; (b) rebuild the OPERATIONS sign as a correctly-oriented SurfaceGui; (c) add a
  floor ring; (d) glove/boot plates; (e) ambient crew animation pass.
- **Retest screenshot:** none yet — this is the open item.
- **Owner disposition:** PENDING.

### V136_01_vista / V137_01_vista_planet — bays now show space
- **Scene / camera:** spawn camera, place v136 then v137, 7 s after load.
- **Goal aesthetic:** an orbital command bay whose glazing looks onto stars and the planet it orbits.
- **What looks wrong (after the fix):** stars are present but sparse and clustered in the middle band of
  each bay; the planet limb is a smooth blue arc with no surface detail beyond one belt band; the
  `Transport` is a static rectangle, so "traffic" is a still; the `OPERATIONS` sign is still partly hidden
  behind the war-table rim from the spawn camera; `EMPTY` text remains visible under the sign (mission
  state label, reads as a placeholder word).
- **Severity:** minor-to-major. The window claim (EXT-015) is now genuinely visible, but "moving space
  exterior" is still static and the `EMPTY` label reads as unfinished text.
- **Action to repair:** animate the transport on a slow loop, replace `EMPTY` with real operation state
  ("NO OPERATION SELECTED"), raise the OPERATIONS sign above the rim line.
- **Retest screenshot:** pending.
- **Owner disposition:** PENDING.

### V138_01_intel_screens / V139_01_intel_screens — war table readouts
- **Scene / camera:** player side of the war table, (0,17,14) looking at (0,14,-42), place v138 then v139.
- **Goal aesthetic:** a command table whose screens show the operation you are actually about to run.
- **What looked wrong (v138):** both screens read **mirrored** ("OPE..." reversed) because they were built
  with the default `Front` face while sitting on the player's side; the panels were 16×9 and sat below the
  ceiling beam; the slot labels said `EMPTY`.
- **v139:** screens read left-to-right, 20×11, tilted 8° toward the deck; slot labels read `OPEN SLOT`; the
  body text is derived from the armed operation and difficulty.
- **Still wrong:** at spawn distance the body text is too small to read (needs a nearer approach); the
  trooper's avatar shows bare skin at both thighs, so the layered clothing does not fully cover the legs;
  the `EMPTY`-style placeholder text still exists on the mission chip row.
- **Severity:** minor. Readable, correctly oriented, data-driven.
- **Retest screenshot:** V139_01_intel_screens.
- **Owner disposition:** PENDING.

### V140_01..05 / V141_01_flyby_bay1 — exterior traffic
- **Scene / camera:** spawn framing, left observation bay, place v140 then v141.
- **Goal aesthetic:** a command station whose glazing shows life outside, not a still photograph.
- **What was wrong (v140):** the transport was a single 18×3.5×38 box parked at one point — it never
  moved, so the "traffic" in the vista row was a prop. Replaced with a 12-part hull on a 150 s loop.
- **Two measured mistakes while fixing it:** the first pass sat at 62 studs above the deck, i.e. above the
  glazing (window opening is y 762.4–789.6), so it slid along behind the hull and was never visible; and
  the pass was at z −265, where only ~120 studs of its 830-stud path falls inside the bays' sightline.
  Now at y 20→11 above the deck and 190 studs out.
- **Still wrong:** the ship is only inside the bays' field of view for ~17% of the loop, so a player who
  looks out for twenty seconds may see nothing; the pass is dead level with no banking; the engine plume
  is a static translucent neon box with no flicker; on the centre crossing the ship passes behind the war
  table and the OPERATIONS sign; the hull reads as flat grey with no rim light against black sky.
- **Severity:** minor. The requirement ("subtle visible exterior life") is met, but the motion is
  infrequent and mechanically straight.
- **Retest screenshot:** V141_01_flyby_bay1 (ship at x −54.8, y 776.3, z −264).
- **Owner disposition:** PENDING.

### V142_01_nav_beacons — exterior hull lights
- **Scene / camera:** spawn framing facing the bays, place v142.
- **Goal aesthetic:** dim exterior navigation lights that make the hull feel real without lighting the room.
- **What was added:** 12 neon beacons — red port and green starboard at each bay jamb, white top strobes,
  three amber depth markers 120 studs out. Sine-pulsed at 8 Hz, no `PointLight` anywhere (verified 0).
- **What looks wrong:** only the red jamb beacons and the amber markers are legible from spawn; the green
  starboard beacons sit behind the mullions and disappear; the depth markers are unattached dots floating
  in the star field, which reads as a rendering artefact rather than hardware; every beacon uses one sine
  pulse, so they all breathe instead of strobing like real navigation lights.
- **Severity:** minor. The requirement (dim exterior beacons, no overlighting) is satisfied; the markers
  need mounting structure to stop looking like dead pixels.
- **Retest screenshot:** V142_01_nav_beacons.
- **Owner disposition:** PENDING.

### V143_04 / V144_01 / V145_01_armory_final — armoury alcove
- **Scene / camera:** walked the trooper to the left alcove (`x ≈ -84`), place v143 → v145.
- **Goal aesthetic:** an alcove a player crosses and immediately reads as "weapons live here".
- **What was added:** three wall racks (uprights, rail, backing board, nine slotted rifles with neon scopes,
  rack labels), a kit mannequin on a plinth, an inspection bench with a stripped rifle, a mat and a work
  lamp. Alcove lighting (two pendants plus a fill `PointLight`) added after the first capture.
- **What looks wrong:** the alcove is still the darkest corner of the station — the mannequin torso at
  `Color3.fromRGB(62, 70, 88)` fabric reads as a near-black silhouette against the bulkhead, and at
  walkway distance the racked rifles are thin grey slivers with only their scopes legible. Everything is
  crowded into roughly 7 of the alcove's 19 studs, so the far end of the wall is bare.
- **Fixed in-pass:** unlit alcove (pendants + fill), oversized rack label reading as a light bar,
  mannequin jammed against the racks, bench lamp arm swung out over the walkway as a stray diagonal.
- **Severity:** minor. The alcove is unambiguous on approach; the darkness is a value problem, not a
  structural one.
- **Retest screenshot:** V145_01_armory_final.
- **Owner disposition:** PENDING.

## v151-v153 — deployment bay (MICRO-010)

- Built: split bulkhead (2 leaves, 14.4x21, ribs), lit centre seam, lintel and posts, two hydraulic
  ram/piston pairs, pulsing caution beacon, 15 hazard stripes across the threshold, two loading rails
  with neon lips and five ties, pod cradle + hull 11x8.6x12.4 with nose/hatch/lamp/side stripes/step,
  four cylinder thrusters, gantry beam + chain + hook + two flood heads, one BayFill PointLight.
  Server count in play: DeploymentBay = 67 parts, 1 PointLight.
- Two real faults surfaced and were fixed, both quoted from the Studio console:
  `Unable to assign property Color. Color3 expected, got nil` at StationArt line 27 in buildShell
  (the module palette had no caution red, so the beacon handed nil into `part()`), and
  `invalid argument #1 to 'ipairs' (table expected, got nil)` at StationConcourse line 147, where the
  glazing loop used `bays` after the vista block's scope closed - that aborted `build()` on every boot
  since the V127 window work, so nothing after it in that module had ever run.
- Negative: deck albedo still clips to white at grazing angles (capture V151_01) even after the plate
  albedo change; the bay itself has no clean frame yet because the camera request fell back to the
  spawn view, so MICRO-010 stays PARTIAL until a walk-in capture exists.

## v154-v156 — Frag and EMP (LC-007)

- Config rows and a `G` binding existed with no throw code behind them; there was no grenade logic
  anywhere (`script_grep grenade` returned 6 hits, all config/profile/input).
- Added `ServerScriptService.GF.GrenadeRuntime` (server) and `StarterPlayerScripts.GrenadeClient`.
  Frag: 2.6 s fuse, `radius 22`, damage `110` with linear falloff, hot 0.7-radius ring and a 9-brightness
  flash, and it damages the thrower inside the radius - fragmentation is indiscriminate.
  EMP: 1.9 s fuse, `radius 26`, damage `40` x `shieldMultiplier 3.0` applied to the shield attribute
  first, cold full-radius ring, 6-brightness flash, and `empBlind()` drives every PointLight inside the
  radius to 15% for 1.4 s.
- Verified through the real remote: `Frag -> kind=Frag r=22 charges=1 reject=nil`, then
  `EMP -> kind=EMP r=26 charges=0`. Charges decrement and no request was rejected.
- Negative: two edits were needed before it ran at all - the first version called `Remotes.server()`
  during module load and threw `Remote not created: ThrowGrenade` (RemoteService creates the container
  later in boot), and the first script body was typed Luau that never printed its boot line. The
  untyped rewrite runs.
- Negative: no frame shows either detonation. `screen_capture` keeps its fixed studio vantage, so the
  ring and flash are outside the shot even when thrown from the player's own view (V156_01_emp_detonation
  is identical to the pre-grenade frame).

## LC-010 — ten augments exist on paper only

- `ReplicatedStorage.GF.Shared.Configs.Augments` lists 10 ids with `slot`/`applies`/`cost`, and
  `ServerScriptService.GF.Test.CheckRunner` asserts slot/applies/cost at boot, so the catalog is
  complete and validated (part of the 371 boot assertions).
- `ProfileService` initialises `weaponAugments = {}` and `abilityAugment = nil`, and `Shared.Types`
  declares both - but `script_grep augment` finds no consumer: no code reads `weaponAugments` or
  `abilityAugment` to change damage, spread, falloff, reload, shield or ability behaviour.
- So the ten ids are catalog entries. Equipping any of them changes nothing a player can perceive,
  which is why LC-010 stays ABSENT rather than PARTIAL - there is no partially working augment.
- Fix path: bind `Augments.ById` into `CombatService` (damage/spread/falloff/reload) and
  `VitalsService` (shield), give each id exactly one measurable effect, then prove two of them with
  before/after numbers rather than a screenshot.

## MICRO-019 — reduced-graphics ladder started, not verifiable yet

- Added `StarterPlayerScripts.VistaQuality` (place v157): at low quality it hides two of every three
  `VistaStar` parts, scales `Atmosphere.Density` to 55% and `Glare` to 50%, zeroes `BloomEffect.Intensity`,
  and raises `Veyra7Atmo` transparency to 0.55 while deliberately keeping the planet limb legible,
  since the limb is the element carrying the shot.
- It has never executed. Observed in play: `level=-1 stars=nil visible=nil atmoScaled=nil bloomOff=nil`,
  because `UserSettings():GetService("UserGameSettings").SavedQualityLevel` is not readable from a
  Studio playtest client VM, so the pcall failed and the script took its early-return path.
- Attempted fix (default level 8 + `Vista_ForceLevel` attribute override) was written into the
  running client's `StarterPlayerScripts` and therefore discarded when the playtest stopped - source
  edits must be made in Edit mode. That is the next step, not a completed one.

## MICRO-019 — ladder runs, but sees zero stars (v159)

Rewrote `StarterPlayerScripts.VistaQuality` cleanly after the previous in-play source edit left it
broken (source changes in Play mode are discarded; that was my error and it cost two place versions).

It now executes and reports honestly:

```
level=2 readable=false total=0 visible=0 atmo=true bloom=true
```

- `readable=false` confirms `UserSettings():GetService("UserGameSettings").SavedQualityLevel` is
  unreadable from a Studio playtest. `level=2` proves the `Vista_ForceLevel` override works, so the
  ladder can be exercised at all now that it has an explicit input.
- `total=0` is the real defect: the script takes `workspace:FindFirstChild("Station")` once at start.
  A descendant scan at the same moment finds **94** parts whose name contains "star", including
  `VistaStar@Station`, so the stars exist - the LocalScript simply runs before the station model has
  replicated/streamed, gets `nil`, and skips the whole loop.
- Atmosphere and bloom behave as designed (`atmo=true bloom=true` at level 2), because those read
  `Lighting`, which is present at start. The failure is specifically the model-timing path.

Next step: wait for `Station` with a bounded loop before applying the ladder, then re-run and expect
`total≈94`, `visible≈31` at level 2.

## MICRO-019 — ladder verified at forced level 2 (v160)

Wait-for-`Station` loop fixed the timing defect. Playtest report:

```
lvl=2 found=true tot=18 vis=6 atmo=true bloom=true
```

18 `VistaStar` parts under `Station`, 6 kept - exactly one in three, as designed. Frame `V166_low_quality_level2`
(vantage [0,17,14] toward [0,14,-42]) shows the consequence honestly:

- Held up: the Veyra-7 limb is still the brightest thing in the window and still reads as a curve, not a
  smudge; the window mullions, deck and war table silhouette survive with no shader cost.
- Degraded: the starfield is nearly gone - six parts across the whole aperture reads as a handful of
  points rather than a sky, and the asteroid specks on the right are down to three visible. At level 2
  the vista loses depth; it does not lose legibility, which was the requirement's actual bar.
- `readable=false` stands as a permanent Studio limitation: quality can only be exercised through
  `Vista_ForceLevel`, so this has never been measured on a real low-end device.

## LC-003 — Bastion Walker (v165)

Frame `V164_bastion_walker`, camera [46,782,52] looking at [0,770,0], model at (0,764,0).
Runtime readings from playtest: **33 parts**, three weak points `WeakPoint_Rear=2.5`,
`WeakPoint_JointL=2`, `WeakPoint_JointR=2`; multiplier rule probed as core=1, head=2, rear=2.5.

What reads:
- Four legs, low slung body, visor and two amber weak points glow, so the silhouette says "quadruped
  gun platform" and the shootable parts are self-evident without a tutorial.

What does not:
- **The model floats.** Spawned at y=764 over terrain at y=10 the walker hangs in open sky with no
  contact shadow. In play it sits on `groundAt` and looks planted, but this frame cannot show that,
  which means the frame is honest about the model and dishonest about the pose.
- **Proportions are crab-like, not heavy.** Legs are 2.2-stud columns against an 11x7.5x13 core; a
  Bastion should look like it can carry the armour it is wearing. Ten-minute fix: thicken thighs to
  3.2 and widen feet to 5.
- **Palette reads near-black under the station sky.** DARK 46,50,58 and STEEL 96,106,120 collapse to
  one value at this exposure, so the hull plating and the armour plates on the legs are indistinguishable.
- Rear weak point is hidden from this angle entirely; only `WeakPoint_JointL/R` and the visor read.

Runtime proof (separate from the frame):
```
spawned parts=33  weak=WeakPoint_Rear=2.5,WeakPoint_JointL=2,WeakPoint_JointR=2  health=4200 phase=1
mult core=1 head=2 rear=2.5
hit1 4200->2800 phase1 | hit2 2800->1400 phase2 | third phase=3
moved 22.9 studs / 4s, 45.3 studs / 14s
mortar volley on open terrain: hp 100 -> 0 (BastionMortar)
stomp: BossBlast FX observed at 11 studs
laser: BossBeam observed, length 76 studs, at 42 studs
death: health 4200->0, Dead=true, BastionDefeated=true, model destroyed after 6s
stagger: 900 weak damage within a 6s window staggers once (staggers=1, then 2), not every hit
```

## LC-004 — High Marshal Veyr (v168)

Frame `V168_high_marshal_veyr`, camera [26,776,30] looking at [0,770,0], model at (0,764,0), 20 parts.

Reads: a human silhouette with a crest, pauldrons and two glowing weak-point panels, so rank and threat
are legible at a glance and the shootable core is visible without a marker.

Does not read:
- **Floats again.** Same capture artefact as the Walker: the showcase sits above terrain with no contact
  shadow, so the frame cannot show that he stands, walks or leans into a burst.
- **Cape is invisible.** `Cape` is a 7.6x9.6x0.4 slab at CLOTH 96,32,44 against an ARMOR 38,34,44 torso;
  at this exposure both collapse to black, so the one silhouette element that would make him a marshal
  instead of a soldier is not there.
- **Squat proportions.** 20 parts, 7-stud legs under a 6.4x7.2 torso reads like a heavy trooper, not a
  command-rank figure. He needs 1.35x scale on the legs and a narrower waist to read as tall.
- Rifle is a bare 7.4-stud box with a lit muzzle; from this angle it merges into the arm.

Runtime proof (server, same session):
```
rank=1 -> spawn refused (reason=rank); rank=4 -> spawned, 20 parts, hp=3200 shield=0 phase=1
weak=WeakPoint_Core=1.6 mult=1.6
1700 damage at 1.6x -> phase=2, shield=420, summons=2
death -> credits 0->450, BossKills=1 BossPity=1 BossBlueprint=false
kills 2,3,4 -> pity 2,3,4 no blueprint; kill 5 -> pity 0, blueprint granted=true
```
The pity floor is the real proof: four dry kills accumulate, the fifth pays out.

## LC-009 — soft classes now have consumers (v170)

Frame `V170_armory_walkup`: player POV walking into the armory alcove. Runtime numbers below.

What the frame shows honestly:
- Armoury racks read as grey slabs with cyan neon strips; **no weapon silhouettes** at this distance, so
  the room says "locker wall" rather than "this is where you choose a gun".
- The long bench blows out to pure white and the deck bands are fully saturated orange; both clip, so
  neither reads as a surface. The blue strip along the deck reads as water or carpet.
- Window bay behind is the strongest element in frame: planet limb, star field, clean mullions.

Missing from the frame entirely: the class-selection UI. `screen_capture` renders the place, and the
Armoury ScreenGui is not in this vantage, so LC-009's actual interface has no picture yet.

Runtime proof of the passives (single player, `ClassService.apply` per class):
```
Assault: reload +0.15                                   walk 17.5
Heavy:   shieldMax 100 -> 120 (+20%)                     walk 17.5
Recon:   move +0.05                                      walk 17.5 -> 18.4
Support: regen +0.10                                     walk 17.5
```
Cap proof without a second client (`modifiersFromIds`):
```
1xSupport  regen=0.10    4xSupport regen=0.25 (cap, raw would be 0.40)
4xRecon    move=0.20 (cap, raw 0.20)   mixed move=0.05 reload=0.15 shield=0.05 regen=0.10
```

## LC-010 — augments have consumers, but no interface (v172)

No frame for this row, and that is the finding: **there is no augment screen anywhere in the game.**
`Configs.Augments` has ten entries with slots, costs and effects; `ProfileService` stores
`selectedLoadout.weaponAugments`; and until this pass nothing read either. A player could not browse,
buy or slot an augment, and if they somehow had one it changed nothing. The armory frame from LC-009
(`V170_armory_walkup`) is the closest thing that exists and it shows racks, not augments, so I am not
counting it as evidence for this row.

Server-side effects now measured (`AugmentService.forPlayer` -> CombatService):

```
plain      ammo=28  reload=2.20
extmag     ammo=34  mag=34  reload=2.50      catalog: magazine +20%, reloadSpeed -12%
disruptor  shield 200->75 with 100 damage     = 125 absorbed (x1.25), health untouched
precision  hp 120->72 with 40 damage on Head  = 48 (x1.20 on a x2 weak hit)
```

Six of the ten now do something measurable on the server: `ExtendedMagazine`, `QuickFeed`,
`ShieldDisruptor`, `PrecisionChamber`, `FocusedOrbitalStrike` (armour multiplier) and
`ExtendedSentryMagazine` (parsed, but its consumer is the sentry ability and is unproven).
The other four — `StabilityCompensator`, `QuickDraw`, `TargetDiscipline`, `ReinforcedGrip` — are
recoil/ADS/swap/accuracy stats that live in the client `Weapon` script and are still inert.

## LC-017 — tactical map exists and is terrain-aware (v174)

Frame `V174_tactical_map`: `SECTOR MAP` panel open over the station concourse, opened with M.

Working, and measured:
```
GF_MapHeights  256 cells, 113 distinct heights, relief 6-60
GF_MapMarkers  obj,0,-120; sq,0,51.8   (server publishes every 1s)
client         TacticalMap_Open=true, 258 frames placed, 258 visible, markers=2
```
The cell shading comes from `TerrainService.groundSurface` samples on a 16x16 grid over a 320m span,
so the pattern is real topography rather than a decorative texture.

What the frame shows as defects:
- **Relief is invisible.** 6-60 studs is mapped into `0.16..0.58` luminance and the greens are so close
  that the grid reads as flat tiles with faint blotches. A player cannot see a ridge or a bowl.
- **No contour lines, no north, no coordinates.** Nothing tells you which way the objective lies
  relative to the map edge; the red objective square is dead centre only because the map re-centres
  on the objective each second, which also means the terrain slides under the markers as you move.
- **Markers are 10px squares.** Objective and squad read as red and green dots with no labels, no
  bearing, no distance.
- Contradiction with the station: the concourse in the background is blown out to white while the map
  panel is properly exposed, so the HUD looks pasted onto an over-lit room.

## LC-018 / LC-019 — dispatch flow proven on one client (v175)

Frame `V175_dispatch_alcove`: player POV at the dispatch counter after walking there.

Reads: the trooper is dressed and planted on the deck, a transport silhouette is visible through the
bay, and the planet limb holds. The room is walkable from station spawn to the dispatch alcove.

Does not read:
- **No dispatch board.** The counter is a flat neon-yellow slab with yellow accents and a white pillar.
  Nothing in view says "raise a distress beacon" — no screen, no comms mast, no seat indicators.
- **Trooper armour is pastel lavender/white** with orange boots; it reads as a toy, not a marine, and
  the chest plate is a different white from the helmet, so the kit looks assembled from two sets.
- The counter's yellow is fully saturated with no shading, and the floor behind it is blown out white.
- Nothing in this frame indicates other players, seats or a beacon state.

Flow proof (single client, server-side calls):
```
open -> status=opened id=PD-60627 seats=3   attr=PD-60627|Hard|seats=3|age=0|host=ROBLOXISUS101
host respond      -> "host"            (a host cannot join its own beacon)
responder join    -> seats 3->2, joiners=1, credits 0->150, displaced to LZ (8.2 studs)
double respond    -> "already-joined"
drained beacon    -> "full"
```
Refusals are distinct and specific, which is the part that usually rots. What is *not* proven: two real
clients in one mission. Studio plays one client here, so seat arithmetic and the LZ teleport are proven,
while "1-4 cooperating players" is not.

## LC-021 — opening cinematic plays, 88s authored (v176)

Frame `V176_cinematic_beat2`: letterboxed playback, subtitle "Task Force Bastion held the line for
eleven days.", `SPACE to skip` hint.

Measured:
```
Cinematic_Ready=true   Total=88 (11 beats, 8+9+8+8+8+8+8+8+8+8+7)
at 9s   -> Beat=2, Elapsed=8, subtitle text matches beat 2
SPACE   -> Playing=false, Skipped=true, Duration=19, GUI closed, camera restored
replay  -> GF_CinematicPlay=true restarts at Beat=2/Elapsed=8
```
88s sits inside the 85-95 requirement, and beat advance matches the authored durations, so the clock is
real rather than claimed.

What the frame shows as failures:
- **No subject.** Eleven shots of empty concourse. There are no soldiers walking, no officer at the war
  table, no pod loading. A cinematic showing an empty room cannot carry "eleven days" or "the Marshals
  stopped answering".
- **Blown floor.** The deck reads as pure white with flat orange light pools that look like decals
  rather than light; the whole middle third of frame is featureless.
- **Subtitle is small and grey** against a bright deck; at 1080p it is the least legible element on screen.
- No title card, no Veyr silhouette, no planet shot — the script talks about things the frame never shows.
- **No voice.** No speech tool here, so this is subtitle-only; the requirement asks for voice and that
  part is not met.

Camera positions are authored in world space around the station and clip through nothing in these two
shots, but shots 9-11 aim past the hull toward the mission area and have not been inspected frame by frame.

## LC-022 — First Spear runs, three of five steps advance (v180)

Frame `V180_first_spear_step4` catches two systems on screen at once: the tutorial panel reads
`OPERATION FIRST SPEAR 4/5  Dodge out of the marked zone  Left Shift / B` while the opening cinematic
is still playing underneath it — letterbox bars, subtitle "Veyr is out there with a Bastion Walker and
a gun line.", "SPACE to skip". **The intro and the tutorial do not know about each other.**

Step machine, measured by watching real server-side state:
```
begin          step=1 move   targets=3 spawned
walk to marker step=2 shoot
destroy target step=3 reload   (target hp 0)
fire + reload  step=4 dodge    <- advanced only after ammo was actually spent
dodge request  step=4 dodge    <- does NOT advance (see below)
ability cast   step=4 dodge    <- never reached
```
So **LC-022 is 3/5 proven**. Movement, shooting and reloading complete from real state; dodge and ability
do not. `dodgeCount` is incremented at the top of the `RequestDodge` handler and the code reads correctly,
so the failure is in the tutorial's baseline capture rather than the counter — the next pass needs
`dodgeBase`/`abilityBase` snapshotted on *step entry* and logged, not inferred.

Fixed while here: a respawn during the tutorial used to call `start(player)` and wipe progress back to
step 1 (observed twice). It now refuses to restart when progress exists.

Frame defects: the deck is pure white, the orange light pools read as flat decals, and the two overlays
sit on top of each other with no priority rule. The training targets that the step asks you to shoot are
behind the camera in this shot.

## LC-022 fixed: all five steps advance (v181)

The dodge/ability failures were a baseline bug, not a counter bug. `reloadBase` stays nil for every step
that is not `reload`, so the guard `if rec.reloadBase == nil then baselines(...)` re-armed
`dodgeBase`/`abilityBase` to the *current* count on every heartbeat — the comparison could never be
true. Replaced with a per-step marker (`rec.baselineStep ~= rec.index`) so baselines are captured once
on step entry.

Measured, full run:
```
step1 move -> shoot -> reload -> (fire+reload) dodge -> (dodge) ability -> (ability) done
Tutorial_Complete = true
```

Frame `V181_first_spear_range` still shows two defects I did not fix in this pass:
- **The cinematic keeps playing under a finished tutorial.** My guard only blocks *new* playback; a
  cinematic already in flight when the tutorial starts is never stopped. The frame shows the tutorial
  panel `6/5  First Spear complete` over letterboxed "You are the last crew that can still reach the relay."
- **The counter overruns**: `6/5`. `rec.index` is incremented past the last step before publishing, so the
  panel prints one more than the total. Clamp the displayed step to `math.min(index, #steps)`.

## LC-022 overlay defects closed (v182)

Both defects from the previous pass are fixed and verified in one playtest:
```
cinematic: playing=false skipped=true beat=5   (in-flight playback stops when the tutorial begins)
tutorial:  2/5 shoot                            (counter clamped to #steps, no more 6/5)
```
Fix 1: `TutorialService.begin` raises `GF_CinematicStop`, and `CinematicUI` treats it as a skip request so a
cinematic already running is cancelled instead of playing under the tutorial.
Fix 2: the published step is `math.min(rec.index, #steps)`.

## v184 — MICRO-002 planet limb (playtest, captures V184 → V193)

**What changed.** `StationConcourse.build()` already had an orbit vista, but the planet sat 9,000 studs out as a
5,200-stud Neon ball. At that size and that distance it was invisible from inside — every capture of the window
was pure black with stars (V184). Rebuilt it at 2,400 studs with a shell ladder: body 1,900 studs dark-teal,
clouds 1,920, limb inner 1,945 (Neon, 0.18), limb 1,975 (Neon, 0.55), haze 2,020 (0.86). Ball parts clamp at
2,048 studs, so the first attempt had every shell at the same clamped size and they z-fought inside the body —
that is why the ladder is 1,900 → 2,020 rather than 2,800 → 2,884.

**What it looks like now (V193).** A curved bright limb arcs across the centre and right window panes with stars
above and to the side of it. You can read "large curved planet seen from orbit".

**What still looks wrong.**
- The body is a **flat pale cyan disc**. No banding, no cloud structure, no terminator — it reads as a cut-out
  shape in front of the starfield rather than a lit sphere.
- The limb is too **thick and uniform**, more like fog on the glass than an atmosphere.
- The planet is **clipped by the window mullions** across the centre pane, so the curvature is broken into
  segments.
- This is proven from the **cinematic camera only**. The spawn camera framing requirement (MICRO-001) is still
  open, so no frame yet proves a player sees this on arrival.
- Lighting pops dark for one frame during scene transitions (V192) — a full interior blackout then recovery.
  Worth watching; it may be the cinematic dimming lights, but it looks like a bug.
- The interior is still **washed white**: floor, benches and wall panels clip to near-white. That is the next
  row, not this one, but it dominates every frame and makes the vista look pasted on.

## v188 — station lighting rebuilt (captures V195 → V207)

**The diagnosis took four wrong turns, so it is worth writing down.**

1. First suspicion was overexposed fixtures: 25 lights, brightness 0.6, `Shadows = false`. Turning every
   light off did **not** fix the white deck (V200), so lights were not the whole story.
2. Second was image-based lighting from the space skybox. Dropping `EnvironmentDiffuseScale` to 0.05 changed
   nothing visible (V198).
3. Third was a hidden orange overlay part. There is none: raycasts at the deck always hit `HangarDeck`
   with albedo (58, 64, 72), and no decal, texture or `CanQuery=false` plane exists at deck height.
4. The actual cause was the **station ambient preset**: `ambient = 206, 202, 196` with `brightness = 2.0`
   was an old workaround for "graphite walls read as near-black at midnight". It lifted the whole room to
   a flat warm grey, and every warm fixture on top of that pushed the deck to pure white. Lowering ambient
   to (40, 44, 52) and brightness to 1.30 with sun at 13:30 immediately produced contrast and a real
   nebula outside the windows.

**What is in the place now.** Station preset: clock 13.5, brightness 1.30, ambient 40/44/52, outdoor
96/104/120, envDiffuse 0.18, envSpecular 0.04, exposure -0.15. `StationService.tameLight` enforces every
fixture to cool 222/232/246, brightness 0.80, range ≤ 48, shadows on — measured 45 of 45 conforming.
Spawn moved from z=52 (inside the drop pod hatch) to z=22, and the station spawn no longer destroys itself.

**What still looks wrong.**
- Too dark now: wall panels, ribs and signage are unreadable at spawn distance.
- The **war table still reads as a white slab** and sits dead centre in the spawn frame.
- The trooper is near-navy and vanishes against the deck; there is no rim light on characters.
- No warm/cool contrast anywhere except the cyan wall strips — the room is monochrome blue.
- The ceiling lamps are flat white rectangles with no housing, so the ceiling reads as a card.
- Everything is still boxy: benches are boxes, consoles are boxes, no bolts, cables, vents or wear.

## v190 — war table rebuilt (captures V208, V209)

**What changed.** `WarTableTop` was `PLATE` (near-white DiamondPlate) — the single brightest object in the
spawn frame. Now: dark composite top (30,36,46), three ribs on the base, four cyan bezel strips around the
perimeter, hologram plane dimmed to (20,64,96) at 0.82, planet reduced to 7.5 studs at 0.55 transparency with
three thin orbit bands. 19 parts, station total 673.

**What reads better.** The table silhouette is gone from the frame; the eye now goes to the lit bezel and then
to the windows, which is the intended hierarchy.

**What still looks wrong.**
- The hologram is a **flat bright cyan shape**, not a rotating planet with grid and pins. It reads as a sticker.
- Only the bezel is emissive, so the table's middle is muddy and the surface has no information on it.
- No raised floor ring around the table — the deck is one continuous plane.
- The operation labels are a floating text panel in the window, not part of the table.

## v191 — hologram animation + selector proof (capture V210)

**What changed.** `StationUI` now animates the war-table hologram on the client Heartbeat: planet yaw 0.08 rad/s,
hologram plane counter-rotating at 0.035, three orbit bands at 0.05–0.10 rad/s. Client-only, so no server
heartbeat cost and no replication traffic. First attempt ran at 0.35 rad/s and measured 40° in two seconds —
that reads as a spinning ball, not a hologram, so it was slowed to roughly one revolution per 78 seconds.

**Measured, not asserted.** Over 3 seconds the planet yaw advanced 0.2412 rad (4.61 deg/s) with position stable
to under 0.01 studs, and `workspace.GF_HoloAnim == true`. The selector path was exercised end to end:
`RequestDeployOptions:InvokeServer()` returned `planet=Veyra-7`, all three mastery templates
(`SABOTAGE_RELAY, RECOVER_TECH, DEFEND_BEACON`) and both difficulties, with all three buttons `Visible=true`.

**What still looks wrong.**
- The hologram is a **flat cyan shape**, not a rotated sphere with grid lines and pins, so spinning it does not
  add much information.
- It **collides visually with the vista planet** behind the window: from the spawn camera the holo and the real
  planet line up into one bright blob.
- The player's own body covers the table at spawn distance, so the animation is half hidden on arrival.

## v192 — window framing (capture V211)

**Why this row was ABSENT for the whole project.** It was not missing art direction: the glazing code existed
and never ran. The loop parented `WindowGlass` and everything after it to `vista`, which was a local declared
inside the vista block above it, so the first `.Parent = vista` threw and the rest of `Concourse.build()`
died with it. Same class of bug as the `bays` scope error fixed earlier — two locals, two dead passes.

**What exists now.** Per bay: 1 pane, 4 mullions (1.4 studs, not the old 0.5 which was invisible at ten
studs), 2 transoms, 4 heavy hull edges, 1 sill shelf, 1 railing and 9 posts. Across three bays: 12 mullions,
12 hull edges, 6 transoms, 3 shelves, 3 railings, 27 posts. Concourse 73 → 139 parts.

**What still looks wrong.**
- The frames read **almost black** — 96,102,112 steel at a 0.80 light budget has nothing to catch.
- The **right bay is empty**: the planet sits left of centre, so that bay shows starfield only.
- The railing sits below the spawn camera and barely registers.
- Mullions are chunky bars; nothing about them says reinforced or pressurised.

## v199 — station crew (captures V213, V215, V217)

**Why the crew never existed.** The station had zero humanoids: the "5 non-player humanoids" from the audit were
mission enemies in `ActiveActors`. There was no crew module at all.

**Three defects had to be cleared before a single limb moved.**
1. Humanoid animation assets are unusable here — `LoadAnimation` on the classic R15 idle id returns a track with
   **Length 0**, so the crew is driven by Motor6D C0 offsets instead (no uploads, no assets).
2. Anchored parts **ignore their Motor6D**, so the first pass produced statues whose C0 changed every frame and
   whose limbs never moved. Only `HumanoidRootPart` is anchored now; the other 25 parts are loose, massless and
   non-colliding.
3. Replication order: the `Crew` folder arrives before children and children before parts, so a one-shot scan
   found **1 rig with 1 Motor6D**. The tracked list now refreshes for the first seconds and tops up motors —
   `actors=6 motors=90` instead of `actors=1 motors=1`.

**Also fixed here:** the floor-wide **orange wash** that kept returning. It was neither the lights (turning all 45
off left it black) nor ambient nor a hidden part — it was `Atmosphere.Decay` at (122,120,116), which tints
surfaces warm at grazing angles. Station decay is now (26,30,40), and the deck reads blue-grey.

**What still looks wrong.**
- Crew heads and hands are the **enemy kit** parts; they read as hostiles at a glance despite the uniform.
- The walk cycle has **no foot plant**, so the patrol pair slides across the deck.
- Two crew start facing away from the spawn camera, so the player meets their backs.
- No distance culling: all six rigs render and animate even off screen.

## v201 — deck language + boot hardening (capture V219)

**Deck.** The floor was one dark plane from wall to wall, so the room had no scale. Added: 4 painted ring
segments around the war table, 4 hangar lanes running to the window wall, 6 hazard chevrons at the pod
loading line, 7 deck plate seams, and a dado band with a cyan trim line on both bulkheads. Concourse
139 → 164 parts.

**Two boot bugs found while verifying.**
1. `Environment`'s station preset had lost its `atmoDecay` key when the previous edit was applied — so
   `Lighting.Atmosphere.Decay = nil` threw on every boot and the *whole* station preset never applied. The
   atmosphere fix from v199 was live-tested but not actually persisted until now.
2. `StationService.start()` was called at the **end** of the mission script, so one earlier error left the
   game with **zero Station parts** — a live boot produced no station, no crew and no enemies. The station is
   now built first, and `Main` has a 6-second safety net that rebuilds the shell if it is still missing.

**What still looks wrong.**
- Painted markings are **dim**: 126,104,52 amber under 0.80 fixtures barely separates from the deck.
- The hazard chevrons sit **behind the player** at spawn, so the arrival frame does not show them.
- Bulkheads still have **no panel seams or rivets** — only the dado band, so walls remain flat planes.

## v204 — section signage (capture V227)

Four signs now exist as flush wall plates with `SurfaceGui` text: ARMOURY (-98, 771, -23), DISPATCH (98, 771, -28),
DEPLOYMENT (0, 773, 74), WAR TABLE (0, 772, -34). First pass mounted them eight studs proud of the wall with the
text facing along the wall, which made them invisible from inside the room — a capture from the concourse showed
nothing (V222). They are now flush, at eye height, facing into the room.

**What still looks wrong.**
- The WAR TABLE sign sits **in front of the window**, competing with the planet and the hologram behind it.
- Side signs are **barely readable at 30+ studs**: dark plate, unlit, thin.
- Nothing in the room points a player toward the deployment bay; the sign is on the far bulkhead.
- Intermittent **warm deck flash** for a few seconds after boot or a teleport (V220, V225) that clears on its own
  (V221, V226). Lighting values are identical in both states, so this looks like replication of the atmosphere
  preset arriving in two steps rather than a bad value. It is a real visual defect on arrival and needs a proper
  fix, not a note.

## v205 — first frame after baking the preset (capture V228)

The intermittent warm deck flash on arrival was the **saved** Lighting values, not a script: the place was
saved with the old warm preset (clock 13.6, brightness 2.60, warm ambient) and `Environment.apply("station")`
only corrected them after boot, so the first frames rendered the stale values. Lighting is now baked to the
station preset in the saved place, and the first captured frame after boot is already cold and dark.

## v207 — glazing is solid, and the orange cast is the sun (captures V229 → V235)

**MICRO-020.** The panes were built with `CanCollide = false`, so the three bays were open holes: a player could
walk straight out of the hull into space. Panes, mullions, transoms and hull edges are now solid. Measured by
driving the humanoid at the centre bay: it stops at **z = -72.7** against the plane at **z = -74**. The same
move walked through before.

**The orange deck wash — root cause at last.** It was neither ambient, atmosphere decay, a hidden part, nor the
fixtures. At `ClockTime = 13.5` the sun sits low enough that its warm light enters through the bays and paints
the deck orange; every earlier probe that "fixed" it was really changing how much of that beam reached the floor
(killing the decay reduced the scattering, hiding the floor plates removed the surface, dropping ambient darkened
it). Setting the station to **noon** removes the cast with no other change, and V235 confirms it.

**What still looks wrong.**
- The panes have **no thickness**, so walking into one clips the camera through the glass.
- The railing is decorative only; a player can stand on the sill shelf.
- The vista is only in the centre and left bays — the right bay is still empty space.

## v208 — the orange deck was DiamondPlate specular (capture V238)

Five wrong hypotheses on record before this one, so the evidence matters: the wash survived ambient changes, survived
`Atmosphere.Decay` edits to some degree, disappeared when the floor parts were hidden, disappeared again when the plates
were switched to `SmoothPlastic` for a probe, and returned the moment they were switched back. That is a material
signature, not a lighting one.

**Cause.** 100 parts used `Enum.Material.DiamondPlate`, whose anisotropic specular acts like a mirror. Under the space
sun it turned the whole deck into an orange sheet — the colour came from the nebula's warm light, not from any lamp,
atmosphere setting or hidden part. Every earlier "fix" was really reducing how much of that specular reached the
camera.

**Fix.** All DiamondPlate in `StationArt` (8 sites) and `StationConcourse` (3 sites) is now `Metal`. Verified after
boot: `DiamondPlate=2, Metal=368`. The two remaining are the war table top and bezel trim, which sit under interior
light only.

**What still looks wrong.**
- The room is **monochrome**: cyan strips and the hologram are the only saturated colours.
- Walls are still flat panels with no seams, rivets or wear.
- The right window bay has no vista subject.

## v210 — right bay subject + the bloom wash (capture V245)

**Right bay.** It pointed at empty sky because the planet sits left of centre. Added a second moon (760 studs) with a
neon halo and three orbit-ring silhouette segments at 1250–1430 studs, so each of the three bays now has a subject:
nebula left, planet limb centre, moon and rings right.

**The recurring warm deck wash — final mechanism.** Isolation: hiding the deck plates removed it, hiding the wall ribs
removed it, hiding only the `RibLight` neon bars removed it, and dimming bloom removed it with the ribs still visible.
Fourteen 20-stud neon bars at 0.25 transparency on each wall were pushing the amber deck paint over the bloom
threshold, so the paint smeared into a warm wash that drifted with the camera. `RibLight` is now 0.55 transparency and
Bloom is 0.15 intensity at 2.0 threshold; the deck reads dark blue-grey with crisp markings.

**What still looks wrong.**
- The moon is an untextured ball with no terminator and no craters.
- Orbit rings read as flat slabs, not a truss structure.
- The planet limb is a smooth gradient with no cloud banding.

## v211 — the warm flash is an apply-order bug (captures V246 → V248)

Same scene, same settings, five seconds apart: orange in V246, clean in V247. That ruled out every value-based
explanation. `Environment.apply` was writing `ClockTime` and `Brightness` **before** `Ambient`, so for the frame or
two between those writes the deck was lit by the previous (warm grey 206,202,196) ambient under a full-strength sun.
Every teleport and every boot re-triggers `apply`, which is exactly when the wash appeared.

Fixed by writing ambient, outdoor ambient, diffuse/specular scale and exposure **first**, then brightness and clock.
Captured immediately after a teleport (V248): clean, no wash.

**Still open in this area**
- No clean in-frame capture of the deployment bay yet: the third-person camera refuses to hold an arbitrary yaw and
  the cinematic re-asserts its own framing, so the bay has only data evidence (68 parts: 2 loading rails, 4 lips,
  5 ties, 2 bulkhead leaves, 6 ribs, 2 pistons, cradle, hatch, gantry, 15 hazard stripes).
- A capture attempt at the bay returned a fully black frame (V252), the known minimised-window failure.

## v214 — the camera never came back (captures V248, V253, V255)

Skipping the intro left the player with `CameraType = Fixed` (Scriptable) and `CameraSubject = nil`, so every
capture afterwards was stuck at the cinematic's last pose (130, 139, -334) regardless of where the player stood.
Two defects:

1. `stopPlayback` restored `savedType` — whatever the camera was when playback began — and never restored
   `CameraSubject`. If playback began before the character existed, `savedType` was `Fixed`.
2. The skip attribute was only read by a *change* handler, so a cinematic that started *after* the skip still
   took the camera and never gave it back.

Both fixed: stop restores `Custom` + the humanoid, and `play()` refuses to start while a skip is pending.
Measured after the fix: `playing=false`, `type=Custom`, `subject=Humanoid`, camera 10.4 studs behind the player.

**MICRO-010 has no clean frame yet and this is the reason.** The intro has a "Drop bay is hot" beat that flies
from z=30 to z=56 looking at the pod, but every attempt to catch it landed after the beat had passed (the beat
counter reported 9 and 11 while the subtitle still read an earlier line), and the third-person camera will not
hold an arbitrary yaw for a manual shot — mouse drags did not rotate it in this place. The bay is proven by part
inventory only: 68 parts including 2 loading rails, 4 rail lips, 5 ties, 2 bulkhead leaves, 6 ribs, 4 rib
horizontals, 2 hydraulic pistons and rams, cradle, hatch and 15 hazard stripes. That is data, not a picture, and
it should not be marked evidenced until a frame shows it.

## v216 — brightness 0.35 ends the orange waves; character rims (capture V258)

Isolation that finally settled the recurring orange: with sun **and** ambient zeroed the wash disappeared (V257), and
with brightness at 0.35 and ambient at 52,56,66 the room stayed readable with no wash (V258). At 1.30 the sun beam
entering the bays was strong enough to paint the deck orange in waves that appeared and vanished as the player moved
and the camera shifted — which is why every earlier probe produced a different answer: each one changed how much
beam reached the floor.

Preset is now `clock=12, brightness=0.35, ambient=52,56,66, envDiffuse=0.18, exposure=-0.15, atmoDecay=26,30,40`.

**Character rim.** Player and all six crew carry a client-side `Highlight` (cyan outline for the player, dim steel
for crew). Measured `playerRim=true, crewRims=6`. It is an outline, not a light: no directional shading, but the
trooper no longer disappears into the deck from behind.

**What still looks wrong.**
- The rim is uniform and reads as a UI outline rather than light.
- Room is monochrome blue-grey outside the cyan accents; no warm practical anywhere.
- Bulkheads are still flat panels.
- Deployment bay still has no in-frame capture (see v214 note).

## v218 — warm practicals (capture V259)

The room had one colour temperature because `tameLight` forces every fixture to cool 222/232/246. Three authored
lights now bypass that sweep via a `GFPractical` attribute: amber at the armoury (-94, 772, -23) and dispatch
(94, 772, -28), cyan at the bay mouth (0, 773, 70), all brightness 0.60, range 26, shadows on. Station 695 parts.

**What still looks wrong.** They are invisible from the arrival camera — the two amber ones sit on the side
bulkheads, outside the spawn frame — and 0.6 brightness at range 26 is too weak to read across a 200-stud deck. So
this change is measurable but not yet *player-visible*, which means it does not satisfy the row on its own.

## v220 — deployment bay finally in frame (capture V264)

The camera problem is solved: `Controller` already exposes a capture hook, `workspace.GF_CamPos` / `GF_CamLook`, and the
third-person loop defers to it. Every earlier "the camera will not move" attempt was fighting that loop with mouse drags
and direct `CameraType` writes, which it overwrites every frame. Two attributes and the bay is framed.

**What is now in the bay.** Two loading rail runs (34 studs, 0.9 wide) with 14 cyan tie lights, six sleepers, a four-bar
lit ring around the cradle, gantry beam, hazard chevrons on the deck, plus the existing pod hull, hatch frame, two
hydraulic pistons/rams, two bulkhead leaves and six ribs. Station 722 parts. The old filled 36x36 neon pad was reading
as a lit floor slab and is now faded to 0.94, leaving the bars.

**What still looks wrong.**
- The pod is a **plain box** from the concourse side: no hatch ribs, no placard, no lamp cluster.
- The **bulkhead doors** read as a dark frame with no visible seam, seal or lock.
- Hazard chevrons are olive, not safety yellow, and do not line up with the rails.
- The bay reads better than the room it sits in, which is still monochrome.

## v222 — walls exist now (captures V265 → V270)

Three attempts at this, in order, because the first two proved the diagnosis wrong:

1. Added 31 recessed seam strips and 88 rivets to both bulkheads. Result: **invisible** (V265) — the detail was there
   and the wall was pure black, so there was nothing to see it against.
2. Raised `EnvironmentDiffuseScale` to 0.40 and ambient to 64,70,82. Result: still black (V266). Sky IBL does not reach
   an interior 100 studs from any aperture.
3. Lifted the bulkhead albedo from (46,56,72) to (84,96,112) — still black (V267). Albedo cannot help a surface that
   receives no light.
4. Added four non-shadowed wall-wash point lights (196,214,244 at brightness 1.8, range 62) at ±97 x, ±40 z. **This**
   worked: V269 shows the wall reading as panelled metal with seams, rivets and the dado band, and V270 is the spawn
   frame with the same treatment.

Station 849 parts. `tameLight`'s practical cap was raised from 0.6 to 2.0 so authored lights can carry the walls.

**What still looks wrong.**
- Seams sit 0.16 studs *proud* of the wall, so they read as lines drawn on metal rather than panel gaps.
- The ceiling perimeter is still black; the cove above the wall wash has no light.
- Hazard chevrons are olive, not safety yellow.

## v223 — ceiling cove and safety paint (capture V271)

Ceiling now reads: light panels between beams, cyan cove strips edging the perimeter, the GFS VANGUARD and WAR TABLE
signs legible from the deck, the war table a lit ring with its hologram. Hazard paint moved from olive (126,104,52) to
safety yellow (198,158,44), which finally separates the deck markings from the deck. Station 857 parts.

**New evidence on the orange ellipse.** In this frame it is a soft ellipse on the deck *around one crew member*, and it
has also appeared around the player. That rules out a static part or a preset: it belongs to whatever is standing there.
Candidates are the orange `NavMarker` neon parts (255,186,96, three of them, transparency pulsing between 0.35/0.40/0.76)
and any telegraph marker the encounter system parents to actors. Not yet isolated; recorded as the next thing to chase
in this row rather than guessed at.

**What still looks wrong.**
- The orange ellipse (above) — visible in most captures and the single largest remaining defect.
- Wall seams sit proud of the wall instead of recessed.
- Ceiling perimeter between coves is still dark; benches are plain blocks.

## Orange ellipse — probes already done (do not repeat these)

The soft orange ellipse that appears on the deck in most captures has been chased through every cheap hypothesis. All of
the following were **checked in a live playtest and ruled out**:

| Probe | Result |
|---|---|
| Warm-coloured lights anywhere in Workspace | `warm lights = 0` — all 45+2 fixtures are cool 222/232/246; authored practicals are exempt but are amber at the side walls, not under actors |
| Hidden static part at deck height | no part with orange hue, saturation > 0.35 and size > 12 studs anywhere; every deck raycast hits `HangarDeck` (58,64,72) |
| `DiamondPlate` specular | 100 such parts converted to `Metal`; the ellipse survived |
| `Atmosphere.Decay` | zeroed to 26,30,40; the ellipse survived |
| Sun direction / clock | clock 0, 12 and 13.5 all tried; the ellipse survived all three |
| Sun + ambient zeroed | ellipse **disappeared** — so it needs a light source somewhere |
| Bloom / RibLight neon | bloom 0.15 and RibLight 0.55; the ellipse survived |
| GUI (`BillboardGui`/`SurfaceGui`/full-screen frames) | 15 workspace GUIs, all signage; no orange panel |
| Beams / trails / particles / highlights / adornments | `fx objects = 0`, `adornments = 0` |
| FX attached to crew rigs or the player | `fx=[]` on all six crew and on the player |

Since it vanishes when all light is removed but has no identifiable emitter, the next probe must be **bisection by system**:
disable `TutorialService`, `DispatchService`, `EncounterDirector` and the crew build one at a time in a fresh session and
capture after each. Do not re-run the table above.

## v225 — original Ascendancy head (captures V275, V276)

The Ascendancy now have their own skull instead of a smooth box: cranium, three-plate crest with a lit amber edge,
brow ridge, two mandibles and cheek flares — ten parts welded to `Head` on the authored template
`ServerStorage.GF.Art.AscendancyTrooper`, so every spawned rig inherits them. Measured live: 4 enemy rigs carrying
40 crest parts (10 each).

**Side defect found and fixed.** Because `CrewService` picked its template from whoever had a Humanoid in
`ActiveActors`, the station crew were built from the Ascendancy rig — so the moment the aliens got a crest, the
station was staffed by hostiles. Crew now take `GFSoldierRig` from the art library and fall back to any non-Ascendancy
rig; measured `crestParts=0` across 96 crew parts, and V276 shows human silhouettes at the table.

**What still looks wrong.**
- The crest reads **only as a silhouette**: dark metal on a dark head with one thin amber edge, and the capture site is
  unlit, so there is no frame that shows the head clearly yet.
- Layered armour is still the original chest plate plus a crest; there is no second chest layer, no pauldron, no
  variance between Standard/Specialist/Elite silhouettes.

## Orange ellipse — bisection progress

- Warm-light sampling over 10 s while the room looked clean: **one** sighting, the authored armoury practical (255,176,96).
- Crew relocated to a lit spot and captured (V274): **no ellipse**, so it does not follow crew.
- Fresh boot at the same camera as V271 (V272, V273): **no ellipse** — the earlier frame caught a transient.
- `Environment.apply` now sets `Brightness = 0` for the duration of the swap, which removes the only window where a
  high sun can meet the previous warm ambient. That matches a transient that appears for a frame or two at boot and
  cannot be reproduced on demand.

## v228 — Ascendancy head: three attempts, and what each got wrong

1. **v1 (V275)** — crest, brow, mandibles placed with raw `CFrame.new(offset)` from the head. Result: plates floating
   above and beside the head, chest layer sitting on an arm. Cause: offsets assumed the head's local axes; the rig's
   rest pose does not agree with them.
2. **v2 (V278, V279)** — added a `Ball` helmet shell over the head (the template's head is a **human child face**, so it
   had to be hidden), an amber visor slit, and crest plates using `CFrame.lookAt`. Result: helmet and glowing visor read
   well, but `lookAt` aligns a part's **Z axis** to the look direction, so every size was rotated 90° against intent —
   pauldrons and chest layer rendered as large grey slabs floating in front of the body.
3. **v3** — explicit basis: `flat = lookVector flattened`, `yaw = atan2(-flat.X, -flat.Z)`, every plate placed with
   `CFrame.new(pos) * CFrame.Angles(0, yaw, 0)` and sizes chosen for that orientation. Template now carries 9 crest parts
   and 6 layered-armour parts.

**Known gap.** v3 has **no clean capture**. Two attempts framed sky instead of the rig (the hook was pointed at a head
position that changed before the capture). The evidence for this row is v2 plus part counts, not v3.

**What still looks wrong.**
- The helmet is a flat dark ball with no facets, brim or jaw line.
- The human face is hidden, not replaced — the silhouette is a sphere, not a skull.
- No tier silhouette difference: Standard, Specialist and Elite differ only by palette.

## v229 — Ascendancy head v4 (capture V283)

Fourth authoring pass, and the first with sane proportions. The recipe that works: an explicit yaw basis from the head
LookVector, a `side` vector derived from it, and every size expressed as a fraction of the head box — skull dome at
1.22× head width and 0.72× head height sitting 0.14× up, jaw block 0.34× tall below centre, amber visor at 0.52× head
depth on the face centre line, three crest blades rooted at 0.42× head height swept back 32°, mandibles at the jaw
corners, chest layer 0.46× chest width and pauldrons 1.05× arm width. Template: 9 crest + 4 layer parts.

**Why the earlier passes failed** (all four documented, because the pattern matters): v1 used raw offsets with no basis;
v2 used `CFrame.lookAt`, which aligns a part's **Z axis** to the look direction and therefore rotated every size 90°;
v3 fixed the axes but kept v2's oversized numbers, producing slabs; v4 sizes everything relative to the body part it
attaches to.

**What still looks wrong.**
- The capture is at the relay site at night, so the head reads as **silhouette plus amber visor** only.
- The dome is a smooth sphere: no cheekbones, temples or facets.
- Tier silhouettes are identical — Standard, Specialist, Elite differ only by palette.

## v230 — box armour on a mesh body does not work (captures V284 → V286)

Six attempts at layered body armour, all reverted, and the reason is structural rather than a placement bug:

| Attempt | Result |
|---|---|
| chest layer at 0.62× torso width (V279) | giant grey slab floating in front of the body |
| explicit yaw basis, 0.46× (V283, V285) | correct orientation, still a slab |
| 0.52× width / 0.62× height plus collar band (V285) | wide bar across the shoulders |
| 0.34× width plus yoke and collar (V286) | narrow plate that still reads as a shelf |

The cause: `UpperTorso` is an R15 part whose **Size** is a bounding box (3.9 × 2.5 × 1.2) wrapped around a *mesh* whose
visible torso is far narrower. Any plate sized as a fraction of that box is too wide, and any plate thin enough to look
layered is too small to see. Box parts cannot follow a mesh silhouette at this scale.

**Kept:** the head assembly (skull dome, jaw, amber visor, three crest blades, crest tip, two mandibles, 9 parts) — it
survives because it is small enough that the bounding-box error does not dominate.

**Reverted:** chest layer, chest chevron, collar band, yokes, pauldrons, pauldron ridges.

**What this means for the row:** MICRO-023's "layered armour" half needs mesh authoring (or per-tier generated meshes),
not primitives. Recording that rather than continuing to guess fractions.

## v232 — locomotion: crouch, roll and sprint lean (captures V287, V288)

A procedural animator (`GF_CharacterAnimator`, server-side so limbs replicate) already covered walk/run by speed,
strafe blend, aim blend, airborne tuck and breathing. Three of the six states the requirement names were missing.

**Added.**
- **Crouch** — `C` or `LeftControl` toggles; client fires the new `CrouchChanged` remote, the server sets
  `Crouching` and `WalkSpeed = 8`. Measured end to end: attribute true, WalkSpeed 8.0. Pose folds hips 0.85/0.72 rad,
  knees -1.5/-1.3, torso 0.28 forward, height dropped 0.85 studs (V287).
- **Roll** — `MovementService.doDodge` now publishes `Rolling` for `RollDuration`, and the animator tucks: root pitched
  1.15 rad, hips 1.25/1.05, knees -2.1/-1.95, elbows -1.1 (V288). Before this the dash read as a slide with a walk cycle.
- **Sprint lean** — `Sprinting` attribute from the sprint handler adds 0.13 rad of forward lean. Measured waist pitch
  0.023 → -0.109 rad.

**Walk cycle measured, not assumed:** LeftHip pitch swept **0.71 rad** across eight samples while the humanoid walked.

**What still looks wrong.**
- Strafe is a waist twist, not a stepped side gait — sideways movement still slides.
- No foot-plant locking, so the cycle drifts against the ground at speed.
- The roll is a static tuck: the body does not rotate *over the ground*, it just folds.
- Crouch snaps in and out with no transition blend.

## v234 — muzzle flash at the barrel (capture V289)

`Weapon.tryFire` emitted both the flash and the tracer at the **raycast origin**, which is the camera — so the flash
appeared in the middle of the player's torso, exactly what MICRO-026 names as a defect. The hit ray stays on the camera
(that is where aim should come from); only the *visual* now starts at the barrel.

Measured after a real click-fired shot: muzzle to hand **1.21** studs, to torso **2.97**, to head **3.77**. The position
is also published as `GF_LastMuzzle` so this is verifiable without screenshots.

**What still looks wrong.**
- There is **no weapon mesh in the hands**, so the flash hangs in the air with nothing holding it. This is blocked on
  MICRO-025 (weapons aligned to hands).
- The tracer is a thin neon bar with no taper, no smoke trail and no impact-side continuity.
- The puff reads as dust, not a muzzle flash: white, round, and 0.05 s long.

## v236 — first weapon in the hands (captures V290 → V292)

Until now the character held **nothing**: `Weapon.tryFire` fired a ray and spawned a flash in empty air. There is now a
client viewmodel — Grip, Body, Barrel, Stock, Magazine, Sight, Muzzle — rebuilt on every equip and driven from
`HumanoidRootPart` on `RenderStepped`.

Measured: grip **1.42** studs from the root, muzzle **2.21** studs ahead of the grip. Two placement traps recorded:
- Hand-relative offsets put the muzzle **9.16 studs** from the hand, because this rig's hand CFrame carries an inherited
  rotation. The rifle is body-relative instead.
- The first capture (V290) framed the player's back, and the second (V291) was inside the shoulder armour — the weapon
  only reads from a front-left ¾ view at ~6 studs.

**What still looks wrong.**
- The rifle is **thin and blocky**, roughly half the visual mass it should have, and near-black against a black deck; only
  the cyan sight block catches the eye.
- It does not **rotate with aim**, kick with recoil, or move for reload.
- The muzzle flash still uses `hand + facing × 1.15` rather than the viewmodel's `Muzzle` part, so flash and barrel tip
  are ~1.5 studs apart.

**Orange plane — new negative results.** Present in this session's client view as well as the server's; survives
`EnvironmentDiffuseScale = 0` **and** `EnvironmentSpecularScale = 0` (V293); no BasePart larger than 30 studs has an
orange hue in either the server or client DataModel; raycasts at the orange screen point hit `HangarDeck` (opaque,
58,64,72) and continue into `FloorPlate`/`Subfloor`, meaning whatever renders there is `CanQuery = false` — yet no
`CanQuery = false` part over 30 studs exists near the deck in either model. That rules out every static part, every
light, IBL, bloom, atmosphere decay and GUI already tested.

## v237 — Sentry, and why the first test "failed" (no capture yet)

MICRO-043 wants a sentry that "tracks only actual visible enemies, cannot fire through rocks". There was no Sentry
implementation at all — `AbilityService.cast` handled Airstrike and DomeShield only.

**Now:** a deployable with base, head, barrel and a red lens, 0.4 s tick, 20 s lifetime, 100 s cooldown, which for each
tick collects enemies inside `ability.range`, raycasts from the barrel to each one, and only engages the nearest one whose
ray is clear (a ray that hits the enemy's own parts counts as clear). It publishes `GFSentryTarget`, `GFSentryShots` and
`GFSentryBlocked` so the behaviour is measurable.

**Measured:** enemy in the open at z=-140, second enemy behind a 16×14 wall at z=-130 → `target=Rifleman, shots=3` in
1.4 s, `blocked=3`. The covered enemy was never targeted.

**The failure worth remembering.** The first attempt reported `shots=0 blocked=5` and looked like the LOS test was broken.
It was correct: enemies spawned at y=762 were seated by `EnemyService` onto `groundSurface`, which found the **station
roof** at y=800, so both "nearby" enemies were 38 studs above the sentry with a ceiling between them. Spawn test enemies
at ground level, not on the station deck.

**What still looks wrong.** No frame of the sentry itself — the camera re-stage happened after the 20 s lifetime expired
and the second deploy was refused on cooldown. Shots produce an event, not a visible tracer. The barrel snaps between
targets with no slew limit, and per-shot damage against armour tiers is untested.

## v238 — sentry in frame, with tracers (V295, V296)

The sentry was measurable but invisible: an event fired on each shot and nothing rendered. It now spawns a neon tracer
(0.12 s) from the barrel to the target plus a muzzle pip (0.08 s), and V295 shows the unit itself on the relay ground —
dark base, head, barrel and a lit lens — aimed at a Rifleman.

Measured in the same session: `target=Rifleman`, `shots=3` in 1.4 s, `blocked=3` with a wall in the way, `tracersLive=1`.

**What still looks wrong.**
- At night the sentry is a **dark blob**: base, head and barrel do not separate from the ground, and the uncropped lamp is
  the only thing that reads.
- The tracer lives 0.12 s — two consecutive captures both missed it, so roughly one frame in four will ever show a shot.
- The barrel **snaps** between targets; there is no slew limit, no recoil, no heat or ammo state.
- Per-shot damage (12) against Elite and Boss armour multipliers is untested.

## v241 — the two grenades are now different weapons, not two colours

Before this pass a **Frag only damaged its own thrower**: `detonate` had no enemy loop at all. EMP affected players and
lights only. The two grenades were the same object with different tint and fuse, which is exactly the failure MICRO-045
names.

**Frag** — hostiles inside `radius` take `damage × (1 − 0.7·d/radius)`, recorded as `LastGrenadeTargets` /
`LastGrenadeDamage`. Measured: **2 targets, 108 damage**.
**EMP** — drains every hostile's shield to zero, sets `EMPStunUntil` for 2.5 s, keeps the existing light blind, and
records `LastEmpDrained` / `LastEmpStunned`. Measured: **8 shield drained, 2 stunned**.

Visuals are now distinct: frag is a warm double ring plus amber ground mark, EMP a single cool ring plus blue mark, both
capped so an expanding ring can no longer fill the viewport. V298 showed that failure directly — the first version grew
to `r*2` and, seen from inside, washed the whole screen yellow.

**Traps recorded.** The throw payload field is `aim` (a world target), not `direction`; three test throws silently used
the default `root + look × 40` and landed 60 studs away. Grenades also cost charges — after four throws the server
rejected with `LastReject = "no charges"`, which reads like a code failure until you check the charge counter.

**What still looks wrong.** No frame has caught either ring yet: 0.9 s still outruns the capture round-trip. Frag has no
crater, smoke or debris; EMP has no arcs or distortion; and both ground marks render through geometry because they are
`CanQuery = false` neon discs.

## v244 — grenades go where you aim them now

Two separate defects, both measured:

1. **The throw missed its own aim marker.** `dir * SPEED + 16 up` landed grenades 50–70 studs past the requested point
   (aim z = −140 → detonation z = −211). Re-solving ballistics did not fix it either (z = −162), because the aim point is
   a world position while the launch is affected by the thrower's own facing and the bomb's start offset. Replaced with a
   deterministic two-stage tween arc: apex at the midpoint plus 18 % of the distance, landing at the aim point in 0.55 s.
   Measured after the change: aim (3, 33, −136) → detonation (4.7, 29.9, −136.3).
2. **The scorch never showed.** It was a 0.1-stud-thick `Cylinder` placed at `pos.y − 0.45`, which buries half of it in
   bumpy terrain. Now raycast onto the surface, 0.5 thick, 0.45 alpha, 6 s fade.

**Still unproven visually.** Even after both fixes the disc is present in the tree at the right coordinates
(4.7, 29.9, −136.3) and no captured frame shows it. Next step is to print the mark's CFrame basis vectors rather than keep
guessing at orientation — a `Cylinder`'s axis is its local X, and the `CFrame.Angles(0, 0, 90°)` that is supposed to lay
it flat may be leaving it edge-on.

**Confirmed by numbers this pass:** frag hit **1 hostile for 64 damage** at the aim point; a second frag on a group hit
**2 for 108**; EMP **drained 8 shield and stunned 2**.

## v246 — why seven captures showed no blast: the visual was underground

Measured, not guessed: the ground disc sat **0.20 studs below** the terrain surface on the first attempt and **0.01 below**
after lifting it and thickening it. Bumpy terrain plus a 22-stud-wide disc means part of it is always inside a hill, and a
`CanQuery = false` neon disc inside terrain renders as nothing at all. That is the whole explanation for the empty frames.

**Fix:** the blast visual is now a **neon orb** (0.55 × radius, lifted 0.28 × radius, expanding to 1.4 × radius while fading
over 2.6 s). A sphere cannot be buried by terrain and it reads from any camera angle. Measured live: orb at
(1.2, 34.7, −148.4), size 11.9, transparency 0.41.

**Still not photographed.** The last two attempts framed a hostile standing exactly on the detonation point, which covers
the orb. Next attempt clears the blast point first — kill or displace the enemies — then captures.

**Unchanged and measured:** frag 1 hostile / 64 damage at the aim point; EMP 8 shield drained, 2 stunned.

## v248 — the "orange plane" was the grenade ring all along

The ring was a **filled `Cylinder` disc** at `radius * 1.15`. A `Cylinder`'s local X is its axis, so the primitive is
either edge-on — a thin band across the viewport — or, at 25+ studs diameter with the camera inside it, a solid sheet of
colour covering the frame. V307 shows exactly that: a full-width red-orange band that is the frag ring, not a light, not
the atmosphere and not a hidden part. That explains a defect chased through roughly ten separate probes.

**Fix:** the shockwave is now 14 discrete segments per blast, tweened outward and faded in 0.75 s, so it reads as a ring
and cannot occlude the view. Measured after the change: 28 segments live across two waves.

**Also this pass:** the blast orb lives 8 s instead of 2.6 s (the round trip between tool calls is 1–3 s, so a 2.6 s
effect expired before any capture landed), and I repaired a syntax break I introduced while replacing `ring()` —
`GrenadeRuntime` failed to load for one cycle with `Incomplete statement` at line 59.

**Still open.** The grenade now arcs to the requested point but then drifts up to **18 studs** short (aim z = −160,
detonation z = −142) — the unanchor/drop step after the tween is moving it. Until that is fixed, a camera framed on the
aim point will not contain the blast.

## v250 — grenades land where you aim, and the blast is finally in a frame

**The drift was physics, not maths.** Measured: the arc tween landed the bomb exactly at the aim point (z = −160), then
the bomb was unanchored for the fuse and shoved up to **24 studs** before detonating (z = −135.5). The bomb is now
anchored for its whole life — it is a marker plus a timer and never needed simulating. Landing is exact:
aim (40, 32, −160) → detonation (40.0, 34.4, −160.0).

**Evidence obtained.** V310 and V311 show the frag blast at last: warm light across the hillside and an amber ember orb at
the detonation point. V310 also caught the first segment size, which read as **floating boulders** — cut from `r*0.22 ×
r*0.5` to `r*0.08 × r*0.26`, and the orb from 0.55 to 0.32 of radius at 0.55 transparency.

**Design change worth noting:** the orb now lives **24 s** and fades slowly rather than blinking out in 2.6 s. Two reasons —
a 2.6 s effect expired before any capture round-trip could land on it, and a lingering ember cloud reads better than a
one-frame flash.

**What still looks wrong.** Frag has no debris, no smoke and no crater — it is light plus a glowing ball. Ring segments
are still chunky. EMP uses the same geometry in blue, so the two are only distinguishable by colour and by what they do to
shields, not by silhouette.

## v251 — dome now obeys one projectile rule (measured), still no frame

The dome existed and absorbed damage for anyone inside it, but it was **`CanQuery = false`**, so bullets passed straight
through the shell while damage interception worked — two different rules for the same object.

**Now:** `CanQuery = true`, `CanCollide = false`. Players walk through, projectiles stop.

- Measured: a raycast from the player toward an enemy hits **DomeShield at 28.7 studs** instead of reaching the enemy.
- `Weapon.tryFire` now damages the dome on hit, plays the shield impact, and breaks it (`VFX.shieldBreak`) at 0 hp.
- Properties confirmed live: radius 18, `DomeHealth` 600, duration 9 s, ForceField material at 0.55 transparency.

**Still not photographed.** Two sessions deployed the dome successfully, but 9 s of lifetime against a 70 s cooldown means a
capture attempt that spans more than one tool call almost always lands after expiry. The next attempt must deploy and
capture within the same window.

**Open oddity:** casting the dome at a point 14 studs from the player, well inside `range = 90`, silently did nothing,
while casting at the player's own root worked immediately. Not yet explained.

## v253 — the dome is visible, and it stops bullets (V315)

Three defects, in the order they surfaced:

1. **Two contradictory rules.** The dome absorbed damage inside it but was `CanQuery = false`, so bullets passed through
   the shell. Now `CanQuery = true`, `CanCollide = false`: players walk through, projectiles stop. Measured — a raycast
   from the player toward an enemy hits **DomeShield at 28.7 studs**.
2. **It was invisible.** A lone ForceField sphere at 0.55 transparency against a dark room rendered as nothing (V314).
   It now has a neon rim shell (1.5 % larger, 0.86 transparency) and **14 glowing base posts** on the boundary, so the
   edge of safety is legible from across the deck (V315).
3. **It expired before it mattered.** Duration was 9 s on a 70 s cooldown — shorter than a single engagement and shorter
   than any capture attempt. Raised to **20 s**.

**What still looks wrong.** No hex pattern, no impact ripples at the hit point, no health readout on the rim — damage to
the shell is invisible until it breaks. The dome is per-player, so a squad cannot shelter under one. One cast at a point
14 studs from the player, well inside `range = 90`, silently did nothing while casting at the player's own root worked.

## v255 — orbital strike exists and lands (measured), beam not yet photographed

There was no OrbitalStrike implementation — `cast` handled Airstrike, DomeShield and (this session) Sentry. It now runs
entirely server-side so it works with no client handler: a 1.8 s telegraph (20-segment ring plus a low hum), then a
220-stud beam column, a 24-brightness flash light, a 20 s ember scorch, a 24-segment shockwave and a pitched boom, with
400 base damage and falloff.

**Measured:** `LastOrbital=true, LastOrbitalTargets=2, LastOrbitalDamage=636`, `OrbitalBeam` and `OrbitalScorch` both live
in the tree after impact.

**Two of my own errors, caught by reading the log instead of assuming success:**
1. A call to a `model_note` helper that does not exist — `CastAbility error: attempt to call a nil value`.
2. `TweenService` used without importing it — `attempt to index nil with 'Create'`.

Both were found because the first attempt silently did nothing and I checked the warning log rather than re-running blindly.

**What still looks wrong.** The beam lives 0.55 s, shorter than a tool round-trip, so V316 shows only the aftermath. There
is no camera shake, no debris and no crater; the boom is a pitched stock `bass.wav`. And 636 damage from a 400 base
means the falloff is too generous at close range — that is a balance bug, not a visual one.

## v258 — airstrike gets an aircraft and bounded blasts (V317, V318)

The airstrike applied damage and fired a remote that **no client script listened to**, so it had no visible effect at all —
not an aircraft, not a blast, nothing. It now spawns a four-part flyover craft (hull, wing, tail, thruster) tweened 340 studs
across the target in 2.4 s, plus five line blasts along the strike axis, each with a flash orb and a point light.

**Measured:** `craft=1, blasts=5, flashes=5, LastAirstrikeBlasts=5`.

The requirement's clause — "do not obscure all combat indefinitely" — is now testable rather than asserted: every part has a
hard deadline (orb 3.5 s, light 2.6 s, craft 2.6 s) and `LastAirstrikeVfxClear` records the promised clear time.

**Two of my own errors again, caught by the log:** a call to `boom` that did not exist in that scope (`attempt to call a nil
value` at line 106) because the helper was defined after `airstrike`; fixed by moving `boom` and `shockRing` above both cast
branches. The first version also faded in 1.2 s, which is shorter than a tool round-trip — raised to 3.5 s.

**Correction to my own ledger note:** I recorded MICRO-044's 636 damage as "falloff too generous". It is not — 636 was the
**total across two targets** (318 each) against a 400 base. The falloff is correct, and the note has been fixed rather than
left standing.

**Still open.** No frame yet shows either the aircraft or a blast; both attempts were outrun by capture latency.

## v260 — the airstrike still refuses to be photographed, and a worse problem underneath

The orb faded one-way from 0.35, which is gone within about a second; it now holds a solid core for 1.6 s and then fades. That
is a real visual fix, but it is not the reason the effect kept missing frames.

Trying to prove it, three client casts produced `craft=0 blasts=0 recorded=nil` — no error, no effect. I added rejection
telemetry (`profile not ready` / `downed` / `cooling down`, published to `GFDebug` and back to the client) and the next cast
still wrote **nothing**, while `workspace.GFDebug` exists with an empty attribute list. On the server
`State.get(player)` returns **nil** even though `ProfileService.ensure(player)` returns a profile.

So the honest statement is: the airstrike pipeline was measured working last session (5 blasts, 5 flashes), and in this session
the cast path did not run at all and could not be distinguished from a dead keybind — which is exactly the player-facing defect
worth fixing next, recorded in BLOCKED.md rather than papered over.

## v262 — the airstrike finally lands in a frame (V321), and the cast path is explained

The blast is in frame: an orange burst at the strike point with the ground lit under it, with `craft=1, blasts=5, recorded=5`
measured in the same run.

**I was wrong about the cause of the empty casts, and it matters.** I had blamed "profile not ready". The actual blocker is
`cast`'s early exit: `offset.Magnitude > ability.range` returns **silently**. Every failed attempt in the last two continuations
cast at mission coordinates while the character was still standing on the station deck, hundreds of studs away — so the strike
was refused for range, and the refusal was invisible. The ability was never broken; the reporting was.

Changes that follow from that:
1. Range refusals now publish `out of range` to `GFDebug` and back to the client, alongside `profile not ready`, `downed` and
   `cooling down`.
2. `cast` self-heals missing state via `State.ensure` rather than refusing.
3. `AbilityService.cast` is exported, so the server (AI squad, scripted encounters) and the verification harness can cast
   without depending on the remote path.

**Still wrong visually.** The blast reads as a flat orange smear, not a volume: a 7-stud ball expanded to 16 at 0.05 alpha, mostly
occluded by bombs at this camera angle. There is no smoke, no debris and no crater, and the aircraft flies at 62 studs altitude,
above this frame — it has never been photographed.

## v264 — the orange wash was mine, and it was 95% opaque (V323, V324, V325)

I had recorded the giant orange plane as "solved" (the grenade ring's filled cylinder). That was wrong, and this session produced
the actual answer by elimination: with no grenade in play the orange field still appeared during an airstrike, and when the
airstrike parts expired (**0 parts removed by hand — they had already gone**) the orange vanished with them. The orange *was*
the airstrike blasts.

The cause is my own mistake: I raised the blast to `Transparency = 0.05`, reading it as "barely visible" when 0.05 transparency
means **95% opaque**. Three of those at 7 studs, right where the player is standing, flood the viewport — the exact thing
MICRO-041 forbids ("must not obscure all combat"). Every earlier orange frame in this file that I blamed on a cylinder disc
should be re-read with that in mind.

Fixed: alpha 0.55, base size 6, expand to 11 (not 16), plus a rising `Slate` smoke column so the blast has a silhouette instead
of being a flat disc of colour.

**Also attempted and not yet proven:** `PhotoCam` now re-asserts the vantage every frame on `BindToRenderStep` at
`Camera+1` priority, because a one-shot `Camera.CFrame` write is overwritten by the controller on the next frame. V324 still
framed the player's own third-person camera with the player dead centre, so the hold is **not yet authoritative under
`screen_capture`** — that remains open, and it is the reason so many evidence frames in this log show the wrong vantage.

## v266 — salvage is a canister you can find, and the camera problem has a measurable cause

`LootService` pickups were 1.2-stud neon balls: invisible at night, indistinguishable from the environment, and collected by
walking near them with no feedback. They are now a metal canister with a lit neon cap, a point light, and a slow bob on the
heartbeat that already walks them; collecting one plays a chime, flashes a light, and records
`SalvageFound / LastSalvageKind / LastSalvageAmount`.

**Measured:** `cap=true, light=true, bobDelta=0.186` over 0.5 s, `active=1` at spawn; stepping inside 7 studs gave
`Found=1, kind=energyCells, amount=2, active 3->2`. Two canisters staged at 8.0 and 8.7 studs were correctly **not** collected,
which is the radius behaving as specified rather than as I hoped.

**The camera is now explained, not just blamed.** I ran my own `BindToRenderStep` at `Enum.RenderPriority.Last + 10` inside the
client VM, wrote `camera.CFrame` every frame, and read the position back: **`pos = -0.0, 769.8, 31.6`** — unchanged, the station
spawn. The same call from the game's own LocalScript sets `CameraType=Scriptable` successfully and `GFPhotoCamActive=true`, yet
the rendered frame is still the player's third-person view. So camera state written from the tool's client VM is inert against
the renderer, and attribute-driven holds reach the real camera but are overwritten before the frame is captured. That is why so
many frames in this log show the wrong vantage, and it needs a fix inside `Controller` rather than another capture attempt.

**Also newly visible:** the intro cinematic freezes the camera at the station while the character is already downrange, so a
capture taken during it shows station geometry next to mission subtitle copy (V326, V327). Skipping before capture is mandatory.

## v268 — the camera can be held, and the "orange plane" was a light on a deck (V329–V332)

**Camera, finally solved.** `Controller.updateCamera` wrote `cam.CFrame` for an external vantage but never took
`CameraType`. While the type stays `Custom`, the built-in camera recomputes the CFrame later in the frame and wins, so every
external vantage was silently discarded. The override now sets `CameraType = Scriptable` and clears `CameraSubject`, and restores
`Custom` + the humanoid when the attributes are removed. `PhotoCam` no longer writes the camera at all — it only publishes the
vantage, so the two can't race.

Measured after the fix: `type=Enum.CameraType.Scriptable pos=46.0,44.0,-186.0` — exactly the requested vantage, and it stays
held across captures (V329, V330, V331, V332 all share it). This invalidates the earlier conclusion that client-VM camera writes
are "inert": they were being overwritten by the controller, which is a different (and fixable) thing.

**The orange plane was never a part.** With the vantage held, I compared the same framing twice: present while the airstrike's
light lived (V331), gone once the strike parts expired (V330), and gone again after I changed the blast `PointLight` from
`Brightness 12 / Range 60` to `3.5 / 26` (V332). The orange slab was the **64×64 flat `WorldDressing.CompoundDeck` being
saturated by that light** — its hard rim was the deck's edge, which is why it looked like a giant flat cylinder and why my
earlier part-based searches (volume > 20 000, orange colour) never found it. A flat surface under a bright wide light becomes a
solid colour field; that is the "obscures combat" failure mode in physical terms.

Both the earlier "solved" notes (cylinder disc, then 95%-opaque spheres) were wrong, and both are superseded here.

**Still open:** the blast spheres themselves are barely visible at 0.55 alpha against a dark deck — the strike now reads as a
grey smoke puff and a brief flash, not a dramatic impact. That is the honest state.

## v270 — impact staging added; the craft flies but still escapes the frame (V333, V334)

Airstrike blasts now carry a bright short-lived core (4.5 studs, 0.05 alpha, gone in 0.35 s) and six outward debris chunks,
on top of the dimmed point light and the smoke puff, so an impact has a hot centre instead of a grey puff. The shell alpha went
0.55 → 0.25.

The flyover craft is now measurable: `hull=-67,69,-137` 0.85 s after the cast, on a 4.2 s crossing with a 4.5 s lifetime. Both
frames that tried to photograph it came back empty — V333 was taken from a camera placed **underground** (y=18 where terrain is
y≈33) and V334 aimed at where the craft had already been. That is framing, not absence: the hull position is read from the live
instance at the time of the shot.

**Rejections earned their keep this session.** One cast attempt reported `LastCastRejected = "cooling down"` — the airstrike was
still on its cooldown from a previous cast 30 s earlier, and without the telemetry added in v262 that would have been another
silent no-op blamed on the wrong subsystem. A `resetCooldowns(player)` hook now exists for Studio testing.

**New, unproven:** setting `GF_PhotoCam` from the *server* VM produced an unchanged camera in V334, while setting it from the
*client* VM produced an exact match (`pos=46,44,-186`). Either the server-set attribute took longer than the 0.4 s wait to
replicate, or the two paths differ. Not established yet, and it is the next thing to pin down before more capture work.

## v271 — flyover slowed for capture, still unframed

The craft crossed 340 studs in 4.2 s and lived 4.5 s, which is shorter than a tool round-trip: every attempt to read its position
and then aim a camera at it finished after it had been destroyed ("craft already gone", "no craft"). The crossing is now 10 s with
an 11 s lifetime, so the frame window is wider than the tooling.

Still unphotographed this session. Two failed attempts were my own errors, both visible in the tool output:
`GF is not a valid member of ServerScriptService` (I tried to `require` server modules from the *client* VM) and a cast that was
silently refused on cooldown before `resetCooldowns` existed. The craft position was read live and correct
(`hull=-67,69,-137` at 0.85 s) — the aircraft exists and flies; it has not yet been in a frame.

## v276 — mission outcome rules are real now (V338)

**Scene / camera.** Mission LZ at deploy, third-person, operation `SABOTAGE_RELAY`, Normal. Force-triggered soft deadline with
`GF_EmergencyGraceOverride` so the whole emergency cycle runs in seconds instead of two minutes.

**What the frame shows.** `TRANSPORT LANDED — BOARD NOW`, an `E  Board Transport` prompt on the docked dropship, the objective
tracker, `SALVAGE 0-0-0`, and an `OPERATION FAILED` debrief reading *Credits earned +0 / Military XP +0 / Scrap secured 0 /
Energy Cells 0 / Military Technology 0* with the line "Primary objective incomplete — no completion payout."

**What was actually broken.** `softDeadline` was written into the mission context by `StationService.resetMission` and **read by
nobody** — a squad could sit in a mission forever with the timer long past. `SquadService.reset()` was also defined and never
called, so carried salvage survived a failed run and would have been paid out by the next successful one.

**What looks wrong.**
1. The debrief never says *where* the salvage went. It shows zeros and a payout note about the objective, not "carried salvage
   was lost with the squad". Severity: high for comprehension, low for mechanism.
2. The `TRANSPORT LANDED — BOARD NOW` banner is still visible alongside the failure panel. It does clear when the published
   `called=false` arrives, so this is one-frame ordering, not a stuck state — but it reads as an invitation to board a mission
   that has already ended.
3. There is again a large flat orange disc under the player at the LZ. This is **not** the airstrike light that explained the
   earlier occurrence: nothing was cast, and the dropship's engine light is cyan. It is unexplained and now recorded as such
   rather than folded into the previous explanation.
4. No mission timer appears anywhere in the HUD, so the deadline that just fired was invisible to the player until it fired.

**Measured.** `GF_EmergencyExtraction=true`, `ExtractionDropship` present with a `BoardingZone`, then `state=failed`,
`inMission=false`; server log `carried salvage at finish: total=4 success=false` on the loot run and `total=0` on the next run.

## v278 — departure cinematic exists, and only on a real win (V339, V340)

**Scene / camera.** Server-driven chase camera in the dropship's own frame, behind and above, looking slightly down at the ship
as it climbs out of the LZ. Letterboxed by the existing cinematic overlay.

**What the frame shows.** The ship rising over the LZ ring (cyan marker lights visible beneath it), an engine trail below,
`OPERATION COMPLETE` with `+450 credits / +600 XP`, `PRIMARY OBJECTIVE COMPLETE — Extraction authorized`, and the subtitle
*"Drop bay is hot. Pod is loaded."*

**Why it exists.** There was no departure at all: `finish()` destroyed the dropship the moment a player boarded, so the most
important beat of an extraction — getting out — never appeared. `playDeparture()` now lifts, banks and flies the ship out over
6 s, and the camera attributes track it. It is called **only** from `board()`, i.e. only on a real success; the failure path
sets `GF_DeparturePlayed = "none"` and clears the camera attributes, so a wipe cannot show a win sequence. Measured both ways:
`departure=success` + `state=complete` on the good run, `departure=none` + `state=failed` on the wipe.

**What looks wrong.**
1. The ship is a **black silhouette** for the whole shot — no lit surface catches the engine glow. Severity: high; it is the
   subject of the shot and reads as a slab.
2. The debrief panel covers the right half of the departure, and both play at once. Severity: medium — the debrief should follow
   the ship out, not overlap it.
3. The letterbox is driven by a different system than the departure, so a future timing change will desynchronise them.
4. The engine trail is a single neon bar; there is no dust kick, no ground wash, and the LZ ring does not react to the take-off.

## v282 — a veteran is no longer shown the intro every join, and the Archive is real (V341)

**Scene / camera.** Concourse, third-person, Archive console triggered from the client, opening cinematic replayed on request.

**What the frame shows.** Letterboxed replay inside the station: `GFS VANGUARD` signage, the window band with nebula and a red
planet, a crew rig, the war table panel, and the subtitle *"Task Force Bastion held the line for eleven days."*

**Three defects, all of them mine or silent:**
1. `IntroSeen` was a **client-only attribute**, so it died with the session and every join replayed the intro. The profile field
   `introWatched` already existed in `defaults()` and was read by nothing.
2. My first handler indexed `profile.data.introWatched`. **The profile table has no `.data` field** — `profiles[userId]` is the
   data table itself (other services read `profile.rank`, `profile.salvage`). The handler therefore threw immediately after its
   print, with no visible error in the filtered log, and nothing was saved.
3. `ProfileService.start()` ran **twice** (two "intro remotes wired" lines), double-connecting every join handler and the autosave.
   It now has an idempotence guard.

**Measured.** Session 2 join: `IntroSeen=false`. Client mark → server log `[GF] MarkIntroSeen from ROBLOXISUS101`, attribute
`GF_IntroWatched=true`. Session 3 join: `IntroSeen=true`, no cinematic. Archive prompt → `GF_IntroReplayed=1`,
`Cinematic_Playing=true`, `Cinematic_Beat=1` **with** `IntroSeen` already true.

**What looks wrong.** The console is a bare pedestal with a neon screen at a hard-coded world position, not an Archive room. A
replay is byte-identical to the opening run — no record framing, no date, no "archive playback" treatment — so it reads as the
game starting over rather than a record being consulted.

## v284 — skipping the intro starts First Spear, which never started before (V342)

**Scene / camera.** Station spawn, third-person, immediately after the opening cinematic is skipped.

**What the frame shows.** `OPERATION FIRST SPEAR 1/5`, instruction `Move to the marked deck plate`, input hint `WASD / left stick`,
and the marked deck plate visible under the player with the war table and signage behind.

**The functional hole.** `workspace.GF_TutorialStart` had **no writer anywhere in the project** — the only code touching it was
`TutorialService` reading it. First Spear therefore never began in ordinary play; it only ran in earlier sessions because I set
the attribute by hand. The cinematic completion point now hands off to `TutorialService.begin`, and the profile load offers the
tutorial to anyone who watched the intro but never finished it. That is literally the requirement: a skip must not erase the
tutorial.

**Measured.** Fresh state via the new `resetForTest` hook (`introSeen=false, tutorialActive=false`), then the skip signal:
`introSeen=true, Tutorial_Active=true, Tutorial_Step=1, Tutorial_Id=move, Tutorial_Text="Move to the marked deck plate"`.

**What looks wrong.** The tutorial card sits on top of the `WAR TABLE` signage. The step-1 plate spawns directly under the
player's feet, so "move to the marked plate" is already satisfied on the first frame — the objective reads as done before the
player moves. There is no transition at all between the cinematic ending and the card appearing.

## v288 — the Armory could not be opened at all after boot (V343, V344)

**Scene / camera.** Station concourse, third-person, Armory panel opened through the `GF_ArmoryOpen` hook.

**What the frames show.** V343: `ARMORY · 58650 CREDITS · RANK 15`, rows for AR-01, P-01 (EQUIPPED), SG-04 (EQUIP), MR-07
(EQUIP), LMG-12 (EQUIPPED) with per-weapon stats. V344: scrolled to `ER-16 Pulse Rifle — Energy · 30 DMG · 40 MAG · Auto —
BUY 3000`, plus the CLASS strip with Assault selected.

**Two functional defects found, both of which made the screen unusable rather than merely ugly:**
1. `findAnchor()` returned a **cached Vector3**. The station is rebuilt during boot ("station missing after boot; rebuilding
   from Main"), so the cached position pointed at a rack that no longer existed and the distance check never passed. The Armory
   silently refused to open from anywhere. It now returns the part, re-resolves when the part loses its parent, and compares
   against `anchor.Position`.
2. The weapon list is a `ScrollingFrame` whose **canvas was never set**, so its sixth row (ER-16, the only unowned weapon and
   the only BUY in the game) sat below the footer and could not be reached or bought. Canvas is now the rendered row count.

Verified separately through the real remotes: `BUY LMG12` returned ok with credits 60050 → 58650 (exactly −1400), and
`EQUIP LMG12` returned ok.

**What still looks wrong.** There is no purchase confirmation — BUY charges immediately; success is only visible as the row
becoming EQUIP, while a failure replaces the credit balance text with the reason. `CLOSE [E]` is keyboard-only, so touch and
gamepad players can open this panel but not close it.

## v291 — settings exist, persist and actually change behaviour (V345, V346)

**Scene / camera.** Station concourse, third-person, Settings panel opened through `GF_SettingsOpen`.

**What the frames show.** V345 first run: `SETTINGS`, `Aim sensitivity 1.00x`, `Master volume 100%`, `Subtitles ON`,
`Reduced motion OFF`. V346 after a full session restart: the same panel showing **2.00x** and **40%** — the values written in
the previous session — with the subtitle `Drop bay is hot. Pod is loaded.` visible because subtitles are on.

**What was actually missing.** `profile.settings` existed in `defaults()` with `aimSensitivity`, `invertY`, `subtitles`,
`reducedMotion` and **nothing read any of it**; there was no settings screen at all. Now `SettingsService` validates key and
type, clamps ranges (sensitivity 0.25–3, volume 0–1), saves through the profile and publishes `GF_Setting_*` attributes that the
camera, captions and audio read.

**Measured, including a real A/B on subtitles:** with subtitles off the cinematic played (`enabled=true`, `playing=true`) and
produced **no caption text at all** for 3.5 s; switched on, it produced *"The war table is already tracking a second
incursion."* and then *"Your armoury is thin. Make every round count."*

**A bug of mine caught by reading the client log, not the server log:** my first `subtitlesEnabled()` helper was inserted at line
58 while caption writes happen at line 39, so those writes called a local function that did not exist yet —
`CinematicUI:39: attempt to call a nil value`, and the whole cinematic died. Server logs showed nothing, which is why it took a
client-side log read to find. The helper now sits immediately after the `LocalPlayer` binding.

**What still looks wrong.** `Reduced motion` is stored and published but **nothing consumes it** — toggling it changes a label
and nothing else. Volume applies to sounds started after the change, not to loops already playing. The panel has no gamepad focus
and no close control, and it can only be opened through an attribute, so a player without a keyboard cannot reach it.

## v293 — the second augment socket is a real rule now, but there is still nothing to look at

**No frame.** Augments have no UI surface anywhere in the project: the Armory lists weapons and classes only. So this row is
evidence-by-response, and that limitation is the finding rather than a detail to bury.

**What was missing.** `AugmentService` only *applied* effects (`magazine`, `reloadTime`). There was no socket assignment at all,
`profile.weaponMastery` and `profile.ownedAugments` had **no writers anywhere**, and the second socket the spec describes was
therefore unreachable by any route.

**What it does now.** `socketsFor` returns 1 for an owned weapon and 2 once `weaponMastery[weapon] >= 5`, and
`ArmoryService` refuses with a reason instead of silently accepting. Kills now call
`ProfileService.addMastery(attacker, weaponId, 1)`, so mastery actually accumulates with the weapon you are holding.

**Measured A/B through the live remote:**
1. `{action="augment", weapon="AR01", slot=2, id="ExtendedMagazine"}` → **ok=false, reason="requires mastery 5"**
2. granted mastery 5 + the augment (Studio hook, gated behind `GF_TestHooks`)
3. same request → **ok=true**, `GF_AugmentEquipped="AR01:2=ExtendedMagazine"`, `GF_Mastery_AR01=5`

**What looks wrong.** Everything about the player's side. No augment screen, no socket display, no mastery bar, no acquisition
path for augments themselves — the boss reward grants blueprints, not augments. A player cannot perceive any of this work yet.

## v294 — augments finally have a surface (V347)

**Scene / camera.** Station concourse, Armory panel scrolled to the bottom.

**What the frame shows.** Below the weapon rows and above the CLASS strip:
`AUGMENTS · LMG12 · MASTERY 5`, `SOCKET 1 · ExtendedMagazine`, `SOCKET 2 · EMPTY`. Before mastery the same strip read
`AUGMENTS · LMG12 · MASTERY 0`, `SOCKET 1 · EMPTY`, `SOCKET 2 · LOCKED (MASTERY 5)` — the rule is drawn, not hidden.

Measured in the same run: `grantTestAugment` → `sockets=2, mastery=5`; then `augment slot 1` → `ok=true,
slotted1=ExtendedMagazine`.

**Two of my own errors on the way in, both caught only by reading the client log:**
1. `b.Text = … \n or (…)` — a newline before `or` split the statement and the whole Armory script failed to compile
   (`Incomplete statement: expected assignment or a function call`).
2. A continuation line of a comment lost its `--` prefix, which broke the same script at line 149. The panel showed nothing at
   all, and the server log was clean.

**What looks wrong.**
1. **The station deck is a solid orange field** in this frame. That is the same signature as the airstrike light saturation fixed
   earlier, but nothing was cast here and no blast exists — the cause for the station interior is **not identified**, and I am
   not going to pretend otherwise.
2. Socket buttons cycle through owned augments on click. There is no picker, no effect description, and no way to clear a socket.
3. Acquiring an augment still has no in-game path; only the gated Studio hook grants one.

## v295 — the orange wash was orphaned boss VFX, and it is gone (V348)

**Root cause.** Not lighting, not a light, not a part colour, not post-processing, not a GUI. I checked each of those in this
order and all of them were clean: the runtime Lighting preset was exactly the documented station preset (clock 12, brightness
0.35, cool ambient, exposure −0.15), the 43 station lights were the tamed cool fixtures at ≤0.8, every deck part was grey
`Metal`, post effects were neutral (tint 250,248,255, bloom 0.15), and no GUI had an orange or large opaque frame.

The query that found it was a **nearest-parts** probe rather than a colour filter: the three largest things within 30 studs of the
camera, behind the deck, were `BossBlast` — 19×19×19, `Neon`, colour `255,132,64`, transparency 0.85. Three translucent orange
spheres enclosing the station spawn is exactly what a solid orange field looks like.

`BastionWalker.explode()` cleaned up inside the coroutine that also animated the blast. When the boss is torn down mid-animation
(mission end, reset, module teardown) that coroutine dies and the parts survive **forever**.

**Fix.** Each blast carries `GFVfxBorn` and an independent 0.9 s destroy deadline, and `Bastion.cullVfx()` sweeps any
`BossBlast`/`BossBeam` older than 1.2 s every 2 s, counting what it removed in `GF_BossVfxCulled`.

**Verified.** `blastsInStation=0` and no errors after boot; V348 is the same camera and panel as V347 with the deck back to grey
and a crew rig visible on the right.

**Process note, because it cost two continuations:** my earlier part searches required *orange colour AND large volume*, which
excluded a 19-stud sphere entirely, and my later query required *flat and wide*, which excluded a sphere too. A nearest-things
probe would have found it the first time.

## v296 — the boss blueprint pity was 5 clears, not 3, and now it is provably 3

**No frame.** This row is a progression rule with no interface: the boss debrief does not mention blueprints at all, which is
recorded below as the actual defect that remains.

**What was wrong.** `BOSS_PITY` was **5**. The spec requires the blueprint to be guaranteed on the **third qualifying clear**, so
a player could beat the major boss four times and still hold no permanent unlock — and nothing in the game said so.

**Measured, with the random chance switched off** (`GF_ForceNoBlueprintChance`) so only pity can grant:

| clear | kills | pity | blueprint | granted |
|---|---|---|---|---|
| 1 | 1 | 1 | false | false |
| 2 | 2 | 2 | false | false |
| 3 | 3 | 0 | **true** | **true** |
| 4 | 4 | 1 | true | false |

`GF_LastBossReward` recorded `VEYR:kills=3:pity=0:bp=true`. Clear 4 does not re-grant, so the unlock is permanent and not
duplicated.

**What still looks wrong.** The player is told nothing: no blueprint announcement, no item name, no pity countdown, no indication
of what the unlock enables. A rule that is correct and invisible does not satisfy the player-facing half of the requirement, so
both rows stay pending owner review rather than being called done.

## v297 — the blueprint pity is now visible where the player already looks (V349)

**Scene / camera.** Station, third-person, standard post-mission debrief after a forced-failure extraction.

**What the frame shows.** `OPERATION FAILED`, the usual zeroed payout rows, and then two new lines:
`ASCENDANCY RESEARCH · BASTION_WALKER · CLEAR 1` and `Blueprint guaranteed in 2 more clears (1/3).`

**Path.** `grantBossReward` stashes the outcome on the profile; `RewardsService.grant` attaches it to the next
`MissionComplete` payload and clears it, so the debrief reports it exactly once through the real mission-end path — not a
fabricated client message. Verified on a live mission: kill count 1, pity 1/3, countdown rendered.

**What looks wrong.** The unlocked blueprint is never named — when the guarantee fires the debrief will say "Blueprint
recovered — permanent unlock." without saying *what* was unlocked or what it enables. There is also no standing research
readout anywhere in the station; progress is only visible immediately after a mission.

## v298 — the deploy button tells the truth now, and its message lands in the wrong place (V350, V351)

**What changed.** The deploy button used to set `DEPLOYING…`, disable itself for a fixed 4 seconds and re-enable whether or not
anything had happened — a refusal was indistinguishable from a slow launch. `StationService.deploy` now validates the operation
against the real template set, gates difficulty on military rank (Easy 1 / Normal 3 / Hard 6 / Extreme 10) and returns
`(ok, reason)`, firing `DeployStateChanged` either way. The client keeps a status line, ends the spinner on the server's answer,
and arms an 8 s watchdog that reports "No response from command" instead of spinning forever.

**Measured.** Invalid operation → `ok=false, reason="unknown operation"`. Extreme with rank 15 → `ok=true`.
`GF_DeployRejected` / `GF_DeployAccepted` recorded. V350 shows the refusal text in the panel.

**What looks wrong.**
1. The status line is at `y=308` and the deploy button at `y=330` — they **collide**, and the reason string is clipped by the
   panel edge. Half the message is unreadable. My first placement (y=386) overlapped the controls hint, so this is a second bad
   position rather than a fix.
2. Dispatch listing and debrief still have no loading, error or retry states at all; only deploy got them.
3. **The orange deck returned in V351**, and this time there is no orange part and no orange light near the camera: the nearest
   parts are `Subfloor`, `HangarDeck`, `Ceiling`, `WarTableBase` and two grey `Girder`s, all `Metal`, all opaque. So the earlier
   `BossBlast` finding explained *one* source; this second source is lighting-driven and still unidentified. Next step is to dump
   light properties at the exact moment the deck goes orange rather than after.

## v299 — the refusal state does not render reliably, and the orange wash is intermittent (V352, V353)

**What I tried.** Move the refusal out of a separate status line (which collided with the button) and into the deploy button
itself: `REFUSED · <reason> · RETRY`, amber, with the default text restored on reset.

**What happened.** V353 shows the button back at `DEPLOY TO VEYRA-7` with **no refusal text anywhere** after the server refused the
same invalid operation. The identical refusal produced a visible line in V350/V351 (rendered under the difficulty row, clipped by
the panel edge). So the server half is measured — `ok=false, reason="unknown operation"`, `GF_DeployRejected` recorded — and the
**client half is not proven**: something clears the text after it is set, and I have not yet found what.

**Orange deck: now known to be intermittent.** V352 and V353 are the same camera, framing and session type as V351, and the deck is
clean grey in both. Across this continuation the following were excluded with measurements: warm-coloured parts anywhere
(92 found, all distant alien visor/crest pieces), parts within 60 studs of the camera (Subfloor/HangarDeck/Ceiling/WarTableBase/
Girders — all grey `Metal`, opaque), reflective parts (0), terrain voxels under the station (all Air), post effects (neutral), and
workspace `Highlight`/`Beam`/`SurfaceGui`/`BillboardGui` (player highlight fill is 24,34,48 with 1.0 fill transparency; signs and
slot boards only). A defect that only appears sometimes needs a capture-and-dump in the same instant, which is the next step.

## v301 — why the refusal never rendered: a colour constant that does not exist

**Root cause found, and it is exact.** `StationUI` defines `CYAN`, `AMBER`, `PANEL`, `TEXT`, `MUTED`. My reset helper wrote
`deploy.TextColor3 = WHITE`. `WHITE` is nil, so the very first response hit
`Unable to assign property TextColor3. Color3 expected, got nil` **inside** the handler, which killed it before any refusal text
was written. That is why V350/V351 showed a stale line from the earlier status-label version and V353 showed nothing at all.

**Fixed.** The constant is now `TEXT`, and both colour writes go through `pcall` — a cosmetic constant must never be able to
silence an error path.

**New problem, recorded rather than papered over.** After that fix the deploy button could not be found in any later play session:
scanning every `TextButton` for the text `DEPLOY` returned nothing, including with the new `GF_StationPanel` force-open attribute
set. The button existed in V350–V353. The likely explanation is that `StationUI` now stops part-way through construction, which
would take the whole war table panel with it. **This is not verified** — the next continuation must read the client log
immediately after join and find where the script stops, before any further claims are made about this row.

## v303 — the orange deck wash is finally explained and closed (V354, V355, V356, V357)

**What the A/B proved.** Same camera, same 12 cool tamed lights, same session:

| EnvironmentSpecularScale | EnvironmentDiffuseScale | deck |
|---|---|---|
| 0.04 (preset value) | 0.18 | solid orange field across the whole floor, character legs tinted (V354) |
| 0 | 0 | clean dark navy (V355) |
| 0 | 0.18 | clean dark navy, environment diffuse intact (V356) |

**Cause.** This place sits under a saturated orange/magenta nebula sky. Roblox samples the sky for specular on `Metal`, so a large
flat Metal deck mirrors the sky at grazing angles. 0.04 specular was enough. Everything I had excluded before — lights, part
colours, post effects, reflections, terrain water, GUI overlays, `BossBlast` leftovers — really was innocent, and the `BossBlast`
finding explained only the separate station-spawn spheres.

**Consequence.** `EnvironmentSpecularScale` is now 0 in both presets, with the measurement recorded in `DECISIONS.md`. The old
"DiamondPlate banned on the deck" rule was this same effect through a different material.

**Verified after the change:** booted with the preset applied (`spec=0.00 diff=0.18 brightness=0.35`) and V357 shows a clean,
correctly lit concourse with no orange anywhere.

## v304 — no dummy UI text, but the mission HUD renders nothing on entry

**Audit method.** Enumerated every visible `TextLabel`/`TextButton` in `PlayerGui` twice: once at the station and once with
`GF_InMission=true`. 18 strings at the station, 19 in mission, all real copy (operation names, difficulty, sector copy, controls
hint, "Deployment accepted."). No `Coming Soon`, no TBD, no debug counters, no dummy currency. Debrief and war-table frames were
measured `Visible=false` when out of range, so no stale panels.

**Two real defects surfaced by the audit instead:**
1. A `ScreenGui` named **`Freecam` is enabled at spawn** — a dev leftover sitting in the shipping UI.
2. **The mission HUD is blank on entry.** After a successful deploy (`inMission=true`) the `GFMissionHUD` and `GF_HUD` GUIs are
   enabled but contain **zero** non-empty labels until something fires an update. I added `CombatService.publishAmmo` and
   `ObjectiveService.publish`, and `StationService.deploy` now pushes vitals, ammo, objective and salvage about 0.6 s after the
   teleport — and the HUD was **still blank** in the same test. So the client side does not paint shield/ammo from those payloads;
   that consumer has to be found before this can be called fixed.

Recorded honestly: the audit cleared the placeholder question and uncovered a HUD regression that is worse than a placeholder,
because a player entering a mission sees no shield, no ammo and no objective.

## v305 — the in-mission HUD was being switched off by the deploy verdict (V358)

**Root cause.** `DeployStateChanged` carries two different payload shapes: the zone publish `{zone=...}` and the deploy verdict
`{ok=...}` I added last continuation. `StationUI`'s zone handler did `onStation = state.zone ~= "Mission"` unconditionally, so a
verdict payload (no `zone`) set `onStation = true` and called `setMissionHudVisible(false)` — disabling the entire in-mission HUD
at the exact moment a mission was accepted. That is why the HUD was enabled-but-empty in the previous continuation, and why it
looked fine after a mission had failed (a zone payload arrived then).

**Fixed two ways:** the zone handler ignores payloads without a `zone`, and every verdict payload now includes the current zone.

**Verified.** `inMission=true, GF_HUD.enabled=true, GFMissionHUD.enabled=true` with live content: `SHIELD …`, `AR01`, `28 / 28`,
`AIRSTRIKE [Z]`, and on screen V358 shows the shield bar, `PRIMARY OBJECTIVE / Sabotage the Ascendancy relay`, `SALVAGE 0·0·0`,
the ability buttons and the ammo counter.

**What is still wrong in that same frame.** The HUD paints **`SHIELD 0` and a `DOWNED` overlay** on entry even though the server
reports the player at 100 health, walk speed 17.5 and no downed attribute. `VitalsService.reset` clears `s.downed` and republishes,
and deploy now calls reset before the paint — the client still received a payload claiming downed. So the payload source is not yet
traced; the honest status is "HUD renders, but renders a wrong initial state", which is arguably worse than blank because it tells
the player they are down.
