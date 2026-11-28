# BACKLOG — spec-linked bugs and low-priority issues

Per V3-10, every entry names the requirement it serves. Items with no requirement mapping are not
worked ahead of absent launch content.

| Bug | Observed | Requirement | Severity | Status |
|---|---|---|---|---|
| B1 | Sky dome renders as a giant pale sphere intruding into every exterior frame | MICRO-047, V2-27 | high | open |
| B2 | Camera cannot be overridden: `Controller` rewrites `Camera.CFrame` every frame, so wide/cinematic captures fail | V2-30, V2-23 | high | open |
| B3 | One hue dominates the scene (sky, terrain, rocks, outpost, both factions) | V2-26, MICRO-015 | blocking | addressed-pending-publish — BiomeLook v2.1 per-biome lighting + orange-haze HD2 pass in Missions Edit DM 2026-11-28 (unsaved) |
| B4 | `DODGE 2/2` label clipped by the viewport bottom edge at 1100×680 | V2-34, MICRO-088 | medium | open |
| B5 | Station spawn shows no window/planet; hub has no armory, dispatch or hangar geometry | V2-23, MICRO-001..010 | blocking | resolved — armory/dispatch alcoves v143-149, StationHangar navy/orange hangar + pods at back 2026-11-28 (unsaved in Playtest1 Edit DM) |
| B6 | Relay is a cylinder stack with no console/conduit/antenna; terminal attribute is on a hidden part | V2-28, MICRO-053 | high | in-progress — legacy primitive site props now gated behind GF_LegacySiteProps attr; SiteDressing service (FOB + story beats) in Missions Edit DM 2026-11-28 |
| B7 | Only `Rifleman` spawns; `Scout/Marksman/Heavy/Officer` never appear despite config | V2-11, LC-002 | blocking | open |
| B8 | `hit_flesh` cue also plays on terrain impacts (no material gate) | V2-37 | low | open |
| B9 | War table shows static "SECTOR CONTESTED" text with no campaign source | V3-14 (fake live data), MICRO-092 | high | resolved — war table rebuilt 2026-11-28: angular region plates on planet face, liberation bars, live replication (MILITARY RANK verified in capture). DROPPED per owner — no further work |
| B10 | Redeploy respawns at `GF_LZ` only because of a recent patch; pod visual is absent | MICRO-034, V2-33 | medium | partially-addressed — 4 walk-in drop pods built in lobby 2026-11-28 w/ entry detection + squad seat wiring (unverified end-to-end) |

- LC-017 map polish: raise relief contrast to 0.10..0.75, add contour bands every 10 studs, a north arrow,
  grid coordinates, and per-marker labels with distance-to-objective.

## 2026-11-28 additions (delta)
| Bug | Observed | Requirement | Severity | Status |
|---|---|---|---|---|
| B11 | Mobile: reload/dodge/abilities have NO touch bindings — input table is keyboard/gamepad only | V2-34 | blocking | open — largest mobile gap, documented in WORK_STATE |
| B12 | Mobile camera touch sensitivity untuned (TouchSensitivity exists but never device-tested) | V2-30 | high | open — needs owner-on-device iteration |
| B13 | BastionWalker visual swap untested: template not installed, movement wiring absent (visual static at spawn) | — | high | open — integration steps in WORK_STATE 2026-11-28 |
| B14 | GF_CargoShip materials import pale in Roblox lighting; no flight/spawn system exists | — | medium | open — design decision pending (supply flyovers vs parked vs extraction) |
