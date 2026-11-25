# GALACTIC FORCE — session handoff (2026-11-25)

Continuation instructions for a LOCAL Devin Desktop session on the Mac. Read this first, then
`WORK_STATE.md`, `.goal/GOAL_2026-11-24.md` and `REQUIREMENT_COVERAGE.csv` in this repo.

## What this project is

A Roblox game built inside the live Studio place `Playtest1` (placeId 120646942844931, universeId
10778576038). The game code lives in the place, NOT in git. This repo is the ledger: GOAL, the
requirement CSV and per-version evidence. Rules from `.goal/`: one thing at a time, finish or stop
never half, evidence first, never invent tool outputs or playtest evidence, no public release or
monetization.

## The harness (already on the Mac)

- `/tmp/gf_handoff_src.tgz` — the full `playtest1_current` Luau working copy (95 files) as of place
  584 PLUS two undeployed in-progress files (see below), all probe scripts and the deploy harness.
  Extract to a stable path, e.g. `mkdir -p ~/gf && tar -xzf /tmp/gf_handoff_src.tgz -C ~/gf`.
- `/tmp/gf_deploy.py` — the deploy/probe runner:
  `python3 /tmp/gf_deploy.py <tgz|-> <probe.lua|-> <MARKER>` env: NOSAVE=1 to test without saving,
  POLLS=n for longer probes. It tars changed files, compiles them into Studio via MCP
  (`loadstring` check), saves the place, creates a temp server Script probe, starts/stops play and
  prints marker lines. `/tmp` survives until reboot; re-extract from the tarball if missing.
- Roblox Studio MCP: `/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP`, newline-delimited
  JSON-RPC. Real tools: `list_roblox_studios`, `execute_luau{code,datamodel_type:Edit|Client|Server,studio_id}`,
  `start_stop_play{is_start}`, `get_console_output{studio_id}` (no other args), `save_place`,
  `screen_capture`. `start_playtest`/`stop_playtest`/`insert_object` do NOT exist. Always
  `list_roblox_studios` first for the current studio id. Keepalive `/tmp/roblox_mcp_keepalive.py` runs on the Mac.
- A keepalive MCP client is registered at user level in Devin (`Roblox_Studio`).

## Verification pattern

Compile-check every edited file, save, then prove behavior with a temporary real-server probe
printing `[GF_XXX] PASS/FAIL`, poll console, stop play, destroy the temp script, clean up every test
artifact (use isolated synthetic data — a broad dismantle probe once ate two real test-profile items).
Boot must print `[GF] boot: config check PASS (688 assertions)`. Test profile userId 1889759131.

## State at handoff

- Place version 584. Ledger merged through PR #6 plus PR #7 (open) restoring clobbered row S10-016.
- Done since v558: numeric conformance; per-instance UID augments + traits/reroll/dismantle/fusion +
  fusion preview-confirm; cache journals w/ idempotent recovery + category selector; range/supportDamage/
  sentryHP consumers; reroll lock UI; late-join payout crash fix; settle-once payouts; destructible
  sentries + one-per-owner dome/sentry cap + dome leak fix; emergency support disable + reportReject nil fix;
  mission loadout lock; difficulty-scaled friendly fire + strike danger-close warning; cooldown acceptance
  + rejoin persistence; per-player boarding extraction rewrite (cabin volume, Extract Squad 2s commit,
  individual extraction, aboard immunity); enemy-drop weight scaling + first-mission Rare guarantee;
  war credits + first-mission +200 credits.
- UNDEPLOYED in-progress work (in the handoff tarball, not in the place): `Requisitions.luau` config
  (ReplicatedStorage/GF/Shared/Configs/) and `RequisitionService.luau` (ServerScriptService/GF/Services/).
  Finish the requisitions system: ArmoryService state/actions (`reqUnlock`,`reqBuy`), premium gate for
  GL22/RL09/TROPHY/BLACKSTAR in Armory buy paths, StationArmoryUI requisitions section, then probe
  (unlock spend, tier thresholds 600/1600, once-only entries, shared ownership) and save. GOAL §12 L199 is the spec.
  Note: the Rare-cache premium tier3 entry price is unspecified in GOAL — implemented as free once-only, flag it.
- Known gaps after that: 2-client tests (friendly hitscan, split extraction), UI click-path/visual evidence
  (use `screen_capture`), canonical catalog identity S11-048 variants, Monte Carlo cache validation,
  crash-mid-payout recovery, boss rows, requisition UI evidence, and the long UNKNOWN tail — audit by area.
- CSV discipline: update rows by exact requirement_id only, never write another row's fields (a script
  once clobbered S10-016; restored in PR #7).
