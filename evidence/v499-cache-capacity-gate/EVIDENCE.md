# Cache opening now respects capacity — and a correction to my own ABSENT verdict (place 499)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 499**.

## Change: the opening gate (`S11-033`)

`CacheService.open` granted unconditionally and **ignored `grantAugment`'s return value** — so with a full inventory a player could
open a cache, watch it roll, and silently receive nothing. The spec asks for the opposite: block *opening* only when the result
cannot fit, and never block deployment or receiving a cache.

```lua
local capacity = tonumber(profile.augmentCapacity) or AugSvc.BASELINE_CAPACITY
local ownedCount = 0
for _ in pairs(profile.ownedAugments or {}) do ownedCount += 1 end
if ownedCount + #rolled > capacity then
    workspace:SetAttribute("GF_CacheBlocked", string.format("full %d/%d needs %d", ownedCount, capacity, #rolled))
    return {}
end
```

## Measured

```
full capacity (1/1):  returned=0  owned 1->1  blocked="full 1/1 needs 1"
room for one   (2/1): returned=1  owned 1->2  blocked=nil
```

The same call succeeds the moment a slot exists — the gate is about fit, not about refusing opening generally.

**Deployment and cache rewards stay ungated, verified by reference rather than assumption:** `augmentCapacity` appears in exactly
three modules — `ProfileService` (default), `AugmentService` (cap + expansion), `CacheService` (this gate). No deployment, squad or
dispatch module reads it, so a full inventory cannot strand a squad; and `grantToInventory`/`grantMission` have no capacity check, so
a cache reward is never denied.

## A correction to my own place-495 verdict

I marked `S11-037` **ABSENT**, concluding there was no per-instance augment generation. That was **too strong**, and the evidence was
in the file I was reading:

```lua
local traitKey, traitValue = Augments.rollTrait(Augments.get(item.id))
if traitKey then
    profile.augmentTraits = profile.augmentTraits or {}
    profile.augmentTraits[item.id] = { key = traitKey, value = traitValue }
end
```

**Trait rolling exists** at open time — `rollTrait` samples the authored `{key,min,max}` range and the result is stored per augment
in `profile.augmentTraits`. So my earlier statement that "the authored min/max range is never sampled" was wrong.

What is genuinely missing from `S11-037` is the **rarity rule** (1/2/3/4 trait entries for Common/Rare/Epic/Legendary): every augment
gets exactly one rolled trait regardless of rarity. And `S11-031`'s UID gap is confirmed differently — traits are keyed by
**augment id**, not by an instance id, so two copies of one archetype can never hold different rolls.

`S11-037` is therefore **PARTIAL**, not ABSENT. I should have read `CacheService.open` before concluding from `grantAugment` alone
that nothing rolled traits.

## Still open

- `S11-035`: bulk opening bounded to 10 caches per action with space calculated before the draw. No bulk path exists to bound.
- `S11-033`'s fusion clause: fusion does not exist, so "blocks fusion only if the result cannot fit" is unenforceable as written.
- `S11-031`: per-instance identity. Traits keyed by archetype id means one roll per archetype forever.

## Disclosed

The probe temporarily replaced `ownedAugments` with a single-entry table and set capacity to 1 and 2, restoring both afterwards.
