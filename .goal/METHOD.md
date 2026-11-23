# METHOD — how work happens in this repo

Owner directive (2026-11-23): **one thing at a time.** This is a near-AAA target on Roblox, and it must
run on Xbox One, low-end phones and tablets. Breadth-first wiring is what produced 85 PARTIAL rows and a
game that looks terrible. Depth on one thing at a time is the correction.

## The rule

1. **One row at a time.** Pick a single row from `REQUIREMENT_COVERAGE.csv`. Do not start a second row,
   and do not "also" fix three other things on the way. If something else is broken, write it into
   `BACKLOG.md` with enough detail that the next session can act on it, and keep going on the row.
2. **Finish or stop, never half.** A row is only worked until it is either provably working (with runtime
   numbers and a frame) or provably blocked by a quotable tool error. Half-built systems are the exact
   failure mode this repo is recovering from.
3. **Evidence first.** Numbers from a live playtest, a captured frame, or a console excerpt. No claim
   without one. If it was not measured, it is not written as working.
4. **Write the negatives.** Every pass appends what looks wrong to `VISUAL_REVIEW.md`, in plain language,
   including the things that are embarrassing. That file is the quality ledger.

## Performance targets (non-negotiable)

Every change is judged against Xbox One / low-end mobile, not against this workstation.

- **Frame budget:** 16.6 ms. Measured in Studio only — never claim FPS on hardware that is not here.
- **Draw calls / parts:** the station is already ~600 parts before dressing. Any new feature must
  justify its part count; prefer one mesh or one material change over twenty parts.
- **Lights:** `PointLight`/`SpotLight` are the most expensive thing in this place. Neon parts and
  emissive materials are nearly free. Fixtures must be cheap by default.
- **Scripts:** no per-frame loops on the server. Heartbeat budgets are capped (see `EnemyService`, which
  thinks about at most 14 actors per step). Client work belongs in one aggregated loop, not ten.
- **No allocation churn.** No `Instance.new` in a heartbeat; no string concatenation per frame for UI.
- **Mobile input:** every new UI must be reachable without a keyboard, and every size must survive a
  720p phone screen. If a control only works with a mouse, it is not done.

## Order of work (from V3-07)

Station shell and UI → in-mission HUD and input → armory → war table and squad → mission content →
cinematic and tutorial → art and audio polish.

Visual quality is *not* last because it is cosmetic. It is last because a material/lighting pass over
half-built geometry has to be repeated. When geometry for an area is settled, the pass happens
immediately for that area and does not wait for the whole game.
