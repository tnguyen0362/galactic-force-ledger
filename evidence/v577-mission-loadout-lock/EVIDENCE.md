# place 577 — mission loadout lock

Before this change, `ArmoryService.handleSet` accepted equip/class/augment changes from a player already deployed. The remote stayed callable mid-mission, so a deploy loadout could be changed after the lock.

`ArmoryService.handleSet` now rejects these `MISSION_LOCKED_ACTIONS` when `StationService.zoneOf(player) == "Mission"`, with the reason `"loadout locked during mission"`:
`equip`, `equipAbility`, `equipGrenade`, `equipArmor`, `loadLoadout`, `class`, `augment`, `augmentRerollAccept`.

Probe: a temporary real-server Script deployed the player, attempted a class change, returned to the station, and retried.

```text
[GF] boot: config check PASS (688 assertions)
[GF_LOCK] PASS deploy=true zoneMission=loadout locked during mission station="" class=Assault
```

Not yet verified: the squad countdown snapshot itself (S02-031) and auto-closing station UI views at transition.
