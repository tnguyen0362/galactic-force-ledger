# v688/v689 lobby, HUD, cursor, minimap, and dodge addendum — 2026-11-25

## Deployments

- v688 deployed all 95 scripts, zero compile failures, saved as cloud version **688**.
- v689 deployed all 95 scripts, zero compile failures, saved as cloud version **689**.

Raw logs: `raw/deploy_v688_stabilization.log`, `raw/deploy_v689_stabilization.log`.

## v688 fixes

1. Interactive panels now actually release mouse lock. The controller scans the real visible war table, debrief, armory, settings, and tactical-map surfaces instead of relying on the effectively static `GF_UIOpen` attribute.
2. The base combat HUD remains active in the station so ability slots and dodge charges are visible in the lobby. Ammo and crosshair are hidden outside missions.
3. The minimap now switches to a station-deck layout in the lobby with labelled WAR / ARM / DSP / POD markers and a moving player marker.
4. Stale control copy corrected: tutorial and station footer now say CTRL dodge and Q/F abilities instead of Shift/Q and Z/X misinformation.
5. First dodge rework attempted to preserve vertical velocity, but runtime measurement exposed that direct server velocity writes were fought by character network ownership.

## v689 fixes

1. Dodge now uses `LinearVelocity` in **Plane** mode. This keeps the physics constraint effective under character network ownership while constraining only X/Z and leaving vertical velocity to gravity and impacts.
2. The boss HP bar is mission-only. v688 visual inspection exposed a Bastion bar leaking into the lobby; v689 verifies it hidden.

## Runtime evidence

Artifacts:

- `raw/v688_station_hud_minimap_0.jpg`
- `raw/v688_station_hud_minimap.json`
- `raw/v689_station_before_dodge_0.jpg`
- `raw/v689_war_table_cursor_0.jpg`
- `raw/v689_dodge_check.json`

Measured live v688/v689 results:

- Lobby minimap station mode: `GF_MinimapStation=true`; capture visibly shows WAR, ARM, DSP, POD labels and the player marker.
- Lobby ability bar visible: `AIRSTRIKE [Q] READY`, `DOME [F] READY`.
- Lobby ammo/crosshair hidden: `ammo=false`, `cross=false`.
- Control hint reads `Dodge [Ctrl]` and `Abilities [Q]/[F]`.
- v688 exposed boss-bar leakage visually; v689 query: `boss=false`.
- Forced war-table panel: `panel=true`, `GF_UIOpen=true`, `MouseBehavior=Default`; capture shows the panel with the cursor released.
- Actual MCP-driven LeftControl dodge:
  - before `(-0.01, 21.80)`
  - after `(-0.01, 8.25)`
  - displacement approximately **13.55 studs**, matching the spec's ~13-stud roll distance.

## Still open / not yet proven

- Death/bleedout/redeploy/debrief flow still needs runtime diagnosis and repair.
- Loading-screen visibility during an actual mission transition still needs capture.
- FPS measurement/performance profiling remains open.
- Natural Scout beacon channel/cancel, natural Officer sweep, weak-core precision damage, and broad general bug audit remain open.
