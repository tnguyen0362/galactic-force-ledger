# First purchase charges exactly the catalogue price; re-buy charges nothing (place 515)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. No source changes; probe scripts removed afterwards.

## Why the earlier attempt could not answer this

The previous batch tried to verify first-purchase charging and found the account already owned everything with a price on it. Re-listing ownership
confirmed the dead end:

```
SG04 500 owned   MR07 850 owned   LMG12 1400 owned   SMG03 600 owned
GL22 1200 owned  RL09 1500 owned  Sentry 900 owned   OrbitalStrike 1800 owned
ReflectiveBarrier 0 owned=false   <- the only unowned item, and it is free
```

Every purchasable-with-cost item was already owned, so only the "already owned" branch was ever reachable.

## How it was made testable

Un-owning `SG04` (500 credits) on the test profile and re-buying it drives the real purchase path without needing a fresh account.

## Measured

```
un-owned SG04; credits=5000
FIRST  buy  credits 5000 -> 4500   delta=500   owned=true
SECOND buy  credits 4500 -> 4500   owned=true
```

Three things hold at once:

- the **exact catalogue price** was deducted — 500, not a rounded or doubled figure;
- **ownership was granted** by the first purchase;
- the **second purchase charged nothing**, so the earlier no-double-charge finding is now confirmed on the same item rather than on a different one.

That closes `S12-010`'s both halves: a first purchase charges once and correctly, and re-buying an owned item does not charge again.

## A separate API-quality finding

`ArmoryService.buy` returns **`nil` for success and `nil` for refusal**, with no reason string. Unlike `equipAugment`, which returns `(ok, why)` and
is what made the compatibility work verifiable, the purchase path gives the caller nothing to distinguish outcomes. The armory UI must be inferring
success from profile state, which is fragile and impossible to assert from the outside. Wheel the callback contract in line with `equipAugment` and
this row's evidence would be cheaper to produce.

## Limits

- Only **weapons** were exercised. `buyAbility`, `buyGrenade` and `buyArmor` share the pattern but were not charged-path tested; `buyAbility` was
  observed granting a **free** item (`OrbitalLance`, cost 0) and reporting nothing.
- Insufficient-credits refusal was **not** tested.
- Ownership was manipulated directly (`p.ownedWeapons.SG04 = nil`) rather than by a supported flow, so this proves the purchase logic, not that
  un-owning is a reachable player state.
- The profile was left with `credits = 4500` and `SG04` owned.
