# place 569 — augment stat consumers + reroll lock evidence

## Boot regression

Fresh playtests after the stat-consumer batch booted with:

```text
[GF] boot: config check PASS (688 assertions)
[GF] boot: services online (persistence=datastore)
```

## Reroll lock/accept probe

A temporary real server `Script` granted a Legendary `MasterworkBore`, locked trait index 2 (`magazine`, a negative trait), rerolled, accepted the offer, then removed the test item and reset test scrap.

```text
[GF_LOCKTEST] PASS rarity=Legendary lock=2 key=magazine cost=300 accept=no-double-charge
[GF_LOCKCLEAN] removed=1 scrap=0
```

This verifies: Legendary lock surcharge is exactly 300, a locked negative trait is preserved in the proposed roll, Accept does not charge a second fee, and pending state resolves.

## Implemented stat-consumer changes

- `range` is now a generated/aggregated stat with canonical rarity bands and asymmetric clamp (-35% floor, +30% cap). Weapon raycast range and falloff distances scale from it.
- `supportDamage` is generated/aggregated with +15% positive cap and -35% floor. Airstrike, Sentry and Orbital damage scale from it.
- `sentryHP` is generated/aggregated. New sentries publish `Health`/`MaxHealth` scaled from the 180 HP baseline.
- `blastRadius` now also scales Dome Shield radius and support blast radii while leaving Dome duration untouched.
- Epic/Legendary inventory rows expose a `LOCK` cycling control and pass `lockIndex` to the reroll remote.

## Scope limits

Sentries now publish health, but enemy targeting/destruction of sentries is still not implemented, so sentry HP is only partially consumed. Exact weapon-range gameplay behavior and support damage/radius still need live combat probes. The catalog identity remains noncanonical.
