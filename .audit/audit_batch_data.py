"""Audit batch 7: Data / security.

Mapped from BLOCKED.md #1 (DataStore proven live, schema=1 persisted), v430
(two full server restarts), v441/v444 (server-applied damage), v438/v439
(server-computed rewards), v422 (guarded cache open), v457 (client sends
direction only), v412 (server-published countdown).

Nothing here is marked VERIFIED on the strength of a module existing: the rows
that stay PARTIAL are the ones whose failure path was never exercised, which for
durability and rate-limiting is the half that matters.

Run: python .audit/audit_batch_data.py
"""
import csv
import sys

CSV = "REQUIREMENT_COVERAGE.csv"

PROF = "ServerScriptService.GF.Services.ProfileService"
REW = "ServerScriptService.GF.Services.RewardsService"
CACHESVC = "ServerScriptService.GF.Services.CacheService"
AUGSVC = "ServerScriptService.GF.Services.AugmentService"
COMPAT = "ServerScriptService.GF.Services.CombatService"
ESVC = "ServerScriptService.GF.Services.EnemyService"
EXT = "ServerScriptService.GF.Services.ExtractionService"
CFG = "ReplicatedStorage.GF.Shared.Configs"
SPEC = "GOAL_2026-11-24.md"

BLOCKED = "BLOCKED.md"
V412 = "evidence/v412-failure-evac/EVIDENCE.md"
V422 = "evidence/v422-cache-inventory/EVIDENCE.md"
V430 = "evidence/v430-persistence/EVIDENCE.md"
V438 = "evidence/v438-debrief/EVIDENCE.md"
V441 = "evidence/v441-enemy-stats/EVIDENCE.md"
V444 = "evidence/v444-heavy-verified/EVIDENCE.md"
V457 = "evidence/v457-weapon-fire/EVIDENCE.md"
HANDOFF = "HANDOFF.md"

UPDATES = {
    "S14-004": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=f"{CFG}; {REW}; {PROF}; {CACHESVC}",
        last_verified_build="430", evidence_ref=V430,
        blocker_or_defect=f"{SPEC} L220 asks for authoritative configs, sensitive receipt/reward logic and server RNG to live in server-only modules 'where appropriate', with sanitised display stats shared. The sensitive half is in ServerScriptService (RewardsService, ProfileService, CacheService, AugmentService) and cache outcomes roll server-side (v408). But the full balance tables - including every weapon's damage, RPM and falloff - sit in ReplicatedStorage.GF.Shared.Configs and are readable by any client. No module-by-module audit was done to prove no sensitive roll or receipt lives in a replicated module.",
        next_action="Audit each replicated module for authority-bearing data and record which configs are intentionally client-visible for prediction.",
    ),
    "S14-013": dict(
        status="PARTIAL", observed_count="1",
        implementation_path=f"{PROF}",
        last_verified_build="430", evidence_ref=BLOCKED,
        blocker_or_defect="A versioned schema demonstrably exists and round-trips: the stored document reads credits=900 xp=1200 rank=2 schema=1, and a full profile survived two server restarts unchanged. What is unproven is the hard part: type/range validation on load, any migration path (only schema 1 has ever existed), and the rule that a failed load must never overwrite the existing profile.",
        next_action="Write a malformed and an out-of-range document, load both, and confirm the profile is rejected without being overwritten.",
    ),
    "S14-015": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=f"{PROF}; {REW}",
        last_verified_build="430", evidence_ref=V430,
        blocker_or_defect="Both the read and the write path survive a server restart: eight fields matched exactly after restart, and an equip made before a second restart read back as VANGUARD. Per-user serialisation and the atomic transaction primitive itself were not observed, and no concurrent-mutation test exists.",
        next_action="Fire two mutations at one profile in the same tick and confirm neither is lost and no currency goes negative.",
    ),
    "S14-019": dict(
        status="PARTIAL", observed_count="1",
        implementation_path=f"{PROF}; {CACHESVC}",
        last_verified_build="430", evidence_ref=V430,
        blocker_or_defect="A pending award is durable: one held Rare cache, 36 owned augments and the full loadout survived two full server restarts. Idempotency is the untested half - a crash between commit and UI confirmation must not duplicate or lose the award, and no reconnect with an in-flight settlement was tested.",
        next_action="Kill the server between settlement commit and debrief display, rejoin, and confirm the award lands exactly once.",
    ),
    "S14-022": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=f"{COMPAT}",
        last_verified_build="457", evidence_ref=V457,
        blocker_defect_placeholder=None,
        blocker_or_defect="The client demonstrably sends direction only and the server recomputes damage from config, armour and falloff, so it holds no authority over the outcome. Type/size and finite-number validation, and rate verification per action, were never exercised with malformed payloads.",
        next_action="Send NaN, an oversized payload and a malformed id to FireWeapon and confirm each is rejected with a logged reason.",
    ),
    "S14-025": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=f"{ESVC}; {REW}; {COMPAT}",
        last_verified_build="444", evidence_ref=V444,
        blocker_or_defect="Server ownership of NPC damage is measured: the Heavy's charge produced two 32.0 damage events through the server path, and archetype burst patterns fire server-side (v441). Rewards are computed server-side by RewardsService.compute (v438/v439). Loot grants and war-reward authority were not measured.",
        next_action="Record a kill, a loot pickup and a war-point commit and confirm each value originates server-side rather than client-reported.",
    ),
    "S14-026": dict(
        status="PARTIAL", observed_count="1",
        implementation_path=f"{CACHESVC}; {EXT}",
        last_verified_build="422", evidence_ref=V422,
        blocker_or_defect="One guard is demonstrated: a second openCache for the same tier was refused with 'no Rare cache held' and the held count stayed 0. Concurrency guards on extraction, revive, objective terminal, reroll and fusion were not tested, and the cache test was sequential rather than concurrent.",
        next_action="Double-fire openCache, extraction and reroll within the same tick and confirm each applies exactly once.",
    ),
    "S14-027": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=f"{EXT}",
        last_verified_build="412", evidence_ref=V412,
        blocker_or_defect="Countdowns are published from the server as GF_ExtractionRemaining and were read from the Server datamodel (6 -> 0 across the emergency grace), so the authoritative clock is server-side. Client interpolation from a single authoritative timebase, with no local decrementing, is not verified.",
        next_action="Compare client countdown display against the server attribute across a 30 s window and confirm no drift.",
    ),
    "S14-029": dict(
        status="PARTIAL", observed_count="6",
        implementation_path="workspace attributes (GF_TestHooks, GF_DebugDamage, GF_ForceNoBlueprintChance, GF_ForceRankUps)",
        last_verified_build="444", evidence_ref=HANDOFF,
        blocker_or_defect=f"{SPEC} L224 requires test-only simulation and debug affordances to be gated by Studio or an explicit private allowlist, with no live arbitrary reward or spawn commands. Six switches are documented in HANDOFF.md, and two of them grant state directly: GF_TestHooks enables grantTestAugment and bossRewardTest, and GF_ForceRankUps forces rank-ups. They are read from workspace attributes. No gate to Studio or an allowlist was found, and none was verified - so it is unknown whether a client can set one.",
        next_action="Read the guard around GF_TestHooks and GF_ForceRankUps and prove a non-Studio client cannot enable them; add an allowlist if it can.",
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
        upd = {k: v for k, v in UPDATES.get(rid, {}).items() if k in fieldnames}
        if not upd:
            continue
        current = row["status"].strip()
        if current != "UNKNOWN":
            print(f"SKIP {rid}: status is {current}", file=sys.stderr)
            continue
        for key, value in upd.items():
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
