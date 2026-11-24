# Cache inventory: earn, hold, open (build 422)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## The gap
Every cache rolled the instant it was awarded. A player never saw a cache, never chose when to open it, and the armory had no cache surface at all. The spec wants unopened caches to stack by tier and open on demand.

## Implemented
- `profile.caches[tier]` holds unopened counts.
- `CacheService.grantToInventory(player, tier, source)` replaces the auto-open in three places: mission cache, enemy drops, boss drops.
- `CacheService.openFromInventory(player, tier)` decrements, rolls, grants augments and traits, and refuses when the count is zero.
- `ArmoryService.state.caches` exposes all four tiers with held counts; `SetLoadout { action = "openCache", tier = "Rare" }` opens one.
- Armory UI renders a row per tier — `Rare Cache · 1 held` with an `OPEN` button, or `NONE` when empty.

## Measured
| Step | Result |
|---|---|
| Complete `SABOTAGE_RELAY` (Normal), extract, board | `GF_MissionCacheResult = granted`, **`GF_CacheHeld = "Rare:1"`**, zero opens — the cache is held, not rolled |
| `state.caches` | `Rare held = 1`, other tiers 0 |
| `openCache Rare` | `ok=true, count=2`, augments **34 → 36**, held Rare → **0** |
| `openCache Rare` again | refused `"no Rare cache held"`, held stays 0 |
| Armory rows | `CacheCommon`/`CacheRare`/`CacheEpic`/`CacheLegendary`, each `· 0 held` + `NONE` |

## Instrumentation defect fixed
The grant wrote `GF_CacheHeld` and the open wrote `GF_CachesHeld`. After a successful open the singular attribute still read `Rare:1` from the earlier grant, which looks exactly like "the open did not decrement". Both paths now write `GF_CacheHeld`; the post-open reading is `Rare:0`.

That is the fifth time this session an attribute-reading choice produced a false conclusion — the rule stands: one writer per attribute, counters for sequences.

## Limits
- The armory `OPEN` button was **not clicked** (rows sit below the scroll viewport, the same harness limitation as the armour buttons). The remote action is verified.
- `S11-033` (a full inventory blocks opening) is not implemented — there is no capacity limit.
- Bulk opening (`S11-035`) and cache UID/timestamps (`S11-031`) remain unimplemented.
- Persistence of held caches across a rejoin untested.
