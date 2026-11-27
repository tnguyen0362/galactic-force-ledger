# Player SEAL-style kit

Open-face operator armor for the player (face always visible), built per R15 limb so it fits any normalized R15 body.

- `blender/gen_player_kit.py` - parametric generator (Blender 5.x): collections PLAYERKIT (limb-local meshes), PLAYERKIT_ASM (preview), PLAYERKIT_PROXY (mannequin face-visibility check).
- `blender/export_player_kit.py` - writes `player_kit_data.luau` + the GLB (set `GF_REPO`, `GF_ART_OUT`).
- `make_install_player.sh <assetId>` -> `install_player_kit.luau` (run in the Studio Edit DM; builds `ServerStorage.GF.Art.PlayerKit`).
- Runtime: `AppearanceService.dress()` clones the templates, scales each by `limb.Size / refDims`, welds with the 180deg-Y import fix, tints per group from the suit config.
- Body: `StarterPlayer.StarterCharacter` is a default blocky R15 (attribute `GF_DefaultR15`); the old custom character is backed up at `ServerStorage.GF_Backup.StarterCharacter_Halo`. Runtime scale 1.28 keeps the old 6.87-stud height.
