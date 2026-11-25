# place 578 — difficulty-scaled friendly fire

Before this change, the codebase had no friendly-fire path: bullets that hit an ally did nothing, and explosions only damaged enemies and structures.

Changes:
- `Difficulties.List` has a `friendlyFire` field (Easy 0, Normal 0, Hard 0.5, Extreme 1.0), read through `Difficulties.friendlyFireFor`.
- `CombatService.fire`: a hitscan/pellet hit on another player's character applies `damagePerPellet × falloff × scale` through `VitalsService.applyDamage`.
- `CombatService.detonate`: allies (excluding the shooter) inside the blast take `damage × distance falloff × scale`.
- Sentries still target only `GFEnemy` models.

Probe: a temporary real-server Script deployed the player, then detonated a 20-damage blast on them (no owner) at each difficulty.

```text
[GF] boot: config check PASS (688 assertions)
[GF_FF] PASS Normal=none | Hard=?->ROBLOXISUS101 20.0 x0.50 | Extreme=?->ROBLOXISUS101 20.0 x1.00 scales=1
```

Not verified: two-client hitscan friendly fire (it needs a multi-client test) and the explicit warning before an ally-affecting strike.
