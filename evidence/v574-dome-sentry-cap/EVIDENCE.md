# place 574 — one dome and one sentry per owner

Before this change, a second Dome cast while one was active was silently refused instead of replacing the old dome. Sentries had no cap at all. Dome rim and post parts were parented beside the sphere, so they leaked after the sphere expired.

Now `dome`/`sentry` destroy the owner's previous instance only after the new cast passes range/root validation (`s.activeDome`, `s.activeSentry`). The rim and posts are children of the dome sphere, so they are removed with it.

Probe: a temporary real-server Script cast DomeShield twice and Sentry twice via `AbilityService.cast` (cooldowns reset between casts).

```text
[GF] boot: config check PASS (688 assertions)
[GF_CAP] PASS domes=1 sentries=1 strayRimPosts=0 posts=14 domeReplaced=ROBLOXISUS101 sentryReplaced=ROBLOXISUS101
```

Not yet verified: that an invalid (out-of-range) recast leaves the old instance intact.
