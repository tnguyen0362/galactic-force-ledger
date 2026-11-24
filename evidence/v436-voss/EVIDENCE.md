# Voss portrait and subtitles (build 436)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client. Frame `ScreenCapture_VOSS`.

## The gap
`DialogueEvent` was a **declared remote with no sender and no receiver** — a dead tube. The commander never spoke, and the HUD had no portrait or subtitle surface. `S03-037` requires both.

## Implemented
- `Services/DialogueService.say(text, kind)` fires `DialogueEvent` with `{speaker = "VOSS", text, kind}`, suppresses an identical line repeated within 8 s, and records `GF_LastVossLine` / `GF_VossLines`.
- Wired to three real transitions: **deploy briefing** (mission display name + difficulty), **primary complete**, **primary failed**.
- `StarterPlayerScripts.Voss`: a bottom-left panel with a shape-built helmet portrait (dark plate + cyan visor band), an amber `VOSS` name, and a wrapped subtitle line. Lines queue while one is showing; each displays for 6 s.

## Measured
| Moment | Result |
|---|---|
| Deploy `SABOTAGE_RELAY` on Normal | visible, speaker `VOSS`, text `Sabotage Relay on Normal. Get in, finish the job, get out.` (`GF_VossLines = 1`) |
| Relay held to completion | text switched to `Primary objective complete. Wrap it up and get to the ship.` (`GF_VossLines = 2`) |

The capture confirms the panel renders bottom-left with the portrait, name and subtitle, alongside the circular minimap, `MISSION 24:40`, `GRENADE x3` and `SQUAD 1` on the right.

## A dead function left in place
`DialogueService.start()` contains an intro line and a stale `hook.onStage` check, and **nothing calls `start()`** — so the intro line never fires. The three wired transitions are the paths that matter; the `start()` body should either be called from `Main` or deleted.

## Limits
- No speech or TTS (no tool for it); subtitles only, which is what the project records as acceptable for now.
- Queued lines were not exercised with more than one pending line.
- The 6-second auto-hide was not observed; only text and visibility were read while a line was up.
- Portrait is a silhouette of shapes, not a character portrait.
