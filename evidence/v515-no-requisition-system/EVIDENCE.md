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

## Correction (same session): `GF-*` are ARMOUR kits, not weapons

I wrote above that "no `GF-*` weapon exists at all" and inferred the spec was naming weapons that had never been built. **That was wrong**, and the
prefix misled me. `GF-01`–`GF-06` are **armour kits**:

```
STANDARD  "GF Standard Kit"      r1   free
RECON     "GF-02 Recon Weave"    r3   500
SIEGE     "GF-03 Siege Plate"    r5   850
VANGUARD  "GF-04 Vanguard Seal"  r8   1200
TROPHY    "Ascendancy Trophy"    r12  2200
BLACKSTAR "Blackstar Command"    r16  3200
```

So `GF-02`, `GF-03` and `GF-04` **do exist**, and their ranks and costs match the spec exactly (`GF-02 rank3/500`, `GF-03 rank5/850`,
`GF-04 rank8/1200`). What is genuinely missing is **`GF-05` (Ash Sentinel) and `GF-06` (Frost Warden)** — the armour list ends at four numbered kits.

The requisition conclusion is unchanged: there is still no requisition catalog, tier structure, spend threshold or premium unlock. But the "spec
names weapons that don't exist" claim was a misreading, and the corrected statement is narrower and more useful:

- `S12-011` — `SG-04` exists but costs 500 rather than being free; `GF-02` exists as armour at 500. The row is still PARTIAL, but for the *free*
  condition, not for a missing item.
- `S12-013` — `GL-22 = 1200` matches; `GF-05 (500)` does not exist; `GF-06` (tier2) does not exist.

This is the fifth time this session that a **prefix-shaped assumption** produced a false finding. The rule that would have prevented it: when a
requirement names an id, resolve that id in the config **before** concluding it is absent.
