# Augment inventory capacity implemented: 200 baseline, +50/expand, 400 cap (place 497)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 497**.

## The absent row

`S11-032`: *"Inventory 200 Augments baseline, expansion +50 via 10 Cells+3 Tech+1000 Credits, max400 initially"* — previously
**ABSENT**, with no capacity field, no expansion and no blocking rule anywhere.

## Implemented

`AugmentService`:
- `BASELINE_CAPACITY = 200`, `CAPACITY_STEP = 50`, `CAPACITY_MAX = 400`, `EXPAND_COST = { energyCells = 10, militaryTechnology = 3, credits = 1000 }`
- `grantAugment` now counts owned augments and **refuses at capacity**, publishing `GF_AugmentCapacity` as `owned/cap` or `full n/n`
- `expandCapacity(profile)` checks all three costs, deducts them, and adds one step clamped to 400

`ArmoryService`: new `expandAugmentInventory` action that calls `expandCapacity` and marks the profile dirty — through the armory,
so the write persists (the lesson from the `markDirty` false lead).

## Measured

Blocking rule, using a deliberately tiny capacity so the rule is reachable without 200 grants:

```
capacity=1 owned=1  grant(MasterworkBore)=false   marker="full 1/1"
capacity=2          grant(MasterworkBore)=true    marker="2/2"
```

Expansion, with funded costs:

```
expand ok=true  cap 37 -> 87   (+50, one step)
credits 5000 -> 4000   cells 40 -> 30   tech 10 -> 7      exact authored costs
```

And with an unset field, the baseline default applies: `baseline capacity field=nil default=200`.

## Not verified

- **The 400 clamp.** Reaching it needs 400 owned augments; the `math.min(CAPACITY_MAX, ...)` guard is read, not exercised. The
  refusal path at max ("already at max capacity") is similarly untested.
- **The insufficient-funds branches.** Every cost check has a rejection message; none was triggered. A player with 9 cells or 999
  credits should be refused, and that is unproven.
- **No UI surface.** The action exists and works when invoked, but no armory button calls it. A player cannot currently buy an
  expansion through the interface.
- Capacity is stored on the profile but **not in the load-time schema default** — it is applied via `or BASELINE_CAPACITY`. A
  migration that writes the field explicitly would be better and was not done.
- `S11-033` (the blocking rule's downstream consequences) is still open and depends on this landing properly.

## Side effects disclosed

The probe temporarily replaced `ownedAugments` with a single-entry table to make the blocking rule reachable, then restored it, and
left `augmentCapacity` at 87 on the test profile. Both are session-state manipulations, not content changes.
