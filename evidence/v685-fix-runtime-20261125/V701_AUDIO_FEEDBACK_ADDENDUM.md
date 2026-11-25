# v701 Audio Feedback / Stock-Oof Removal Addendum

Date: 2026-11-25
Live cloud version: v701
Harness/evidence: `tools/verification/run_audio_verify.py`, `raw/audio_feedback_verification.json`, `raw/audio_real_fire_scan.json`, `raw/audio_verify_v701.log`

## What changed

- Removed the Roblox legacy `uuhhh.mp3` enemy-death cue from the authored audio event table.
- Replaced water-impact combat feedback with minimal sci-fi/impact substitutions using existing zero-upload bundled sounds:
  - `hit_flesh`: `impact_water.mp3` -> low-pitched `snap.wav`
  - `player_hurt`: `impact_water.mp3` -> low-pitched `bass.wav`
  - `enemy_death`: `uuhhh.mp3` -> low-pitched `metal.ogg`
- Added a client-side sanitizer that destroys locally injected legacy character `Died`/`uuhhh.mp3` sound instances as soon as they appear. These instances do not exist in the server datamodel, so a server-side deletion cannot reach them.

## Runtime evidence

- Fresh character scan: `gf_stock_death_sounds_removed=1`.
- No remaining character sound path ending in `.Died` was present after sanitization.
- No `uuhhh.mp3` sound instance remained in the client scan.
- Real mouse fire against a live Marksman produced `count_hit_flesh=16` through the actual Weapon client path.
- Positional hit voices in `Workspace.GFAudioAnchors` were `rbxasset://sounds/snap.wav` at volume `0.28`; rifle-fire voices were `metal.ogg` at volume `0.38`.
- The only remaining `impact_water.mp3` instance observed was Roblox's stock locomotion `Splash` sound, not a combat hit/death cue.

## Honest limits

- Enemy-death replacement is implemented and stock `uuhhh` removal is runtime-proven, but a natural enemy kill did not occur during the short audio harness window, so `count_enemy_death` remained 0. Hit feedback is runtime-proven; death-cue substitution still needs a kill-pass capture.
- This verifies sound identity/routing, not subjective mix quality. Final audio polish still needs real listening review.
