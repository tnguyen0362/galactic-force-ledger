# v700 Spawn Supply-Crate Verification Addendum

Date: 2026-11-25
Live cloud version at capture: v700
Harness: `tools/verification/run_supply_verify.py`
Machine-readable evidence: `raw/supply_prompt_verification.json`
Captures: `raw/supply_spawn_layout_0.jpg`, `raw/supply_before_use_0.jpg`, `raw/supply_after_use_0.jpg`

## Runtime sequence actually observed

1. A fresh mission deployment spawned three supply crates around the LZ.
2. Player spawn/LZ proximity was measured:
   - nearest crate: `5.22` studs from the player root after settling
   - other crates: approximately `9.29` and `9.89` studs away
   - crates were therefore visible/usable at insertion rather than hidden along the route
3. Two real `G` key inputs threw two grenades:
   - `GrenadeCharges 3 -> 1`
   - HUD showed `GRENADE x1`
4. Real mouse fire input consumed ammunition through the authoritative fire path:
   - accepted server shots `0 -> 15`
   - HUD before resupply showed `13 / 28 · 168`
5. The player was positioned beside the nearest crate and a real held `E` input triggered the proximity prompt.
6. After resupply:
   - crate count decreased `3 -> 2`
   - server refill diagnostic: `ammo=28 reserve=268`
   - grenade diagnostic: `Frag 1->3 (max 3)`
   - `GrenadeCharges` returned to 3
   - HUD showed `28 / 28 · 268` and `GRENADE x3`
7. A second held `E` attempt at the same location produced no additional refill and no further crate-count change. The crate was destroyed on first use.

## Verdict

Spawn-proximate resupply, real prompt activation, ammunition refill, grenade cap behavior, client HUD update, and one-use destruction are verified for the current implementation.

## Honest limits

- The test used controlled teleport positioning beside the crate after independently proving spawn proximity. The prompt itself was triggered through real input.
- The reserve math was verified for AR01 without an intervening reload: 168 starting reserve plus one catalogue charge, capped at 268 (`1.6 × 168`, floored).
- Crate art remains simple and is still open under the broader visual-quality task.
