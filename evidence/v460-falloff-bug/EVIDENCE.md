# falloffEnd was dead config; reload verified (build 460)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## The 30.32 mystery, solved by arithmetic
Last batch measured **30.32** damage at 199 studs on a base of 18 and called it unexplained. Two facts close it:

- `CombatService.weakMultiplier("Head")` returns **2**, torso returns **1**.
- Solving backwards: 30.32 ÷ (18 × 2) = **0.842** falloff at 199 studs.

The spec window (90/240, min 0.55) predicts **0.673** there. The old window (120/320, min 0.6) predicts 0.842 — but that config was already replaced. So neither matched the *configured* values, which means the code was not using them.

**It wasn't.** `CombatService.fire` computed:

```lua
local span = math.max(1, weapon.range - falloffStart)
```

`weapon.range` is 400 for AR-01. The span was 400 − 90 = 310 studs, not the authored 240 − 90 = 150. Recomputing with the real span: (199 − 90)/310 = 0.351 → 1 − 0.351 × 0.45 = **0.8418**. That is 0.842 to three decimals.

So `falloffEnd` was **dead configuration** — every weapon's curve was silently stretched to `range`, roughly 2.5× wider than authored. Aligning `falloffEnd` last batch changed nothing.

Fixed to use `falloffEnd` (falling back to `range`), which also makes the minimum clamp reachable inside the weapon's own range.

## Reload verified
Firing three shots then requesting reload:

```
ammo sequence: 27 -> 26 -> 25 -> 28
```

One `AmmoUpdated` event at completion, magazine back to 28, elapsed **1.88 s** against a configured 2.1 s. The difference is the class/augment reload factor, which I did not decompose.

## Not verified
The corrected curve has **not been measured at range**. Two attempts to land a 200-stud shot failed: targets are anchored, but the sightline I verified and the shot's actual origin drift apart between the positioning call and the client's fire, and both shots missed (no `LastDamage`). The cluttered relay compound has few long sightlines.

**Next action:** stand up a dedicated open lane (or use the open terrain beyond the compound) with a fixed target, then record body damage at 60 / 150 / 240 / 400 studs and confirm the 0.55 floor clamps at 240.
