# There is no reserve ammo: reload refills the magazine from nowhere (place 530)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client.

## Finding

`S04-025` specifies the reload economy: *"reload `n = min(capacity - mag, reserve)`, subtract reserve, add n after animation commits."* `S04-027` requires
*"limited ammo/reserve and supply."*

**Reserve is not modelled at runtime at all.** `State` carries `ammo` and no reserve key; the only mention of `weapon.reserve` anywhere in the project is inside
`CheckRunner`'s config assertions. The reload commit is:

```lua
live.reloading = false
live.ammo = weapon.magazine      -- unconditional, no min(), no reserve decrement
```

Measured through the real client remote:

```
before reload:  ammo = 19      (one shot fired through FireWeapon: 20 -> 19, Accepted=1, lastShotId=1)
after reload:   ammo = 28      reloadCount = 1      reserveKeys = NONE
```

So a player can empty and refill indefinitely. Effective ammunition is **infinite**, and the `min(capacity - mag, reserve)` arithmetic the row describes has no
implementation to be right or wrong about.

## What does work

- **Reload fires, commits, and takes time.** `reloadCount` incremented, ammo restored to magazine size, `AmmoUpdated` pushed to the client.
- **Reload is refused when full** (`if s.ammo >= weapon.magazine then return end`) and while already reloading.
- **Cancel-before-commit is handled**: the delayed commit checks `live.reloading and now() >= live.reloadDone`, so a cancel (weapon switch sets
  `s.reloading = false`) leaves ammo unchanged. That half of `S04-026` is implemented by construction.

## A hypothesis I had to retract mid-batch

For several probes, firing `FireWeapon` from the client changed nothing — `lastShotId` stayed 0 and ammo didn't move — and I was one step from recording that the
**client→server combat remotes were dead**. Two things refuted it:

1. An ad-hoc listener attached to the same remote *did* receive the event (`RECEIVED from … payload=table`), so transport was fine.
2. Firing with `origin = root.Position` instead of an origin derived from a `CFrame` offset worked immediately: `ammo 20 → 19`, `Accepted=1`,
   `lastShotId=1`.

The `GFDebug` counters (`Received`, `Accepted`, `LastReject`) are the instrument that settles this, and I only checked them late. They live on
`workspace.GFDebug`, not `workspace` — the same container mistake as earlier in this project.

## Ledger effect

- **`S04-025` → PARTIAL.** Commit and cancel semantics are real; the retention/reserve arithmetic is absent because reserve does not exist.
- **`S04-027` → PARTIAL.** "Limited ammo/reserve" is not implemented; there is nothing to limit.

## Not changed

Adding a reserve field touches every weapon's economy, the HUD ammo display, supply crates and drops, and the reload commit — plus it would make the reserve
values in `Configs/Weapons` (168/216/225/42/72/16/7/72) live for the first time. That is a design decision with visible gameplay consequences, so it is recorded
rather than implemented.

## Limits

- One weapon (AR01), one player, no supply crates and no drops involved.
- Reload timing was not measured against `reloadTime`; only the resulting ammo.
- The `AmmoUpdated` payload was not captured, only the server-side state and the firing result.
