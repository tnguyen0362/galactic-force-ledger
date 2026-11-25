# GALACTIC FORCE — session handoff (2026-11-25, place 587)

Continuation instructions for a LOCAL Devin Desktop session on the Mac. Read this first, then
`WORK_STATE.md`, `.goal/GOAL_2026-11-24.md` and `REQUIREMENT_COVERAGE.csv` in this repo.

## What this project is

A Roblox game built inside the live Studio place `Playtest1` (placeId 120646942844931, universeId
10778576038). The game code lives in the place, NOT in git. This repo is the ledger: GOAL, the
requirement CSV and per-version evidence. Rules from `.goal/`: one thing at a time, finish or stop
never half, evidence first, never invent tool outputs or playtest evidence, no public release or
monetization.

## The harness (already on the Mac)

- Working copy: `~/gf/playtest1_current/` (Luau extraction/working tree; keep it in sync with the place
  by deploying changed files after edits).
- Deploy/probe runner: `~/gf/gf_deploy.py`:
  `python3 ~/gf/gf_deploy.py <tgz|-> <probe.lua|-> <MARKER>` env: `NOSAVE=1` to test without saving,
  `POLLS=n` for longer probes. It compiles changed files into Studio via MCP (`loadstring` check),
  saves the place, creates a temp server Script probe, starts/stops play and prints marker lines.
- Tar changed files from `~/gf` with paths beginning `playtest1_current/` and exclude macOS AppleDouble
  files (`COPYFILE_DISABLE=1 tar --exclude='._*' ...`); `._*.luau` files crash the deployer's UTF-8 decode.
- Harness limitation: it can overwrite existing scripts but cannot create new instances. If adding a new
  module/script, first create the empty shell in Studio with `execute_luau`, then deploy its source.
- Roblox Studio MCP tools: `list_roblox_studios` (always first for the studio id),
  `execute_luau{code,datamodel_type:Edit|Client|Server,studio_id}`, `start_stop_play{is_start}`,
  `get_console_output{studio_id}`, `save_place`, `screen_capture`, `user_mouse_input`. During playtests
  `Edit` is rejected; use `Client` or `Server`.
- Do NOT resurrect extra MCP keepalive processes. Devin CLI already spawns its own StudioMCP from the
  user-level config; duplicate clients confuse the connection list.

## Verification pattern

Compile-check every edited file, save, then prove behavior with a temporary real-server probe printing
`[GF_XXX] PASS/FAIL`, poll console, stop play, destroy the temp script, clean up every test artifact
(use isolated synthetic data — a broad dismantle probe once ate two real test-profile items). Boot must
print `[GF] boot: config check PASS (689 assertions)`. Test profile userId 1889759131.

## State at handoff

- Place version **587**. Ledger branch in progress: `devin/1764027600-requisitions` unless already merged.
- Requisitions are implemented and probed: permanent Frontline Arsenal (free) and Siege Division
  (1000 War Credits), 3 tiers each, 600/1600 per-catalog spend thresholds, any-order buying, preview,
  rank/tier locks, shared ownership/spend ledgers, once-only resource/cache entries, premium access and
  premium tier gates in plain-Armory paths. Probe: `[GF_REQ] PASS credits=4650 frontSpend=2050
  siegeSpend=3300 scrap=44 cells=26`; evidence `evidence/v587-requisitions/EVIDENCE.md`.
- Important owner-acceptance flag: GOAL §12 does not specify the premium tier3 one-time Rare cache price;
  it is implemented as a free once-only claim, not an invented price.
- Premium armor canonical prices are GF-05 500 / GF-06 750. Internal ids TROPHY/BLACKSTAR remain for save
  compatibility; display names now match GF-05 Ash Sentinel / GF-06 Frost Warden.
- Remaining requisition-adjacent gaps: mock/test receipts and entitlement interfaces (S12-018) and the
  armor plate-shape variant audit. S12-015 premium weapon comparison is verified in
  `evidence/v587-premium-weapon-comparison/EVIDENCE.md`.
- Broader known gaps: 2-client tests (friendly hitscan, split extraction), UI click-path evidence,
  canonical augment catalog identity S11-048 variants, Monte Carlo cache validation, crash-mid-payout
  recovery, boss rows, and the long UNKNOWN tail — audit by area.
- CSV discipline: update rows by exact requirement_id only, never write another row's fields (a script
  once clobbered S10-016; restored in PR #7).
