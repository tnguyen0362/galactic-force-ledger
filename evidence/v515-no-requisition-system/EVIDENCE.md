# There is no requisition system, and the spec's catalog weapons don't exist (place 515)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, plugin-level inspection of code and config. No place changes.

## What the scan found

A search for `requisition` across `ServerScriptService`, `ReplicatedStorage` and `StarterPlayer` returns **one** module, with two kinds of hit:

```
Armor:2   -- Six wearable kits: four standard, two requisition. Cosmetic palettes rather than meshes...
Armor:32  id = "TROPHY",    tier = "Requisition", unlockRank = 12, cost = 2200
Armor:38  id = "BLACKSTAR", tier = "Requisition", unlockRank = 16, cost = 3200
```

So "Requisition" exists **only as an armour tier label**. There is no requisition catalog, no tier structure, no spend thresholds, no premium
unlock and no progress display. `Configs` contains `Abilities, Armor, Augments, Caches, Cinematic, Classes, Difficulties, Economy, Enemies, Missions,
Weapons` — no requisition module.

## The worse finding: the catalog names weapons that do not exist

The spec describes the requisition contents by weapon id — `GF-02`, `GF-05`, `GF-06`. The entire weapon set is:

```
AR01, GL22, LMG12, MR07, P01, RL09, SG04, SMG03
```

**No `GF-*` weapon exists.** So `S12-011` (free catalog: tier1 `SG-04`/`GF-02`), `S12-013` (premium tier1 `GL-22 (1200)`/`GF-05 (500)`, tier2
`GF-06 (750)`) cannot be implemented as written — two of the three named weapons have no config entry, and `SG-04` already costs 500 credits rather
than being free.

One number does line up: **`GL-22` costs 1200**, exactly as the premium tier1 entry specifies.

## Ledger effect

Ten rows move out of UNKNOWN:

| row | verdict |
|---|---|
| `COUNT-REQ` | ABSENT — zero requisitions exist (the armour label is not a requisition) |
| `COUNT-REQ-TIERS` | ABSENT — no requisition to have tiers |
| `S12-003`–`S12-008` | ABSENT — no catalog, tiers, thresholds, ordering or progress display |
| `S12-011` | PARTIAL — stub evidence only: `SG-04` exists but costs 500, `GF-02` does not exist |
| `S12-013` | PARTIAL — `GL-22 = 1200` matches exactly; `GF-05` and `GF-06` do not exist |

## Why this is a scope question, not a bug

The requisition catalog is a **store feature** with tiered spend, premium access and a contents preview. It is not partially present — the concept
appears once as a label. That is a build-vs-spec decision for the owner, not something to infer from a single armour string.

## Confidence

High for absence: one module mentions the word, and the config list is exhaustive. The `GF-*` claim is a straight comparison against the weapon ids
and is unambiguous.
