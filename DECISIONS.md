# DECISIONS

**Moved.** The single source of truth is `.goal/DECISIONS.md` (now through D15).
Historical root-only entries are preserved at `.goal/legacy-DECISIONS.md`.

Do not append here; split decision logs produce contradictory rationales.

## D-21 ArmoryService is the single writer of loadout state
Purchases and equips go through `ArmoryService` only; `CombatService` reads the profile and never mutates it. Rejected the alternative of letting the client tell the server "now carry weapon X" — `CombatService.equip` accepting an arbitrary id from the client is exactly how the 3000-credit ER-16 was free, so the ownership check now lives server-side next to the config lookup, and the armory selection is pushed by the server rather than requested by the client.

## Template-driven objectives instead of three services
One `ObjectiveService` dispatching on `mission.objectiveTemplate`, rather than three objective services.
Reason: the relay was already 80% of the machinery (ground snap, terminal interact, publish, complete
FX); the templates differ in **object built** and **completion rule**, not in plumbing. Three services
would triple the surface the deploy path has to keep in sync.
Consequence accepted: `complete()` gates its explosion FX on template id, so a new template must say
whether it explodes.

## EnvironmentSpecularScale is 0 in every lighting preset (v303)

Measured A/B on the concourse deck, same camera, same lights, same session:

| EnvironmentSpecularScale | EnvironmentDiffuseScale | result |
|---|---|---|
| 0.04 | 0.18 | solid orange wash covering the entire floor and tinting the character (V354) |
| 0.00 | 0.00 | clean dark deck (V355) |
| 0.00 | 0.18 | clean dark deck, environment diffuse still present (V356, V357) |

Cause: this place sits under a saturated orange/magenta nebula sky, and Roblox samples the sky for specular on `Metal`. A large
flat Metal deck mirrors it at grazing angles. The earlier "DiamondPlate is banned on the deck" rule was this same problem seen
through a different material — 0.04 specular was enough to produce it on plain Metal too.

Consequence for future art work: any large flat surface in this place must either use a matte material or accept that specular is
globally disabled. Do not raise `EnvironmentSpecularScale` to "add gloss" without re-checking the deck at grazing angles.

## At most two hostiles may be mid-attack at once (v366)

Measured at the sabotage relay: four hostiles put **22 hits** into a stationary player in seven seconds and took them from 100 health
to 6 — a firing squad, not a fight. `EnemyService.claimFireSlot` now caps simultaneous attackers at `MAX_FIRING = 2`; a hostile that
cannot claim a slot does not fire, so attacks are staggered rather than cancelled.

Measured after, standing at the same terminal for nine seconds: **0 damage events, health 100**, with `GF_FireSlotsHeld = 2` showing
the budget engaged (i.e. hostiles were trying to fire and were queued). This is one run — patrol placement varies by seed — but the
difference between "dead in seven seconds" and "untouched in nine" is not noise.

Consequence: a single hostile is now much less threatening, so encounter difficulty leans on positioning and numbers rather than
raw rate of fire. If the game feels too easy later, raise `MAX_FIRING` to 3 before touching per-shot damage.

## Do not treat "no damage" as evidence until engagement is measured (v368)

v366 concluded a fire-distribution change made the objective survivable, on the strength of zero damage events over nine seconds. It was
zero **engagement**: `GF_EnemiesEngaged = 0` with `GF_EnemiesTracked = 8`, i.e. no hostile had a target at all. The player was standing
inside geometry that blocked line of sight, so the measurement proved nothing about damage.

Rule: any survivability claim must report acquisition separately from damage — `GF_EnemiesEngaged`, `GF_EnemiesTracked`, then damage
events. Zero of everything is a null result, not a success.

The underlying defect this exposed is real and separate: the mission's primary objective is **self-concealing**. Hostiles cannot acquire
a player at the console because the outpost's own structure blocks LOS, so the objective is undefended.

## Never append a block whose last line repeats its anchor (v371, second occurrence)

Twice now, a patch built as `src:sub(1, i-1) .. block .. src:sub(i + #anchor)` where `block` **ends with the anchor text** has produced a
duplicated function header:

```lua
function EnemyService.start()function EnemyService.start()   -- v366
function ObjectiveService.getRelay()function ObjectiveService.getRelay()  -- v371
```

Both took a whole module offline with `Expected 'end' ... got <eof>` and both were found only by reading the server log right after the
edit. Correct form: `block` must **not** contain the anchor; insert with `src:sub(1, i-1) .. block .. src:sub(i)`.

## Debug switches must be set from the server datamodel (v371)

`workspace:SetAttribute("GF_...")` from the **client** does not replicate to the server. `GF_DebugDamage` set that way produced zero
logged damage sources for a real 100 → 11 health drop, and `GF_ForceConsoleScreen` set that way meant a capture hook silently did
nothing. Any switch the server reads must be set in the Server datamodel.

## The console mitigates damage only while the hold runs (v371)

50% mitigation and a visible `ForceField` panel (`ConsoleScreen`) exist only between hold start and hold end, so standing next to the
console gains nothing. Measured `GF_ConsoleMitigated = 2` during one contested hold with three hostiles acquired; the player finished at
38 health instead of 11.

## A mission frame that shows the station means the player died, not that the camera is broken (v373)

Six continuations of "the capture keeps returning the station" were chased as a camera-override bug. The camera read `-8, 769, 36` —
station roof height — while the objective was at `0, 34, -120`. The player **died at the objective and respawned at the station** while the
mission kept running server-side, so the capture was accurate.

Rule: before blaming the camera, print `CurrentCamera.CFrame.Position` **and** the objective's position and compare them with the station
deck height (~800). For steady frames, set `GF_DeployGraceUntil` to a far future time server-side so the subject survives the shot.

## The mission zone must never fall back to the engine default sky (v374)

`Environment.apply` used to `sky:Destroy()` for every non-station zone. Destroying the Sky instance restores Roblox's engine default — a
clear blue daylight sky — so a nebula outpost was lit like a summer morning and its pale voxel ground read as snow. Every "snow under a
blue sky" frame (V402, V404, V408) traces to this one branch.

Rule: both zones install the space skybox; only the star density differs (station 20000, mission 6000, measured back as 5000). Voxel
terrain keeps its own material colours, so `Terrain:SetMaterialColor` per zone is required for the ground to agree with the sky.

## Never fix a palette by recolouring a live scene by colour predicate (v377)

Two attempts to remove green plant dressing from a violet world by walking `workspace` and hue-shifting "green" parts:

- Strict predicate (`g > b + 0.03`) skipped the plants entirely — the spires are 58,88,82, where green leads blue by 0.023.
- Relaxed predicate swept **136 parts** and collapsed the compound to near-black (V413). It cannot tell a plant from a rock, and its
  failure mode is the whole scene.

Reverted. Rule: palettes are **arguments at construction time**, not post-hoc filters. If a colour must change, pass it in where the part is
built. Blanket recolouring is only acceptable for a whole named material family with a known enumeration (as with
`Terrain:SetMaterialColor`).

## Capture discipline that is now mandatory (v377)

A mission capture must assert three things before it is trusted: `CurrentCamera.CFrame.Position`, the objective part's position, and their
distance. V412 was the first good relay frame in six attempts **because** the camera was forced `Scriptable` with `CameraSubject = nil` at a
computed offset and the distance was printed (33 studs) before capturing.

## 2026-11-24 — Context strategy: no pruning plugin; the loop carries state instead

**Measured before deciding** (session `01a205b4`, model `deepseek-v4.1-flash`, window 1,000,000):
- Live context at decision time: **135,197 tokens = 13.5%** (`input 1,700 + cacheRead 133,120 + output 377`).
- **6 native compactions** in this session, all `fromHook: false`; `tokensBefore` = 1,078,490 · 1,088,116 · 216,825 · 711,002 · 818,297 · **162,043**.
- Compaction spend: **$0.427** across those six. Whole session: **$8.17**.
- 71 `context_edit` omission records, Pi-native, clustered immediately before compactions.

**Decision:** do not build a pruning / "DCP" layer, and do not reintroduce an ACP-style package.

Reasons, in order of weight:
1. **Cache economics run against pruning.** A request is dominated by `cacheRead` (133k cached vs 1.7k fresh). Rewriting or dropping mid-conversation history invalidates the cached prefix and makes the next request pay full input price. Pruning to "save tokens" typically increases cost.
2. **Pruning breaks the structure the API requires.** Removing an assistant `tool_call` without its result, or vice versa, is a hard request error — the exact failure class that makes a session unusable mid-task.
3. Pi already has the mechanisms: native compaction plus native omission (`context_edit`). A second writer into the same context is how the earlier harness became unusable.

**What was actually broken:** the *loop*, not the context. After compaction or `/reload` nothing re-injected the goal, so the owner had to re-prompt. Fixed in `~/.pi/agent/extensions/goal-loop.ts`:
- `.goal/LOOP_STATE.json` — durable `{active, goal, iteration, startedAt, compactions}`.
- `session_start` with `reload`/`resume` re-arms the loop and sends a turn. Previously `/reload` silently ended it.
- `session_compact` sets a re-anchor flag; the next continuation is a **resume packet** naming `WORK_STATE.md`, the ledger and the spec — so the turn rebuilds from disk instead of trusting a summary.
- Circuit breaker: **4 compactions** in a session writes `.goal/PAUSE` and stops, instead of compacting forever.
- Verified: `test_goal_loop.ts`, **15/15 passing** on a fake ExtensionAPI and a temp repo.

**Open anomaly:** a compaction fired at `tokensBefore = 162,043` on a 1,000,000-token window, and another at 216,825. Neither matches the threshold path (983,616). Both need attribution (overflow recovery vs a model switch with a smaller effective window) before any threshold tuning is trusted.

## 2026-11-24 — Two plugins, both narrow: context-gc (pruning) and gf-orchestrator (batches)

**Pruning is justified by measurement, but only for what actually grew.** In one session: tool traffic
108 MB, of which `screen_capture` was **105.1 MB / 389 calls** (avg 270 KB base64). Everything else
combined was under 3 MB. So `context-gc.ts` elides old **screenshots** and shortens old **bulk tool
output** (default: older than the last 5 results and over 8 KB → head 1200 + tail 400 chars + marker).
It never removes a message, so tool-call pairing stays valid; decisions are permanent per tool-call id,
so the prefix is stable instead of churning the prompt cache. Past **600k estimated tokens** the limits
tighten (images to the newest 1, text from 2.5 KB), which is the owner's requested soft limit rather
than waiting for the 1M wall.
Tests: `.audit/test_context_gc.ts` **13/13**.

**Orchestration uses the documented seam, not private internals.** `pi-subagents` exposes
`prompt-template:subagent:request|response` on `pi.events`. `gf-orchestrator.ts` registers
`gf_orchestrate` with `start|status|abort`: a planner (`oracle`, model `deepseek-v4-pro`, thinking
high) reads the ledger + `WORK_STATE.md` and returns strict JSON; the plan is schema-validated before
any launch; up to 3 workers run in parallel; an `evidence-auditor` gate decides whether to advance.
A rejected gate stops the pipeline and reports. Responses are matched on
`(requestId, ownerRunId, nodeId)` so a late or duplicated reply cannot advance the wrong stage.
Tests: `.audit/test_orchestrator.ts` **21/21** against a fake delegation bus, including planner
failure, gate rejection, and a missing event bus.

**Boot safety, learned the hard way twice:**
- Tests live in `.audit/`, never in `~/.pi/agent/extensions/` (Pi auto-discovers every `.ts` there; a
  test with `process.exit` took Pi down at startup).
- `gf-orchestrator.ts` imports nothing at runtime except node builtins — the tool schema is plain JSON
  Schema rather than a typebox builder, so no alias resolution can fail.
- `.audit/boot_check.mjs` imports every extension file and fails if one throws or lacks a default
  export. Run it after any extension edit.

**Not yet verified:** neither plugin has been exercised against live agents. The orchestrator's
delegation path is proven only against a fake bus; the first real `/gf-orchestrate start` must be
watched, and its `.goal/ORCH_LOG.jsonl` is the evidence to check.

## 2026-11-24 — Escalation-only orchestration, and anti-sawtooth pruning

**Model choice is per-role, not one global brain.** `gf_orchestrator` reads:
- `GF_ORCH_PLANNER` (agent, default `oracle`) and `GF_ORCH_MODEL` (default `deepseek-v4-pro`) — the
  planner is the only place a stronger model is requested, once per escalation.
- `GF_ORCH_WORKER` (default `worker`), `GF_ORCH_GATE` (default `evidence-auditor`), `GF_ORCH_MAX_WORKERS` (3).
Workers use whatever model their own agent definition declares; the planner override does not leak into them.

**The orchestrator is an escalation, not a resident loop.** It is never wired into the goal loop and
never fires on its own. `gf_orchestrate` now **requires `blockedOn`** (≥15 chars) describing the concrete
blocker, and refuses to launch anything without one. Rationale: the base model does the bulk of the work;
a planner plus three workers plus a gate per turn would multiply cost for no gain on ordinary rows.
The blocker is written into `.goal/ORCH_LOG.jsonl` with every batch, so escalations are auditable.

**Pruning no longer sawtooths.** The earlier design had one threshold, which is exactly the failure the
owner named: cross 600k → prune just under it → grow → cross again. `context-gc` now:
- enters tight mode at **600k**, leaves only below **420k** (70%), and the latch is persisted;
- while tight, keeps shortening old bulk output **until the projection is under 420k**, rather than
  stopping the moment it is under the trigger;
- persists the latch even when a pass rewrote nothing (otherwise the decision was lost and re-made on
  the next request, which reintroduced the thrash);
- orders candidates oldest-first from a single index pass, not `indexOf` inside a comparator.
Tests: `.audit/test_context_gc.ts` **16/16**, including "stays tight between floor and soft" and
"leaves tight below the floor". Orchestrator: **23/23**, including "refuses start without a named blocker".

## 2026-11-24 — The orchestrator is installed, and it decides for itself when to escalate

**Why it never fired: it was not loaded, and its auto path could not run.** `gf-orchestrator.ts` had been
moved to `.audit/quarantine/` during the boot-safety cleanup, so `gf_orchestrate` did not exist in any
session — `.goal/ORCH_LOG.jsonl` did not exist either, i.e. zero launches ever, not "too few". The
quarantined copy also built its `Orchestrator` lazily **inside the tool call**, so the automatic path's
`if (!engine) return` was always true until someone called the tool by hand. Reinstalled at
`~/.pi/agent/extensions/gf-orchestrator.ts`; construction is now behind `ensureEngine()` and both the tool
and the automatic path go through it.

**It escalates on being stuck, not on a schedule.**
- repeated failure: 3 identical normalised tool-error signatures in the window, or 3 failures in a row;
- ledger stall: the last 4 `LOOP.log` iterations carry a byte-identical ledger line **and** span ≥5 min.
  Identical counts alone are ordinary (one row can legitimately take several turns); identical counts over
  minutes means tokens are being spent without moving the ledger.
Knobs: `GF_ORCH_AUTO=0` disables automation; `GF_ORCH_STALL_AFTER` (4), `GF_ORCH_STALL_MIN_MS` (300000),
`GF_ORCH_AUTO_COOLDOWN_MS` (900000), `GF_ORCH_AUTO_MAX` (3 per session).

**One writer at a time.** An automatic escalation writes `.goal/PAUSE` (and remembers the exact text it
wrote) before the planner runs, then deletes it when the run ends, so the loop resumes by itself. Only the
exact text this extension wrote is ever removed — an owner's PAUSE is never overwritten or deleted. An
escalation for a loop recorded as owned by another session is refused outright.

**Ownership is not claimed by helpers.** `gf-escalation.ts` stamped `OWNER_SESSION` and the heartbeat on
every `session_start` and every 30s, in every session, which silently defeated the goal loop's sidecar gate
(the last chat to start owned the loop; a harness chat at `C:/Users/tnguy` took it at 20:18). It now
refreshes the heartbeat only when the recorded owner *is* the current session.

**Deploy note:** extensions load at session start. A chat that is already open keeps the old code until it
is reloaded, so the orchestrator and the heartbeat gate only take effect there after a reload.

Tests: `.audit/test_orchestrator.ts` **36/36** — adds `parseLoopLog`/`detectStall`, foreign-owner refusal,
stall launch with PAUSE release, and "auto works before the tool was ever called".

## 2026-11-24 — Scope correction: only the orchestrator was de-GF'd

The rename pass briefly touched the goal loop and the escalation advisor too. Both are reverted: their file
names, `GF_REPO`, and the fixed `.goal` location are exactly as before. The scope was the orchestrator
extension. The heartbeat-ownership gate in `gf-escalation.ts` stays, because that was an approved bug fix
rather than a rename.

What remains changed, all inside the orchestrator:
- `gf-orchestrator.ts` → **`orchestrator.ts`**; tool `orchestrate`, with `gf_orchestrate` still registered
  as an alias so existing goal text and decisions keep working.
- `GF_ORCH_*` → **`ORCH_*`**, `GF_REPO` → **`GOAL_ROOT`**; the legacy names still resolve.
- It no longer hardcodes a repository: nearest ancestor with `.goal`, else `GOAL_ROOT`, else a directory
  whose single child project has `.goal` (the home-directory case), else the cwd. Two candidates is
  ambiguous and nothing is guessed, so it can never plan against the wrong project.

Verified from `C:/Users/tnguy`: `orchestrate status` resolves its log to
`<local>\.goal\ORCH_LOG.jsonl` — the GF project is found without being named.
Live source is mirrored at `.audit/quarantine/orchestrator.ts`; the old `gf-orchestrator.ts` snapshot is
back to its committed state as history. Tests: orchestrator **37/37**, goal loop **15/15**, boot check clean.

## 2026-11-26 — Phase 15 art direction reconciliation (claude)
- Master-prompt four biomes (forest, mountain/frozen, arid, industrial) SUPERSEDE the 2025-11-25 "two themes only" note; the four already exist in code, so no new biomes are added.
- Ascendancy armor: dark obsidian/bronze/ivory with RESTRAINED violet tech accents only; no red accents; not a human-kit recolor. Final violet balance decided at owner gate with an in-game sample.
- Phase-15 work extends the existing GFArtKit/gf-art-build program rather than restarting it; gf-art-build/EVIDENCE.md items fold into VISUAL_REVIEW/BUILD_MANIFEST, no third ledger.
- 2026-11-26 (claude) Mission biome rotation changed {Forest, Arid, Tundra, Volcanic} -> {Forest, Arid, Tundra, Industrial}: Volcanic was never an approved biome; Industrial (already in WorldDressing kits) is. Volcanic data retained, unused. Per-biome lighting lives in Services/BiomeLook.luau (data + apply), called last by Environment.apply("mission").
