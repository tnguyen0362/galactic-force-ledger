# Mission clock and grenade counter on the HUD (build 433)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## What was missing
`S03-037` asks for a mission timer that turns amber in the last five minutes and red in the last one, plus grenade counts among the lower HUD readouts. Neither existed:

- The mission clock lived only inside `mission.softDeadline`; **nothing published it** and the HUD had no timer at all.
- Grenade charges were a player attribute with **no on-screen counter**.

## Implemented
- `StationService` publishes `GF_MissionRemaining` once a second (with a `GF_MissionRemainingOverride` test hook).
- New `StarterPlayerScripts.StatusStrip`: a `MISSION m:ss` label under the minimap that colours normal / amber (≤300 s) / red (≤60 s), and a `GRENADE xN` label fed by the replicated `GrenadeCharges` attribute. Both mirror their state into ScreenGui attributes for testing.

## Measured
| State | Remaining | Label | Colour |
|---|---|---|---|
| Deployed, fresh | 1492 s | `MISSION 24:52` | `220,230,240` normal |
| Override 200 s | 200 s | `MISSION 3:20` | **`255,200,90` amber** |
| Override 30 s | 30 s | `MISSION 0:30` | **`255,110,100` red** |
| Grenades | 3 charges | `GRENADE x3` | light blue |

Both thresholds fire at the specified boundaries, and the timer counts down from the real mission deadline (1492 s of the 1500 s budget a few seconds after deploy).

## Limits
- The 5-minute and 1-minute thresholds were exercised with an override, not by playing out 20 minutes of a real mission.
- `GF_MissionRemaining` is published every second for the whole session even at the station (reads 0 there); a player at the station sees `MISSION --:--`, which is correct but the loop is wasteful.
- No pause when the squad is absent, no warning flash, no audio cue.
- The timer sits under the minimap rather than in a dedicated mission bar; visually untested beyond attribute reads.
