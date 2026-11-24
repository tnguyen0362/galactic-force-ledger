# Mission cache moves to extraction (build 415)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## Change
The guaranteed mission cache was paid inside `ObjectiveService.complete()`, so it landed the moment the primary finished — before extraction, and therefore even if the squad then failed to get out. It now lives in `ExtractionService.finish(success)`:

```lua
if success and payoutObjective then
    local okGrant, grantErr = pcall(function()
        local Cache = require(script.Parent.CacheService)
        Cache.grantMission(Cache.tierForDifficulty(payoutDifficulty))
    end)
    workspace:SetAttribute("GF_MissionCacheResult", okGrant and "granted" or ("error: " .. tostring(grantErr)))
else
    workspace:SetAttribute("GF_MissionCacheResult", string.format("skipped success=%s objective=%s", ...))
end
```

`CacheService.tierForDifficulty` is now the single difficulty→tier mapping (Easy Common, Normal Rare, Hard Epic, Extreme Legendary).

## Measured
Full successful round trip: `SABOTAGE_RELAY` on Normal, relay held to completion (**0** cache opens at that point), extraction requested, dropship landed, boarded.

| After boarding | Value |
|---|---|
| `GF_MissionCacheResult` | `granted` |
| `GF_CacheOpens` | 1 |
| `GF_CacheLastSource` | `mission` |
| `GF_ExtractionState` | `complete` |

Reward settlement on the same run: `credits 450`, `xp 600`, `objectiveComplete true`.

## The bug inside the fix
The first attempt produced `GF_MissionCacheResult = "error: attempt to call a nil value"`. Two separate faults:

1. **A no-op edit.** My patch computed the new `CacheService` source and ran `loadstring` on it, but never assigned `C.Source = src`. The file on disk still lacked `tierForDifficulty`, so the call hit nil. This is the first time this session that an edit silently did nothing — every previous failure at least threw.
2. **`pcall` hid it.** The original branch wrapped the grant in `pcall` with no reporting, so the first run showed only "no cache opened". Recording the error string is what found the cause in one step.

## Limits
- The failure→skip branch (`skipped success=false ...`) was **not** re-measured after the move; the last failed-extraction run predates this change. The code path exists but its attribute was never observed.
- One player, one difficulty, no co-op.
- Cache contents still go straight to the profile; there is no unopened inventory.
