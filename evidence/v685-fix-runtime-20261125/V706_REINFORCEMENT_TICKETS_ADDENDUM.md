# V706 reinforcement-ticket economy addendum

Build deployed: v706, 125/125 scripts, zero deploy failures.

## Implemented

- Replaced the retired one-automatic-redeploy-per-player rule with the spec's shared squad ticket budget.
- Permanent deaths now consume `mission.tickets`; no-ticket deaths eliminate the player and fail the mission when nobody active/pending remains.
- Emergency extraction closes reinforcement support.
- Ticket count is replicated as `GF_ReinforcementTickets` and surfaced in the status strip as `SQUAD n · TICKETS n`.
- Redeploy pending messages now report remaining tickets.

## Runtime evidence

Harness: `tools/verification/run_ticket_deathflow_verify.py`; raw `raw/ticketflow_ticket_verification.json`, log `raw/ticketflow_verify_v706.log`.

Verified live:

- Easy mission published an initial ticket count (`tickets=6` in Studio Play Solo harness conditions).
- First lethal fall produced `DOWNED`, then `K.I.A.` with `GF_RedeployPendingFor=ROBLOXISUS101` and countdown.
- Ticketed automatic redeploy restored health `100`, cleared downed state, and returned the player near the LZ.
- Captures include `ticketflow_deploy_loading_0.jpg`, `ticketflow_first_downed_0.jpg`, `ticketflow_kia_countdown_0.jpg`, and `ticketflow_after_redeploy_0.jpg`.

## Honest failures / open defects

- The harness attempt to force the shared budget to zero did not mutate the authoritative mission context, so the no-ticket squad-elimination branch was not proven in this run.
- Ticket spend dropped from `6` to `4` around the first death rather than the expected single decrement. This needs root-cause correction before the ticket economy can be marked conformant.
- Reinforcement pod presentation is still minimal; redeploy is a positional respawn, not the full visible drop-pod sequence required by the spec.
- Downed crawl/pose remains unimplemented.

Therefore v706 is an implementation checkpoint, not a completed ticket-economy verification.

## V707/V708 correction and passing verification

v707 removed the boot-time fake Normal mission context and fixed deployment to publish the freshly reset mission's ticket budget rather than the stale pre-reset object. v708 added a server-only Studio verification bridge because plugin execution uses a separate Luau VM and cannot mutate authoritative module state directly.

Passing v708 evidence in `raw/ticketflow_ticket_verification.json` / `raw/ticketflow_verify_v708.log`:

- Easy solo deploy now publishes exactly `tickets=5` (`3 + 2P`, P=1).
- First permanent death decremented exactly one ticket to `4` and automatically redeployed the player.
- After forcing the remaining budget to zero through the server-only verification bridge, the second permanent death produced:
  - `endReason=squad_eliminated`
  - `inMission=false`
  - visible `SQUAD ELIMINATED` debrief body
  - mouse returned to `Default`
  - return-to-station loading visibility during transition

The ticket-spend defect from v706 is corrected. Remaining open work is limited to presentation and edge cases: full visible reinforcement drop pod, downed crawl/pose, spawn-trap protection, multiplayer revive/redeploy timing, live squad-size ticket scaling, and disconnect/rejoin abuse resistance.
