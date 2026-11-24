# Reliable "engaged" counter and a Marksman telegraph (build 450)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## The diagnostic was lying
`GF_EnemiesEngaged` counted actors holding a `target` pointer, which is cleared by intervening ticks — so it read **0 while twelve hits landed** (measured at build 449). Any conclusion drawn from it, including two of my own "no engagement" readings, was worthless.

Now every shot stamps `actor.lastFiredAt`, and `engaged` counts actors that fired within the last 3 s. It means **"shooting right now"**, which is what a test needs.

| State | `GF_EnemiesEngaged` |
|---|---|
| Under fire, player 8 studs from a Rifleman | **2** |
| After leaving to the station, 5 s later | **0** |

## Marksman telegraph
`Configs/Enemies` Marksman gained `chargeTime = 0.8`, so it now uses the same wind-up path as the Heavy (telegraph event plus `ChargingUntil`) instead of firing instantly.

## A bug I introduced and fixed within the batch
I first routed the shot through a `local function replicatedStorageFire(...)` declared **below** its first use inside `tickActor`. Result: `EnemyService:450: attempt to call a nil value`, twelve times in one run, and every hostile stopped firing. `loadstring` compiled it happily — the failure was only visible in the runtime log.

Fixed by inlining the two statements (`actor.lastFiredAt = ...` then `FireAllClients`). Re-verified: zero `EnemyService` errors, `engaged = 2` under fire, `0` after.

## Still stale
`GF_EnemiesTracked` stayed at **13** even with the player at the station, because `actor.target` is not cleared when the target leaves. That counter means "has ever acquired", not "has a live target", and needs the same treatment.

## Limits
- The 3 s engaged window is my choice, not a spec value.
- The Marksman telegraph duration (0.8 s) is an authored guess; the spec gives no number for it, unlike the Heavy's 1.4 s.
- Neither the telegraph event nor `ChargingUntil` was observed for the Marksman in this run — only that the config compiled and the module loads.
