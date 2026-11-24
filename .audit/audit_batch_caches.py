"""Audit batch 2: Caches / Augments.

Populates UNKNOWN rows from evidence/v404, v406, v408, v422. Rows already
PARTIAL or VERIFIED (S11-033, S11-035, S11-009, S11-008) are deliberately left
alone so this script cannot silently overwrite another batch's work.

Run: python .audit/audit_batch_caches.py
"""
import csv
import sys

CSV = "REQUIREMENT_COVERAGE.csv"

AUGCFG = "ReplicatedStorage.GF.Shared.Configs.Augments"
CACHECFG = "ReplicatedStorage.GF.Shared.Configs.Caches"
CACHESVC = "ServerScriptService.GF.Services.CacheService"
AUGSVC = "ServerScriptService.GF.Services.AugmentService"
ARMORY = "ServerScriptService.GF.Services.ArmoryService"

V404 = "evidence/v404-augments/EVIDENCE.md"
V406 = "evidence/v406-augment-loop/EVIDENCE.md"
V408 = "evidence/v408-caches/EVIDENCE.md"
V422 = "evidence/v422-cache-inventory/EVIDENCE.md"

UPDATES = {
    "S11-003": dict(
        status="PARTIAL", observed_count="9",
        implementation_path=f"{AUGCFG}; {AUGSVC}; {ARMORY}",
        last_verified_build="404", evidence_ref=V404,
        blocker_or_defect="Nine categories exist and a category-parameterised purchase works, but the player cannot choose the category: there is no Armory category selector. The category is supplied on the remote payload, so the 'player selects at Armory opening' half of the requirement is unmet.",
        next_action="Add a category selector to the Armory augment surface and verify the choice reaches buyAugment from a click.",
    ),
    "S11-004": dict(
        status="VERIFIED", observed_count="32",
        implementation_path=f"{AUGCFG}",
        last_verified_build="408", evidence_ref=V404,
        blocker_or_defect="",
        next_action="Owner acceptance only. Per-category floor measured at 3 (build 404, 9x3=27); catalogue grew to 32 at build 408 with 3-4 per category.",
    ),
    "S11-022": dict(
        status="VERIFIED", observed_count="4",
        implementation_path=f"{CACHECFG}; {CACHESVC}",
        last_verified_build="408", evidence_ref=V408,
        blocker_or_defect="Legendary tier's Rare share measured 26% against the spec's 30%: only five Legendary archetypes exist, so a 4-draw cache can exhaust the pool and the fallback shifts draws. Not a table error.",
        next_action="Add one Legendary archetype per category so a 4-draw cache cannot exhaust the pool, then re-run the 1200-draw sample.",
    ),
    "S11-031": dict(
        status="ABSENT", observed_count="0",
        implementation_path=f"{CACHESVC}",
        last_verified_build="", evidence_ref=V422,
        blocker_or_defect="Explicitly unimplemented: caches carry no UID, generation timestamp or stored source, and draws are not decided once on opening via an idempotent transaction.",
        next_action="Store UID/timestamp/tier/source on grant and resolve the draw once inside a single transaction so a disconnect cannot re-roll.",
    ),
    "S11-032": dict(
        status="ABSENT", observed_count="0",
        implementation_path=f"{AUGSVC}; {ARMORY}",
        last_verified_build="", evidence_ref=V422,
        blocker_or_defect="No augment capacity limit exists at all: baseline 200, the +50 expansion (10 Cells + 3 Tech + 1000 Credits) and the 400 cap are unimplemented. v422 states there is no capacity limit, which is also why S11-033 cannot be satisfied.",
        next_action="Add the capacity field, the expansion purchase and the 400 clamp, then re-test the blocking rule in S11-033.",
    ),
    "S11-038": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=f"{AUGCFG}; {AUGSVC}",
        last_verified_build="406", evidence_ref=V406,
        blocker_or_defect="Rarity currently changes only cost and roll weight. It does not change the magnitude range of the rolled trait, which is the behaviour this requirement specifies (the anti-pattern half is satisfied: there is no rarity-based raw damage multiplier).",
        next_action="Make the trait magnitude range a function of rarity in Configs/Augments, then sample rollTrait per rarity and record the ranges.",
    ),
    "S11-039": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=f"{AUGSVC}",
        last_verified_build="404", evidence_ref=V404,
        blocker_or_defect="rollTrait demonstrably produces in-range values (blastRadius 0.344 inside 0.24-0.38), but the quantized integer 0..1000 storage, the rounding to 0.1% for display and the gold max-roll presentation are unverified.",
        next_action="Read back the stored quantized quality for several rolls and confirm 0..1000, then capture the gold max roll in the UI.",
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
