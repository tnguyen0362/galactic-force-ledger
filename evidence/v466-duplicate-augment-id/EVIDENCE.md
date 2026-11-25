# Duplicate augment archetype id fixed; the boot check clears (place 466)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, fresh Play VM. Place saved as **version 466**.

## The defect

`CheckRunner` reported `Augments: duplicate id FastHands`. Two archetypes declared the same id:

```lua
-- line 33, SMG
entry("FastHands", "Fast Hands",          "SMG",    "Rare",  380, { swapSpeed = 0.25 }, ...)
-- line 70, Pistol
entry("FastHands", "Fast Hands (Pistol)", "Pistol", "Epic",  480, { reloadSpeed = 0.2, adsRecovery = 0.15 }, ...)
```

Both were created in the 32-archetype rebuild at build 408. The boot check computed the collision every run since; nothing ever
acted on the result, because `Main` only prints `CheckRunner.run()`'s output.

This is not cosmetic. `Augments.ById` is keyed by id, so one entry overwrote the other, and a Pistol-category roll that
resolved to `FastHands` could return the SMG archetype's effects and cost. It also makes `S11-054` — *"archetype IDs separate
from display labels and UID, so duplicates detectable"* — false in practice.

## The fix

Renamed the Pistol entry to `PistolFastHands`, keeping its display label `Fast Hands (Pistol)` unchanged.

Checked first that nothing else referenced the id: searching every `LuaSourceContainer` under `ServerScriptService.GF`,
`ReplicatedStorage.GF` and `StarterPlayer` for `FastHands` returned exactly **two** hits, both the config definitions. So the
rename could not break a reference, a saved loadout key, or a test.

## Measured

```
before:  ok=false  passed=625  failed=13   (includes "Augments: duplicate id FastHands")
after:   ok=false  passed=625  failed=12   (augment error gone)
```

`passed` does not increase because the existing duplicate check only calls `ok(false, ...)` when a collision is found — there is
no corresponding assertion on the clean path. The failing assertion is removed, which is why the total fell by exactly one.

The 12 remaining failures are all **spec drift on balance values** (launcher radii, ability cooldowns/radii/damage, boss HP).
They are the owner's to rule on and were deliberately left red.

## Limits

- Only the id was changed. The Pistol archetype keeps `reloadSpeed 0.2 / adsRecovery 0.15` at Epic 480 credits, which was never
  checked against an authored row.
- Any profile that already owns the colliding id cannot distinguish which archetype it bought; this fix stops future
  ambiguity but does not repair existing saved data.
- `CheckRunner.run()` is still non-fatal at boot (`Main` warns). The drift count staying visible is the intended signal.
