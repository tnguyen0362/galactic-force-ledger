"""Audit batch 5: Engineering / QA — acceptance-integrity and beta test-matrix rows.

These rows are process/meta requirements, so the "functionality" they describe IS
reporting discipline. Evidence is therefore concrete repo state rather than a
place measurement: OWNER_ACCEPTED 0 on all 815 rows, BLOCKED.md's visible
external blockers, and no publish path.

Device/squad TEST_MATRIX rows are marked PARTIAL with an EXTERNAL blocker rather
than ABSENT: they are not unimplemented, they are untestable in this environment,
and S16-103 requires such blockers stay visible instead of being marked green.

Run: python .audit/audit_batch_qa.py
"""
import csv
import sys

CSV = "REQUIREMENT_COVERAGE.csv"
BLOCKED = "BLOCKED.md"
LEDGER = "REQUIREMENT_COVERAGE.csv"

V383 = "evidence/v383-elimination/EVIDENCE.md"
V385 = "evidence/v385-conquest/EVIDENCE.md"
V388 = "evidence/v388-variants/EVIDENCE.md"
V453 = "evidence/v453-regression/EVIDENCE.md"

NO_DEVICE = (
    "EXTERNAL BLOCKER (BLOCKED.md #2): no device farm. Studio's device emulator validates layout only, "
    "not frame cost, and the goal forbids claiming a hardware target without real hardware."
)
NO_COOP = (
    "EXTERNAL BLOCKER: one local client only. Every measured run in evidence/ is solo, so no co-op or "
    "multi-client path has been exercised."
)

UPDATES = {
    # ---- beta test matrix: untestable here, must stay visible ----
    "BETA-DEVICE-GAMEPAD": dict(status="PARTIAL", observed_count="0", implementation_path="StarterPlayer.StarterPlayerScripts.Input",
        last_verified_build="", evidence_ref=BLOCKED, blocker_or_defect=NO_DEVICE,
        next_action="Capture an external gamepad session on real hardware and record which actions bind."),
    "BETA-DEVICE-XBOX": dict(status="PARTIAL", observed_count="0", implementation_path="StarterPlayer.StarterPlayerScripts.Input",
        last_verified_build="", evidence_ref=BLOCKED, blocker_or_defect=NO_DEVICE + " Original Xbox One profiling specifically is impossible here.",
        next_action="Run on an actual Xbox One and record frame time during a normal operation."),
    "BETA-DEVICE-PS": dict(status="PARTIAL", observed_count="0", implementation_path="StarterPlayer.StarterPlayerScripts.Input",
        last_verified_build="", evidence_ref=BLOCKED, blocker_or_defect=NO_DEVICE,
        next_action="Run the full gameplay and UI action list on a PlayStation controller."),
    "BETA-DEVICE-TOUCH": dict(status="PARTIAL", observed_count="0", implementation_path="StarterPlayer.StarterPlayerScripts.Input",
        last_verified_build="", evidence_ref=BLOCKED, blocker_or_defect=NO_DEVICE + " Touch layout is the one thing the emulator can validate.",
        next_action="Complete the touch action list on a real phone and profile a low-end device."),
    "BETA-DEVICE-PC": dict(status="PARTIAL", observed_count="0", implementation_path="StarterPlayer.StarterPlayerScripts.Input",
        last_verified_build="453", evidence_ref=V453,
        blocker_or_defect="Sessions run a single local client on PC, so keyboard/mouse movement, firing and extraction are exercised. The full action list (every menu, settings, tactical map, tutorial, armory scroll) has not been walked once end to end, and the armory buttons below the scroll viewport were never actually clicked.",
        next_action="Walk the complete PC keyboard/mouse action list once and record each action as it is performed."),
    "BETA-SQUAD-SIZES": dict(status="PARTIAL", observed_count="1", implementation_path="ServerScriptService.GF.Services.SquadService",
        last_verified_build="439", evidence_ref="evidence/v439-salvage-bonus/EVIDENCE.md",
        blocker_or_defect=NO_COOP + " The four-player bonus is pure maths from compute() (450 -> 562 credits, 600 -> 750 XP, 40 -> 50 salvage); no four-player mission was ever run.",
        next_action="Run one mission at each of 1/2/3/4 players and record the settlement for every participant."),
    "BETA-OPS-COOP": dict(status="PARTIAL", observed_count="0", implementation_path="ServerScriptService.GF.Services.SquadService",
        last_verified_build="", evidence_ref=BLOCKED, blocker_or_defect=NO_COOP,
        next_action="Complete one operation per family with a real co-op squad."),
    "BETA-OPS-SOLO": dict(status="PARTIAL", observed_count="8",
        implementation_path="ServerScriptService.GF.Services.ObjectiveService",
        last_verified_build="398", evidence_ref=V385,
        blocker_or_defect="Only 8 of the 15 operation variants have a per-variant evidence file: 3 elimination (v383), 3 conquest (v385) and 2 recovery/defense (v388). WORK_STATE claims all 15 complete on Normal across builds 393-398, but the remaining 7 have no per-variant EVIDENCE.md to check against, so the aggregate claim is not itself evidence.",
        next_action="Give each of the 7 unrecorded variants its own evidence file, or re-run them and capture it."),

    # ---- acceptance integrity: verifiable from repo state ----
    "S16-099": dict(status="PARTIAL", observed_count="0", implementation_path=LEDGER,
        last_verified_build="", evidence_ref=LEDGER,
        blocker_or_defect="No milestone label is stated anywhere: WORK_STATE and HANDOFF give build numbers but never declare the build UNFINISHED / PARTIAL. The underlying count also misreported itself until this audit - the loop showed 'ABSENT 0 | PARTIAL 68' while 732 rows were UNKNOWN.",
        next_action="State the milestone label explicitly in WORK_STATE and derive it from the ledger counts."),
    "S16-100": dict(status="VERIFIED", observed_count="0", implementation_path=LEDGER,
        last_verified_build="", evidence_ref=LEDGER,
        blocker_or_defect="",
        next_action="Owner acceptance only."),
    "S16-103": dict(status="PARTIAL", observed_count="3", implementation_path=BLOCKED,
        last_verified_build="", evidence_ref=BLOCKED,
        blocker_or_defect="External blockers are visible in BLOCKED.md (no device farm, no publish, no audio assets), but one is not: place-version numbers contradict each other across WORK_STATE (448), HANDOFF (318), BLOCKED (232) and recent commits (461), which is an unstated evidence-integrity blocker.",
        next_action="Surface the place-version discrepancy as a blocker and resolve it from a live save_place."),
    "S16-107": dict(status="VERIFIED", observed_count="0", implementation_path=LEDGER,
        last_verified_build="", evidence_ref=BLOCKED,
        blocker_or_defect="",
        next_action="Owner acceptance only. No device or live-co-op evidence exists, and the build has never been presented as beta-qualified."),
    "S16-110": dict(status="VERIFIED", observed_count="0", implementation_path="ServerScriptService.GF.Services.StationService",
        last_verified_build="", evidence_ref=BLOCKED,
        blocker_or_defect="",
        next_action="Owner acceptance only. Deploy is an in-place teleport; there is no publish path and no charging surface."),
    "S16-111": dict(status="PARTIAL", observed_count="0", implementation_path=".pi/agent/extensions/goal-loop.ts",
        last_verified_build="", evidence_ref=LEDGER,
        blocker_or_defect="The loop's ledger line was actively violating this until this session: it counted five statuses, omitted UNKNOWN, and therefore reported 'ABSENT 0 | PARTIAL 68' while 732 of 815 rows had never been audited. It now prints every status and reconciles against the row count, so verified/partial/absent/unknown are exact. A blocked count is still not reported separately.",
        next_action="Add a BLOCKED-EXTERNAL count to the ledger line so external blockers are counted rather than inferred."),
    "S16-112": dict(status="VERIFIED", observed_count="815", implementation_path=LEDGER,
        last_verified_build="", evidence_ref=LEDGER,
        blocker_or_defect="",
        next_action="Owner acceptance only. owner_acceptance is empty on all 815 rows and no row has been self-certified."),
    "S16-115": dict(status="VERIFIED", observed_count="0", implementation_path=LEDGER,
        last_verified_build="", evidence_ref=LEDGER,
        blocker_or_defect="",
        next_action="Owner acceptance only."),
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
        print(f"  {rid:22} UNKNOWN -> {upd['status']}")
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
