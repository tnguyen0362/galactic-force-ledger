# Phase 15 Studio window runbook (claude) — one pass, ~12 min, NO save_place

Pre: claims.md shows Studio free; post a claim row. Studio must be in Edit mode.

1. Install kits: run tools/art/kit/install_kit.luau via execute_luau (Edit). Expect installed=17 failed=0
   (17 = 11 Human + 6 Ascendancy). Spot check: dims of Kit_Human_Bunker ~ 36x32x26, Watchtower height ~53, CommMast ~60.
   Check Mesh.TextureID is set on each; if empty, set from the embedded palette (see veg install notes).
2. Deploy SkyWar: multi_edit className=LocalScript at StarterPlayer.StarterPlayerScripts.SkyWar, body from
   game-mirror/.../StarterPlayerScripts/SkyWar.luau.
3. Deploy BiomeLook SunRays edit: replace game.ServerScriptService.GF.Services.BiomeLook source from mirror.
4. Play (is_start true). Per biome: workspace GF_Biome set, Environment.apply("mission"), wait for GF_VegCounts, capture 3 views
   (ground level, elevated, skyward). Verify: sky is daylight dome (not station starfield), SkyWar effects appear within ~15 s,
   max 3 effects + 1 ship alive, no new console errors, FPS unchanged (stats).
5. Weather-vs-BiomeLook: trigger WeatherService transitions during a mission; confirm BiomeLook values are restored after.
6. Re-capture Industrial (retuned look). Stop play, leave Edit, release claim + bus post. Never save_place.

Rollback: delete ServerStorage.GF.Art.Kit_*, StarterPlayerScripts.SkyWar; BiomeLook previous source is in git (8213490).
