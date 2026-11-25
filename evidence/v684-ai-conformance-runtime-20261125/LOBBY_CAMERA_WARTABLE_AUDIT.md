# Lobby, war table, minimap, difficulty, and camera audit — 2026-11-25

Initial runtime audit prompted by the user's direction: Helldivers-like over-the-shoulder camera/aiming, major lobby work, abilities in lobby, brighter lighting, missing hard/insane options, Helldivers-like war table, and lobby minimap.

Artifacts:

- `raw/station_spawn_baseline_0.jpg`
- `raw/station_war_table_near_0.jpg`
- `raw/station_gui_texts.json`
- `raw/station_deploy_ui_texts.json`
- `raw/station_ability_gui_scan.json`

## Findings

### War table difficulty selection is incomplete

The captured war table UI shows only `EASY` and `NORMAL`. Runtime client source confirms:

```lua
local difficulties = { "Easy", "Normal" }
```

The server deploy options contract advertises `Easy`, `Normal`, `Hard`, and `Extreme`, so the client UI is narrower than the server contract. The current spec vocabulary appears to use `Extreme`, not `Insane`; adding `Insane` is a product/spec decision, not merely a UI repair.

### War table presentation is functional but not Helldivers-like

The captured UI is a flat rectangular side panel with rows of text buttons. The 3D table behind it is a cyan holographic silhouette. It does not yet provide the Helldivers 2 fantasy: rotating planet/galaxy map, sector/front-line control state, spatial mission pins, orbit-layer composition, or a dramatic theater-of-war read. It is a usable menu, not a product-defining war table.

### Lobby readability/lighting is weak

`station_spawn_baseline_0.jpg` shows strong sci-fi mood, but large portions of the station are near-black. War-table cyan emissives read well; navigation, workstations, and surrounding interactables do not. A real lighting pass should measure multiple player positions rather than rely on this single angle.

### Minimap exists but is not a useful lobby map

A minimap is visible in the top-right of station captures, so minimap presence is GREEN. Its usefulness in the lobby is RED/PARTIAL: it appears terrain/mission-oriented and does not communicate station rooms, war table, armory, dispatch board, exits/docking pads, POIs, or squad members.

### Abilities are not cleanly absent, but lobby ability UX is unresolved

The GUI scan found effective-visible entries for `AIRSTRIKE [Q] / READY` and `DOME [F] / READY` in the station. Server `AbilityService` inspection did not show a station-zone gate in the `UseAbility` handler. However, the first station spawn capture does not visually read as a complete ability/weapon HUD, and the armory prompt/panel was not visible at spawn. This needs a focused interaction/cast test before a pass/fail claim. Product target: ability slots, cooldowns, and armory ability editing should be obvious and usable in the lobby.

### Helldivers-style over-the-shoulder camera is explicitly incomplete

Runtime client source says:

```lua
-- Third-person camera envelope. Over-the-shoulder rig lands in Phase 2 polish.
```

`CameraCtl` currently applies `humanoid.CameraOffset = Vector3.new(1.75, 0.6, 0)`, so there is a right-shoulder offset, but the codebase itself says the full over-the-shoulder rig is not done. Needed: stable hip-fire framing, smooth ADS shoulder transition, collision/occlusion handling, recoil/reticle relationship, correct shoulder swap, and consistent station/mission behavior.

## Recommended implementation order after edit authorization

1. Camera/ADS feel first — highest moment-to-moment impact.
2. War table as central planet/hologram interaction rather than a flat side menu.
3. Expose all supported difficulties; decide whether `Insane` is a rename or new tier.
4. Lighting/readability pass for navigation and interactables.
5. Lobby-specific minimap/POI rendering.
6. Unambiguous lobby ability loadout/cooldown presentation and cast test.

## Hard blocker

No implementation was attempted because `playtest1_current/` is missing on this machine and the project instruction says to ask before editing game code when it is absent. Runtime evidence capture and audit can continue without it; safe code changes cannot.
