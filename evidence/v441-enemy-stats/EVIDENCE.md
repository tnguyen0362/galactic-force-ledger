# Enemy stats realigned to spec, and burst fire (build 441)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## The authoring gap
Every archetype was authored in the checklist with specific HP, shields, movement and burst patterns. The build used **none** of those numbers — and every attack was a single instantaneous hit, so the authored `8 × 3`, `6 × 4`, `12 × 2` patterns did not exist at all.

| Archetype | Spec HP/shield | Was | Now |
|---|---|---|---|
| Rifleman | 240 / 80 | 120 / 60 | **240 / 80** |
| Scout (Vanguard) | 210 / 60 | 80 / 30 | **210 / 60** |
| Marksman | 210 / 60 | 100 / 40 | **210 / 60** |
| Heavy | 620 / 180 | 260 / 150 | **620 / 180** |
| Officer (Commander) | 420 / 160 | 180 / 100 | **420 / 160** |

Movement, damage and bursts were realigned in the same edit: Rifleman 13 / 8 dmg ×3, Scout 18 / 6 ×4, Marksman 11 / 38 ×1, Heavy 8 / 32 ×1, Officer 12 / 12 ×2.

## Burst fire implemented
`EnemyService` resolved an attack with one `VitalsService.applyDamage`. It now reads `def.burst` and fires `count` hits `interval` apart, breaking early if the model dies, the target loses its character, or the target leaves `attackRange × 1.35`.

## Measured
| Check | Result |
|---|---|
| Scout spawn stats after the config change | HP **210**, shield **60** |
| Damage taken at 4 studs from a Scout | 10 log lines, each `amount=6.0 source=Scout` |

Ten separate 6-damage events rather than one 24-damage event is the burst working: the Scout's authored 6 × 4 pattern arrives as four small hits.

## A mistake worth recording
My first config edit was a string-splicing helper that produced `burst = burst = { ... }, },` and **the module stopped compiling** — I had no backup. I recovered by reconstructing the mangled lines with targeted patterns and verifying with `loadstring` at each step. The file is correct now, but the lesson is blunt: **splice config by hand or by line range, verify compile after every step, and keep a copy before bulk edits.**

## Limits
- Only the Scout was measured in play. Rifleman, Marksman, Heavy and Officer stats changed but were not re-observed.
- Burst timing (0.15 s interval, full 4-shot volley) was not timed; only that multiple 6-damage events occurred.
- Heavy still has no charged-blast telegraph, Officer has no ally fire-rate aura, and no archetype uses armour factors.
- Shield-taking behaviour means player HP stayed at 100 while the shield absorbed the burst.
