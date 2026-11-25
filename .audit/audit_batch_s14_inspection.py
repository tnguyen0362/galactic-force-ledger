"""Audit batch: S14 inspection rows — evidence is code/repo state, gathered place 591-594."""
import csv
import sys

CSV = "REQUIREMENT_COVERAGE.csv"
EV = "evidence/v594-data-security/EVIDENCE.md"

UPDATES = {
    "S14-001": dict(status="PARTIAL", observed_count="1", last_verified_build="594", evidence_ref=EV,
        blocker_or_defect="Modular structure yes; configuration-driven stable string ids yes (all catalogs keyed by id); strict mode coverage 67/100 files - the remainder are mostly client UI/animation scripts. Typed service contracts exist at boundaries (Types.luau, Remotes.ContractVersion=1) but are not universal.",
        next_action="Raise strict coverage mechanically across client scripts; low risk but churn-heavy."),
    "S14-002": dict(status="VERIFIED", observed_count="1", verified_count="1", last_verified_build="594", evidence_ref=EV,
        blocker_or_defect="", next_action=""),
    "S14-003": dict(status="VERIFIED", observed_count="1", verified_count="1", last_verified_build="594", evidence_ref=EV,
        blocker_or_defect="", next_action=""),
    "S14-004": dict(status="VERIFIED", observed_count="1", verified_count="1", last_verified_build="594", evidence_ref=EV,
        blocker_or_defect="", next_action=""),
    "S14-005": dict(status="PARTIAL", observed_count="1", last_verified_build="594", evidence_ref=EV,
        blocker_or_defect="Explicit init order in Main, idempotent start() guards, zero LOAD-TIME require cycles (static analysis of 53 modules). Structural lazy cycles exist among mission services (ObjectiveService<->ExtractionService etc.) resolved through in-function requires - load-safe but not acyclic. Per-mission/profile cancellation tokens are partial.",
        next_action="Inventory connection/timer cleanup per service; document structural cycles as accepted deviation or decouple."),
    "S14-006": dict(status="VERIFIED", observed_count="1", verified_count="1", last_verified_build="594", evidence_ref=EV,
        blocker_or_defect="", next_action=""),
    "S14-007": dict(status="VERIFIED", observed_count="1", verified_count="1", last_verified_build="594", evidence_ref=EV,
        blocker_or_defect="", next_action=""),
    "S14-008": dict(status="PARTIAL", observed_count="1", last_verified_build="594", evidence_ref=EV,
        blocker_or_defect="Tracers/muzzle/impacts/weather/vista are client-local (VFX.luau, Weapon.luau, VistaQuality.luau; server never replicates them). Explosion blast spheres and structure-destroyed flashes are still instanced server-side in CombatService (transient 0.7s neon parts) - gameplay telegraphs, but replicable to client rendering.",
        next_action="Move transient blast/impact visual parts to client-rendered effects driven by a remote."),
    "S14-009": dict(status="PARTIAL", observed_count="1", last_verified_build="594", evidence_ref=EV,
        blocker_or_defect="revision field now exists and increments per save; replication is event-driven per action (no per-frame inventory syncs); late-join dispatch reconstructs from server snapshot. Snapshot+sequence recovery for mission state mid-session is partial.",
        next_action="Late-join reconstruction test during a live mission with sequence verification."),
    "S14-010": dict(status="VERIFIED", observed_count="1", verified_count="1", last_verified_build="594", evidence_ref=EV,
        blocker_or_defect="", next_action=""),
    "S14-011": dict(status="PARTIAL", observed_count="1", last_verified_build="594", evidence_ref=EV,
        blocker_or_defect="No universe-wide broadcasting exists (single instance); bullets are never broadcast - DamageFeedback is per-client. FireAllClients is used for mission-state events inside a 4-player mission population. No explicit location-based interest filtering for NPC/VFX.",
        next_action="Measure replication volume in a 4-player combat peak; add distance culling for enemy VFX events if hot."),
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
