"""Audit batch: Combat / weapons data-table and fire-path conformance.

Populates the UNKNOWN combat rows from evidence already on disk (62 evidence dirs).
Every status below cites a measurement in evidence/, not the presence of a script.
Run: python .audit/audit_batch_combat.py
"""
import csv
import sys

CSV = "REQUIREMENT_COVERAGE.csv"

WEAPONS = "ReplicatedStorage.GF.Shared.Configs.Weapons"
ENEMIES = "ReplicatedStorage.GF.Shared.Configs.Enemies"
CLASSES = "ReplicatedStorage.GF.Shared.Configs.Classes"
DIFFS = "ReplicatedStorage.GF.Shared.Configs.Difficulties"
COMBAT = "ServerScriptService.GF.Services.CombatService"
ARMORY = "ServerScriptService.GF.Services.ArmoryService"
CLASSSVC = "ServerScriptService.GF.Services.ClassService"
WPNCLIENT = "StarterPlayer.StarterPlayerScripts.Weapon"

V402 = "evidence/v402-weapons/EVIDENCE.md"
V416 = "evidence/v416-difficulty/EVIDENCE.md"
V457D = "evidence/v457-weapon-data/EVIDENCE.md"
V457F = "evidence/v457-weapon-fire/EVIDENCE.md"
V460 = "evidence/v460-falloff-bug/EVIDENCE.md"
V461 = "evidence/v461-falloff-verified/EVIDENCE.md"

UPDATES = {
    "COUNT-DIFF": dict(
        status="VERIFIED", observed_count="4",
        implementation_path=f"{DIFFS}; {COMBAT.replace('CombatService', 'StationService')}.deploy",
        last_verified_build="416", evidence_ref=V416,
        blocker_or_defect="",
        next_action="Easy was never deployed in the measuring session (Normal 600, Extreme 650 generator HP); capture Easy before beta.",
    ),
    "COUNT-SECONDARY": dict(
        status="VERIFIED", observed_count="1",
        implementation_path=f"{WEAPONS} (P01); {ARMORY}",
        last_verified_build="402", evidence_ref=V402,
        blocker_or_defect="",
        next_action="Fire P-01 through a full magazine and reload in a mission; only catalogue and equip are measured.",
    ),
    "COUNT-CLASS": dict(
        status="IMPLEMENTED_UNVERIFIED", observed_count="4",
        implementation_path=f"{CLASSES}; {CLASSSVC}",
        last_verified_build="", evidence_ref="",
        blocker_or_defect="Four classes exist in config and ClassService, but no capture or measurement exercises a personal or squad passive. v417 records class fields as copied but unverified.",
        next_action="Fire and heal under each class, read the aura/stat effect, and confirm a squad-mate receives the aura once.",
    ),
    "S04-034": dict(
        status="VERIFIED", observed_count="8",
        implementation_path=f"{WEAPONS}; {ARMORY}",
        last_verified_build="457", evidence_ref=V402,
        blocker_or_defect="GOAL.md L21 names ER-16 as one of the five primaries. ER-16 was removed at build 402 and SMG-03 stands in its place; the authored arsenal list at GOAL.md L393-397 names neither. Two spec sections disagree with each other, so this needs an owner decision, not an agent edit.",
        next_action="Owner resolves the ER-16 vs SMG-03 naming conflict. Roster count (5 standard + 2 requisition + 1 secondary) is otherwise demonstrated.",
    ),
    "S04-035": dict(
        status="PARTIAL", observed_count="8",
        implementation_path=f"{WEAPONS}; {WPNCLIENT}",
        last_verified_build="457", evidence_ref=V457F,
        blocker_or_defect="Only the fire path for AR-01 is proven. Distinct silhouettes, fire/ADS/reload animations and per-weapon muzzle reports are not captured, and launchers are hitscan-with-blast rather than ballistic.",
        next_action="Capture each weapon's model, muzzle and fire animation, and record one report per weapon category.",
    ),
    "S04-036": dict(
        status="PARTIAL", observed_count="8",
        implementation_path=WEAPONS,
        last_verified_build="461", evidence_ref=V461,
        blocker_or_defect="The data table carries damage, rpm, magazine, reserve, reloadTime, falloffStart/falloffEnd and falloffMin, but has no aimed-spread field at all (only spreadBase and adsZoom). 'Aimed spread degrees' is therefore absent from the authored data.",
        next_action="Add an authored ADS/aimed spread value per weapon and verify the aimed grouping in play.",
    ),
    "S04-046": dict(
        status="PARTIAL", observed_count="18",
        implementation_path=f"{WEAPONS}; {ENEMIES}; {COMBAT}",
        last_verified_build="461", evidence_ref=V461,
        blocker_or_defect="AR-01 body damage 18 and the 90/240 @ 0.55 falloff curve are measured. Normal infantry health+shield = 320 and the 18-shot / 1.7 s time-to-kill were never measured.",
        next_action="Spawn one Normal infantry, fire 18 body shots at 600 RPM, and record elapsed time, shield and health.",
    ),
    "S04-047": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=f"{WEAPONS}; {COMBAT}",
        last_verified_build="461", evidence_ref=V457D,
        blocker_or_defect="SMG-03 computes 184.17/s and LMG-12 187.0/s from config, matching spec arithmetic, but neither sustained rate is measured in play. GL-22/RL-09 are hitscan-with-blast, so authored projectile speed, gravity and the 2 s fuse are not modelled.",
        next_action="Measure sustained SMG and LMG DPS on a fixed target, then decide whether launchers need travelling projectiles.",
    ),
    "S04-048": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=COMBAT,
        last_verified_build="457", evidence_ref=V402,
        blocker_or_defect="The server raycast is a swept segment with no per-round physical part, which satisfies the anti-pattern clause. However launchers do not travel: 'projectile explodes on valid collision or lifetime' is unimplemented for GL-22 and RL-09.",
        next_action="Either implement travelling projectiles with collision/lifetime detonation, or record the simplification as an owner-accepted defect.",
    ),
    "S04-025": dict(
        status="PARTIAL", observed_count="28",
        implementation_path=COMBAT,
        last_verified_build="460", evidence_ref=V460,
        blocker_or_defect="One reload returned the magazine 25 -> 28 with a single AmmoUpdated. Reserve subtraction and the n = min(capacity-mag, reserve) branch with a partly empty magazine are unmeasured.",
        next_action="Fire to a partial magazine, reload, and read reserve before and after to confirm n.",
    ),
    "S04-026": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=COMBAT,
        last_verified_build="460", evidence_ref=V460,
        blocker_or_defect="Manual reload verified: 1.88 s elapsed against 2.1 s configured, difference attributed to a class/augment factor that was not decomposed. Empty auto-reload, switch-cancels-reload and the 0.4 s swap are unmeasured.",
        next_action="Empty the magazine to confirm auto-reload, then swap weapons mid-reload to confirm the cancel.",
    ),
    "S04-014": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=COMBAT,
        last_verified_build="", evidence_ref=V461,
        blocker_or_defect="Open discrepancy: GOAL.md/spec requires head or marked weakpoint x1.5, but the note in v461-falloff-verified records the function as reading a 2x head multiplier. Neither value was fired, so which is live is unconfirmed.",
        next_action="Read the multiplier constant in CombatService and fire one measured headshot; reconcile 1.5 vs 2x against the spec.",
    ),
    "S04-008": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=f"{WPNCLIENT}; {COMBAT}",
        last_verified_build="457", evidence_ref=V457F,
        blocker_or_defect="The server accepts a client-supplied direction and traces to damage, but the right-shoulder parallax aim-ray point selection is not verified, and the test does not model client aim or spread.",
        next_action="Verify the camera aim ray selects the reported world point and that the server traces from the validated muzzle to it.",
    ),
    "S04-030": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=COMBAT,
        last_verified_build="457", evidence_ref=V457F,
        blocker_or_defect="The client supplies direction only and the server recomputes damage from config, armour and falloff, so the design is correct. No test forges a target or a damage value, so the rejection path itself is unproven.",
        next_action="Send a forged hit target and a forged damage value from the client and confirm both are rejected with telemetry.",
    ),
}


def main() -> int:
    with open(CSV, encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh)
        fieldnames = reader.fieldnames
        rows = list(reader)

    seen = set()
    changed = 0
    for row in rows:
        rid = row["requirement_id"].strip()
        upd = UPDATES.get(rid)
        if not upd:
            continue
        seen.add(rid)
        before = row["status"].strip()
        for key, value in upd.items():
            if key not in fieldnames:
                print(f"ERROR: unknown column {key}", file=sys.stderr)
                return 1
            row[key] = value
        print(f"  {rid:16} {before:24} -> {upd['status']}")
        changed += 1

    missing = sorted(set(UPDATES) - seen)
    if missing:
        print(f"ERROR: rows not found: {missing}", file=sys.stderr)
        return 1

    with open(CSV, "w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames, lineterminator="\r\n")
        writer.writeheader()
        writer.writerows(rows)

    print(f"\nupdated {changed} row(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
