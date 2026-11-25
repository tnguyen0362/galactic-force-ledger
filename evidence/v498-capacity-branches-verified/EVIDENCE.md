# Capacity rules fully verified: every refusal branch and the 400 clamp (place 498)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 498**.

## What last batch left unproven

`S11-032`'s expansion was verified for the happy path only. The rejection branches, the 400 clamp, and the schema default were all
read but never exercised — and capacity relied on `or BASELINE_CAPACITY` at read time rather than being a real stored default.

## Change

`ProfileService.defaults` now writes it explicitly:

```lua
ownedAugments = {},
-- Explicit on load rather than relying on 'or BASELINE_CAPACITY' at read time (GOAL: 200 baseline, 400 cap).
augmentCapacity = 200,
```

## Measured — every branch

```
default capacity on a real profile = 200

noCells    = false (not enough energy cells)         credits 9999, cells 9,  tech 10
noTech     = false (not enough military technology)  credits 9999, cells 40, tech 2
noCredits  = false (not enough credits)              credits 999,  cells 40, tech 10
funded     = true  (250)                             credits 1000, cells 10, tech 3

atMax400   = false (already at max capacity)
from380    = true  cap = 400                         380 + 50 clamped to 400
```

Every refusal names the specific shortfall rather than a generic failure, all three resource checks are independently reachable, the
spec's exact cost boundary (1000 credits / 10 cells / 3 tech) is both sufficient and required, and the 400 ceiling clamps a
380 → 430 attempt down to 400 instead of overshooting.

`S11-032` is now **VERIFIED**. The requirement text is about capacity rules and costs; it says nothing about a purchase button, and
the action is reachable through the armory remote. A dedicated armory UI button is still absent and is tracked with the other armory
panel rows rather than here.

## Still open around this

- **No armory UI button** for the expansion. The action works when invoked; a player cannot click it.
- Capacity is not enforced on the *armory purchase* path for augments bought directly, only in `grantAugment`. If any future code
  writes `ownedAugments[id] = true` directly it would bypass the cap — the same class of hole as the `markDirty` bypass found earlier.
- `S11-033`, which depends on a real capacity limit existing, can now be assessed properly.

## Test-state disclosures

The probe wrote `credits`, `salvage.energyCells`, `salvage.militaryTechnology` and `augmentCapacity` on the test profile across six
trials, leaving `augmentCapacity = 400` and `credits = 9999 - 1000` from the `from380` trial. These are session-state mutations, and
the persisted profile now carries them.
