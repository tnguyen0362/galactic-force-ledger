# BLOCKED

1. **DataStore persistence — RESOLVED 2026-11-22.** Owner enabled File > Experience Settings >
   Security > "Enable Studio Access to API Services". Verified live: probe `SetAsync/GetAsync` returned a
   timestamp; then a full play cycle showed `[GF] profile ready 1889759131 credits=450` (reading the previous
   session's award) and `[GF] profile persisted=true`; the stored document now reads
   `credits=900 xp=1200 rank=2 schema=1`. Bug fixed along the way: `RewardsService.grant` awarded but never
   saved and never added salvage to the profile, so payouts were lost on session end.

2. **Xbox One / mobile hardware profiling impossible here.** No device farm. All performance numbers must be
   produced on real hardware; the goal forbids claiming an FPS target without it. Studio device emulator only
   validates layout, not frame cost.

3. **No publish / no second place.** Deploy is an in-place teleport because publishing needs explicit owner
   authorization and a second place file.

4. **No audio assets.** No upload/licensing path via MCP; voice lines exist as subtitle-ready text and cue IDs
   only. Every story beat is readable without audio, per spec.
