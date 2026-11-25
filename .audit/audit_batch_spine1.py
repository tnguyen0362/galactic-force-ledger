"""Audit batch: mission spine measurements spine1+spine2."""
import csv
import sys

CSV = "REQUIREMENT_COVERAGE.csv"
EV = "evidence/v594-mission-spine/EVIDENCE.md"

UPDATES = {
    "S04-046": dict(status="PARTIAL", observed_count="1", last_verified_build="594", evidence_ref=EV,
        blocker_or_defect="Exact calibration anchor measured live: synthetic 240+80 Rifleman died in exactly 18 AR-01 shots at full accuracy (spec authors 18). The 65%-accuracy ~2.65s expected firing time and the 2-4s cover/reload band remain unmeasured.",
        next_action="Measure TTK under realistic accuracy (65%) and confirm the 2-4s band."),
    "S04-018": dict(status="PARTIAL", observed_count="1", last_verified_build="594", evidence_ref=EV,
        blocker_or_defect="Shield-first ordering consistent with live measurement: 324 total damage distributed shield-first on a 240+80 synthetic target. Partial-overflow arithmetic itself verified in DamageChecks; the exact consume-only-shieldBefore/factor edge case unmeasured live.",
        next_action="Measure a shield-break overflow hit confirming health damage uses only overflow raw."),
    "S14-025": dict(status="PARTIAL", observed_count="1", last_verified_build="594", evidence_ref=EV,
        blocker_or_defect="Kill damage, kill credit, mastery accrual and war-point commit all originate server-side in live measurement; payloads carry no damage fields (inspection). Loot pickup and support-reward server-origin not yet measured.",
        next_action="Measure a loot pickup confirming the value is server-decided."),
    "S10-026": dict(status="PARTIAL", observed_count="1", last_verified_build="594", evidence_ref=EV,
        blocker_or_defect="Successful primary extraction paid exactly Normal=10 war credits fixed (not squad-bonus multiplied). Easy5/Hard15/Extreme25 and failure-zero unmeasured.",
        next_action="Probe failure payout grants 0 war credits."),
    "S14-027": dict(status="PARTIAL", observed_count="1", last_verified_build="594", evidence_ref=EV,
        blocker_or_defect="Countdown published live from server (2 at +1.5s from 3s override). Client interpolation/no-drift comparison still owed.",
        next_action="Compare client countdown display against the server attribute across a 30s window."),
    "S09-004": dict(status="PARTIAL", observed_count="1", last_verified_build="594", evidence_ref=EV,
        blocker_or_defect="Extraction callable immediately after primary completion; countdown publishes server-side. Difficulty-variant countdown durations unmeasured; 75s default timing unverified end-to-end.",
        next_action="Time a real extraction defense window and verify difficulty variants."),
}

rows = list(csv.DictReader(open(CSV)))
fields = rows[0].keys()
byid = {r["requirement_id"]: r for r in rows}
missing = [rid for rid in UPDATES if rid not in byid]
if missing:
    print("MISSING ROWS:", missing); sys.exit(1)
for rid, upd in UPDATES.items():
    for k, v in upd.items():
        byid[rid][k] = v
with open(CSV, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(fields))
    w.writeheader()
    w.writerows(rows)
print(f"updated {len(UPDATES)} rows")
