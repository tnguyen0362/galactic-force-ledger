# place 573 — destructible sentries

Hostiles never targeted sentries: `EnemyService` only picked visible players and the defence structure. A sentry's `Health` attribute was therefore decorative.

`EnemyService` now runs `nearestSentry`, which finds visible `GFSentryDestructible` models in `GameplayEffects`. A hostile engages a sentry when it is nearer than the hostile's player target. The hostile uses the normal telegraph, fire slot and cooldown, and the damage is `def.damage × DamageMultiplier × burst count`. `EnemyService.damageSentry` lowers `Health` and destroys the sentry at 0, recording `GF_LastSentryDestroyed`.

A temporary real-server probe placed a 60 HP synthetic sentry on an isolated floor and spawned a Rifleman 20 studs away. The sentry, enemy and floor were removed afterward.

```text
[GF] boot: config check PASS (688 assertions)
[GF_SENTRY] PASS destroyed=true firstHit=0.8s hp=0 last=Sentry:Rifleman
```

Not yet verified: the full ability-deployed sentry in a mission with mixed player/sentry targets, 300 RPM, and the expiry visual.
