# v702 Surface Hit-Audio Correction Note

Date: 2026-11-25
Live cloud version: v702

`Weapon.luau` previously played the organic `hit_flesh` cue for every non-shielded ray impact, including terrain and props. That made ordinary misses sound like wet enemy hits. v702 separates enemy flesh hits from surface impacts: enemy models use shield/flesh cues, while non-enemy surfaces use a quieter high-pitched `hit_surface` cue.

Deployment proof: `raw/deploy_v702_surface_audio.log` shows 125/125 scripts deployed, zero failures, saved as cloud v702.

Honest status: implemented and deploy-verified; a dedicated real-fire terrain/enemy audio comparison still needs to be captured before marking the broader audio task fully verified.
