# Armoury clicks verified; a cache no longer burns for nothing (build 423)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## Layout change
Caches and armour now sort **above** the weapon list (`LayoutOrder` 10–13 and 20–25 versus 100+), so the newest sections are the first thing a player sees — and the first thing a synthetic click can reach.

Measured row order: `Loadout1..3` (1–3) → `CacheCommon/Rare/Epic/Legendary` (10–13) → `ArmorSTANDARD..BLACKSTAR` (20–25) → weapons (100+).

## The click limitation was mine, not the harness's
The list viewport is **286 px tall starting at y = 167**. A row outside that band cannot be clicked. Earlier failures were rows at y = 837 (armour) and y = 141 (cache, scrolled too far). With the row inside 167–453, both clicks landed:

| Click | Result |
|---|---|
| `ArmorRECON.Wear` at y = 329 | `GF_ArmorEquipped = "RECON:true"`, suit `RECON` |
| `CacheRare.Open` at y = 351 | `held Rare → 0`, `GF_CacheOpens = 1` |

So armour and cache buttons **are** reachable and wired; my previous "harness cannot click scrolled frames" note was imprecise — it cannot click *clipped* ones.

## A real defect the click test exposed
That cache open produced **`Rare:0`** — zero augments — because every Rare archetype was already owned, and the cache was consumed anyway. A player would have lost a cache for nothing.

Fixed: `openFromInventory` rolls first, and if the roll is empty it refuses with `nothing left to roll` **without decrementing**. Measured on the next held cache: `held` stayed `Rare:1`, `GF_CacheRejected = "nothing left to roll"`.

## Limits
- The `nothing left to roll` state is correct but unhelpful as a player experience: the armory still shows the cache as held with an `OPEN` button that will refuse. A "pool exhausted" hint on the row is not implemented.
- Cache contents and Augment inventory have no capacity model, so `S11-033` is still only partly met.
- One player, one difficulty.
