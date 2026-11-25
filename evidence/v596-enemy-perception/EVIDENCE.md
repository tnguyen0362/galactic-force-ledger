# v596 — enemy perception/FSM core (S06-A)

Implementation: perception layer added to EnemyService (110 deg sight cone unless alerted, 14-stud proximity
bypass, 90-stud gunfire hearing with 8s alert, lastSeenPos/lastSeenAt with exp(-age/4) confidence decay,
spec target-scoring formula 0.40vis+0.25prox+0.20threat+0.15role, threat memory wired from damageEnemy,
hearing wired from CombatService accepted shots). FSM states published per enemy via GFState attribute:
Guard at home, Investigate toward last known position, Search wander on arrival, Return home below
confidence 0.2 (~6.4s stale, max 10s), Engage while a target is held. Engage behavior itself unchanged.

## Probe `[GF_PERC] PASS hidden=Guardx9 alerts=9 afterFire=Investigate conf=0.94`

- All 9 mission enemies sat in Guard with the player hidden far away: no stale Engage states.
- One server-validated gunfire shot alerted 9 hostiles within hearing range (GF_AlertedCount delta=9).
- The nearest enemy transitioned Guard->Investigate within ~2.5s of the shot.
- PerceptionConfidence attribute live and decaying (0.94 shortly after stimulus, consistent with exp decay).

Row coverage: S06-004 (states live, Patrol/Dormant/Acquire not distinct), S06-008 (hearing measured,
cone rejection untested), S06-010 (confidence live), S06-013 (implemented, behavioral verification owed),
S06-005/006/007 partial architectural evidence (single central heartbeat, server-only decisions).
