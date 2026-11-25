# place 579 — ability cooldown acceptance and rejoin persistence

## Cooldown starts only on accepted deployment (no code change; verified at 578)
For each ability, a temporary server Script first cast 4000 studs away (rejected), then cast in range.

```text
[GF_CD] PASS Airstrike far=nil cd=90.0/90 | DomeShield far=nil cd=70.0/70 | Sentry far=nil cd=100.0/100 | OrbitalStrike far=nil cd=150.0/150
```

## Cooldowns survive state rebuild (place 579)
Before this change, `State.ensure` keyed state by the `Player` object, so a rejoin created fresh state with no cooldowns. Cooldown tables are now held in `cooldownsByUser[UserId]` and shared by reference. `AbilityService.resetCooldowns` clears the table in place instead of replacing it.

Probe: cast Sentry, `State.clear` + `State.ensure` (the same path a rejoining Player takes), then recast.

```text
[GF] boot: config check PASS (688 assertions)
[GF_REJOIN] PASS before=4972.093018333311 after=4972.093018333311 recast=cooling down
```

Limits: persistence is within the same server only; cross-server rejoin was not handled. A real disconnect/reconnect was not performed.
