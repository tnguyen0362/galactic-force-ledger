# Art direction reset — "Helldivers 2, but cheap" (2026-11-28)

Owner verdict: Ascendancy and Bastion Walker look bad; world reads empty/cheap; target is **"2.5 AAA"** and the owner handed me creative control. This supersedes the primitive-kit approach (gen_kit.py boxes + 8-colour palette) as the quality bar. Prototype kit stays as blockout until replaced.

## What actually makes HD2 read as AAA (and what is cheap to copy)
Research was thin on tech (no public trim-sheet/perf breakdown found); this is my synthesis plus the public direction notes: realism is NOT the goal, player fantasy is; harsh, minimalist, bleak-but-beautiful worlds; Terminids = metallic shells + glowing optics; Automatons = cold, mechanical, military-plausible.
1. **Atmosphere beats polygons.** Low warm sun vs cold fill, layered haze, smoke, ash/embers, strong colour grade. Cheapest, global, biggest jump. FIRST.
2. **Silhouette + colour blocking.** One dominant shape and 2-3 values per faction readable at 80 studs.
3. **Lived-in finish:** bevelled edges that catch light, edge wear, grime in crevices, material variety (painted metal / bare metal / stone / emissive). Done with baked maps, not geometry.
4. **Composition of the ground:** clusters, landmarks, debris trails, craters, wreckage; never uniform scatter.
5. **Restraint:** big forms, few details, strong emissive accents.

## Faction identity (my call)
- **Ascendancy:** tall, vertical, asymmetric monolithic armour; obsidian/charcoal slate shell, bronze trim, ONE thin violet glow line per unit/structure. Sharp planar facets + large smooth bevels; no ornament noise. Bastion Walker: bipedal siege mech, reverse-joint legs, shoulder artillery, exposed glowing weak core; the most imposing silhouette in the game.
- **Human (Bastion outposts/Super-Earth-style kit):** chunky, painted graphite/navy with stencils, hazard striping, cyan lights, scuffed bare-steel edges.

## Pipeline (to prove on ONE hero piece before scaling)
Blender: hi-poly (bevels, panel cuts) -> low-poly (weighted normals) -> bake normal/AO/curvature-wear to a shared 1K trim/atlas per faction -> Roblox `SurfaceAppearance` (Color/Normal/Roughness/Metalness). Gate: confirm Edit-DM `execute_luau` can set SurfaceAppearance maps on an uploaded MeshPart. Hero piece = Ascendancy rifleman (most visible), A/B captured in-engine on High from the same camera, owner reviews before scaling.
Rocks/trees: evaluate CC0 scanned assets (Poly Haven via search_assets), decimated + baked to budget, license checked.

## Order of work
1. Atmosphere/lighting/particle pass (client, BiomeLook-adjacent; no gameplay impact).
2. PBR hero piece (rifleman) + feasibility gate.
3. Ground composition: kit rocks/cliffs clusters + war debris + landmarks (needs alpha/beta ack for ArtService/Vegetation wiring).
4. Trees (silhouette variety, burnt variants).
5. Bastion Walker redesign.

## Budgets (Xbox One class; PC numbers are proxies only)
One atlas/trim per faction, maps <=1K, texture memory reported with triangle counts; enemy <= ~3-4k tris; shadows off for small props.

## Not doing
No more primitive-only pieces; gen_trooper.py output (box armour) is shelved as blockout, not for upload.
