# The join repair works across a real server restart (place 514)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`. No source changes — this closes a verification gap, not a code change.

## What was unverified

Place 514 added `AugmentService.sanitiseLoadout` and called it from `ArmoryService.PlayerAdded`. The evidence then said, honestly:

> *"the `PlayerAdded` path itself was **not** exercised: the probe called `sanitiseLoadout` directly… that needs a client disconnect/reconnect or a
> fresh server."*

## How it was tested this time

Three deliberate steps, the middle one easy to forget:

1. **Plant** a known-bad loadout and persist it: `Choke` (shotgun-only) into slot 1 with `selectedLoadout.primary = "SMG03"`, then
   `ProfileService.save(player)` → `save=true`, `mode=datastore`.
2. **Remove the planting probe before restarting.** Left in place, it would have re-planted the mismatch at the top of the next session and made a
   passing test meaningless.
3. **Restart Play**, let a fresh server load the profile from DataStore, and read the observable.

## Measured

```
sanitisedCount  = 1
sanitisedDetail = "Choke from SMG03"
```

A completely new server loaded the persisted mismatched loadout, the `PlayerAdded` hook ran the repair, and it removed the shotgun augment from the
SMG primary. The stored profile was dirty-marked, so the repair itself persists.

## Why this verification was worth a whole batch

The difference between the place-514 claim and this one is the difference between *"the function works"* and *"the system repairs a real player's
saved state on rejoin"*. Only the second is what the requirement means, and only persistence plus a restart can demonstrate it.

This is also the first end-to-end test in this project that exercised **DataStore round-trip + join hook** together, rather than either half in
isolation.

## Observability

No code was added. The existing `GF_AugmentSanitised` / `GF_AugmentSanitisedCount` attributes (written at place 514) were enough to observe the repair
after a restart. A silent repair is still silent to the player, but visible to a developer reading attributes after a join.

## Remaining gaps on this row

- The player is still not **told** anything was removed. The repair is correct and invisible, which is a UX gap rather than a correctness one.
- `loadout.abilityAugment` (the ability socket) is not validated by the same pass.
- Nothing repairs a mismatched augment while the player stays connected — only on join.
