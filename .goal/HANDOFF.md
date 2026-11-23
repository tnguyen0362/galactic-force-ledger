# Handoff — session state at commit 326b504, place version 156

## Done recently
- MICRO-010 deployment bay: 67 parts + 1 PointLight in `DeploymentBay` (split bulkhead, hydraulics,
  hazard band, loading rails, pod on cradle, gantry). PARTIAL — deck still clips white at grazing angles.
- LC-007 Frag/EMP: `ServerScriptService.GF.GrenadeRuntime` + `StarterPlayerScripts.GrenadeClient`.
  Verified via remote: Frag r=22 charges 2->1, EMP r=26 charges 1->0. PARTIAL — blast not captured.
- Two boot faults fixed: StationArt had no module-level caution red (buildShell aborted at `p.Color`),
  StationConcourse used `bays` out of scope at line 147 (aborted `build()` since the v127 glazing work;
  now re-collected as `windowBays`). Station builds 602 parts and logs `[GF] station online`.

## Tool limits found this session (do not re-derive)
- `screen_capture` keeps a fixed studio vantage: player-POV events (grenade blasts, bay interior) never
  appear in frames. Any row judged "visible to player" needs a different proof path.
- Edit-mode `execute_luau` cannot touch `workspace` runtime builds; Play-mode cannot edit Script.Source
  and discards source edits on stop. Every script edit must be made in Edit mode, then saved, then played.
- `Remotes.server()` asserts during module load; wait on `GF.Remotes` container instead.
- Typed Luau (`--!strict`, `::`) in newly created scripts failed silently here — untyped bodies run.

## Next up (V3-07 order, ABSENT)
LC-003 Bastion Walker encounter, LC-004 High Marshal Veyr phases/rewards, LC-010 ten augments,
LC-018 distress broadcast + responder join, LC-019 mid-mission join, MICRO-002 curved planet limb,
MICRO-019 space visuals at reduced graphics settings.

## Owner preference on record (m04346, paraphrase)
Do not compress at 40K; target roughly 250K before compressing.

## Loop health (read this first)
`.goal/LOOP.log` shows iteration 7, 8 and 9 landing 30 seconds apart with identical counts
(155 rows | ABSENT 69 | PARTIAL 75 | UNPROVEN 2 | PENDING-OWNER 5) and no commit between them.
The cause is structural, not the ledger: every continuation is being driven into ONE long-lived
agent session, so each new "continuation N" arrives in a context that is already exhausted and
returns within seconds without touching the place.

Fix before trusting loop numbers: run each iteration in a FRESH session and carry state in
`.goal/` + git + this handoff only. A continuation that resumes a saturated session cannot build;
it can only agree that it is out of room.

## 2026-11-23 — METHOD.md is now binding

Owner: "work on 1 thing at a time, we are making a damn near triple aaa game optimized for roblox and
optimized for xbox one low end phones tablets". `.goal/METHOD.md` records the rule: one row at a time,
finish or stop (never half), evidence first, write the negatives, and judge every change against
Xbox One / low-end mobile budgets (16.6 ms, part counts, light costs, no per-frame server loops).

ACP (billion-context-pi) is fully removed: package, lockfile, settings entries, all nine subagent tool
allowlists, backups, and `acp.json*`. Verified by a clean grep across `C:/Users/tnguy/.pi`.
A live session can therefore use the full 1,000,000-token window of `deepseek-v4.1-flash`; the old
"context limit reached" nudges came from ACP and no longer exist.

`goal-loop.ts` ledger parsing fixed: a real CSV parser (quoted fields, embedded newlines), the status
column found by header name instead of a hardcoded index, and acceptance reported honestly —
`ACCEPTED` counts only `OWNER_ACCEPTED`, with legacy `PROVEN`/`DONE` and `NOT_AUDITED` surfaced as
separate counters.

## Studio connection is not durable between turns

Place work requires an open `Playtest1`. On 2026-11-23 the instance id changed and the only reported instance had
`"state": "Place is not open"`, which blocked every place tool while the ledger still showed 54 ABSENT rows. Resolve
the id fresh each continuation; treat a missing place as a hard block, not as an excuse to edit the ledger.
