# Correction: the over-cap mission start is an explicit allowance, not a missing check (place 554)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`. **No source changes**; probe removed.

## The correction

Last batch I recorded, on `S06-035`:

> a mission **starts above its own cap** (measured `active=9, cap=8`) because `beginMission` spawns posts + patrol + commander + boss without a joint check

The measurement was real, but the *cause* I asserted was wrong. Reading every `MAX_ACTIVE` reference:

```
 11| local MAX_ACTIVE = 8
 51| if activeCount() >= MAX_ACTIVE then          -- spawnAround: hard cap
154| if farEnough and activeCount() < MAX_ACTIVE + 2 then   -- spawnPosts: EXPLICIT allowance
223| if activeCount() >= MAX_ACTIVE then          -- extraction pressure: hard cap
```

`spawnPosts` deliberately allows **cap + 2** for objective posts — a design allowance so the defence point gets its pickets even when the map is busy. So exceeding 8 is
**not a missing joint check**; it is written into the code on purpose (though with no comment saying why). `beginMission` also spawns an optional commander and a boss
with no cap check at all, which can add to the total.

So my earlier framing turned intended behaviour into a defect. Corrected.

## What I could *not* confirm

I tried to measure the allowance directly: fill to the mob cap, then request 4 posts.

```
cleared active=0 cap=8 | filled=8 active=8 | postsPlaced=0 active=8 | furtherMobsPlaced=0 active=8
```

`postsPlaced=0` — at my test location the posts loop placed nothing, most likely failing its ground raycast or line-of-sight test (`canSeeConsole`) rather than the cap.
So the `+2` allowance remains **code-read, not measured**. The hard cap *was* measured again: `filled=8`, and a further mob request at the cap placed `0`.

Being precise about that distinction matters here, because "I read `MAX_ACTIVE + 2` and inferred 9" is exactly the sort of inference this project has punished before.

## Effect on `S06-035`

The row's remaining gaps are now only the design ones:

- **"Dynamic" budget is static** — `PATROL_COUNT = 4`, fixed `MISSION_SPAWN_BUDGET`, nothing adapts to squad size, difficulty or elapsed time.
- **Extraction pressure is interval-driven** (2 every 9 s) rather than authored wave composition.
- Whether the `+2` post allowance and the uncapped commander/boss are intended is an **owner decision**, not a defect list item.

## Limits

- The post-placement path was not exercised successfully in any probe this session (0 placed twice at different centres), so objective-post behaviour is still only
  code-read. That is a real hole in this row's evidence.
