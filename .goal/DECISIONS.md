# GALACTIC FORCE — Decisions

## D1. The built terrain, not the analytic sampler, is the ground authority
Analytic `TerrainService.surfaceY` and the actual voxels drifted apart — measured at spawn:
sampler 49.7 vs terrain 26.0 (23.7 studs). Any placement that trusted the sampler floated or
buried geometry. Added `TerrainService.groundSurface(x, z)` which raycasts `workspace.Terrain`
(Include filter) and falls back to the sampler only outside the built region.
ObjectiveService, WorldDressing and StationService now all use a raycast-based surface.
Why: one authority removes an entire class of "object is 26 studs underground" bugs.

## D2. Extraction LZ is published at deploy, not derived from the caller
`ExtractionService.call` used to raycast down from whoever pressed the button. If that player
had already returned to the station the ship landed 800 studs away at Y≈824 and boarding was
impossible. `StationService.deploy` now writes `workspace:SetAttribute("GF_LZ", spawnPoint)`
and extraction prefers that attribute, falling back to the old raycast.
Why: the LZ is a property of the mission, not of the caller.

## D3. Interaction range 16, terminal outside the tower collision envelope
The relay tower's mesh body is 19.9 wide (half-depth ~10) and the terminal sits at +11 on Z,
so a 14-stud interact range left the terminal effectively unreachable from the approach side.
Range is now 16 and the terminal remains outside the collidable body.

## D4. Grade the approach instead of trusting a straight-line walk
`Humanoid:MoveTo` stops climbing when terrain is steep enough. Added a corridor blend in
`TerrainService`'s sampler: within 11 studs of the spawn→objective spine the height is pulled
to `BASE`, easing out over 30 studs. Verified: the player now walks the full 228-stud approach
and stops 3.8 studs from the terminal (was stuck at 24 studs out).

## D5. Primitive hit volumes stay invisible under authored rigs
Enemy logic parts remain raycastable for combat but `Transparency = 1`, and the authored
`AscendancyTrooper` rig is welded on top. Keeps combat code untouched while the silhouette is
the sculpted mesh.

## D6. One authored palette owns every asset, so imported meshes get reskinned
AI-generated meshes arrived with baked, saturated artwork in mutually clashing palettes
(orange energy, teal crystal, rose stone). Tinting `Color` alone does nothing visible because
the texture dominates. `ArtService.reskin` now clears `TextureID` and destroys
`SurfaceAppearance`/`Decal`/`Texture` children before applying colour and material, so
`Art` imports keep their geometry and lose their artwork. Cost: per-asset surface detail is
gone; benefit: cohesion, and one place to change the palette.

## D7. Ascendancy energy reads cold cyan, not hazard orange
Orange (255,150,60) on the relay core, the light masts and the outpost lamps read as human
industrial hazard striping and fought the planet's cool stone. Energy is now (96,214,232) at
reduced brightness (1.5, range 26) so it reads as alien tech rather than a bonfire.

## D8. Compounds sit on a levelled plateau; props follow terrain
Per-piece `groundY` placement stepped 30 wall modules from Y21 to Y34 down a hillside, which
read as scattered blocks. `OutpostService` now fills an air cylinder over the ring and a rock
cylinder beneath it, then places every perimeter module and tower at one Y. Verified spread
0.0 studs. Environment props still sample terrain because scatter should follow the ground.

## D9. Clusters, not uniform scatter
46 single cliff pieces at random yaw looked like dice on a table. Outcrops are now 2-4 pieces
sharing an orientation, packed within 9 studs, scale 0.16-0.38. Verified: 16 outcrops, 56
pieces.

## D10. Captures are a geometry oracle only
`screen_capture` drops Lighting post-effects — a pure-red `ColorCorrection` control rendered
grey — and applies a cyan cast that survived a complete lighting rewrite. Colour decisions are
therefore made from authored values and verified numerically; captures are trusted for
geometry, composition and instance counts only. Final art acceptance needs human eyes in
Studio, which is why `.goal/DONE` is gated on a human quality review.

## D11. No dynamic light shadows (v57)
Ten decorative point lights each took a shadow-map slice; the 4 outpost relay-core lamps alone cost
a pass. Every decorative light now runs `Shadows = false`. Verified in a live session: 10 lights /
**0 shadow casters** among lamps, frame p95 18.0 ms at the 60 FPS cap. Shadows stay on the sun only.

## D12. [OBSOLETE] ACP exploit config
The context-pruning plugin (`billion-context-pi`) was tuned via a private `~/.pi/acp.json` override.
User order (m02641) removed the plugin outright: package deleted from `~/.pi/agent/settings.json`,
`~/.pi/acp.json` deleted. Nothing here is actionable; kept only so the decision trail is not silent.

## D13. Audio is re-pitched engine sounds, no uploaded assets (v61)
Roblox has no runtime PCM synthesis, so "synthesized placeholders" means re-pitching engine-bundled
`rbxasset://sounds/*` (16 of 17 candidates verified loading with real durations).
`StarterPlayerScripts.GFAudio` holds a 15-event/3-loop table and a 14-voice round-robin pool;
`GFAudioRuntime` drives ambient, footsteps, jump/land, hurt, death, mission start/end and UI clicks.
Rationale: ships audio with zero upload budget and zero Open Cloud permission; cost is a borrowed
timbre. Falsifier: if it reads wrong-genre to a listener, swap the `EVENTS` entries for uploads —
that table is the single swap point.

## D14. Gait comes from velocity, not MoveDirection (v61)
Measured 212 consecutive client frames with the character travelling 19 studs while
`Humanoid.MoveDirection.Magnitude` stayed exactly 0, so intent-based footsteps silently never fire
in this movement setup. `GFAudioRuntime.step()` now integrates horizontal
`rootPart.AssemblyLinearVelocity` and emits a step every 3.0 studs. Verified 5 steps/17 studs,
6 steps/20 studs. Any future movement-driven logic must use velocity or a position delta.

## D15. `.goal/PAUSE` is a hard stop for the supervisor
The agent and the user share one Studio place. `~/.pi/goal-loop.sh` checks `.goal/PAUSE` before every
iteration and sits still while it exists (verified: sentinel present → zero `pi` invocations;
removal → iteration 1 starts). The user touches the file to take the place; `rm` hands it back.
An in-flight turn is not interrupted, so the boundary is the iteration, not the second.

## D15 — Goal supervisor was passing a mangled goal command (fixed 2026-11-22)
`~/.pi/goal-loop.sh` invoked `pi -p "/goal continue"` from Git-bash, and MSYS path conversion rewrote the argument into `C:/Program Files/Git/goal continue` before pi ever saw it. Evidence: `Get-CimInstance Win32_Process` on a live iteration showed the child node process with `-p "C:/Program Files/Git/goal continue"`. Every supervisor iteration therefore ran with a nonsense prompt instead of the `/goal` command — the goal prompt "not applying" was this, not the prompt text. Fix: `export MSYS_NO_PATHCONV=1` and `export MSYS2_ARG_CONV_EXCL='*'` at the top of the script. Verified with a stub `pi` that echoes argv: iter 1 now receives `-p /goal continue`, iter 2 `-c -p /goal continue`. Any future script that spawns pi with slash-prefixed arguments from Git-bash needs the same export.
### 2026-06-14 — Sky deletion over texture blanking, and why the station never built

- **Mission sky:** chose to `Destroy()` the Sky in the mission preset rather than assign empty strings. An empty Sky
  still renders a magenta nebula — proven at runtime with all six textures `''` and the frame showing nebula anyway.
  The engine default sky only exists when no Sky instance is present.
- **`ceilingY`:** the bug was invisible for three iterations because the station build error was swallowed by a
  `pcall` in `StationService.start`. Lesson: a swallowed build error reads as "the part does not exist", which sent
  me hunting for missing builders instead of reading the console. Console output is now checked after every play
  start before any conclusion about missing geometry.

## Remote surfaces come from one registry
`GF.Check` walks `ReplicatedStorage.GF.Remotes` and fails on anything not listed in
`Shared.Remotes.Names` / `.Functions`. Creating a remote inline (as `StationService.start` did for
`RequestReturn`) is therefore always a gate failure, even when the handler works: it leaves the folder
with a surface the registry and the check cannot see. Add the name to the shared list and create it
through `RemoteService.ensureRemotes` / `ensureRemote`.

## Stop Play before editing the place
Source and property edits made while a playtest is running are discarded when the playtest stops.
They appear to apply inside the running session, which makes the mistake invisible until the next
launch. Verify after stopping, then save.
