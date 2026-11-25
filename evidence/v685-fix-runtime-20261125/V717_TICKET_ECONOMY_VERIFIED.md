# Ticket economy + no-ticket squad elimination — VERIFIED (live v717)

Harness: `tools/verification/run_ticket_deathflow_verify.py`
Evidence JSON: `raw/ticketflow_ticket_verification.json`
Captures: `raw/ticketflow_deploy_loading_0.jpg`, `ticketflow_first_downed_0.jpg`,
`ticketflow_kia_countdown_0.jpg`, `ticketflow_after_redeploy_0.jpg`,
`ticketflow_squad_eliminated_debrief_0.jpg`

## Full verified sequence (Easy solo, SABOTAGE_RELAY)

1. **Mission start: `tickets=5`** — matches spec formula Easy 3+2P with 1 player. The v706 defect
   (boot-time hardcoded 6, then double-decrement 6→4) is gone.
2. **Lethal fall induced** (210-stud drop, terminal velocity) → `GFDowned=true`, health 1,
   client DOWNED state visible. `GF_LastFallDamage` records the lethal hit.
3. **Solo bleed/conversion delay** → permanent death → trace
   `permanent death; ticketed redeploy pending player=ROBLOXISUS101 tickets=4` — exactly ONE ticket
   decremented (5→4). Client transitions DOWNED→K.I.A. with 8s countdown
   (`GF_RedeployPendingFor`, `GF_RedeployCountdown=8`).
4. **Automatic redeploy** fires with zero input: `pending=nil downedAttr=nil health=100`,
   respawned at `(-2, 33, 130)` vs LZ `(0, 32.5, 118)` — near-LZ placement correct.
   Tickets stay 4 (no double-spend on redeploy execution).
5. **Budget forced to zero** (`GF_DebugReinforcementTickets=0` — the harness hook consumes it
   through the same mission context, proving the live mission tickets object is authoritative).
6. **Second lethal fall** → downed again → no redeploy this time → server
   `endReason=squad_eliminated`, trace `failMission stationRequire=true`.
7. **Debrief client state:** `SQUAD ELIMINATED` text visible, debrief body
   ("Automatic redeploys exhausted") present, mouse released to `Enum.MouseBehavior.Default`,
   player returned to station (pos y 734 → 555 descending into station volume).
8. **Loading screen** observed `loading=true` both at deploy-fire time and during the
   elimination return-to-station transition; `loading=false` once settled in each location.

## Rows this closes / advances

- No-ticket squad-elimination branch: **proven end-to-end** (was the longest-open death-flow gap).
- Shared ticket economy arithmetic: correct initial count and exactly-one decrement per permanent
  death, no spend on execution.
- Loading screen: deploy + failure-return transitions now evidenced (extraction-success and
  initial-join transitions remain for the loading item).
- Downed solo conversion: 10s solo delay compressed by harness timing but the state ordering
  downed→K.I.A.→redeploy is evidenced.

## Honest residuals

- Redeploy spawn point is ~12 studs from LZ marker — inside tolerance, but pod-drop presentation
  (descending reinforcement pod visual) is still not implemented; the soldier simply reappears.
  That presentation layer remains an open item.
- The downed soldier visually lies at the death spot during K.I.A. countdown; crawl/pose polish
  remains open.
