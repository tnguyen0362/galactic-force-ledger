# Cache system — measured evidence (build 408)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`. Server reads; no frames.

## What existed before
**Nothing.** `Configs` had no cache entry, `LootService` only spawned resource pickups, and there was no code that could open, roll or grant a cache. Four cache tiers were an unmet requirement with zero implementation.

## Implemented
`Configs/Caches`: four tiers with `augments` (1/2/3/4), spec rarity weights, per-tier enemy-drop chances, colour.
`Services/CacheService`: `roll(tier, owned)` and `open(player, tier, source)` plus `grantMission(tier)`.
- A tier's rarity weighting **restricts the candidate set**: the roll picks a rarity by the tier's weights, then takes an owned-excluded archetype of exactly that rarity (same category first, then any category). Before this it picked an archetype and only labelled it with the tier rarity, so the weights were dead data.
- Opening grants the augments to the profile, rolls a trait for each, marks the profile dirty, and publishes a loot line.
- `ObjectiveService.complete()` grants one guaranteed cache: Easy→Common, Normal→Rare, Hard→Epic, Extreme→Legendary.

## Five Legendary archetypes were needed
The Legendary tier's 15% weighting had nothing to roll: every archetype was Common/Rare/Epic, so 120 Legendary-tier draws produced **0** Legendary augments. Added `MasterworkBore`, `SiegeChamber`, `ExecutionerOptic`, `SiegePayload`, `OverclockedCore` at Legendary rarity. Catalogue is now 32 archetypes across 9 categories (3–4 each).

## Measured
Tier counts, deterministic path (`CacheService.roll`), 300 caches per tier:

| Tier | Draws | Common | Rare | Epic | Legendary |
|---|---|---|---|---|---|
| Common (spec 82/16/1.9/0.1) | 300 | 81.7 | 16.0 | 2.3 | 0.0 |
| Rare (48/43/8/1) | 600 | 48.5 | 42.3 | 8.0 | 1.2 |
| Epic (18/48/30/4) | 900 | 17.4 | 49.7 | 29.0 | 3.9 |
| Legendary (0/30/55/15) | 1200 | 0.0 | 26.0 | 58.5 | 15.5 |

Augment counts per cache: Common 1, Rare 2, Epic 3, Legendary 4 — the tier table and the draw count are both real.

Mission path: completed `SABOTAGE_RELAY` on Normal → `GF_CacheOpened = "Rare:2:mission"`, and the profile's owned augments went 10 → 13 (new: `ArmorPiercer`, `BorePolish`, `QuickFeed`).

## Known defects and limits
- **Legendary-tier Rare share is 26% against the spec's 30%.** Only five Legendary archetypes exist, so a 4-draw cache can exhaust the pool and the fallback shifts draws to other rarities. One Legendary archetype per category would stabilise it.
- Enemy cache drop chances exist in config (`infantry 1%`, `heavy 4%`, `commander 7%`) but **nothing rolls them yet**; `S11-008`/`S11-009` (per-mission cap 3) are unimplemented.
- The mission cache is granted at **primary completion**, not at extraction, so a failed extraction still pays it. `S11-007` wants the successful-primary-plus-extraction rule.
- Caches have no UID, no unopened stack, no bulk open, no fusion (`S11-031`, `S11-033`–`S11-035`).
- "Legendary 0.0 on Common tier" is sampling (expected 0.3 draws in 300), not an exclusion.
