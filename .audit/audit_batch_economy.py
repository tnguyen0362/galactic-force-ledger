"""Audit batch 4: Economy / mastery.

Mapped from evidence/v430 (persistence), v438 (debrief base/bonus), v439 (salvage
bonus). Only rows with a real measurement are touched. Mastery rows (S10-037,
S10-038, S10-039) have no evidence anywhere in evidence/ and are deliberately left
UNKNOWN rather than guessed.

Run: python .audit/audit_batch_economy.py
"""
import csv
import sys

CSV = "REQUIREMENT_COVERAGE.csv"

REW = "ServerScriptService.GF.Services.RewardsService"
PROF = "ServerScriptService.GF.Services.ProfileService"
AUGSVC = "ServerScriptService.GF.Services.AugmentService"
SPEC = "GOAL_2026-11-24.md"

V430 = "evidence/v430-persistence/EVIDENCE.md"
V438 = "evidence/v438-debrief/EVIDENCE.md"
V439 = "evidence/v439-salvage-bonus/EVIDENCE.md"

UPDATES = {
    "S10-004": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=f"{PROF}; {REW}",
        last_verified_build="430", evidence_ref=V430,
        blocker_or_defect="A lifetime-XP rank ladder demonstrably persists: rank 15 with 123,700 XP survived two server restarts unchanged, and a rank-up crossing moves the label 13 -> 15. The threshold formula itself (cumulative sum to rank r, rank 1 = 0) is not checked against the table.",
        next_action="Tabulate the configured thresholds for ranks 1-15 against the spec formula and assert rank 6 = 3,150 XP.",
    ),
    "S10-006": dict(
        status="PARTIAL", observed_count="600",
        implementation_path=f"{REW}",
        last_verified_build="438", evidence_ref=V438,
        blocker_or_defect=f"Measured Normal payout is 450 Credits and 600 XP for a solo success. Credits sit inside the intended 450-600 band, but XP is BELOW the 650-900 band by 50 at the floor. Sample is pure maths from compute() plus one real solo extraction; no 10-15 minute mission was timed.",
        next_action=f"Either raise Normal base XP to at least 650 or record the deliberate 600 as an owner-approved revision, then time a real 10-15 minute clear.",
    ),
    "S10-021": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=f"{REW}",
        last_verified_build="439", evidence_ref=V438,
        blocker_or_defect="Floor-at-settlement is demonstrated for the squad bonuses: 25% of 450 floors to 112, 25% of 600 is 150, and 25% of 40 salvage floors to 10 per resource. Per-event fractional accumulation before that single floor is not demonstrated, because no run split an event total.",
        next_action="Record a mission with several kill events and confirm the sum is floored once at settlement rather than per kill.",
    ),
    "S10-025": dict(
        status="PARTIAL", observed_count="1050",
        implementation_path=f"{REW}",
        last_verified_build="439", evidence_ref=V439,
        blocker_or_defect=f"Baseline solo success measures 450 Credits + 600 XP = 1,050 combined, inside the intended ~450-600 Credits / ~650-900 XP shape on credits but 50 XP short at the XP floor. Inferred from compute() plus one real extraction, not from a timed operation.",
        next_action="Reconcile against S10-006 so both rows move together: either raise the XP baseline or record the revision.",
    ),
    "S10-031": dict(
        status="PARTIAL", observed_count="40",
        implementation_path=f"{REW}",
        last_verified_build="439", evidence_ref=V439,
        blocker_or_defect="Shared salvage is credited in full per eligible player in compute(): a 60-unit squad pool pays 40 each solo and 50 each with the +25% four-player bonus, floored per resource. The 10-20 Scrap-equivalent average for a real Normal mission is not measured, and no multi-player extraction was run.",
        next_action="Extract with two eligible players and confirm each receives the full shared amount, then record actual per-mission salvage totals.",
    ),
    "S10-040": dict(
        status="PARTIAL", observed_count="36",
        implementation_path=f"{AUGSVC}; {PROF}",
        last_verified_build="430", evidence_ref=V430,
        blocker_or_defect="Augment ownership is independent of weapons and persists: 36 owned augments survived two server restarts, and a saved loadout kept its augment socket (BeltFeed) across the restart. Equipping the same owned copy across multiple saved loadouts is not demonstrated, because only one loadout exists.",
        next_action="Save two loadouts that reference the same augment copy and confirm both stay valid.",
    ),
}


def main() -> int:
    with open(CSV, encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh)
        fieldnames = reader.fieldnames
        rows = list(reader)

    touched = []
    for row in rows:
        rid = row["requirement_id"].strip()
        upd = UPDATES.get(rid)
        if not upd:
            continue
        current = row["status"].strip()
        if current != "UNKNOWN":
            print(f"SKIP {rid}: status is {current}, not UNKNOWN", file=sys.stderr)
            continue
        for key, value in upd.items():
            if key not in fieldnames:
                print(f"ERROR: unknown column {key}", file=sys.stderr)
                return 1
            row[key] = value
        print(f"  {rid:10} UNKNOWN -> {upd['status']}")
        touched.append(rid)

    missing = sorted(set(UPDATES) - set(touched))
    if missing:
        print(f"ERROR: rows not updated: {missing}", file=sys.stderr)
        return 1

    with open(CSV, "w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames, lineterminator="\r\n")
        writer.writeheader()
        writer.writerows(rows)

    print(f"\nupdated {len(touched)} row(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
