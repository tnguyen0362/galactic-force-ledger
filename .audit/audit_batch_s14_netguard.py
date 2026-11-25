"""Audit batch: S14 data/security core (place 591-594, evidence/v594-data-security).

Updates rows verified or advanced by the NetGuard + profile data-layer batch.
Idempotent: asserts every targeted row exists; only overwrites rows whose ids are listed.
Run: python3 .audit/audit_batch_s14_netguard.py
"""
import csv
import sys

CSV = "REQUIREMENT_COVERAGE.csv"
EV = "evidence/v594-data-security/EVIDENCE.md"
NG = "ServerScriptService.GF.Services.NetGuard"
PROF = "ServerScriptService.GF.Services.ProfileService"
CS = "ServerScriptService.GF.Services.CombatService"

UPDATES = {
    "S14-012": dict(status="PARTIAL", observed_count="1", last_verified_build="593", evidence_ref=EV,
        blocker_or_defect="Schema fields now complete in defaults(): revision, tutorialProgress, firstMissionBonusClaimed, settledMissions, ownedBlueprints, recentTransactionIds all present and migration-validated (probe GF_PROF place 593). Deviations with identical information content documented: rankXP=rank+xp, resources=salvage{scrap,energyCells,militaryTechnology}, inventoryCapacity=augmentCapacity, lastSaveAt=lastSaveTime, bossPity=bossResearch[id].pity. tutorialProgress now persists per validated step and resumes.",
        next_action="Read back warCredits, settings and the transaction journal across a genuine server restart."),
    "S14-013": dict(status="PARTIAL", observed_count="1", last_verified_build="593", evidence_ref=EV,
        blocker_or_defect="Malformed and out-of-range documents now provably repaired: negative credits clamped, NaN xp scrubbed (finiteOr; math.max cannot stop NaN), rank 999 clamped, infinite warCredits scrubbed, non-boolean ownership entries and shapeless augment entries dropped, non-table document replaced by defaults. Load-failure now fences per-player: unpersisted session, save() refused, durable document cannot be overwritten.",
        next_action="Failure-injection test: force a GetAsync failure and confirm the session-only fence engages without touching the durable document."),
    "S14-014": dict(status="PARTIAL", observed_count="1", last_verified_build="593", evidence_ref=EV,
        blocker_or_defect="Session lease implemented: fresh token per load, revision increments per save, UpdateAsync transform aborts when a newer revision exists under a different token. Decision logic exported pure (ProfileService.leaseConflict) and verified across 5 cases. Single-place Studio cannot exercise a live cross-place handoff.",
        next_action="When the mission place exists, teleport mid-session and confirm the stale-session write aborts."),
    "S14-015": dict(status="PARTIAL", observed_count="1", last_verified_build="593", evidence_ref=EV,
        blocker_or_defect="Same-mission settlement double-fire pays exactly once (duplicate flagged). Same-tick mutations are inherently serialized by cooperative Luau scheduling; yielding operations (save) interleave safely because every mutation completes synchronously before any yield. UpdateAsync transform is lease-fenced but otherwise last-writer-wins by design.",
        next_action="Two mutations in the same tick from independent paths (e.g. purchase + settlement) confirming neither lost."),
    "S14-016": dict(status="VERIFIED", observed_count="1", verified_count="1", last_verified_build="591", evidence_ref=EV,
        blocker_or_defect="",
        next_action=""),
    "S14-017": dict(status="PARTIAL", observed_count="1", last_verified_build="594", evidence_ref=EV,
        blocker_or_defect="Settlement and receipts persist before final success (save precedes debrief/grant decision); saveWithRetry adds bounded exponential backoff with jitter (1/2/4s, 3 attempts); autosave corrected into the authored 60-90s band (75s).",
        next_action="Observe one real backoff recovery (transient datastore failure) in a live session."),
    "S14-018": dict(status="PARTIAL", observed_count="1", last_verified_build="594", evidence_ref=EV,
        blocker_or_defect="Dedup journals exist at three layers: processedReceipts (receipt ids), settledMissions (mission settlement, retention 30 settled-only eviction), cacheOpenJournal (committed draws reused on retry), plus the new umbrella recentTransactionIds ring (64) wired into settlement and receipts. GF_JRN PASS: journal records, ring cap enforced.",
        next_action="Recovery audit: replay a settled mission id and a settled receipt id against the umbrella journal."),
    "S14-020": dict(status="PARTIAL", observed_count="1", last_verified_build="593", evidence_ref=EV,
        blocker_or_defect="Session-only safe mode implemented: failed load -> unpersisted flag, GF_PersistenceMode=session-only attribute, no unbacked purchases possible because save() refuses; reset-to-zero cannot persist.",
        next_action="Player-facing retry/restricted-mode notice in the HUD."),
    "S14-021": dict(status="VERIFIED", observed_count="1", verified_count="1", last_verified_build="594", evidence_ref=EV,
        blocker_or_defect="",
        next_action=""),
    "S14-022": dict(status="VERIFIED", observed_count="1", verified_count="1", last_verified_build="591", evidence_ref=EV,
        blocker_or_defect="",
        next_action=""),
    "S14-023": dict(status="VERIFIED", observed_count="1", verified_count="1", last_verified_build="591", evidence_ref=EV,
        blocker_or_defect="",
        next_action=""),
    "S14-024": dict(status="PARTIAL", observed_count="1", last_verified_build="591", evidence_ref=EV,
        blocker_or_defect="Repeated invalid actions are throttled and logged in aggregate (NetGuard reason counters, console warns capped at 1 per 5s). Plausible-displacement movement validation (anti-teleport against sprint/dodge/vault budgets) is not implemented.",
        next_action="Implement server-side movement plausibility checks with latency tolerance."),
    "S14-026": dict(status="PARTIAL", observed_count="1", last_verified_build="593", evidence_ref=EV,
        blocker_or_defect="Reroll same-tick double-fire refused (pending-state guard, cost charged exactly once); settlement double-fire pays exactly once; cache open already dedups via cacheOpenJournal committed draws; objective terminal holds guard via holding[player]; revive re-entry guarded. Receipt idempotency proven at v588.",
        next_action="Cache-open same-tick double-fire measurement (the one surface not yet directly exercised)."),
}

def main():
    rows = list(csv.DictReader(open(CSV)))
    fields = rows[0].keys()
    byid = {r["requirement_id"]: r for r in rows}
    missing = [rid for rid in UPDATES if rid not in byid]
    if missing:
        print("MISSING ROWS:", missing)
        sys.exit(1)
    for rid, upd in UPDATES.items():
        for k, v in upd.items():
            byid[rid][k] = v
    with open(CSV, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(fields))
        w.writeheader()
        w.writerows(rows)
    print(f"updated {len(UPDATES)} rows")

main()
