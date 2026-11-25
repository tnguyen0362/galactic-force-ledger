# HANDOFF — GALACTIC FORCE: COUNTEROFFENSIVE

Place: `Playtest1`, placeId 120646942844931, universeId 10778576038. **Studio id is not stable — always call
`list_roblox_studios` first**; a missing place is a hard block, never a ledger edit.

**Place version at handoff: 510.** Last commits: `82d93c6` (category compatibility unenforced), `653cade` (spreadBase retraction), `d680e1b` (pellet stance bug), `cae5e22` (pellets on target), `dfdaf89` (shotgun pellets), `13532ef`/`b7f2963` (cache odds).
`a8ef2f5` (carry visuals), `61fd34e` (RECOVER carry), `14a7ecb` (glyph re-render), `50b639a` (survivable drop).

## Continuation 74 state (read this first)

**Ledger:** `591 UNKNOWN · 171 PARTIAL · 38 VERIFIED · 15 ABSENT` of 815 rows. Place **510**.

### What is verified and working
- Four classes, both passives, values conform (L66).
- Cache odds disclosed in the armory: per-draw percentages for **every held tier** plus `1-(1-p)^n` and enemy drop chances.
- Augment inventory capacity: 200 baseline, +50/expand, 400 cap, every refusal branch exercised.
- Cache instances carry uid/tier/source/timestamp; opening is capacity-gated **before** consuming.
- Bulk cache open bounded to 10/action with space computed first; armory buttons for expansion and bulk open.
- SG-04 fires **8 pellets of 12** and deals exactly **96.0** at point blank (measured), matching the authored 8 × 12.
- 13 of 14 augment stat keys are wired and measured; clamps implemented per authored caps.

### The owner queue (all recorded with exact numbers, none applied)
Ordered by coupling, not importance:
1. **Trait magnitudes** — config runs 3–8× the authored bands. **Rescale needs bands for 4 keys the spec never gives**: `sentryAmmo`,
   `movingAccuracy`, `adsRecovery`, `followUpSpeed`. A partial rescale would create mixed scales, which is worse.
2. **Clamps** — depend on 1. Cooldown cap 20%, blast radius 25%, etc. are already coded.
3. **Loot distributions** — mission tiers drift progressively (Extreme has **0% Common** where the spec keeps 20%); per-class enemy
   distributions and the `.65/1.35/1.7` difficulty multipliers do not exist; no first-mission Rare guarantee.
4. **Ability tuning** — DomeShield 20s vs guaranteed 10s; reloads uniformly 0.1–0.8s longer than authored; the 15 recorded cooldown/radius drift rows.
5. **Category compatibility** — declared on all 36 augments (`Category`×28) and enforced **nowhere**; a shotgun augment equips on a rifle.
6. **RNG** — cache outcomes use `math.random()`, not crypto-appropriate randomness.
7. **Mission clock** — `StationService.MISSION_SECONDS = 1500` (25 min) against an authored 15 min; `Constants.Mission.Duration*` is unused.

### The biggest unbuilt thing
**The augment instance model** (`S11-031`) gates 14+ rows: the whole reroll/dismantle/fusion cluster (`S11-057`–`S11-067`, all ABSENT), signature
variants, tradeoff pairing, and per-instance trait rolls. Traits are keyed by archetype id, so two copies of one augment can never differ.

### Carried risk
- Durability is still undecided: the rewards ledger is in-memory, so settlement must not read it.
- The test profile has accumulated probe state (capacity 400, credits, equipped augments incl. a shotgun `Choke` on `AR01`).
- **Method lesson, learned four times this session:** a wrong *premise* produced a wrong *conclusion from correct measurements*. Print the value,
  never recall it (`e.stats`→`e.effect`, `#e.trait`, `"ODDS"`, `spreadBase 0.15`→`3.2`). Verification scans must match text that **only** the real
  output produces.

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
- **A tool-VM `require` is cached across calls, so `Source` edits look like they did not apply.** After changing a
  module's `Source`, calling `require(module).something()` from the MCP tool VM can return the **previous compiled version** —
  not an error, just stale output. This produced a phantom "ability missing from config" twice in one session and made a
  working fix look broken. Verify edits in a **fresh Play VM**, or from a temporary `Script` parented into
  `ServerScriptService`, which compiles against the current source. Only trust the tool VM for reading `Source` text and
  attributes.
- `WHITE` does not exist in `StationUI` (constants: `CYAN`, `AMBER`, `PANEL`, `TEXT`, `MUTED`). A nil colour inside a handler kills
  the handler, not just the colour.

## Next actions, in order

1. MICRO-088 / MICRO-089 — touch-button overlap at small phone size, and console focus visibility; both need a real capture at
   another resolution/input family.
2. MICRO-076 — dispatch listing must show only genuine manual requests.
3. Terminal geometry (untextured slab) and the ragged bottom HUD row.
4. Balance pass on patrol lethality at the objective (22 hits in 7 s to a stationary player) — owner judgement.
