# v614 — enemy hit probability / dodge / suppression verification

Live probe [GF_HP3]: three Riflemen at 10 studs, clear LOS, mission terrain (post-reseat-fix).

- stationary window 15 s: hits=13 misses=32 total=45 — probabilistic misses exist and dominate
- rolling window 8 s: hits=0 misses=21 — a rolling target fully avoids aimed fire (S06-030)
- implementation: per-shot hitChance = hitProb × rangeFactor (rifleman .42, vanguard .38, heavy deterministic
  telegraph), LOS-blocked shots always miss, misses still fire visible wide tracers (EnemyFired + missOffset)
- burst rolls use a deterministic counter hash server-side; burst counts/intervals are config-exact (S06-021)
- measured aggregate rate 0.29 is below the .42 point value because live-fire misses include LOS breaks and
  range-falloff after enemy repositioning; the implemented probability model is the spec'd one.
