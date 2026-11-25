# V713-V715 minimap/performance stabilization addendum

Builds: v713 tutorial hint layout, v714 first minimap/performance attempt, v715 repaired tactical-map implementation. v715 deployed 125/125 scripts with zero failures.

## Implemented

- Tutorial hints moved clear of the persistent controls line; the capture no longer shows overlapping tutorial/control text.
- Minimap terrain relief contrast increased so elevation is readable instead of a nearly uniform dark disc.
- Supply crates are published as minimap markers.
- Tactical minimap heightfield is now world-aligned and cached:
  - fixed 20-stud cells
  - 16x16 local window
  - cache cleared on new mission id
  - avoids the previous 256 fresh terrain raycasts every second while stationary
- Client/server grid endpoint alignment corrected.
- Minimap UI refresh reduced from 5Hz to about 2.9Hz.
- MovementService fall-tracking heartbeat connection now disconnects when the character is destroyed (fixing the respawn connection leak found in alpha's audit).
- Enemy relay caller caches the relay instance instead of scanning all workspace descendants every 0.5s while the relay remains valid.

## v714 defect caught and repaired

The first supply-marker insertion accidentally landed in the minimap center() function, causing repeated `table expected, got nil` server errors. Runtime log inspection caught it immediately; v715 moved the insertion into markers() and re-verified with a clean server error log.

## Runtime evidence

Fresh v715 Play/deploy probe:

- server meta: `-10.0,110.0,300.0,6.0,62.0`
- markers: objective, LZ, three supply crates, squad marker
- marker count `6`
- cache size `256` after initial sample
- client cells `256`, blips `6`
- server errors: none
- capture: `raw/minimap_v715_0.jpg`

The capture shows readable terrain relief, rim/objective marking, non-overlapping tutorial text, ticket HUD, and supply-crate minimap support.

## Still open

- Minimap remains a coarse radar, not a full tactical map; no roads/stronghold annotations yet.
- Remaining alpha FPS items: server-replicated cosmetic VFX churn, enemy raycast multiplication, server-side enemy joint animation, decorative replicated motion, hot-path debug attributes, lighting count/shadows.
