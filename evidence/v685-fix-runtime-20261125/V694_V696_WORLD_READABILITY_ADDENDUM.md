# V694-V696 World Readability Addendum

## Scope

Runtime stabilization batch targeting mission-spawn readability defects visible in the first seconds of a mission: an empty/off-center minimap, a permanent boss banner, an oversized landing-pad/baseplate read, and an over-saturated sky grade.

## Implemented

- Tactical-map heightfield now follows the active squad centroid instead of remaining centered on the objective hundreds of studs away.
- Mission minimap objective/LZ/squad markers are clamped to the rim rather than hidden when outside the 320m heightfield window.
- Boss HP bar is no longer inferred from stale `BossHealth` values and is suppressed for distant, undamaged field bosses; it appears only when a boss is close enough to engage or has taken damage.
- Mission boot/reset clear untagged boss residue defensively.
- Landing pad reduced from a large rectangular black slab to a smaller low-profile slate pad with smaller approach strips.
- Supply crate contrast adjusted; cap reduced and darkened.
- Mission lighting graded toward the spec's pale blue-green/dusty horizon using atmosphere tuning plus a `ColorCorrectionEffect`.

## Runtime verification

- Deployment v694: 125/125 scripts, save version 694.
- Deployment v695: 125/125 scripts, save version 695.
- Deployment v696: 125/125 scripts, save version 696.
- v696 runtime verification after deployment to `SABOTAGE_RELAY`:
  - `bossVisible=false`
  - `bastion=true`, `hp=3600` (field boss exists in ecology but distant/undamaged)
  - `mapBlips=3`
- Capture: `raw/v696_mission_spawn_final_0.jpg`

## Honest interpretation

The first-person-visible spawn scene now has:

- no premature Bastion boss banner;
- a terrain-filled minimap with an objective rim marker;
- a less dominant spawn pad;
- a greener, less saturated sky/terrain grade.

This is not a complete terrain-generation or skybox solution. The terrain still reads as terraced/noisy rather than a fully composed Helldivers-style theater, and the supply-crate cap still reads as a simple yellow plate. Those remain open foundational visual-quality items.

## Loading transition verification

A separate v696 runtime probe triggered `returnToStation` and sampled inside the transition window:

- during: `teleporting=true loadingVisible=true`
- after: `teleporting=false loadingVisible=false`
- capture: `raw/v696_loading_transition_0.jpg`

This verifies the loading screen can appear and clear during a real in-session station-return transition. It does not yet prove every transition path (initial join, deployment, extraction, failure) or that the fixed-duration window is visually sufficient on slow machines.
