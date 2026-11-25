# EMP disable implemented and proven with a real enemy (place 548)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 548**.

## The defect

`GrenadeRuntime` set `EMPStunUntil` on every enemy inside an EMP blast, and **nothing in the project read it**. The requirement's "2 s disable turret/robot
subsystem" therefore did nothing; only the shield drain had any effect.

## The fix

`EnemyService.isStunned(model, now?)` is the single definition:

```lua
local untilValue = model:GetAttribute("EMPStunUntil")
if type(untilValue) ~= "number" then return false end
if (now or os.clock()) < untilValue then return true end
model:SetAttribute("EMPStunUntil", nil)   -- clear, so a stale value cannot look permanent
return false
```

`tickActor` calls it immediately after the death check and returns early, so a stunned hostile neither moves nor fires. The clock is injectable so the unit checks
are deterministic rather than timing-dependent.

## Verified with a real enemy

Spawned a `Rifleman` through `EnemyService.spawn`, set `EMPStunUntil = now + 6`, then measured position:

```
stunned=true   movedWhileStunned=0.00
afterExpiry:  stunned=false  movedAfter=2.84     (enemy still alive)
```

Frozen for the full stun, moving again the moment it expired. That is a before/after differential on one actor, not an inference from code.

## Unit checks

Four assertions added (suite **`passed=671 failed=17 nonDrift=0`**): active before expiry, ended after expiry, expired attribute cleared, and no attribute means
not stunned.

## What this does and does not close on `S04-053`

- **Closed:** the disable exists and works. The write now has a reader.
- **Still open (owner tuning):** the stun duration is **2.5 s** in `GrenadeRuntime` vs **2 s** in spec — `isStunned` obeys whatever the field says, so changing
  that one number is all it takes.
- **Still open:** the requirement scopes the disable to *turret/robot subsystems or energy guns*. The implementation is a blanket stop — it freezes any hostile,
  including Riflemen. A scoped version needs per-enemy subsystem metadata that does not exist.
- **Still open (recorded last batch):** Frag radius 22 vs 15, Frag damage 110 vs 135, Frag fuse 2.6 vs 2.5, EMP radius 26 vs 13, EMP shield drain vs 90, EMP 15
  health damage absent, Frag 4 s flight cap absent.

## Limits

- One enemy type (`Rifleman`), one stun, one duration. Boss/Elite behaviour while stunned was not exercised.
- The stun stops the tick entirely; it does not model a "subsystem" being offline while the actor still turns or plays reactions.
- Verified in single-player; pulse/AoE interactions with other hostiles are untested.
