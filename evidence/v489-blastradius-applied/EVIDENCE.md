# `blastRadius` applied — and the first augment stat that honours its authored cap (place 489)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 489**.

## What was dead

Four augments rolled `blastRadius` — `WideCharge` (+0.3), `SiegePayload` (+0.45), `SlugLoad` (-0.2), `FocusedOrbitalStrike`
(-0.4) — and nothing read it. `CombatService.detonate` took the radius straight from the weapon config:

```lua
local radius = (weapon.explosive and weapon.explosive.radius) or 8
```

## The change

```lua
if player then
    local blastBonus = 0
    pcall(function()
        local augs = require(script.Parent.AugmentService).forPlayer(player)
        blastBonus = tonumber(augs and augs.blastRadius) or 0
    end)
    radius = radius * math.clamp(1 + blastBonus, 0.4, 1.25)
    workspace:SetAttribute("GF_LastBlastRadius", ...)
end
```

**`1.25` is not my choice — it is the spec's.** `GOAL_2026-11-24.md` caps blast radius at **+25%**. This is the first augment
stat in the project to honour its authored cap; every other one sums unbounded.

Signs are data-driven, not guessed: positive values widen the blast, negative values tighten it, so a single `1 + bonus` handles
both directions. The `0.4` lower bound is mine, to stop a stack of negatives reaching zero radius.

## Measured

```
base (no augment)   -> radius 9.00   bonus 0
+ SiegePayload      -> radius 11.25  bonus 0.8514343019655977
```

`9 × 1.25 = 11.25` — the clamp engaged and held, exactly as specified. Without the clamp the same stack would have produced
`9 × 1.8514 = 16.66`, an 85% increase.

## The number to notice: 0.8514

One `SiegePayload` is only **+0.45**. The measured bonus was **0.8514**, because the test account has accumulated several
`blastRadius` augments across this session's probes (`SlugLoad −0.2`, `WideCharge +0.3`, `SiegePayload +0.45`, plus any trait
rolls). So:

- the stacking defect is **live and reproducible**, not theoretical (`S11-055`)
- and the clamp is what kept it sane — the first evidence that a clamp is both necessary and sufficient here

## Limits

- `detonate` was called directly with `GL22`; no launcher was fired, so the coupling from trigger-pull to blast is unverified.
- Only `GL22` (base radius 9) was used. `RL09` and ability-explosion paths were not checked, and `FocusedOrbitalStrike` implies
  ability blasts should also respect the stat — they do not, because only `detonate` was instrumented.
- The structural-damage branch uses the same `radius` local, so it inherits the change, but no structure was detonated to prove it.
- Test-account state continues to accumulate equipped augments between batches; that is a side effect of probing, disclosed.
