# Augments: one trait each, no signature variants (place 504)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, plugin-level config inspection. No place changes.

## Shape of the catalog

Every one of the 36 archetypes carries exactly these fields:

```
applies, category, cost, displayName, effect, id, rarity, slot, trait
```

**There is no `variant`, `signature`, `isSignature` or `tier` field.** And trait sign splits **30 positive / 6 negative**, one trait per
archetype.

## `S11-044` — negative tradeoffs: partial, and not in the authored shape

The spec's model is a *mix*: *"Negative tradeoff values e.g. reload duration +8–15%, mag -8–12%, spread +8–15%, range -10–18%, support
cooldown +8–15%"*, combined with S11-037's *"rarity gives 1/2/3/4 positive/negative trait entries"*.

What exists is **one trait per augment**, and 6 of 36 happen to be negative trades (`StabilityCompensator -0.08 adsSpeed`, and the
negative-coefficient recoil group which are benefits rather than tradeoffs). No augment carries a positive **and** a negative entry, and
rarity does not govern the count. So the tradeoff mechanic exists as data, but not as the positive-plus-negative pairing the spec describes.

## `S11-045` / `S11-046` — signature variants: ABSENT

The spec defines *"strong signature variants as 1.25× ordinary defining range"* and a corresponding definition of the defining stat. With no
variant field and no second trait slot, there is nowhere for a signature variant to be expressed. Every augment is a single fixed archetype
with one rolled trait, so all 36 are "ordinary" by construction.

## What this means for the catalog

Three of the spec's augment features collapse into the same absence — multi-trait generation, tradeoff pairing and signature variants all
need **more than one trait slot per augment**. That is the same instance model blocking `S11-031` and the entire reroll/dismantle/fusion
cluster: the archetype table is flat, and every richer idea needs instances that can hold N traits.

Worth stating plainly: the catalog is not broken, it is **simpler than specified** — 36 working single-trait augments rather than 36
multi-trait items with variants. Functionally playable; structurally about a third of the authored depth.

## Confidence

High. Field enumeration is exhaustive over all 36 entries, and the trait-sign count comes from the same pass. What I did not check is
whether `rollTrait` could ever emit a second trait opportunistically — it cannot, because it returns a single `key, value` pair and callers
store one entry per augment id.
