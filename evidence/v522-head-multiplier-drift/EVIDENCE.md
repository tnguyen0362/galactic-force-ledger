# Headshots are ×2, not the authored ×1.5 — and "marked weakpoint" doesn't exist (place 522)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client.

## What the spec asks

`S04-014`: *"Enemy body hit x1, head/marked weakpoint x1.5; boss parts use defined coefficients."*

## What the build returns

Called `CombatService.weakMultiplier` directly against a live `Rifleman` rig:

```
Head[1]=2.00  Head[2]=2.00  Torso=1.00  heads=2  torsos=1  markedWeakPoints=none
```

Three findings in one line:

1. **Head is ×2.00 against an authored ×1.5** — every headshot is 33% stronger than specified. On a 240 HP Rifleman that is the difference between
   killing in 7 headshots and 6.
2. **Body is ×1.00** — conforms.
3. **No part carries a `WeakPoint` attribute**, so the *"marked weakpoint"* half of the clause has no implementation. The code supports it —
   `weakMultiplier` reads `part:GetAttribute("WeakPoint")` before falling back to the name check — but nothing ever sets that attribute on any enemy.

A secondary observation: the rig contains **two parts named `Head`** and both resolve to ×2. `FindFirstChild("Head")` therefore picks one
arbitrarily, which matters for any code that looks the head up by name rather than by raycast.

## Where this was nearly missed

This is the same ×2 that produced the puzzling `196.8` damage figure in the shotgun-pellet batch. At the time I explained the total as "eight pellets with
several headshots at mult 2" — correct about the arithmetic, but I filed it as expected behaviour rather than noticing that **2 is not the authored
number**. The value was visible and I read past it.

## Boss coefficients

Not assessed here — `S06-053` covers boss armour multipliers (.55–.75) and exposed weakpoints (×1.5–2). Since the ordinary head is already at the top of
that boss range, boss weakpoints may effectively have no headroom. Worth checking together.

## An unresolved anomaly in the fire path

I tried to confirm the multiplier through a live shot: spawn an enemy, itemise it at ×0 shield, fire `AR01` (18 base) into the torso, then the head, reading
health deltas. Every attempt returned **0 damage with no rejection reason** (`GF_LastReject` empty), from origins well inside the 8-stud
`MAX_ORIGIN_OFFSET` and with ammo set.

So `fire` accepts the shot but no damage lands. Candidate causes I did **not** distinguish: the ray hits a rig part `resolveEnemy` does not map, the ray
hits nothing (I never read `LastMiss`), or the spawn/scoping means the model is not the one being raycast. The multiplier answer above does not depend on
this, but **the fire path's ability to damage a spawned test enemy is itself unverified**, which limits future combat testing.

## Not changed

The head multiplier is a damage-tuning constant. Changing 2 → 1.5 alters every TTK measurement in the project, so it belongs with the owner's balance
pass, not an autonomous edit. Recording the value precisely is the useful contribution.
