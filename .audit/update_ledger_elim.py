import csv, os, tempfile

PATH = "REQUIREMENT_COVERAGE.csv"
EV = "evidence/v383-elimination/EVIDENCE.md"
BUILD = "383"
OBJ = "ServerScriptService/GF/Services/ObjectiveService (buildElimination, elimAdd, elimTick, elimSite)"
CFG = "ReplicatedStorage/GF/Shared/Configs/Missions"


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
        4, 1, "PARTIAL", "S08-003", CFG + "; " + OBJ,
        "Each family played end to end solo Normal with a capture and a measured completion.",
        "Conquest family absent. Sabotage, Recovery and Defense each have one variant, not three. "
        "Only the Elimination family was re-verified this session; the other three rest on earlier evidence.",
        "Build the Conquest family (Forward Dominion, Iron Foundry, Thronefall), then the two missing variants per existing family.",
    ),
    "COUNT-VARIANT": row(
        6, 3, "PARTIAL", "S08-003", CFG + "; " + OBJ,
        "Each of the 15 variants played to completion solo Normal.",
        "6 of 15 playable: 3 Elimination variants verified this session, plus one Sabotage, one Recovery and one Defense variant from earlier work.",
        "Add the 9 missing variants; Elimination already meets its three.",
    ),
    "S08-003": row(
        4, 1, "PARTIAL", "", CFG + "; " + OBJ,
        "Five families x three distinct variants, each played once.",
        "4 families, 6 variants. Conquest has no implementation; Sabotage/Recovery/Defense are one variant each.",
        "Conquest family next; it is the only family with zero playable content.",
    ),
    "S08-OP-HEAD-OF-THE-SPEAR": row(
        1, 1, "PARTIAL", "S08-003", OBJ + " buildElimination",
        "Deploy on Normal, defeat commander + guards, confirm completion and the optional relay stage.",
        "Playable and completes at 3/3 kills (Officer + 2 Rifleman, measured). The optional relay that disrupts the commander's call is not implemented.",
        "Add the optional relay stage: destroying it suppresses reinforcement call.",
    ),
    "S08-OP-SIEGE-BREAKER": row(
        1, 1, "PARTIAL", "S08-003", OBJ + " buildElimination + BastionWalker.spawn",
        "Deploy on Normal, destroy the required walker, secure the battlefield stage.",
        "Playable and completes on the walker's death (4200 HP, measured). The 'secure battlefield' stage is not implemented, so completion is a single event.",
        "Add the second stage: after the walker dies, clear the remaining siege crew before completion.",
    ),
    "S08-OP-BROKEN-TALON": row(
        1, 1, "PARTIAL", "S08-003", OBJ + " buildElimination",
        "Deploy on Normal, defeat the three elites as one linked encounter.",
        "Playable and completes at 3/3 kills (Marksman, Heavy, Officer, measured). They spawn as three separate actors, not a linked encounter, and nothing stops patrol respawns nearby.",
        "Link the three elites: shared aggro group and a hard respawn cap while the objective is active.",
    ),
    "S08-033": row(
        0, 0, "MISSING", "S08-012", OBJ,
        "Target markers approximate the site, then refine once the player has line of sight.",
        "No target marker system exists anywhere in the build. Elimination sites are only findable by walking; the hint line names the target but not a position.",
        "Reuse the mission HUD: a world marker at the objective plus a marker on each tagged target that tightens on discovery.",
    ),
    "S08-035": row(
        3, 3, "PARTIAL", "S08-003", OBJ + " buildElimination rosters",
        "Every variant differs in entities and conditions, not just a renamed terminal.",
        "The three Elimination variants pass: different rosters (Officer+2 Rifleman / Bastion Walker / Marksman+Heavy+Officer) and different labels. The other families still reuse one interaction each.",
        "Give Sabotage, Recovery and Defense their authored stage differences when their variants are built.",
    ),
    "S08-032": row(
        1, 1, "PARTIAL", "S08-003", OBJ + " elimTick",
        "No unbounded enemy source feeds an objective, and repeated reset cannot farm XP.",
        "Elimination rosters are authored and spawned once (3 or 1 tagged models); the tracker never respawns. Measured: tagged count stayed 3 across the mission and only tagged models moved progress.",
        "Confirm the same for the wave-based Defense variants before marking complete.",
    ),
}

with open(PATH, encoding="utf-8-sig", newline="") as f:
    reader = csv.DictReader(f)
    fields = list(reader.fieldnames)
    key = fields[0]
    rows = list(reader)

touched = 0
for r in rows:
    rid = r[key].lstrip("\ufeff")
    if rid in UPDATES:
        r.update(UPDATES[rid])
        touched += 1

fields = [fields[0].lstrip("\ufeff")] + fields[1:]
with open(PATH, encoding="utf-8-sig", newline="") as f:
    pass

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
