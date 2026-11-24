"""Audit batch 6: Enemy AI / bosses.

Mapped from v385 (Thronefall/Veyr), v441 (archetype HP + burst), v444 (Heavy
charge, LOS gate), v461 (Walker present in Workspace). Also refines S04-046, whose
blocker claimed Normal infantry 320 was unmeasured: v441 authored Rifleman
240/80 = 320 exactly.

Boss HP is where the numbers do not meet the spec, so those rows carry the defect
explicitly rather than a vague PARTIAL.

Run: python .audit/audit_batch_enemy.py
"""
import csv
import sys

CSV = "REQUIREMENT_COVERAGE.csv"

ENEMIES = "ReplicatedStorage.GF.Shared.Configs.Enemies"
ESVC = "ServerScriptService.GF.Services.EnemyService"
WALKER = "ServerScriptService.GF.BastionWalker"
VEYR = "ServerScriptService.GF.Veyr"
SPEC = "GOAL_2026-11-24.md"

V385 = "evidence/v385-conquest/EVIDENCE.md"
V441 = "evidence/v441-enemy-stats/EVIDENCE.md"
V444 = "evidence/v444-heavy-verified/EVIDENCE.md"
V461 = "evidence/v461-falloff-verified/EVIDENCE.md"
HANDOFF = "HANDOFF.md"

UPDATES = {
    "COUNT-BOSS": dict(
        status="VERIFIED", observed_count="2",
        implementation_path=f"{WALKER}; {VEYR}",
        last_verified_build="385", evidence_ref=V385,
        blocker_or_defect="",
        next_action="Owner acceptance only. Both boss models are observed as live Workspace objects: HighMarshalVeyr spawned tagged in Thronefall (v385) and BastionWalker as a physical obstacle with distinct geometry (v461).",
    ),
    "S06-020": dict(
        status="VERIFIED", observed_count="0",
        implementation_path=f"{ESVC}",
        last_verified_build="444", evidence_ref=V444,
        blocker_or_defect="",
        next_action="Owner acceptance only. GF_LastAttackAttempt reports entry / los-fail / los-pass / hit, and a blocked line produced los-fail while a clear line produced hit.",
    ),
    "S06-022": dict(
        status="PARTIAL", observed_count="5",
        implementation_path=f"{ENEMIES}",
        last_verified_build="441", evidence_ref=V441,
        blocker_or_defect="Attack timing and pattern are genuinely distinct per archetype and measured: Rifleman 13/8dmg x3, Scout 18/6 x4, Marksman 11/38 x1, Heavy 8/32 x1, Officer 12/12 x2, with burst count and interval driving separate hits. Silhouettes, posture and per-archetype audio are not captured, so the no-identical-reskin clause is unproven.",
        next_action="Capture each archetype's silhouette and posture, and record one distinct report per archetype.",
    ),
    "S06-031": dict(
        status="PARTIAL", observed_count="5",
        implementation_path=f"{ENEMIES}; {ESVC}",
        last_verified_build="441", evidence_ref=V441,
        blocker_or_defect="Per-archetype HP and shield are authored to spec and one spawn was measured (Scout 210 HP / 60 shield). Difficulty-driven HP scaling is not measured, and squad-size independence is untestable here because every run is solo.",
        next_action="Deploy the same archetype on Easy and Extreme and confirm HP tracks difficulty only.",
    ),
    "S06-032": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=f"{ENEMIES}",
        last_verified_build="441", evidence_ref=V441,
        blocker_or_defect="Archetype base stats were realigned to spec at build 441, but the (HP, damage, attack cadence, reinforcement pressure) modifier table per difficulty was not exercised; only Normal runs exist.",
        next_action="Record one archetype's HP, damage and cadence on all four difficulties and compare against the table.",
    ),
    "S06-033": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=f"{ESVC}",
        last_verified_build="444", evidence_ref=V444,
        blocker_or_defect="The Heavy's warning is 1.4 s and is measured (GF_LastCharge = 'Heavy:1.4', ChargingUntil set then expiring 2 s later), which clears the 0.9 s floor. The Marksman's minimum warning was never measured, and cadence under difficulty pressure was not tested.",
        next_action="Measure the Marksman telegraph on Extreme and confirm it never drops below 0.9 s.",
    ),
    "S06-057": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=f"{ESVC}",
        last_verified_build="444", evidence_ref=V444,
        blocker_or_defect="Telegraph-then-damage is demonstrated for the Heavy: a 1.4 s charge followed by two measured 32.0 damage events. Weighted move selection with no immediate repeat is not demonstrated, and only one archetype was observed attacking.",
        next_action="Record three consecutive Heavy attacks and confirm no immediate repeat, then repeat for Veyr's three moves.",
    ),
    "S06-052": dict(
        status="PARTIAL", observed_count="3200",
        implementation_path=f"{VEYR}; {WALKER}",
        last_verified_build="385", evidence_ref=V385,
        blocker_or_defect=f"DEFECT: Veyr spawned at Health 3200 where {SPEC} L102 sets base 7200. Even at Normal, solo, unscaled, the formula HPbase*difficultyHP*(1+0.45*(P-1)) gives 7200. The 3200 reading predates the build-441 stat realignment and Veyr's base was never re-measured, so the current value is unknown rather than proven wrong. The freeze-until-fight-end clause is untested and the 1+0.45*(P-1) scaling is untestable solo.",
        next_action="Read Veyr's configured base HP, compare against 7200, fix if short, then confirm the value does not change mid-fight.",
    ),
    "S06-061": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=WALKER,
        last_verified_build="461", evidence_ref=V461,
        blocker_or_defect=f"BastionWalker exists as a real Workspace model and is a required objective in Siege Breaker, but {SPEC} L101 specifies base 3600 HP plus destructible components (two leg actuators 400 each, cannon housing 550 with a 40% sweep-damage reduction). None of the component HP or the component effects is measured.",
        next_action="Destroy one leg actuator and confirm walk speed drops, then destroy the cannon housing and confirm sweep damage falls 40%.",
    ),
    "S06-059": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=VEYR,
        last_verified_build="385", evidence_ref=V385,
        blocker_or_defect="Thronefall requires the Veyr kill before the command node completes, which matches 'major Veyr required in boss operations'. The 'optional Walker elsewhere' half is unverified: Walker has only been seen as a required Siege Breaker target, never as an abandonable field boss.",
        next_action="Spawn Walker as an optional field boss and confirm extraction is possible without defeating it.",
    ),
    "S06-060": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=VEYR,
        last_verified_build="385", evidence_ref=V385,
        blocker_or_defect="Thronefall ran as staged kills with no invulnerable phase: 3 guards, then Veyr spawns and dies, then the node completes at stage 3. That is consistent with the requirement, but it was observed once and the two pylons (350 HP each, +5% resistance up to 10%) were never exercised.",
        next_action="Destroy both pylons and confirm resistance rises to 10% without any invulnerable window appearing.",
    ),
    "S06-065": dict(
        status="PARTIAL", observed_count="3200",
        implementation_path=VEYR,
        last_verified_build="385", evidence_ref=V385,
        blocker_or_defect=f"DEFECT: measured Health 3200 against {SPEC} L102 base 7200 during the Thronefall clear. The named warlord, its spawn stage and its defeat-before-completion all work; the HP is the mismatch. Its three attacks (3x22 volley, 65 beam, 50 shockwave), the two 350 HP pylons and the below-50% aggression change are all unmeasured.",
        next_action="Reconcile Veyr's base HP to 7200 (or record the deviation), then measure all three attacks and the sub-50% cadence change.",
    ),
    "S06-072": dict(
        status="PARTIAL", observed_count="3",
        implementation_path="ServerScriptService.GF.Services.LootService",
        last_verified_build="", evidence_ref=HANDOFF,
        blocker_or_defect=f"DEFECT / deviation: {SPEC} L102 specifies guaranteed blueprint pity at 5 qualifying extracted boss kills with a 15%/kill earlier success chance. HANDOFF records the implementation at 3 clears '(was 5)' and reports it in the debrief. It is deterministic under GF_ForceNoBlueprintChance, but 3 is a spec change that no decision record authorises.",
        next_action="Either restore pity to 5 or record the owner's approval of 3 in DECISIONS.md; also verify the 15%/kill early chance and that owned blueprints stop dropping.",
    ),
    "S04-046": dict(
        status="PARTIAL", observed_count="18",
        implementation_path="ReplicatedStorage.GF.Shared.Configs.Weapons; ReplicatedStorage.GF.Shared.Configs.Enemies; ServerScriptService.GF.Services.CombatService",
        last_verified_build="461", evidence_ref=V441,
        blocker_or_defect="AR-01 body damage 18 and the 90/240 @ 0.55 falloff curve are measured. The 320 health+shield target is now confirmed as authored and configured: v441 realigned Rifleman to 240 HP + 80 shield = 320 exactly. What is still unmeasured is the 18-shot / 1.7 s time-to-kill itself.",
        next_action="Spawn one Rifleman, fire 18 body shots at 600 RPM, and record elapsed time, shield and health.",
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
        is_correction = rid.startswith("S04-")
        if current != "UNKNOWN" and not is_correction:
            print(f"SKIP {rid}: status is {current}", file=sys.stderr)
            continue
        for key, value in upd.items():
            if key not in fieldnames:
                print(f"ERROR: unknown column {key}", file=sys.stderr)
                return 1
            row[key] = value
        print(f"  {rid:14} {current:8} -> {upd['status']}")
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
