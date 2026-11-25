# Capturing the Helldivers 2 Feel — Researched Design Direction

Source material: Arrowhead developer interviews (Pilestedt, Eriksson, Lasota), patrol/spawn
mechanics community documentation, HD2 wiki systems analysis. Everything below is grounded in
what Arrowhead actually said and what the game actually does — then mapped to concrete work
items for THIS project with an honest exists/missing assessment.

## The two guiding stars (Arrowhead's own words)

1. **"Trainwreck in slow motion"** — combat must NOT escalate fast. The player feels control
   slipping gradually, and even fully out-of-control situations remain recoverable. Arrowhead
   balances this through spawn-count vs enemy-movement-speed: you always FEEL outmatched but
   can normally run away. Skin-of-teeth survival is the core emotional product.
   - GF status: PARTIAL. The breather system (pressure windows then 20-32s lulls) is the right
     skeleton. Escape velocity untested: can a player actually disengage by running? Unknown.

2. **"The tingle"** — anticipation tension. Things should ALMOST kill you rather than kill you,
   giving time to think "oh shit" before dying or surviving. Error-prone interactions under
   pressure (stratagem codes) create lean-in focus moments.
   - GF status: PARTIAL. Shield-then-health two-layer damage is inherently "almost killed"
     structure. Telegraph beams now give dodge windows. Untuned: TTK on player, spike damage.

## Pillar 1: PATROL ECOLOGY (the single biggest gap)

HD2 has four spawn classes: static POI guards, reinforcement drops, fabricator/nest spawns,
and PATROLS. Patrols are the only enemies that move through the world without provocation.
Documented mechanics worth copying faithfully:
- Patrols spawn at intervals at map edges and march across the map on routes
- Routes are PLAYER-BIASED: they cross near/over player positions but spawn UNAGGROED —
  you see them coming and choose engagement or avoidance. This choice is the gameplay.
- Patrols despawn at 175m+ from players when not engaged (performance bound)
- Patrol count scales linearly with squad size (solo = 25% of 4-player)
- Killing even one patrol member alerts the whole group; avoidance (crouch/prone off-path)
  is a legitimate strategy — stealth exists as a layer without being a stealth game
- GF status: MISSING. Enemies are spawn-defenders tethered to objectives. The FSM now has
  Patrol state vocabulary but nothing generates routes. IMPLEMENT: PatrolDirector — edge
  spawns, spline routes biased across player positions, unaggroed march state, 175m despawn,
  squad-scaled spawn intervals, group-alert-on-member-death.

## Pillar 2: REINFORCEMENT THEATER

HD2 reinforcement calls are VISIBLE, INTERRUPTABLE events — the automaton flare animation,
the terminid retching scream — with a hidden cooldown after each call. Critical detail: the
dropship/breach horde itself is SMALL AND FINITE; the flood feeling comes from alerted nearby
patrols/POI units converging, not infinite spawns. "Once you get one alert, you're temporarily
safe from another."
- GF status: PARTIAL. Scout beacon now channels visibly with cancel-on-damage (implemented
  v684, unverified). Officer relay calls exist. MISSING: dropship delivery theater (enemies
  should ARRIVE visibly, not materialize), finite-per-call horde caps + visible cooldown
  rhythm, converging-alerted-units as the real pressure source.

## Pillar 3: WATERING-HOLE COHESION

"A good co-op game forces players together; a great one makes them WANT to be together."
HD2 creates gathering gravity through: shared resupply points, samples dropped on death
(retrieve your buddy's stuff), reinforcement drop placement near squadmates.
- GF status: PARTIAL. Redeploy tickets + drop pods exist. Supply caches exist in generation.
  MISSING: shared-resupply interaction design, dropped-salvage-on-death recovery incentive
  (salvage currently just persists?), revive-pulling-you-to-squad dynamics. Mostly a
  multiplayer-tuning item — but the mechanical hooks can be built solo-ready.

## Pillar 4: FEELING HUMAN / DISPOSABLE HEROISM

HD2: death replaces you with a NEW character — you are literally disposable. Missions count
COMPLETE even if nobody extracts, as long as objectives finished. The fantasy is vulnerable
humans against overwhelming force, not power fantasy.
- GF status: STRONGER THAN EXPECTED. Spec S33 already distinguishes PRIMARY SUCCESS /
  EXTRACTION SUCCESS / SALVAGE LOST independently — implemented in the debrief (verified
  this session). Tickets-as-reinforcements exist. Solo viability is intentional per spec —
  divergence is deliberate (HD2 punishes solo hard; GF spec says solo-compatible).

## Pillar 5: VOLUME-OF-FIRE READABILITY

Malevelon Creek's terror signature: "the air becoming majority red tracer fire by volume."
Automaton pressure is experienced as VISIBLE lanes of incoming fire — terrifying AND readable.
Suppressive fire is atmosphere, information, and threat simultaneously.
- GF status: PARTIAL-PLUS. Violet enemy tracers exist; suppression lanes just implemented
  (v684). Missing: volume calibration at higher difficulties, sound design pairing (crack-
  overhead audio), tracer ricochet/impact atmosphere. Cheap high-value tuning pass.

## Pillar 6: PLANET IDENTITY THROUGH MODIFIERS

HD2 planets are characters: ion storms block stratagems at the worst moment, fire tornadoes,
darkness that affects players more than automatons, heat/cold time-of-day cycles. Modifiers
change DECISIONS, not just visuals.
- GF status: WEAK. WeatherService exists (structural), but weather is cosmetic. IMPLEMENT:
  2-3 gameplay-active modifiers — ion interference (ability cooldowns pause), fog banks
  (sight ranges compress for both sides), crystal-static (shields recharge slower). Tie to
  time-of-day or seeded mission modifiers.

## Pillar 7: VISTA COMPOSITION (the feel-large trick)

HD2 maps aren't huge — they COMPOSE. Elevation reveals: you crest a ridge and read the
objective at distance with layered ridgelines behind it. Sightline engineering, not size.
- GF status: MISSING as deliberate craft. Terrain is noise-driven; never composes a reveal.
  IMPLEMENT: generator post-pass that places landing zones at local elevation with a
  valley-corridor toward the objective — one guaranteed "crest and see the theater" moment
  per mission. Cheap: the spine system already knows the route; bias spawn-side elevation.

## Pillar 8: SKY PRESENCE

Your destroyer overhead, pelicans crossing, extraction incoming visible from far. The war
extends upward constantly.
- GF status: PARTIAL. Extraction gunship flies in (verified). MISSING: ambient sky traffic
  (distant transport splines exist at the STATION but not in-mission), enemy dropship
  silhouettes delivering reinforcements (ties to Pillar 2), orbital-strike sky signature
  for the airstrike ability (spec already requires aircraft silhouette — verify).

## Pillar 9: SOUND-AS-INFORMATION

HD2 players read the battlefield by ear: retching = breach incoming, flare = dropships,
specific heavy-unit audio signatures. Every threat has an audible tell.
- GF status: UNKNOWN/WEAK. Audio exists structurally (GFAudio) but information-channel
  design is unverified. Note: spec says voice fallback to subtitles is acceptable —
  but threat audio cues are a distinct channel from dialogue.

## Pillar 10: EMERGENT STORY SYSTEMS (the metagame)

Malevelon Creek happened because the Galactic War is a shared persistent narrative —
planets fall, communities rally. Even solo players feel part of a larger war.
- GF status: STRONG STRUCTURALLY. GalacticWarService + war table exist. The war-map
  presence in the station is verified visually. Tuning/content depth unknown. This is the
  least urgent pillar — the bones are there.

## PRIORITY ORDER (impact per effort, solo-verifiable first)

1. PatrolDirector — patrol ecology (transforms every minute of every mission)
2. Objective distance enforcement 300-650 + vista composition pass (spatial feel)
3. Reinforcement theater: dropship delivery + finite hordes + readable cooldown
4. Tracer volume + suppression tuning pass (combat feel)
5. Gameplay-active weather modifiers (2-3 to start)
6. TTK/escalation tuning for trainwreck pacing (requires measurement first)
7. Watering-hole mechanics (needs multiplayer to matter fully)
8. Threat audio cues
9. Ambient sky traffic in-mission

## WHAT NOT TO DO
- Do NOT enlarge the map before terrain math is measured (multiplies traversability risk)
- Do NOT copy stratagem-code input friction — GF spec deliberately diverges (Q/F abilities)
- Do NOT punish solo — the spec mandates solo compatibility throughout
- Do NOT inflate enemy HP — spec forbids it; pressure comes from composition and ecology
