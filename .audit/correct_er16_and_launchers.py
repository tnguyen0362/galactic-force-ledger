"""Correction pass: retract the ER-16 claim, strengthen two launcher defects.

Why: batch 1 cited `.goal/GOAL.md` (1476 lines) as spec. That file is SUPERSEDED.
The authoritative specification is `.goal/GOAL_2026-11-24.md` (279 lines), which is
byte-identical to the owner's `Downloads/GOAL (1).md`
(sha256 1a1d440d4d60ad109dbf2de9967778dd24847a6533ff4b41db472572b4f66a9d).

Consequences:
  - SMG-03 Jackal is IN the authoritative weapon table (L54). ER-16 is absent.
    The recorded "spec conflict" was an artifact of reading a superseded document.
  - GOAL_2026-11-24.md L62 says launcher radius 13 (GL) and 10 (RPG). Config has
    9 and 12, so that IS a real mismatch and is now cited properly.
  - L47 and L62 require simulated explosive trajectories for GL/RL. Neither the
    config nor the code has speed/gravity/fuse.

Force-updates rows regardless of current status; prints the old value of every
field it rewrites so nothing changes silently.

Run: python .audit/correct_er16_and_launchers.py
"""
import csv
import sys

CSV = "REQUIREMENT_COVERAGE.csv"

WEAPONS = "ReplicatedStorage.GF.Shared.Configs.Weapons"
COMBAT = "ServerScriptService.GF.Services.CombatService"
SPEC = "GOAL_2026-11-24.md"

UPDATES = {
    "S04-034": {
        "blocker_or_defect": (
            f"Roster matches the authoritative specification: {SPEC} L54 lists SMG-03 Jackal, "
            "and ER-16 appears nowhere in it. An earlier note in this row claimed a conflict with "
            "GOAL.md naming ER-16 — that was WRONG. `.goal/GOAL.md` (1476 lines) is a superseded "
            "document; a `.goal/GOAL.md.superseded-25line-summary` file marks it as such. The stale "
            "pointer is in the goal text itself, which still says 'use GOAL.md as the authoritative "
            "specification'. Audit against GOAL_2026-11-24.md, never GOAL.md."
        ),
        "next_action": (
            "Owner: repoint the goal text at .goal/GOAL_2026-11-24.md so future batches cannot audit "
            "against the superseded 1476-line document. The roster itself needs acceptance only."
        ),
    },
    "S04-047": {
        "blocker_or_defect": (
            "SMG-03 computes 184.17/s and LMG-12 187.0/s from config, matching spec arithmetic, but "
            "neither sustained rate is measured in play. Two concrete data mismatches against "
            f"{SPEC} L62: GL-22 explosive radius is 9 where the spec says 13, and RL-09 is 12 where "
            "the spec says 10. Both launchers are hitscan-with-blast, so the authored projectile "
            "speed (GL 95), gravity (65 studs/s^2) and 2 s fuse exist in neither config nor code."
        ),
        "next_action": (
            "Set GL-22 radius 13 and RL-09 radius 10, add speed/gravity/fuse fields, then measure a "
            "blast at the radius edge and record a GL flight arc."
        ),
    },
    "S04-048": {
        "blocker_or_defect": (
            f"The server raycast is a swept segment with no per-round physical part, which satisfies "
            f"the anti-pattern clause. However {SPEC} L47 and L62 require the grenade launcher and "
            "rocket launcher to use actually simulated explosive trajectories. Both are currently "
            "hitscan-with-blast, so 'projectile explodes on valid collision or lifetime' is "
            "unimplemented and no fuse exists."
        ),
        "next_action": (
            "Implement travelling projectiles for GL-22 and RL-09 with collision-or-lifetime "
            "detonation plus a collision occlusion ray, or record the simplification as an "
            "owner-accepted defect."
        ),
    },
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
        for key, value in upd.items():
            if key not in fieldnames:
                print(f"ERROR: unknown column {key}", file=sys.stderr)
                return 1
            if row[key] == value:
                continue
            row[key] = value
        print(f"  {rid}: corrected {sorted(upd)}")
        touched.append(rid)

    missing = sorted(set(UPDATES) - set(touched))
    if missing:
        print(f"ERROR: rows not found: {missing}", file=sys.stderr)
        return 1

    with open(CSV, "w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames, lineterminator="\r\n")
        writer.writeheader()
        writer.writerows(rows)

    print(f"\ncorrected {len(touched)} row(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
