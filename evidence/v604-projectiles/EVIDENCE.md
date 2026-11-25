# v604 — traveling launcher projectiles (S04-048)

Implementation: ProjectileService (new server module) simulates kinematic shells at 30hz - GL22 55 studs/s
with 35 gravity (readable arc), RL09 110 studs/s with 4 gravity (flatter). Collision raycast per step plus
lifetime airburst both route into the existing detonate() AoE math. Fire path no longer hitscan-detonates
launchers. Clients receive ProjectileFired with the ballistic parameters and ProjectileDetonated at impact.

`[GF_PROJ] PASS gl=55/35g rl=110/4g detonated=GL22@0.2s hits=0 after~0.25s travelTime=0.2`
- No instant detonation: 0.15s after the trigger pull the shell was still tracked mid-flight.
- Positive measured travel time before collision detonation (0.2s - short because the probe fired a
  downward arc into nearby ground; geometry-appropriate).
- Boot config check now 705 assertions (was 701).

Open debt: client visual shell animation unimplemented (server publishes ballistic parameters);
immediate DamageFeedback at trigger time is cosmetic-only leftover. Enemy-hit radius/falloff
measurements for GL22/RL09 rows still owed against grouped targets.
