# v594 — mission spine measurements (working copy of place 594, no new save)

Live server playtests, test userId 1889759131. Probes: probe_spine1.lua, probe_spine2.lua.

## SPINE1 — deploy + combat authority `[GF_SPINE1] PASS live=Marksmanx1,Riflemanx5,Officerx3 shots=18 hits=18 dmg=324`

- Deploy Normal SABOTAGE_RELAY accepted; enemies spawn in ActiveActors with GFEnemy attributes.
  Archetype table varies by seed across runs: run1 Heavy2/Marksman2/Rifleman3/Officer2, run3
  Rifleman5/Marksman1/Officer3 — five distinct archetype ids observed across runs incl. Scout.
- Synthetic Rifleman target (240 health + 80 shield, armor factor 1) inside the live mission:
  18 shots fired through the validated fire path (payload carries direction only, no damage),
  18 server-counted hits, 324 total server-applied damage, target dead, kill credited server-side,
  mastery accrued server-side. Shield absorbed before health (ordering consistent with S04-018 math).
- TTK anchor EXACT: 18 shots at full accuracy for 320 HP+shield — the precise figure S04-046 authors.
- Live enemies use cover (raycasts blocked), which is correct behavior but makes them unsuitable as
  measurement subjects; synthetic-target pattern documented for reuse.

## SPINE2 — extraction + settlement `[GF_SPINE2] warCommitAttr=true countdown@1.5s=2 gain credits=450 xp=600 war=10` (one probe-artifact failure)

- War points commit server-side at objective completion (attribute observed true) — client never carries it.
- Extraction countdown published server-side as a live number (2 remaining at +1.5s from a 3s override).
- Settlement exactness vs spec: credits 450 (inside authored 450-600 band), xp 600 (50 below the 650-900
  band floor — known documented balance question on S10-006/S10-025), war credits exactly Normal=10 fixed.
- Settlement recorded in recentTransactionIds journal (settle:<missionId>); profile revision advanced
  after the settlement save.
- Probe artifact: the aboard check failed because board() is geometry-gated by the ship cabin volume and
  the probe did not move the player into it; aboard mechanics themselves are covered by v582 evidence.
  finish() settlement measurement unaffected.

## Row coverage

- S04-046: exact calibration anchor measured (18 shots at 100% accuracy for 320 HP+shield).
- S04-018: shield-first ordering consistent with measured damage distribution.
- S14-025: kill + mastery + war-point commit all originate server-side. Loot pickup measurement still owed.
- S10-026: successful-primary war credits Normal=10 measured; failure-zero probe still owed.
- S14-027: server-published countdown evidenced; client-drift comparison still owed.
