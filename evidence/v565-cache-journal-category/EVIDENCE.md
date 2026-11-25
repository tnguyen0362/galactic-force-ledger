# place 565 — cache journal + category selection evidence

## Cache receipt journal probe

A temporary real server `Script` ran in a fresh server/client playtest and was removed afterward. It awarded a Common cache, opened it through `CacheService.openFromInventory`, inspected `profile.cacheOpenJournal`, forced the completed receipt back to `committed`, and invoked `CacheService.reconcileProfile` to prove recovery is idempotent.

```text
[GF_JOURNALTEST] PASS tier=Common rolled=1 uid=Common-1795590884-1 inv=38->39 recovered=1
[GF_JOURNALCLEAN] items=2 journals=2
```

The repeated receipt key exposed a cross-session uniqueness flaw in the first implementation (`tier-os.time-sessionSeq`). That was fixed before this checkpoint: cache instance UIDs are now `cache_` + GUID, and completed receipts are pruned after 50 entries.

## Category-constrained rolls

A fresh playtest sampled 30 Legendary cache rolls constrained to AR. Every draw stayed in AR, and a newly granted cache instance used the GUID receipt format:

```text
[GF_CATTEST] PASS AR=30rolls bad=0 uidFormat=true
```

The Armory UI now exposes a `CAT ...` cycle button on each held cache row and passes the selected category to both single-open and bulk-open requests. `ANY` preserves random category selection.

## Boot regression

Fresh playtests in this batch continued to boot with:

```text
[GF] boot: config check PASS (688 assertions)
[GF] boot: services online (persistence=datastore)
```

## Scope limits

No physical client disconnect was performed. Recovery was tested by replaying a committed journal inside the live server profile, which proves idempotent materialization but not every real disconnect timing. The exact UI click path has compile evidence but still needs visual/client inspection evidence.
