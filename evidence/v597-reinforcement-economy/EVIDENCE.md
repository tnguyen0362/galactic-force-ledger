# v597 — reinforcement token economy (S06-B)

Implementation in EncounterDirector: player-scaled concurrent cap round(4+2*(P-1)) x difficulty pressure
(Easy .7/Normal 1/Hard 1.3/Extreme 1.6), threat costs per archetype (Rifleman/Scout 1, Marksman 1.5,
Officer 2, Heavy 2.5, bosses 6), reinforcement tokens refilling 0.12 x P^0.7 x pressure x phase x
(0.5+A/100)/s with burst cap 8 and refill paused at cap, alert scalar 0-100 raised +6 per gunfire event
decaying 2/s, phase scalar .6 travel/1 skirmish/1.4 objective-complete/1.5 extraction, spawn validation
requiring 65-140 studs from every player and no clean line of sight. Token spend per spawn by threat cost.

## Probe `[GF_ECON] PASS capN=4 capX=6 tokens=6 cap=4 active=6 visible80=false alertAfterShot=6`

- Solo Normal cap = 4 (inside spec 3-5 band); Extreme scales above Normal; arithmetic for 4-player Normal
  = round(10)x1 = 10 (spec 8-10 band) and Extreme = 16 (spec 14-16 band) verified by formula inspection.
- Tokens refill live in-mission (6 observed after initial spend), published cap correct.
- Spawn validation rejects a point 10 studs away (too close), a point at 80 studs with clean LOS (visible),
  and a point at 200 studs (too far).
- Gunfire raises the alert scalar to 6 immediately.

Fixed in verification: forward-reference error (refillTokens referenced activeCount before its local
definition - ticker died silently, found by probe), alert decay 4/s made gunfire influence vanish in
1.5s (tuned to 2/s), probe race sampling alert after decay.
