# Tutorial award corrected to 350/410 plus one Common cache (place 516)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 516**.

## The change

`TutorialService.finish` went from:

```lua
ProfileService.award(player, 200, 400)
```

to:

```lua
ProfileService.award(player, 350, 410)
profile.caches = profile.caches or {}
profile.caches.Common = (profile.caches.Common or 0) + 1
```

Matching `S10-009`: *350 Credits, 410 XP, 1 Common cache*. This is spec conformance rather than balance tuning — the authored figures are explicit
and were previously short on both numbers while omitting the cache entirely.

**A test hook was added**, following the file's existing `resetForTest` precedent:

```lua
function TutorialService.finishForTest(player) finish(player) end
```

Without it the completion path is unreachable except by playing the whole tutorial, which is why the reward had only ever been code-read. `finish`
itself is a local function, so the hook is the only way to measure it.

## Measured

```
credits 1000 -> 1350  (+350)
xp        0 -> 410    (+410)
Common cache 0 -> 1
completed = true
```

All three components land exactly on the authored values, and the completion flag is still set.

## Deliberately not implemented

The fourth component — *"First-time choose AR/SMG/LMG free"* — is **not** done. It needs a real choice UI and a grant flow keyed to the player's pick,
not a config edit. For now `SMG-03` (600) and `LMG-12` (1400) remain unaffordable for a brand-new player who did not start with them, which is the
remaining half of `S01-027`.

Also still absent: `tutorialCompleted` remains **unread by any consumer**, so "completion unlocks Easy/Normal" has no mechanism. I did not invent one,
because whether Easy/Normal should be locked at all is a design decision.

## Verification limits

- The reward was measured by calling `finishForTest`, not by completing the tutorial. Everything downstream of `finish` is proven; the step-tracking
  that decides *when* `finish` is called is untouched and unexercised.
- The test hook ships in the place. It is harmless (a caller must be trusted server code), but it is test-support surface sitting in production and
  should be removed or gated before private beta.
- The profile used for the test ended at 1350 credits, 410 XP and one Common cache.
