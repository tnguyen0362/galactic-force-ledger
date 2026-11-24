import csv, os, tempfile

PATH = "REQUIREMENT_COVERAGE.csv"
EV = "evidence/v385-conquest/EVIDENCE.md"
BUILD = "385"
OBJ = "ServerScriptService/GF/Services/ObjectiveService (buildConquest, conqEnterStage, conqTick)"
CFG = "ReplicatedStorage/GF/Shared/Configs/Missions; StationService VALID_TEMPLATES + TEMPLATE_RANK"


def row(observed, verified, status, dependency, path, required, blocker, next_action):
    return {
        "observed_count": str(observed),
        "verified_count": str(verified),
        "status": status,
        "dependency": dependency,
        "implementation_path": path,
        "verification_required": required,
        "last_verified_build": BUILD,
        "evidence_ref": EV,
        "blocker_or_defect": blocker,
        "next_action": next_action,
    }


UPDATES = {
    "COUNT-FAMILY": row(
        5, 2, "PARTIAL", "S08-003", CFG + "; " + OBJ,
        "Each family played end to end solo Normal at the current build.",
        "All five families now exist and are playable. Elimination and Conquest were verified at build 385; "
        "Sabotage, Recovery and Defense were verified at earlier builds and were not re-run this session, "
        "so only 2 families carry current-build evidence.",
        "Re-run Sabotage, Recovery and Defense once each to bring all five families onto the same build.",
    ),
    "COUNT-VARIANT": row(
        9, 6, "PARTIAL", "S08-003", CFG + "; " + OBJ,
        "Each of the 15 variants played to completion solo Normal.",
        "9 of 15 playable: 3 Elimination and 3 Conquest variants verified at build 385, plus one Sabotage, "
        "one Recovery and one Defense variant from earlier work.",
        "Add the six missing variants: two each for Sabotage, Recovery and Defense.",
    ),
    "S08-003": row(
        9, 6, "PARTIAL", "", CFG + "; " + OBJ,
        "Five families x three distinct variants, each played once.",
        "5 families, 9 variants. Sabotage, Recovery and Defense still have one variant each where the spec requires three.",
        "S08-OP-SHATTERED-AEGIS / BURN-THE-ARSENAL, SILENT-ARCHIVE / FALLEN-CONVOY shape, LAST-TRANSMISSION / POWER-UNDER-FIRE shape.",
    ),
    "S08-007": row(
        2, 2, "PARTIAL", "", OBJ,
        "Objectives expose Pending, Active(stageIndex), Completed and Failed, with server-owned transitions.",
        "Elimination and Conquest have real server-owned stage transitions (measured stage 1->2->3->complete). "
        "No template can report Failed: there is no failure state, so the state machine is incomplete.",
        "Add a Failed terminal state and a failure trigger (objective destroyed, defense object lost, timer expiry).",
    ),
    "S08-OP-FORWARD-DOMINION": row(
        1, 1, "PARTIAL", "S08-003", OBJ,
        "Clear defenders, seize console, hold 45 s, with a failure path.",
        "All three stages verified: 4 tagged defenders -> console interaction -> 45 s hold -> completion. "
        "The hold cannot fail and does not pause when the squad leaves.",
        "Add defense-object HP and the absence pause so the hold has stakes.",
    ),
    "S08-OP-IRON-FOUNDRY": row(
        1, 1, "PARTIAL", "S08-003", OBJ,
        "Cut turret power, capture control point, hold 60 s, with a failure path.",
        "Stages verified: power interaction -> control point interaction -> 60 s hold -> completion. "
        "The turrets that should be disabled by cutting power are not modelled.",
        "Model the turret power dependency, then give the hold a failure condition.",
    ),
    "S08-OP-THRONEFALL": row(
        1, 1, "PARTIAL", "LC-004", OBJ + "; StationService TEMPLATE_RANK",
        "Breach outer defense, defeat Veyr, capture command node, rank 10+.",
        "Stages verified: 3 tagged guards -> HighMarshalVeyr (3200 HP) -> command node -> completion. "
        "Rank gate verified by refusing at rank 99 with 'requires military rank 99'. "
        "The breach is a three-elite clear rather than a fortification with its own HP.",
        "Give the stronghold an actual outer-defense object to breach.",
    ),
    "S08-035": row(
        6, 6, "PARTIAL", "S08-003", OBJ,
        "Every variant differs in entities and conditions, not just a renamed terminal.",
        "All six verified variants differ: Elimination by roster/site, Conquest by stage-1 type (clear vs interact), "
        "presence of a boss stage, and 45 s vs 60 s holds. The other families still reuse one interaction each.",
        "Keep the pattern when the remaining six variants are built.",
    ),
    "S08-032": row(
        2, 2, "PARTIAL", "S08-003", OBJ,
        "No unbounded enemy source feeds an objective; repeated reset cannot farm XP.",
        "Elimination and Conquest spawn authored rosters once per mission (measured tagged counts stayed fixed at 3-4). "
        "Neither family respawns objective targets.",
        "Confirm for wave-based Defense variants before marking complete.",
    ),
}

with open(PATH, encoding="utf-8-sig", newline="") as f:
    reader = csv.DictReader(f)
    fields = list(reader.fieldnames)
    rows = list(reader)
key = fields[0].lstrip("\ufeff")

touched = 0
for r in rows:
    rid = r[key].lstrip("\ufeff")
    if rid in UPDATES:
        r.update(UPDATES[rid])
        touched += 1

fields[0] = key
fd, tmp = tempfile.mkstemp(dir=".", suffix=".csv")
os.close(fd)
with open(tmp, "w", encoding="utf-8", newline="") as f:
    w = csv.DictWriter(f, fieldnames=fields)
    w.writeheader()
    for r in rows:
        w.writerow({k.lstrip("\ufeff"): v for k, v in r.items()})
os.replace(tmp, PATH)
print("rows updated:", touched)
from collections import Counter
print(Counter(r["status"] for r in rows))
