# HD2 WAR TABLE / DEPLOY EXPERIENCE — COPY-READY REFERENCE SPEC
# Owner directive: war table = "literally word for word copy for copy of Helldivers 2, triple AAA quality"
# Compiled by research agent 2026-11-27. Implementers copy verbatim from this file.

## DIFFICULTY TIERS (10, always number + name — NOT generic Easy/Normal/Hard)
1 TRIVIAL · 2 EASY · 3 MEDIUM · 4 CHALLENGING · 5 HARD · 6 EXTREME ·
7 SUICIDE MISSION · 8 IMPOSSIBLE · 9 HELLDIVE · 10 SUPER HELLDIVE
Unlock rule: completing an Operation at tier N unlocks N+1. Selector bottom-center of table, cycled.

## CORE VOCABULARY (verbatim, all caps)
GALACTIC WAR · WAR TABLE · SUPER DESTROYER · SUPER EARTH · MANAGED DEMOCRACY
MAJOR ORDER · PERSONAL ORDER · DISPATCHES · LIBERATION · DEFEND · DEFENSE/LIBERATION CAMPAIGN
SECTOR · PLANET · OPERATION · MISSION · MAIN OBJECTIVE · TACTICAL OBJECTIVE
HELLPOD · HELLDIVER · STRATAGEM · BOOSTER · REINFORCE · SOS BEACON · QUICKPLAY
ENVIRONMENTAL CONDITIONS · OPERATION MODIFIERS · EFFECTS · BIOME
The deploy verb is DIVE — READY UP / PREPARE TO DIVE, never generic "LAUNCH".
Matchmaking states: SEARCHING FOR ACTIVE SOS BEACONS → GAME FOUND.
Faction colors: Terminids yellow/amber · Automatons red · Illuminate purple · Super Earth blue.

## OPERATION/MISSION NAMES (copy pool)
Operations: PEACEKEEPING OPERATION · DEFEND PLANET · DEFEND FREEDOM · BUG EXTERMINATION · PROTECT LIBERTY
Missions: SPREAD DEMOCRACY · CONDUCT GEOLOGICAL SURVEY · RETRIEVE VALUABLE DATA · LAUNCH ICBM ·
EMERGENCY EVACUATION · EVACUATE HIGH-VALUE ASSETS · TERMINATE ILLEGAL BROADCAST · ERADICATE TERMINID SWARM ·
BLITZ: SEARCH AND DESTROY · PURGE HATCHERIES · SABOTAGE SUPPLY BASES · DESTROY COMMAND BUNKERS ·
NEUTRALISE ORBITAL DEFENSES · COLLECT METEOROLOGICAL DATA
(BLITZ: prefix = short-timer variant; one MAIN OBJECTIVE orange + optional TACTICAL OBJECTIVES blue)

## PLANET/SECTOR/BIOME NAMING
Sectors: short mythological words — SEVERIN · AKIRA · ORION · XZAR · YMIR · TRIGON · VALDIS · URSA · HYDRA
Planets: evocative — MALEVELON CREEK · ANGEL'S VENTURE · ERATA PRIME · HELLMIRE · MORT · BEKVAM III ·
CERBERUS IIIc · WIDOW'S HARBOR · FREEDOM PEAK · FORT JUSTICE · ZEGEMA PARADISE (apostrophes, roman numerals, propaganda)
Biomes (one per planet + flavor line): VOLCANIC JUNGLE · ETHEREAL JUNGLE · IONIC JUNGLE · DESERT DUNES ·
ROCKY CANYONS · ACIDIC BADLANDS · ICY GLACIERS · MOON · DEADLANDS

## ENVIRONMENTAL CONDITIONS / OPERATION MODIFIERS
ACID STORMS · BLIZZARDS · EXTREME COLD · FIRE TORNADOS · INTENSE HEAT · ION STORMS · METEOR STORMS ·
RAINSTORMS · SANDSTORMS · THICK FOG · TREMORS · VOLCANIC ACTIVITY — each with one-line effect
COMPLEX STRATAGEM PLOTTING · ORBITAL FLUCTUATIONS · POOR INTEL · ATMOSPHERIC SPORES — modifiers at high tiers

## PA / ANNOUNCER STRINGS
"Mission coordinates locked." — select mission · "Hellpods primed." · "Mission preparation aborted."
"Helldivers to Hellpods. Repeat: Helldivers to Hellpods." — 60s idle nag
Loading tips labeled TRAINING MANUAL TIPS, satirical: "Don't die!" · "Remember: Freedom!" · "Friendly Fire isn't."

## SQUAD IDENTITY
Size 4. Call-signs letter+number (A1,B3,C1,D2). Colors: orange #FF9D45 blue #81ABFF pink #F88AFF green.
Own block monochrome, teammates colored.

## LAYOUT — zoom hierarchy (diegetic hologram above physical table)
GALAXY VIEW (Super Earth center, faction-colored territories, warp links, campaign planets pulse,
  Major/Personal Order panel RIGHT, difficulty selector BOTTOM-CENTER, quickplay prompt bottom)
→ SECTOR VIEW (planets selectable, two-tone liberation bars under planets, helldiver counts, defend timers)
→ PLANET VIEW (planet center-left; RIGHT = operations list expanding to missions w/ icons+rewards;
  planet name caps, LIBERATION/DEFEND + bar + helldiver count; BOTTOM-RIGHT = EFFECTS readout)
→ BRIEFING (tactical drop map, leader picks drop zone, 4 stratagem squares + 1 hexagonal booster,
  OFFENSIVE/SUPPLY/DEFENSIVE categories, roster with ready states, READY UP)
Key anchors: orders panel right · difficulty bottom-center · effects bottom-right · operations list right.

## FLOW (table → boots on ground)
1 approach table, prompt · 2 camera seats into hologram, galaxy view · 3 set difficulty ·
4 select sector → planet (PA "Mission coordinates locked") · 5 hellpod bay, enter pods ·
6 briefing: leader drop zone, stratagems/booster · 7 READY UP each · 8 all-ready short countdown launch ·
9 launch cinematic + loading screen w/ rotating training tip · 10 impact, objective pins.
Squad sees each other's selections live; nobody drops until everyone ready.

## PALETTE (hex)
UI YELLOW primary interactive #FFE710 · SUPER EARTH BLUE #41639C · HOLO GROUND #04070B ·
PANEL NAVY #0B2233 · HOLO CYAN #38D4FF · OFF-WHITE INK #E4F6FF · AMBER WARNING #FF9D2E · DANGER RED #FF3B30
60% near-black ground / 28% deep navy / sparse high-chroma accent. ONE accent per context.
Liberation bars: blue fill vs faction color on dark translucent backing.

## FRAMES / TYPE
Cut corners NEVER round — chamfered octagon panels, hexagonal special slots, corner-bracket framing.
All-caps tracked headers, bold condensed/extended sans, tabular numbers, T-MM:SS timers.
State written in WORDS (READY · INBOUND T-00:12 · COOLDOWN T-03:33), not color alone.
Scanlines/flicker/glow on holograms, hairline grids, micro-text filler at panel edges, open center.
Every state change ANIMATES (zooms, expanding hover rings, panel assembly) — never instant swaps.
Difficulty re-skins accent channel (cool→hot) per First Descendant pattern.

## THE 10 AAA RULES
1 diegetic hologram on physical table · 2 one accent per context, color = meaning · 3 cut corners never round ·
4 caps tracked headers, tabular numbers · 5 states in words · 6 scanlines/flicker on holo ·
7 two-tone contested bars · 8 animate every state change · 9 voice/satire in strings (war effort, Liberty) ·
10 synchronous squad ritual — drop together or not at all.

## IMPLEMENTATION CAVEATS
- Pixel-exact layout not extractable from text sources; anchors above are verified, keep reference video open.
- Full-ready countdown undocumented — pick 3-5s with unready window.
- Take core first: zoom tiers, liberation bars, operation→mission structure, ready-up staging.
