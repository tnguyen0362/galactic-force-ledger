# `S04-032` VERIFIED: damage, hitmarker and kill all confirmed on the client (place 548)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. **No source changes**; probe and watcher removed.

## Why the earlier attempts failed, now measured

Before building the target I retried `EnemyService.spawn` at six different offsets and validated each against `GetBoundingBox()`:

```
off=14 vertical=32.3 flat=14.6 | off=14 vertical=30.9 flat=14.0 | ... all six: vertical ≈ 31–32
```

**Every single spawn landed ~31 studs above the player.** So this was not occasional overhead geometry — the player was standing under a ~30-stud roof, and because the
ground raycast starts 40 studs up it hits the roof's top surface every time. Indoors, enemies would spawn on the ceiling *systematically*.

## The run

A target part built **on the aim line at the player's own height** (766.46 both), 200 HP, no shield, 12 studs ahead. 16 shots:

```
hits=16   lastDmg=18   health 200 -> 0   Dead=true
client received: d=18 k=false ×11, d=18 k=true ×1, then d=18 k=false ×4
client kill counter: 1
```

The 12th shot is the kill (200 / 18 = 11.1 → 12). **Server-confirmed damage, client hitmarkers, and a kill confirmation all arrived.** `S04-032` → VERIFIED.

## A defect the run exposed

Shots 13–16 were fired at an **already dead** target and still produced `d=18 k=false` feedback — hitmarkers on a corpse. The damage no longer moves health (`hp` stays
0), but the client is told it hit something. The hit path has no "already dead" guard, so it keeps firing feedback while the model is still parented.

Small, cosmetic, and real: recorded as a defect note on `S06-035`'s queue rather than fixed, because the natural fix (`if model:GetAttribute("Dead") then skip`) sits
inside `CombatService.fire`'s hit branch and deserves its own verified batch.

## Also confirmed

Damage is clamped at 0 rather than going negative, and `Dead` is set — so the kill path is idempotent even if extra shots land.

## Limits

- The target was a hand-built part, not a real enemy model: this verifies the **damage → feedback → kill** pipeline, not enemy-model hitboxes or death animation.
- `workspace.GF_ClientKills` reads nil *server-side* because the attribute is set by the client and does not replicate — the client's own counter (`GF_Kills = 1`) is the
  valid observation.
- One weapon, one target, 12 studs.
