# The `cooldown` augment stat works — three more augments are real (place 487)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 487**.

## What was dead

`cooldown` was one of the eight unconsumed augment stats. Three augments rolled it — `CoolantLoop` (+0.25), `OverclockedCore`
(+0.4), `ExtendedSentryMagazine` (+0.2) — and none of them changed anything.

`AbilityService` set cooldowns inline at **four** identical call sites:

```lua
s.cooldowns[ability.id] = now() + ability.cooldown
```

## The change

One helper, defined beside `now()`, and all four sites route through it:

```lua
local function beginCooldown(player, s, ability)
    local bonus = 0
    pcall(function()
        local augs = require(script.Parent.AugmentService).forPlayer(player)
        bonus = tonumber(augs and augs.cooldown) or 0
    end)
    s.cooldowns[ability.id] = now() + ability.cooldown * math.max(0.25, 1 - bonus)
end
```

All three authored values are **positive reductions**, so `1 - bonus` shortens the cooldown — consistent with the same formula
now used for `adsSpeed`. The `math.max(0.25, ...)` floor is my invention to stop a pathological stack reaching a zero or negative
cooldown.

## Measured

```
augment cooldown bonus = 0.47852450056172374
Airstrike cast -> remaining = 46.1 s      (base 90)
```

`90 × (1 − 0.4785) = 46.94`, and the watcher sampled 0.8 s after the cast, so 46.1 is the expected reading. Before this batch the
same cast would have read ~90. The ability was accepted (`LastCastRejected = nil`) and drove the real cooldown path, not a
simulation.

## A mistake I made and caught inside this batch

My replacement loop counted `5` substitutions where I expected `4` — because it also matched the line **inside the helper I had
just inserted**, producing `beginCooldown(player, s, ability) * math.max(...)` and a syntax error at line 26. `loadstring` caught
it before anything ran; one targeted edit repaired it.

The lesson is specific and worth keeping: when inserting code that contains the very string you are about to replace, insert
**after** doing the replacements, or anchor on surrounding context. Replacing a line I had authored seconds earlier is a new
version of the "edit landed in the wrong spot" hazard.

## The stacking problem, now with a concrete number

This same measurement exposes `S11-055`:

```
bonus = 0.4785     ->  47.85% cooldown reduction on one ability
```

`GOAL_2026-11-24.md` caps support cooldown rate at **+20%**. The account reached **47.85%** — more than double the cap — because
`AugmentService.forProfile` sums effects additively per stat and no clamp exists anywhere. With the floor I added, the worst case
is a 75% reduction; without a clamp, more augments simply keep stacking.

## Limits

- Only `Airstrike` was cast. `cooldown` applies to all four sites, but the other three ability paths were not individually run.
- The 0.4785 bonus is unexplained by the three listed augments (0.25 + 0.4 + 0.2 = 0.85 would exceed the floor, so the account
  must hold a subset). I did not enumerate the equipped set.
- `ExtendedSentryMagazine` may be intended to affect **sentry ammo**, not cooldown — the config puts `cooldown = 0.2` on an
  augment whose name says magazine. That looks like an authoring slip worth an owner glance.
- The 0.25 floor is my invention and is not in the spec.
