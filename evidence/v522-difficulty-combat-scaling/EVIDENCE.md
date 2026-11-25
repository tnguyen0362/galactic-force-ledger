# Difficulty now scales enemy HP; damage and cadence wired but unproven live (place 522)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 522**.

## Change

`Configs/Difficulties` gains the authored table plus an accessor:

```lua
local MODIFIERS = {
    Easy    = { hp = 0.70, damage = 0.60, cadence = 0.85, pressure = 0.65 },
    Normal  = { hp = 1,    damage = 1,    cadence = 1,    pressure = 1    },
    Hard    = { hp = 1.50, damage = 1.30, cadence = 1.10, pressure = 1.25 },
    Extreme = { hp = 2,    damage = 1.60, cadence = 1.20, pressure = 1.50 },
}
function Difficulties.modifiersFor(difficultyId) ... end
```

`EnemyService.spawn` applies them at spawn time, reading the live `GF_OperationDifficulty` attribute:

- `Health` / `MaxHealth` × `hp`
- `DamageMultiplier` and `CadenceRate` published as attributes
- `Difficulty` recorded on the model

two consumers read them: the attack interval is **divided** by `CadenceRate` (so Easy's 0.85 slows attacks), and player damage is
`def.damage * DamageMultiplier`.

Applied at spawn rather than at damage time deliberately: a mid-mission difficulty change must not retroactively alter enemies already on the field.

## Measured — HP scaling is exact

```
Easy     hp=168  dmgMul=0.6  cadence=0.85     (base 240, dmg 8, cd 1.6)
Normal   hp=240  dmgMul=1    cadence=1
Hard     hp=360  dmgMul=1.3  cadence=1.1
Extreme  hp=480  dmgMul=1.6  cadence=1.2
```

240 × 0.70 = 168, × 1.50 = 360, × 2.00 = 480. The multipliers reach the model exactly as authored.

## Not proven live: damage and cadence

I tried to measure damage scaling with an enemy 6–8 studs from the player and got **nothing**:

```
Normal:  shield 100 -> lowest 100  (drop 0)
Extreme: shield 100 -> lowest 100  (drop 0)
```

A follow-up probe watching the charge attribute for 8 seconds returned `charges=0` with `GF_InMission=false`. So the hostiles never entered their
attack cycle at all — the enemy was alive and adjacent, but never aimed.

That means the damage and cadence multipliers are **code-wired and attribute-verified, but not demonstrated end to end**. They may well work; I cannot
claim it. Verifying them needs a live mission, or an investigation into why `nearestVisiblePlayer` finds no target outside one.

That last part is itself a lead worth recording: if hostiles will not engage a player who is not in a mission, an out-of-mission test world can never
exercise enemy combat, which limits how much of the AI can be verified cheaply.

## Not implemented

- **`pressure`** is defined but unused. Reinforcement pressure is currently expressed by `enemyBudget` (8/12/16/18) and `eliteFrequency`, which are a
  different mechanism from the authored multiplier. Applying `pressure` on top of budget would double-count unless budget is first normalised back to a
  baseline — that needs an owner decision, not a guess.
- Shield is **not** scaled, only health. The spec column says "HP"; whether Extreme's 2× should also thicken the 80-point shield is ambiguous.

## Limits

- HP scaling measured by spawning `Rifleman` at four difficulties and reading attributes; no live damage received.
- `cadence` semantics are my reading: treated as a **rate** multiplier, so Easy's 0.85 lengthens the interval. If the author meant "interval ×
  cadence", Easy would attack 15% faster than Normal, which contradicts every other column. Recorded as an interpretation, not a certainty.
