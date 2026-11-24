# Weapon fire verified end to end (build 457)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## Why this mattered
Every elimination kill in the last two batches was applied through `CombatService.damageEnemy` — the API, not a weapon. So the path players actually use (client `FireWeapon` → server validation → raycast → damage → feedback) had not been exercised.

## The path, exercised
Six `FireWeapon` calls from the client at a 21-stud clear line on an **Officer**:

| Reading | Value |
|---|---|
| Server ammo updates received | 6 (`ammo 27 → 22`, six distinct values) |
| `DamageFeedback` events on the client | **6** |
| Officer shield | **160 → 120.4** |
| Damage per shot | **6.6** |

6.6 matches the composition the code claims: AR-01 base 8, multiplied by the Officer's `ArmorFactor 0.9` (= 7.2), reduced by linear falloff at 21 studs (~0.92). Three systems (weapon damage, armour factor, falloff) compounding correctly.

Rejections were exercised implicitly: an earlier volley at the station fired into a hangar wall 5 studs away — ammo still decremented (the shot is accepted) but no damage was applied, which is the correct hitscan behaviour.

## Two harness errors I made getting here
1. **`GF_DeployGraceUntil` set from the Client does not replicate.** The player died, respawned at the station, and my shots went into the station deck 748 studs from the target. Positioning and grace must be set from the **Server** datamodel — this is the fourth time this exact mistake has produced a false reading.
2. **Line of sight has to be checked, not assumed.** A 15-stud target was behind `AscendancyOutpostWall`. I now pick the target by *finding an enemy whose raycast first-hit is itself*.

## Limits
- One weapon (AR-01), one archetype (Officer), one range (21 studs), six shots.
- Aim spread and recoil are not modelled in this test — the client supplies the direction, so this proves the server path, not the client's aiming feel.
- Shotgun pellets, explosives, weak points and friendly fire are untouched.
- No reload cycle, no ammo depletion, no dry-fire.
