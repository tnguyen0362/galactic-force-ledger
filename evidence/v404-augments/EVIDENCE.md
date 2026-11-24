# Augment catalogue rebuild — measured evidence (build 404)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`. Server reads only; no frames.

## What changed
`ReplicatedStorage/GF/Shared/Configs/Augments` was a flat list of 10 entries with no category and no rarity. It is now built from an `entry()` helper with **9 categories × 3 archetypes = 27**, each carrying `category`, `rarity` (Common/Rare/Epic), `cost`, an `effect` table using only keys `AugmentService.KEYS` already consumes, and a `trait` range.

New API: `Augments.forCategory`, `Augments.countFor`, `Augments.RarityWeight`, `Augments.roll(category, owned)` (rarity-weighted, skips owned), `Augments.rollTrait(entry)`.

`AugmentService.forProfile` now adds the rolled trait for each equipped augment (`applyTrait`), so the same archetype can roll a different value per player.

`ArmoryService.buyAugment(player, id, category)` accepts a category instead of an id: it rolls an unowned archetype from that pool, charges that archetype's cost, stores `ownedAugments[id]` and `augmentTraits[id] = { key, value }`, and pushes the actual id/category/rarity.

## Measured
| Check | Result |
|---|---|
| Catalogue size | 27 |
| Per-category counts | Universal 3, AR 3, SMG 3, LMG 3, Shotgun 3, Marksman 3, Launcher 3, Pistol 3, Support 3 |
| `Augments.roll("Launcher")` | `WideCharge`, rarity Common |
| `Augments.rollTrait` on it | `blastRadius = 0.344` (range 0.24–0.38) |
| `augmentBuy` with `category = "Launcher"` | `GF_AugmentBought = "Launcher:ShapedWarhead:660"` |
| `augmentBuy` with `category = "Marksman"` | `GF_AugmentBought = "Marksman:StableStock:430"` |

## Open defect — repeat purchases did not take effect
After the first purchase in a category, further `augmentBuy` calls changed nothing: `GF_AugmentBought` kept its previous value across three attempts in Marksman, and no `RequestLoadout` push reached the client for those calls (the weapon-buy pushes had worked earlier in the same session). The roll correctly excludes owned ids, and Marksman still had two unowned archetypes, so the cause is **not** exhaustion of the pool. Not isolated: the refusal happens before the attribute write, and `augmentBuy` failures do not set `GF_AugmentRejected` (only the `augment` action does), which is why nothing surfaced.

Next step: have `buyAugment` set a rejection attribute with the exact reason, then read it.

## Limits
- Rarity affects **cost and roll weight only**; it does not add extra traits or tiers of effect magnitude yet.
- Caches do not consume these pools; cache tiers still roll independently.
- The Armory UI has no category selector; the category is supplied on the remote payload, so a player-facing choice is not wired.
- Traits are applied to stat keys but no UI surfaces the rolled value.
