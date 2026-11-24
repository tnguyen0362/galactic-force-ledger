# Archetype armour and the Commander aura (build 442)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## Implemented
- **Armour factors** per archetype (`Rifleman 1.0, Scout 1.0, Marksman 1.0, Heavy 0.75, Officer 0.9`), published on the model as `ArmorFactor` at spawn and applied in `CombatService.damageEnemy` **after** shields absorb, with `GF_LastArmorMitigated` recording the result.
- **Commander aura**: `EnemyService.auraRate(model)` returns 0.9 when a live `Officer` is within 45 studs and 1 otherwise, applied to the attacker's cooldown (`nextAttack = now + cooldown * rate`). It reads live models each call, so death clears it without any bookkeeping. `AuraRate` is stamped on the model for inspection.

## Measured
Armour, via `damageEnemy(model, 40)`:

| Archetype | Shield before → after | Damage taken | Expected |
|---|---|---|---|
| Heavy (0.75) | 180 → 150 | **30** | 40 × 0.75 = 30 |
| Officer (0.9) | 160 → 124 | **36** | 40 × 0.9 = 36 |

Aura, by reading `AuraRate` on archetypes that had just attacked:

| Condition | Marksman | Heavy | Scout | Rifleman |
|---|---|---|---|---|
| Officer alive within 45 studs | 0.9 | 0.9 | 0.9 | 0.9 |
| Officer killed | **1** | **1** | **1** | **1** |

Both halves of the Commander rule — the buff and the clearing on death — are observed, and the +10% is applied as a shorter cooldown rather than a damage change.

## Limits
- The aura's *measurable effect* is the cooldown multiplier; the actual shot cadence difference (1.6 s → 1.44 s) was not timed shot-to-shot.
- The aura has no radius falloff and no visual, and "no stacking" is implicit (the function returns a single 0.9, never 0.81).
- Armour applies to shields too; the spec's wording is about health, so this may be stricter than intended.
- The Officer's relay call and the Heavy's charged blast remain unimplemented.
- One client; archetypes measured one at a time.
