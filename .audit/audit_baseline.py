"""Fill REQUIREMENT_COVERAGE.csv with the observed baseline from the 2026-11-23 audit.

Every value here comes from tool output in this session:
  - Edit-mode inventory (configs, services, client scripts, code keyword hits, workspace part counts)
  - Play-mode runtime inventory (station parts above Y700, non-player humanoids, PlayerGui label/button counts)
  - Four screen captures (station spawn, mission landing, outpost relay)
No value is guessed. Where a feature exists in code but was not demonstrated, status is
IMPLEMENTED_UNPROVEN and present_count is 0.
"""
import csv
import datetime
from collections import Counter

SRC = "REQUIREMENT_COVERAGE.csv"
A = "ABSENT"
P = "PARTIAL"
U = "IMPLEMENTED_UNPROVEN"
N = "NOT_AUDITED"

rows = list(csv.DictReader(open(SRC, encoding="utf-8")))
FIELDS = list(rows[0].keys())

obs = {
    "LC-001": (1, P, "Only SABOTAGE_RELAY is selectable; deploy options expose one template"),
    "LC-002": (1, P, "4 hostiles spawned, all EnemyId=Rifleman; Marksman/Heavy/Officer never spawn"),
    "LC-003": (0, A, "No Bastion Walker code or spawn"),
    "LC-004": (0, A, "No High Marshal Veyr code or operation"),
    "LC-005": (1, P, "AR-01 fired live; SG-04/MR-07/LMG-12/ER-16 exist only as config rows, never equipped"),
    "LC-006": (0, U, "P-01 in config and loadout defaults; never equipped or fired"),
    "LC-007": (0, A, "No grenade implementation"),
    "LC-008": (2, P, "Airstrike and Dome verified with cooldowns; Sentry and Orbital absent"),
    "LC-009": (0, A, "Classes config exists; no service applies class passives"),
    "LC-010": (0, A, "Augments config exists; no slot, no modifier, no UI"),
    "LC-011": (0, P, "Salvage counters exist and are awarded on extraction; no world pickups observed"),
    "LC-012": (1, P, "Credits/XP/rank persist; no purchase, no mastery, no research"),
    "LC-013": (2, P, "Easy/Normal selectable; Hard/Extreme not exposed and no scaling content"),
    "LC-014": (0, A, "Station is a flat blue floor + black void; no windows, planet, traffic; crew unanimated"),
    "LC-015": (0, A, "No armory UI at all"),
    "LC-016": (0, P, "War Table is a text panel; one operation; no planetary state"),
    "LC-017": (0, A, "No tactical map"),
    "LC-018": (0, A, "No Priority Dispatch"),
    "LC-019": (0, A, "No matchmaking or mid-mission join"),
    "LC-020": (1, P, "Solo only; no multi-client session"),
    "LC-021": (0, A, "No cinematic code"),
    "LC-022": (0, A, "No tutorial code"),
    "LC-023": (0, P, "Dropship + boarding + complete state exist; no vote, no failure branch, no departure"),
    "LC-024": (0, P, "28 HUD labels + 12 buttons across 4 screens; no icons, map or settings"),
    "LC-025": (0, A, "No gamepad-only path; no touch UI verified"),
    "LC-026": (0, A, "No controller focus system"),
    "LC-027": (0, A, "No gamepad parity"),
    "LC-028": (0, A, "No touch parity or safe-area layout"),
    "LC-029": (0, A, "Blue part-stack characters, cylinder relay, flat pads; blockout only"),
    "LC-030": (0, P, "Server-authoritative combat verified; no matchmaking, no shared war state"),
    "LC-031": (0, A, "No device/hardware performance evidence"),
    "EXT-001": (1, P, "Solo deploy works"),
    "EXT-002": (0, A, "No extraction vote"),
    "EXT-003": (0, A, "No soft-timer emergency extraction"),
    "EXT-004": (1, P, "Seeded terrain exists; one seed used, no validation pass"),
    "EXT-005": (0, A, "Single biome; no microregion variants"),
    "EXT-006": (1, P, "Shield-then-health damage verified"),
    "EXT-007": (1, P, "Two charges + recharge verified; no roll animation"),
    "EXT-008": (0, A, "No shop, no affordability curve"),
    "EXT-009": (0, A, "No boss, no pity"),
    "EXT-010": (0, A, "War table shows static text, not campaign state"),
    "EXT-011": (0, A, "No late join"),
    "EXT-012": (1, P, "DataStore profile with retry exists; migration unverified"),
    "EXT-013": (0, A, "No Voss dialogue system, no subtitles"),
    "EXT-014": (0, A, "No hardware profiling"),
    "EXT-015": (0, A, "No viewing windows"),
    "EXT-016": (0, P, "War table opens/closes; no Back/focus contract, no other terminals"),
    "EXT-017": (0, A, "One objective mechanic only"),
    "EXT-018": (0, A, "No touch layout"),
    "EXT-019": (0, A, "No teleport/reserved-server path"),
    "EXT-020": (0, N, "Owner approval is an owner action"),
    "EXT-021": (1, P, "4 captures taken this session; VISUAL_REVIEW.md written"),
    "EXT-022": (0, A, "Blockout assets in the live scene"),
    "EXT-023": (0, P, "Claims cite captures/console; MCP returns images inline, no files on disk"),
    "EXT-024": (0, N, "Owner review not yet requested for a milestone"),
}

micro = {}


def setr(lo, hi, present, status, note):
    for i in range(lo, hi + 1):
        micro["MICRO-%03d" % i] = (present, status, note)


setr(1, 5, 0, A, "Spawn view is a blue floor and black void; no window, planet, beacons or flyby")
micro["MICRO-006"] = (0, P, "War table is a raised pad with a text panel; no holographic planet")
micro["MICRO-007"] = (0, P, "Panel opens the operation selector; no hologram animation")
setr(8, 10, 0, A, "No armory, dispatch alcove or deployment bay geometry")
micro["MICRO-011"] = (0, P, "5 non-player humanoids exist; animation not verified")
micro["MICRO-012"] = (1, P, "Crew separate from players and non-blocking")
setr(13, 16, 0, P, "Emissive strips on plain parts; no ribs, decals, signage or distinct materials")
micro["MICRO-017"] = (1, P, "War table opens and closes immediately")
micro["MICRO-018"] = (0, P, "Mouse/keyboard works; controller Back/Cancel untested")
setr(19, 20, 0, A, "No space visuals; hull containment unverified")
setr(21, 23, 0, A, "Player and enemies are default-avatar part stacks, not rigged soldier/alien meshes")
setr(24, 26, 0, A, "No animation blending, no hand-aligned weapons, no muzzle transform")
micro["MICRO-027"] = (1, P, "Firing verified with hitscan and impact audio; no recoil model")
setr(28, 29, 0, P, "Ammo and reload work; no dry-fire cue, no per-gun feel")
micro["MICRO-030"] = (1, P, "Shield absorb and Shield attribute verified; break VFX unverified")
setr(31, 33, 0, P, "Regen and downed state exist; no prompt/ring/revive alignment")
micro["MICRO-034"] = (1, P, "Solo redeploy verified returning to the LZ")
setr(35, 39, 0, P, "Line-of-sight damage works; no scout transmit, marksman beam, heavy telegraph or death anim")
micro["MICRO-040"] = (1, P, "Airstrike and Dome recharge repeatedly")
setr(41, 45, 0, A, "No airstrike aircraft, dome collision rules, sentry, orbital strike or grenades")
setr(46, 49, 0, P, "Terrain exists but reads blue/green plastic; scatter not terrain-logical")
micro["MICRO-050"] = (0, P, "Landing pad has a relay sightline; no second approach route verified")
setr(51, 53, 0, P, "Relay exists as a cylinder stack; no wreck, no beacon, no iconic silhouettes")
setr(54, 55, 0, P, "Objective state is server-driven; no map")
micro["MICRO-056"] = (0, A, "No in-world salvage pickups observed")
setr(57, 59, 0, P, "Patrols spawn at the outpost; no reinforcement audio/location cues")
setr(60, 63, 0, P, "LZ, dropship and boarding exist; no dust, ramp animation or authored vehicle")
micro["MICRO-064"] = (1, P, "Single-player extraction secures salvage and payout")
setr(65, 67, 0, A, "No wipe branch, no emergency extraction, no departure cinematic")
micro["MICRO-068"] = (1, P, "Debrief shows credits/xp/salvage lines")
micro["MICRO-069"] = (0, A, "No device glyph system")
micro["MICRO-070"] = (0, A, "No cinematic")
micro["MICRO-071"] = (0, A, "No intro flag or Archive")
setr(72, 73, 0, P, "One operation; Easy/Normal only, no lock explanation")
setr(74, 79, 0, A, "No squad, matchmaking, dispatch or vote")
micro["MICRO-080"] = (1, P, "Profile persists across restarts; mastery absent")
micro["MICRO-081"] = (0, A, "No mastery socket")
micro["MICRO-082"] = (0, A, "No boss pity")
setr(83, 84, 0, P, "Two abilities equip and recharge; classes inert")
micro["MICRO-085"] = (0, A, "No armory actions")
micro["MICRO-086"] = (0, P, "War table closes; no per-screen Back contract")
setr(87, 91, 0, A, "No glyph switching, touch layout, focus system or settings persistence UI")
micro["MICRO-092"] = (0, A, "War table prints 'SECTOR CONTESTED' as static text with no campaign source")
setr(93, 94, 0, P, "Server validates fire and ammo; idempotent reward IDs unverified")
setr(95, 100, 0, A, "No multiplayer, hardware proof, mobile playtest, controller flow or release checklist")

now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
out_rows = []
for r in rows:
    rid = r["id"]
    if rid in obs:
        present, status, note = obs[rid]
    elif rid in micro:
        present, status, note = micro[rid]
    else:
        present, status, note = 0, A, "Not found in audit"
    r["present_count"] = str(present)
    r["status"] = status
    r["supporting_evidence"] = note
    if status != N:
        r["next_action"] = "Close gap: " + note
    r["last_reviewed"] = now
    r["owner_decision"] = "PENDING"
    out_rows.append(r)

with open(SRC, "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=FIELDS)
    w.writeheader()
    w.writerows(out_rows)

counts = Counter(r["status"] for r in out_rows)
groups = {}
for r in out_rows:
    groups.setdefault(r["id"].split("-")[0], Counter())[r["status"]] += 1

L = []
L.append("# REQUIREMENT COVERAGE — GALACTIC FORCE: COUNTEROFFENSIVE")
L.append("")
L.append("Ledger: `REQUIREMENT_COVERAGE.csv` (155 rows). Audited **%s** against Studio `Playtest1`" % now)
L.append("(placeId 120646942844931, universe 10778576038, saved version 73).")
L.append("")
L.append("No row is GREEN. `OWNER_ACCEPTED` requires the owner (V3-12).")
L.append("")
L.append("## Totals")
L.append("")
L.append("| Status | Rows |")
L.append("|---|---:|")
for k in ["ABSENT", "PARTIAL", "IMPLEMENTED_UNPROVEN", "NOT_AUDITED", "EXTERNAL_BLOCKER", "FUTURE_SPEC_ONLY"]:
    if counts.get(k):
        L.append("| %s | %d |" % (k, counts[k]))
L.append("| **total** | **%d** |" % len(out_rows))
L.append("")
L.append("## By group")
L.append("")
L.append("| Group | Rows | ABSENT | PARTIAL | IMPLEMENTED_UNPROVEN |")
L.append("|---|---:|---:|---:|---:|")
for g in ["LC", "EXT", "MICRO"]:
    cc = groups.get(g, Counter())
    L.append("| %s | %d | %d | %d | %d |" % (g, sum(cc.values()), cc.get("ABSENT", 0), cc.get("PARTIAL", 0), cc.get("IMPLEMENTED_UNPROVEN", 0)))
L.append("")
L.append("## Launch inventory (LC-001..LC-031)")
L.append("")
L.append("| ID | Requirement | Req | Have | Status | Basis (observed this session) |")
L.append("|---|---|---:|---:|---|---|")
for r in out_rows:
    if r["id"].startswith("LC-"):
        req = r["requirement"].replace("|", "/")[:64]
        basis = r["supporting_evidence"].replace("|", "/")
        L.append("| %s | %s | %s | %s | %s | %s |" % (r["id"], req, r["required_count"], r["present_count"], r["status"], basis))
L.append("")
L.append("## Reading")
L.append("")
L.append("- **0 of 31** launch obligations complete. Two have real function behind them")
L.append("  (Airstrike/Dome with cooldowns; the solo deploy-to-payout loop). The rest are absent")
L.append("  or a single stand-in instance.")
L.append("- Station, armory, tactical map, Priority Dispatch, matchmaking, cinematic, tutorial and the")
L.append("  shared Galactic War have **no code**: keyword hits for each were 0 across")
L.append("  `ReplicatedStorage` and `ServerScriptService`.")
L.append("- The station spawn frame shows a blue floor and a black void with cyan strips; the mission")
L.append("  frame shows blue/green terrain, blue boulder meshes and a cylinder-stack relay; every")
L.append("  character is a default-avatar part stack. See `VISUAL_REVIEW.md`.")
L.append("")
open("REQUIREMENT_COVERAGE.md", "w", encoding="utf-8").write("\n".join(L) + "\n")

print("rows:", len(out_rows))
print("status:", dict(counts))
print("groups:", {g: dict(c) for g, c in groups.items()})
