# place 582 — per-player boarding extraction

Before this change, one press of "Board Transport" ended the mission for the whole server: no cabin volume, no individual extraction, no +25% squad bonus logic beyond a hardcoded 4-player check, and players aboard could still fire, use abilities or throw grenades. `model.PrimaryPart = body` also referenced an undefined variable, so the dropship had no primary part.

Changes:
- A server-side tracker (0.25s tick) marks `aboard` players whose HumanoidRootPart is inside the BoardingZone cabin volume; `GF_Aboard` mirrors it to the player. Volume state, not client flags.
- The zone prompt reads `Extract Individually (n/m aboard)` until every eligible survivor is aboard, then `Extract Squad (n aboard, +25% bonus)`.
- `board` while some eligible survivor is missing pays that one player individually (`RewardsService.grant(…, squadBonus=false)`), returns them to the station, and leaves the ship for the rest.
- `board` when all eligible survivors are aboard shows a 2s departure warning, cancels if someone exits, then commits: `finish(objectiveDone, squadBonus=true)`. Solo always qualifies.
- `RewardsService.compute/grant/grantAll` take an explicit `squadBonus` boolean instead of a hardcoded `size >= 4` check.
- While aboard: firing is rejected, abilities and grenade throws are refused, enemy targeting skips the player, and damage is 0 (`VitalsService.applyDamage` returns 0) — the cabin is safe.
- `finish` returns every player still in the Mission zone to the station and clears aboard/extracted sets.

Probe: deploy, force-complete the objective, 2s countdown override, step into the cabin volume, press extract.

```text
[GF] boot: config check PASS (688 assertions)
[GF_BOARD] PASS landed=true aboard=true squad=committed zone=Station prompt="Extract Squad (1 aboard, +25% bonus)"
```

Not verified: multi-player split extraction (one leaves early, rest extract later), downed-player board block, enemies failing to enter the interior, and client rendering of the bonus line.

## Aboard immunity and downed boarding (live, place 582)

```text
[GF_ABOARD2] PASS aboard=true damageApplied=0 downedAboard=false
```

A player inside the cabin volume takes 0 damage, and setting `downed` un-marks them as aboard even while standing inside.
