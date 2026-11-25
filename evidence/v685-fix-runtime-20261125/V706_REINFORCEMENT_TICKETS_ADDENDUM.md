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
