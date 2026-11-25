# v702 Combat Audio and Live Hit-Registration Verification

Date: 2026-11-25
Live cloud version: v702
Harness: `tools/verification/run_audio_combat_verify.py`
Machine-readable evidence: `raw/audio_combat_verification.json`
Log: `raw/audio_combat_verify_v702.log`

## Runtime sequence actually observed

A controlled Marksman was moved into a flat open lane and engaged with real mouse fire through the actual client Weapon input path. The camera used the Controller's supported `GF_CamPos`/`GF_CamLook` evidence override rather than fighting the custom camera loop.

### Live hit registration and kill

- First real-fire burst: server `Accepted=10`, server `Hits=10`, zero rejects.
- Marksman shield went `60 -> 0`; health went `147 -> 27`.
- Short follow-up burst killed the target.
- Final combat counters: `Accepted=26`, `Hits=12`, `Rejected=0`.
- Target final state: `Dead=true`, `Health=0`.

This is positive evidence that the server hitscan path can hit and kill a live enemy when the camera ray is actually on target.

### Hit/death audio

- Enemy-hit events fired through the real client impact path: `count_hit_flesh=9`.
- Enemy-death event fired on the kill: `count_enemy_death=1`.
- The death voice captured immediately after the kill was:
  - asset `rbxasset://sounds/metal.ogg`
  - pitch `0.67205`
  - volume `0.36`
  - path `Workspace.GFAudioAnchors.GFAudioAnchor_13.Voice14`
- No `uuhhh.mp3` instance remained in the client sound scan.
- The client-side stock death sanitizer removed the legacy character `Died` sound (`gf_stock_death_sounds_removed=1`).

### Surface-versus-flesh separation

After the enemy was dead, real fire was aimed into open terrain:

- `hit_surface` increased `2 -> 13`
- `hit_flesh` stayed fixed at `9`
- `enemy_death` stayed fixed at `1`

Terrain/prop impacts therefore no longer trigger organic flesh-hit audio.

## Verdict

The stock-oof removal, sci-fi hit feedback, enemy-death event replacement, and surface/flesh audio separation are now runtime verified. This also provides a positive live-enemy hit-registration baseline for the broader aiming audit.

## Honest limits

- The enemy placement and evidence camera were controlled; this verifies mechanics and routing, not subjective aiming feel.
- Some positional voices are pooled and overwritten quickly, so sound-object evidence must be captured immediately after the event.
- The harness proves hitscan correctness in a controlled lane. It does not prove spread/reticle agreement, recoil feel, ADS feel, or practical unassisted mouse aiming.
