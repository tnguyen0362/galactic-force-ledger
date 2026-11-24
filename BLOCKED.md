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

## 2026-11-23 — Studio lost the place (blocks all in-editor work)

`list_roblox_studios` now returns a single instance, and it is not usable:

```json
{"studios":[{"id":"a828ce66-ff1a-43c5-b662-dc096996bcc4","mode":"Unavailable","name":null,"state":"Place is not open"}]}
```

The previous instance id `586a4e54-321f-4609-aee4-e09dbc1e269c` is gone, and every tool call against it returns
`The requested studio_id is not connected — that Roblox Studio instance may have been closed or its place unloaded.`

**What this blocks:** every place-side action — `execute_luau`, `save_place`, `start_stop_play`, `screen_capture`.
No row can be built, saved or captured until `Playtest1` is open again.

**What is safe to do meanwhile:** repository work only — ledger accuracy, review notes, documentation, and reading
source through the file system. Nothing in this file should be counted as a place change.

**To unblock:** open `Playtest1` in Roblox Studio (Team Create), then call `list_roblox_studios` to get the new id and
replace the hard-coded id in the loop's habits. Last saved place version before the disconnect: **232**.

## Ability casts from the client VM produced nothing at all (v260) — unresolved

Three separate attempts this session fired `ReplicatedStorage.GF.Remotes.UseAbility:FireServer({ abilityId = "Airstrike", ... })`
from the client VM. Each produced **zero** effect: `craft=0, blasts=0, recorded=nil`, no error in the log, and — after I added
rejection telemetry — **no `LastCastRejected` attribute either**, even though `workspace.GFDebug` exists and had zero attributes.

The same module ran correctly in the previous session (`craft=1, blasts=5, flashes=5`), so the pipeline is real; what is not
established is why the handler appears not to run in this play session.

Reproduced facts:
- `workspace.GFDebug` exists, attribute list is empty.
- `require(Services.State).get(player)` returns **nil** on the server, while `ProfileService.ensure(player)` returns a profile.
  So even a connected handler would take the "profile not ready" branch and reject.
- Log after boot contains no `[GF]` errors, only the usual Assistant-plugin version notice.

**This matters for players:** if `State.get` is nil when an ability key is pressed, the key does nothing and the HUD shows
nothing. That is the same class of defect as the camera and the silent boot faults already fixed; the rejection telemetry
added in v260 is the first half of the fix (the HUD does not yet render it).
