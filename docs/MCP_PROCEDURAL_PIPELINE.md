# How agents build art here: Studio MCP + Blender MCP + procedural generators

Audience: any model or agent joining the project. This is the working method, not a wish list. Every step below has been run end to end for the hero squad (`tools/art/hero/`), the kit pieces (`tools/art/kit/`) and vegetation (`tools/art/vegetation/`).

## 0. The shape of the pipeline

```
 parametric generator (Python, Blender)      <- art is CODE: a table of variants + shared parts
   -> UV unwrap -> bake PBR atlas (albedo / normal / rough / metal)
   -> export GLB + a data .luau (joint pivots, part list)
   -> upload through Open Cloud (Assets API)    <- gives a durable rbxassetid
   -> generated installer .luau run in Studio   <- builds the rigged Model into ServerStorage
   -> verify in Edit + Play (captures, console, attributes)
   -> save_place (version only). Publishing is the OWNER'S File > Publish to Roblox.
```

Why procedural: one shared humanoid base and skeleton plus a per-unit "kit" gives a whole squad that reads as one faction with a visible rank hierarchy, and a change (new helmet, new theme colour) is a one-line edit followed by re-running the bakes, not hand re-modelling five characters.

## 1. Tools you need

| Tool | Used for |
|---|---|
| Blender MCP (`execute_blender_code`, `look`, `get_scene_info`) | run the generators, render critique images (`look` with several view vectors) |
| Roblox Studio MCP: `open_cloud_invoke` | upload GLBs, poll operations |
| Roblox Studio MCP: `execute_luau` (Edit DM) | run installers, inspect the DataModel |
| Roblox Studio MCP: `multi_edit`, `script_read`, `script_grep` | edit and read game scripts (`multi_edit` needs `file_path` + `edits[]` + `datamodel_type`) |
| Roblox Studio MCP: `start_stop_play`, `screen_capture`, `get_console_output` | verify in Play |
| Roblox Studio MCP: `generate_mesh`, `generate_material`, `generate_procedural_model` | AI / procedural assets when a parametric generator is the wrong tool (see `docs/MESH_GEN_PIPELINE.md`) |
| Roblox Studio MCP: `list_roblox_skills` / `get_roblox_skill` | call first; current guides for Roblox APIs |

`list_roblox_studios` returns the `studio_id` every Studio call needs.

## 2. Coordinate before you touch Studio

There is ONE shared Studio. Use the bus (`devin-comms/`):

1. Read the last rows of `claims.md`. If `roblox-studio-control` is `claimed_by:` someone else, do NOT edit or save. Do Blender, file and repo work meanwhile.
2. Claim: append `| roblox-studio-control | claimed_by: <you> | since: <UTC ts> | status: active ~Nmin — <what> |`.
3. Do the work. Release with `claimed_by: none`. Post what you changed in `messages.log` (`### <ts> | <you> -> others`). Append with `>>`, never overwrite.
4. Edit-DM tools do not work while someone is in Play mode (`get_studio_state` shows the mode).
5. There is no mandatory waiting period before `save_place`.

Another agent deploying files from the repo mirror can silently overwrite edits you made only inside Studio. If you change a script in Studio, put the same change in `game-mirror/` in the same sitting.

## 3. Generator conventions (so parts from different authors fit)

`tools/art/hero/blender/` holds the squad generator. Set the path constants at the top of each file (they default to `C:\gf-art-build\blender` and `C:\galactic-force`).

- Blender units are metres, Z up, character faces +Y, character RIGHT is +X. Export maps `(x, y, z) -> (x, z, -y) * S`. Roblox's importer rotates the model 180 degrees about Y; the installer re-applies the inverse. Do not "fix" orientation in the generator.
- Material indexes: 0 suit, 1 plate, 2 trim (accent colour), 3 strap, 4 skin, 5 dark. The bake colours come from the `SPEC` table in `hero_bake.py`, so a theme change is one table.
- `hero_lib.py` helpers: `loft` (ring sections), `arcshell` (curved plates), `rbox` (box; a bevel costs 44 tris, no bevel costs 12), `cyl`, `sphere`, `new_bm`, `tri_count`.
- Variants are rows in the `VARIANTS` dict in `gen_hero_v12.py` (head type, shoulder size, torso kit, rifle, rank, scale). To add a troop: add a row, add or reuse a head function, run `lineup.py` to see it in clay beside the others, critique with `look`, then bake.
- Helmets: paint the visor and mask faces onto the shell (material index by face angle and height) instead of floating a band on top. Make helmets larger than the bare head, give a thick gorget so there is no thin neck, and keep a distinct silhouette per unit.
- Triangle budget per troop is 4 to 6.5k, with the head the largest single piece. Detail comes from the baked textures, not from extra geometry.
- Leftover Blender objects must be renamed or deleted before a rebuild; a name collision produces `.001` suffixes. `exec`'d scripts do not share a namespace between calls, so run one variant per call.
- Do not re-run `make_v12.py`-style one-shot patchers over a generator that has been edited by hand.

## 4. Bake and export, one call per variant

In Blender (through `execute_blender_code`):

```python
VARIANT = "Heavy"
exec(open(r"C:\gf-art-build\blender\run_variant.py", encoding="utf-8").read())
```

It rebuilds the variant, UV-unwraps, bakes the albedo/AO/rough/height/mask/metal passes, composites with normal strength 0.55 (1.4 or more looks like stucco), collapses to one material per part, and writes `out_hero/Hero_Ascendancy_<Variant>_v12.glb` plus `tools/art/hero/<variant>_data.luau`. Read the printed `TOTAL tris` and `height studs` lines before going on. Player height in this game is 6.87 studs; troops should be slightly taller.

## 5. Upload (Open Cloud)

The GLB must sit inside a directory the creator has approved for the MCP.

```
open_cloud_invoke POST /assets/v1/assets
  body:  {"request":{"assetType":"Model","displayName":"GF_Hero_Asc_<Name>_v12",
          "creationContext":{"creator":{"userId":"<CREATOR_USER_ID>"}}}}
  files: [{"name":"fileContent","path":"<abs path to .glb>"}]
  scopes: ["asset:read","asset:write"]
-> returns an operation id; poll GET /assets/v1/operations/<id> until done:true, read response.assetId
```

Only `rbxassetid://` meshes are durable and replicate. `rbxruntime://` ids from raw generation are session-local and dead after the session (see `docs/MESH_GEN_PIPELINE.md`).

## 6. Install and verify

```
sh tools/art/hero/make_install.sh <assetId> Hero_Asc_<Name> <name>_data.luau
```

Run the generated `install_Hero_Asc_<Name>.luau` with `execute_luau` in the Edit DM (with a bus claim). It builds the rigged Model at `ServerStorage.GF.Art.Hero_Asc_<Name>`. Then:

- Check the model's height, that the feet are at ground level, and that the Motor6D names are as the rig contract expects.
- Rig contract: `RootJoint`, `Waist`, `Neck`, hips/knees/ankles; the arms are `HoldShoulder/HoldElbow/HoldWrist` L/R so the client animator ignores them and the arms stay rifle-ready. The model carries the attribute `GF_HeroBaked=true` so `TroopVisuals.restyle` does not stack primitive armour on top.
- Play-verify: spawn each role, capture front and three-quarter views, read `get_console_output`. Capture one image at a time with a unique `capture_id`; in Play the camera arguments are ignored, so steer the camera with `RunService:BindToRenderStep` at Camera priority + 5.
- `save_place` saves a version only. The owner publishes.

## 7. Show the owner before going live

For anything the owner will look at: render the generator output in Blender first (clay lineup, front and three-quarter, close-ups) and send the images. Upload and install only after approval. Critique your own renders against the reference images in the owner's reference folder before sending.

## 8. Hard rules

- Never touch the player's blocky armour; it is deliberately simple.
- Do not commit the creator's user id, tokens, emails or local usernames; this repository is public. Use placeholders.
- A procedural generator is the default for characters, kit pieces and props. `generate_mesh` is for one-off organic assets. Hand-placed Part blockouts are a last resort.
- Keep the per-troop triangle budget and the Xbox One-class performance target; check instance and triangle counts after installing.
- Report faithfully: if a bake, upload, install or Play check fails, say which and show the error.
