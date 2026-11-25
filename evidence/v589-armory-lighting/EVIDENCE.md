# place 589 — armory lighting visual pass

Studio playtest, one local client. This was a real rendered-camera review, not an Explorer-tree audit.

## Captures reviewed

- `graphics_start_default`: initial station spawn. First frame was extremely dark, though later frames brightened as lighting/exposure settled.
- `graphics_station_wide`: war-table concourse. Readable overall, coherent navy/graphite/cyan palette, but large surrounding surfaces remain very dark and the minimap reads as a low-resolution green terrain patch while indoors.
- `graphics_armory_player`: pre-fix armory. The alcove was a black pocket; rack silhouettes, the mannequin and bench were present but hard to read, and the player character collapsed into a near-black mass with only the cyan rim visible.
- `graphics_armory_after`: post-fix armory. The alcove wall, racks, mannequin, inspection bench, floor and cyan rack details are immediately readable while preserving the dark military interior.

## Change made

- `StationArt`: each armory pendant strip now has a small local practical PointLight (`GFPractical`, brightness 1.35, range 24, no shadow pass); the armory fill is marked practical, raised to 1.45, and made shadowless. These lights are local to the alcove rather than a global ambient increase.
- `CharRim`: player highlight fill transparency changed from fully transparent to 0.86; crew changed to 0.94. This gives a subtle dark-blue body lift without turning characters into full glowing holograms.

## Result

The armory no longer reads as an unlit hole. The improvement is visible in the post-fix rendered capture. No layout, collision, interaction, gameplay timing, or economy behavior changed.

## Remaining visual issues honestly observed

- The player body is still darker than ideal from behind in the armory; the rim is better, not final lighting/character art.
- The station minimap is not visually meaningful indoors in these captures.
- The station is coherent blockout, not final art: large flat surfaces, simple ceiling fixtures, simple mannequin/rack geometry.
- A local `screencapture` attempt failed because macOS did not permit the terminal to create a display image; the reviewed images above are the MCP rendered screen captures in the session transcript.
