# The second augment socket gated on 5 XP, not mastery level 5 (place 470)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, fresh Play VM. Place saved as **version 470**.

## The defect — and it was partly mine

`GOAL_2026-11-24.md` L165: *"starter one Augment socket, level5 second permanent socket"*.

`AugmentService.socketsFor` compared **raw XP** against a constant named `SECOND_SOCKET_MASTERY`:

```lua
local SECOND_SOCKET_MASTERY = 5
...
mastery = tonumber(profile.weaponMastery[weaponId]) or 0
return mastery >= SECOND_SOCKET_MASTERY and 2 or 1
```

The name says "mastery 5" (level 5), the comparison uses XP. So:

- **before** the mastery rescale, at **1 XP per kill** with a cap of 10, this behaved as "five kills" — wrong versus the spec, but
  plausibly mistaken for a level.
- **after** the rescale to the authored **10 XP per kill** with a 650 cap, it would have unlocked on the **first kill**.

So a latent naming bug became a visible exploit *because of my own earlier change*. I introduced the conditions for it two batches
ago while fixing the cap; this batch catches it. That is worth stating plainly rather than filing as a pre-existing quirk.

## The fix

| item | before | after |
|---|---|---|
| constant | `SECOND_SOCKET_MASTERY = 5` | `SECOND_SOCKET_XP = 650` (the level-5 threshold) |
| comparison | `mastery >= 5` | `mastery >= 650` |
| refusal message | `"requires mastery %d"` → `requires mastery 5` | `"requires mastery level 5 (650 XP)"` |

No `SECOND_SOCKET_MASTERY` references remain. `AugmentService` compiles.

## Measured

Fresh Play VM, `socketsFor` called on plain profile tables:

```
xp=0    sockets=1     xp=649  sockets=1
xp=10   sockets=1     xp=650  sockets=2
xp=100  sockets=1     xp=900  sockets=2
xp=500  sockets=1     unowned sockets=0
equip slot2 @500xp -> ok=false  reason="requires mastery level 5 (650 XP)"
equip slot2 @650xp -> ok=true
```

`xp=10 → sockets=1` is the assertion that matters: that is one kill under the authored rate, and under the previous code it
returned 2.

## A mistake in my own test, for the record

The first probe called `A.assign(...)`, which does not exist — `AugmentService` exposes `forProfile, grantAugment, socketsFor,
slotTable, equipAugment, unequipAugment, forPlayer, magazine, reloadTime`. It threw `attempt to call a nil value` at line 14,
**after** the sweep had run but **before** the result attribute was written, so the whole probe published `nil` and looked like
the fix had failed. Reading the console output showed the real cause in one line. Second time in this session that an
instrument failed and briefly impersonated a code fault.

## Still open

- `S10-039`: mastery progress is still not displayed in the debrief or the Armory. The socket now unlocks at the correct point but
  a player has no way to see how close they are.
- "Track every **owned** weapon" is not enforced — any weapon id on session state can be credited.
- The socket count is enforced in `equipAugment`; the Armory UI was not exercised, so what a player actually sees at level 4
  versus level 5 is unverified.
