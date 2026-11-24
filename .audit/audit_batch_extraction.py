"""Audit batch 3: Extraction / settlement.

Mapped from evidence/v412, v413, v416, v438, v439. Only rows with an actual
measurement are touched; rows with no evidence (voting, mastery settlement) are
deliberately left UNKNOWN rather than guessed into PARTIAL.

Run: python .audit/audit_batch_extraction.py
"""
import csv
import sys

CSV = "REQUIREMENT_COVERAGE.csv"

EXT = "ServerScriptService.GF.Services.ExtractionService"
REW = "ServerScriptService.GF.Services.RewardsService"
WAR = "ServerScriptService.GF.Services.GalacticWarService"
OBJ = "ServerScriptService.GF.Services.ObjectiveService"
HUD = "StarterPlayer.StarterPlayerScripts.MissionHUD"

V412 = "evidence/v412-failure-evac/EVIDENCE.md"
V413 = "evidence/v413-failed-settlement/EVIDENCE.md"
V416 = "evidence/v416-difficulty/EVIDENCE.md"
V438 = "evidence/v438-debrief/EVIDENCE.md"
V439 = "evidence/v439-salvage-bonus/EVIDENCE.md"

UPDATES = {
    "S09-010": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=f"{EXT}; {REW}; {HUD}",
        last_verified_build="439", evidence_ref=V439,
        blocker_or_defect="The +25% full-squad bonus is measured in the settlement payload and rendered by the debrief, but the extraction button itself was never checked: nothing shows the boarded count or the bonus text on the button, and every run so far has been solo.",
        next_action="Read the extraction button label with 1 and with 4 boarded and confirm the boarded count and the 25% bonus are stated before the press.",
    ),
    "S09-022": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=f"{EXT}; {REW}",
        last_verified_build="413", evidence_ref=V413,
        blocker_or_defect="A full failed round trip settles as failure: board with the objective incomplete yields credits 0, xp 0, rankUps 0 and salvage 0/0/0, and GF_CarriedLost reads true. Unsecured cache and blueprint loss are not demonstrated, and only a solo squad was used.",
        next_action="Carry a cache and a blueprint into a failed extraction and confirm both are lost, with a squad present so the eligible-set rule is exercised.",
    ),
    "S09-029": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=f"{REW}; {HUD}",
        last_verified_build="439", evidence_ref=V438,
        blocker_or_defect="The debrief now shows success/failure, the primary result, the extraction result and base vs bonus for credits, XP and salvage. A 'pending recovery' state is not implemented or rendered, so settlement is not described while the squad outcome is still unknown.",
        next_action="Add a pending-recovery line to the debrief for an unsettled squad and verify it resolves once on outcome.",
    ),
    "S09-031": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=f"{EXT}; {REW}",
        last_verified_build="416", evidence_ref=V416,
        blocker_or_defect="With a failed extraction the mission cache is skipped (GF_MissionCacheResult = 'skipped success=false objective=false', zero cache opens) and GF_CarriedLost is true. That covers a squad that lost and boarded; the 'nobody extracts at all' branch is a different code path and is unmeasured.",
        next_action="Let the emergency countdown expire with nobody committed and confirm unsecured salvage and the mission cache are both lost.",
    ),
    "S09-033": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=f"{REW}",
        last_verified_build="439", evidence_ref=V413,
        blocker_or_defect="Open defect: this requirement says rank XP and Credits earned from completed tasks, kills and participation survive failure. Measured on a failed run the settlement is credits 0, xp 0, salvage 0/0/0, and the failed debrief reads 'Credits base 0' / 'Military XP base 0'. Base is computed from difficulty, success and objectiveComplete only, so nothing accrues from participation or kills and none of it survives. Not cosmetic: a lost mission currently pays nothing at all.",
        next_action="Accrue participation/kill XP and credits into a separate earned bucket that is granted regardless of extraction success, then re-run a failed mission and read the debrief.",
    ),
    "S09-035": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=f"{WAR}; {EXT}",
        last_verified_build="413", evidence_ref=V413,
        blocker_or_defect="Open defect: the requirement commits war points once at primary success, independent of extraction. The measured path calls GalacticWarService.recordMission(template, success) from inside ExtractionService.finish(), so the commitment happens at extraction and carries the extraction outcome. v413 also records that the campaign total on a loss was never read back.",
        next_action="Move the war-point commitment to the primary-success transition, then lose a mission after a completed primary and confirm the commitment still stands.",
    ),
    "S09-038": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=f"{OBJ}; {REW}",
        last_verified_build="413", evidence_ref=V413,
        blocker_or_defect="Boss blueprint pity exists, is deterministic under GF_ForceNoBlueprintChance and is reported in the debrief, but the requirement conditions it on a qualifying boss kill FOLLOWED BY the player's extraction. The extraction gate on pity advancement is not demonstrated.",
        next_action="Kill a qualifying boss, fail the extraction, and confirm pity did not advance; then extract and confirm it did.",
    ),
    "S09-039": dict(
        status="PARTIAL", observed_count="0",
        implementation_path=f"{REW}",
        last_verified_build="439", evidence_ref=V439,
        blocker_or_defect="The fail half is measured: a failed run reports squad bonus 0 for credits, XP and salvage. The disconnect half (no bonus for a player who disconnects) is untested, and no squad beyond solo was used.",
        next_action="Disconnect one player of four mid-mission and confirm their settlement carries no squad bonus.",
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
