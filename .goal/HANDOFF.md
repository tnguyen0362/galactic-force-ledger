# HANDOFF — GALACTIC FORCE: COUNTEROFFENSIVE

Place: `Playtest1`, placeId 120646942844931, universeId 10778576038. **Studio id is not stable — always call
`list_roblox_studios` first**; a missing place is a hard block, never a ledger edit.

**Place version at handoff: 318.** Last commits: `6b4457a` (terminal damage measured), `9bfdd77` (HUD band de-conflict),
`a8ef2f5` (carry visuals), `61fd34e` (RECOVER carry), `14a7ecb` (glyph re-render), `50b639a` (survivable drop).

## State of the truth

Everything below was **measured this session**, not asserted:

| thing | state |
|---|---|
| Orange deck wash | **solved** — `EnvironmentSpecularScale` was 0.04, mirroring the nebula sky onto the flat Metal deck. Pinned to 0 in both presets. A/B in `VISUAL_REVIEW.md` v303. |
| Bosses shelling the drop | **solved** — Veyr no longer auto-spawns in an ordinary op, both bosses gated to 120 studs, mortar refuses targets inside the 80-stud landing zone. 0 damage events over 14 s at the LZ. |
| Mission HUD blank in mission | **solved** — deploy verdict payloads (no `zone`) were switching the HUD off. Zone-less payloads ignored; verdicts now carry the zone. |
| Objective tracker | **solved** — `MissionHUD.setProgress` now follows the published `hint`, so RECOVER reads the carry line. |
| Three operations | hold / carry / survive. RECOVER is a 0.6 s pickup + delivery to the LZ, with a welded case and a delivery patch. |
| Boss blueprint pity | 3 clears (was 5), deterministic proof, reported in the debrief. |
| Settings | sensitivity/volume/subtitles persisted in profile, published as `GF_Setting_*`, applied; reduced-motion stored but unconsumed. |
| Intro gating | `introWatched` persisted, Archive console replays on request. |
| Deploy refusals | real reasons in the deploy button (`REFUSED · <reason> · RETRY`), watchdog for no-response. |

## Debug switches that saved the most time

- `GF_DebugDamage = true` → prints every `VitalsService.applyDamage` with its **source**. This named the boss artillery and the
  terminal patrols in one run each. **Start here for any "why is the player losing health" question.**
- `GF_TestHooks = true` → enables `grantTestAugment` and `bossRewardTest` actions on `SetLoadout`.
- `GF_ForceNoBlueprintChance = true` → makes the pity rule deterministic.
- `GF_ArmoryOpen` / `GF_StationPanel` / `GF_SettingsOpen` → force-open those panels for capture.
- `GF_HoldCraft` → parks the airstrike aircraft for a photo.
- `GF_ExtractionCountdownOverride` / `GF_SoftDeadlineOverride` / `GF_EmergencyGraceOverride` → compress extraction timing.
- `TutorialService.resetForTest(player)` → fresh-account state without wiping a profile.

## Known traps (each cost real time)

- Client-side errors **do not appear in the server log**. Read `LogService:GetLogHistory()` from the **Client** datamodel when a UI
  script misbehaves.
- `player:GetAttributes()` returned an empty list in tool VMs even when attributes existed — read attributes **by name**.
- Tool-VM `require` gets its own module instances, so `State.get`, `ProfileService.get` and `SquadService.snapshot` read empty
  copies. Verify through attributes, remotes and **logs**, never through a probe-local module state.
- `DeployStateChanged` carries two payload shapes (zone publish and deploy verdict). Any listener must ignore payloads it does not
  understand.
- Editing `Source` while a playtest runs fails; a broken edit fails **silently** until the log is read.
- `WHITE` does not exist in `StationUI` (constants: `CYAN`, `AMBER`, `PANEL`, `TEXT`, `MUTED`). A nil colour inside a handler kills
  the handler, not just the colour.

## Next actions, in order

1. MICRO-088 / MICRO-089 — touch-button overlap at small phone size, and console focus visibility; both need a real capture at
   another resolution/input family.
2. MICRO-076 — dispatch listing must show only genuine manual requests.
3. Terminal geometry (untextured slab) and the ragged bottom HUD row.
4. Balance pass on patrol lethality at the objective (22 hits in 7 s to a stationary player) — owner judgement.
