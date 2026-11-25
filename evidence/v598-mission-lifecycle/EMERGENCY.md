# v599 — emergency extraction path

DEFECT FOUND AND FIXED: emergency() passed the 60s grace as the pre-landing countdown, so the ship
waited 60s before landing. Spec S09-019 requires arrival within 8-12s with the 60s as post-landing
boarding grace (which the watchdog already enforced). Fixed to a 10s arrival countdown.

`[GF_EMRG] PASS emergencyCountdown=5 landedIn=5 failPayout war=0 credits=0` (override-scaled timing)

- Emergency triggers with primary incomplete (regardless of primary success) - S09-018 behavior.
- Arrival countdown short band (production 10s, probe override 5s; previously 60s defect) - S09-019.
- Ship lands after the short arrival window; post-landing 60s boarding grace enforced by watchdog.
- Failure settlement: war credits exactly 0 (S10-026 failure leg), credits 0 measured - cross-check
  against spec whether failure should pay partial objective/kill credit.
