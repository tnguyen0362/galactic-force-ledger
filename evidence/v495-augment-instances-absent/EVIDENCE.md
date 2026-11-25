# Augments have no per-instance generation at all — `S11-037` is ABSENT, not unverified (place 495)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, plugin-level source + config inspection. No place changes.

## What the row claimed

`S11-037` was marked **IMPLEMENTED_UNVERIFIED**: *"Augment generation: rarity gives 1/2/3/4 positive/negative trait entries
(Common/Rare/Epic/Legendary)"*, with the next action *"Roll 1-4 traits per augment by rarity."*

The label implies a generator exists and needs testing. It does not exist.

## A measurement I had to discard first

My first attempt counted `#e.trait` per rarity and got **3 for all four rarities** — which looks like a clean finding ("the 1/2/3/4
rule is missing") but is **meaningless**. `trait` is a single roll definition:

```
one archetype.trait = {key=recoil, max=-0.12, min=-0.17}
```

Three *keys*, not three traits. Every archetype has exactly one trait definition, so counting its keys measures the shape of the
data structure, not the number of traits.

## What is actually true

Ownership is a **boolean set**, not instances:

```lua
if profile.ownedAugments[augmentId] == true then return false end
profile.ownedAugments[augmentId] = true
```

So an augment is an **archetype**, and a player either owns it or does not. There is no per-instance record that could carry rolled
traits, no rarity-dependent count, and nothing for "1/2/3/4 entries" to apply to.

Two structural consequences:

1. **Every copy is identical.** Two "SlugLoad" augments are the same item, not two rolls. A min/max range in the config
   (`min = -0.17, max = -0.12`) is therefore only usable as an archetype-level range — `forProfile` reads `def.effect`, the fixed
   value, so the authored *range* is never sampled at all.
2. **`S11-031` and `S11-037` are the same missing subsystem.** Without a UID/timestamp per instance there is nothing to roll onto;
   without per-instance traits there is nothing for a UID to identify. They cannot be fixed independently.

## Corrected status

`S11-037` → **ABSENT**, with the reason recorded. Marking it `IMPLEMENTED_UNVERIFIED` overstated the build: it implied code to
verify, and there is none.

This also means `S11-031`, `S11-037` and the durability-dependent rows are one coherent future batch — an augmentation **instance**
model — rather than three separate gaps.

## Confidence

High for the structural claim: `ownedAugments[augmentId] = true` is unambiguous, and `forProfile` sums `def.effect` with no
per-instance lookup. The only way a generator could exist elsewhere is if a different module minted instances under another key
name, which contradicts `grantAugment` being the only writer.

## Not done

I did not add an instance model. It interacts with persistence (`S11-031`), cache opening (`S09-*`), dismantle/fusion protection
(`S11-042/043`) and the augment UI, and would need the same durability decision already pending for the rewards ledger. Recorded so
the shape is understood before anyone starts.
