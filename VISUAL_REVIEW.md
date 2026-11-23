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
