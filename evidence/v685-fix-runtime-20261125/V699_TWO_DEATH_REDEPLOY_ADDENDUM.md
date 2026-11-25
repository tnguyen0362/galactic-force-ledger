# v699 Two-Death Automatic Redeploy Verification Addendum

Date: 2026-11-25
Live cloud version at capture: v699, with the same death-flow code carried forward into v700.
Harness: `C:\Users\tnguy\gf_tools\run_deathflow_verify.py`
Machine-readable evidence: `raw/deathflow_two_death_verification.json`
Captures: `raw/deathflow_deploy_loading_0.jpg`, `raw/deathflow_first_downed_0.jpg`, `raw/deathflow_kia_countdown_0.jpg`, `raw/deathflow_after_redeploy_0.jpg`, `raw/deathflow_squad_eliminated_debrief_0.jpg`

## Runtime sequence actually observed

1. Mission deployment fired successfully. The loading overlay was visible immediately during deployment (`loading=true`) and hidden after mission entry.
2. A controlled lethal fall produced the first downed state:
   - `downedAttr=true`
   - `health=1`
   - client DOWNED overlay visible
   - server downed debug showed the downed timer advancing
3. After the solo no-revive delay, the first death became permanent and the automatic redeploy countdown started:
   - `pending=ROBLOXISUS101`
   - `countdown≈7.2`
   - `used=true`
   - health stayed at 1 rather than regenerating behind the overlay
   - client showed `K.I.A.` and `AUTOMATIC REDEPLOY IN 7 — ABILITIES PRESERVED`
4. Automatic redeploy executed without player input:
   - pending cleared
   - player respawned in the mission near the LZ
   - health returned to 100
   - downed attribute cleared
   - DOWNED/KIA overlay hidden
5. A second controlled lethal fall produced a second downed state. Because the solo automatic redeploy had already been consumed, the next expiration ended the mission:
   - `inMission=false`
   - `endReason=squad_eliminated`
   - client squad-elimination debrief visible
   - debrief body visible
   - mouse released to `Enum.MouseBehavior.Default`
6. Final station state was clean in v699/v700:
   - server health 100
   - downed debug false
   - no pending countdown
   - downed attribute nil
   - debrief remained visible for dismissal

## Fixes proven by this run

- The first permanent death now keeps the player visibly downed through the redeploy countdown instead of silently clearing the downed state and allowing health regeneration underneath the K.I.A. overlay.
- Stock Roblox character `Health` scripts are removed when custom characters spawn, preventing the stock script from independently regenerating health outside `VitalsService`.
- Downed-state collision restoration is centralized and re-applied after automatic redeploy, preventing permanently non-colliding or partially colliding characters after death/redeploy.
- Automatic redeploy is genuinely automatic in the tested solo path; no manual input was sent after the lethal fall.
- Squad elimination reaches the end screen and releases the cursor.

## Honest remaining conformance gaps

- `GOAL.md` describes a broader shared redeploy-ticket economy (initial tickets, reinforcements at squads of 2+, tickets restored on objective completion, extraction restoring tickets, and solo reinforcement conversion). The current runtime proves only the existing solo one-automatic-redeploy flow. The full ticket economy is still **not verified** and partly not implemented as specified.
- The spec calls for downed/pending visual presentation including the player dropping, crawling, a spectating/deployment-pod sequence, and richer end-screen treatment. The current proof covers state, overlay, respawn, failure, cursor, and health correctness; cinematic polish remains open.
- This was a controlled verification using induced lethal falls. That is valid for flow/state verification, but it is not a natural combat death sequence.
