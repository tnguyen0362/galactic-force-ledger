# Weapon roster to spec + area launchers (build 402)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## Roster now matches the authored seven-plus-sidearm
| Slot | Weapon | Notes |
|---|---|---|
| Standard primary | AR-01 Service Rifle | unchanged |
| Standard primary | SMG-03 Jackal (`SMG03`) | new, spec stats: D 13, 850 rpm, 36/216, reload 1.7, falloff 45–150, rank 1, 600 cr |
| Standard primary | SG-04 Breacher | unchanged |
| Standard primary | MR-07 Ranger | unchanged |
| Standard primary | LMG-12 Suppressor | unchanged |
| Requisition primary | GL-22 Arcus (`GL22`) | new, D 110, 4/16, area radius 9, rank 4, 1200 cr |
| Requisition primary | RL-09 Atlas (`RL09`) | new, D 205, 1/7, area radius 12, rank 7, 1500 cr |
| Sidearm | P-01 Service Pistol | unchanged |

`ER16` (human energy rifle) was **removed**: the spec lists human energy weapons as future-only, and it was never an authored weapon. It had exactly one reference (its own config row).

## Defect found: equipping never changed the live weapon
`CombatService.applyLoadout` calls `require(ArmoryService).selection(player)` inside a `pcall`. **`selection` did not exist**, so the pcall failed silently and `s.weaponId` kept whatever it was — equipping changed the menu and the profile but not the gun in the player's hands. Measured before the fix: `SetLoadout {action="equip", id="SMG05"}` returned `ok=true`, then every shot was rejected `weapon-mismatch:AR01!=SMG05`. After adding `ArmoryService.selection`, the same equip produced `accepted` shots.

## Measured
| Check | Result |
|---|---|
| `Weapons.List` | 8 entries, categories Rifle/SMG/Shotgun/Marksman/LMG/Launcher/Pistol |
| Armory catalogue (`RequestLoadout` push) | 8 rows with correct prices and `owned` flags; LMG20/AR09 are gone |
| Buy `GL22` (rank 4, 1200 cr) | `ok=true` |
| Buy `RL09` (rank 7) | `ok=true` |
| Rank gate | `buy LMG20` earlier returned `requires rank 18` — the refusal path works (that weapon has since been removed) |
| Fire `SMG03` | `accepted` |
| Fire `GL22` at a tagged target | `GF_BlastHits=1`, `LastShieldHit=Marksman`, `TotalDamage=33`, target's shield 30 → 7 |
| Fire `RL09` | `accepted`, `GF_BlastHits=1` |
| Session totals | `Accepted=4`, `Rejected=0`, `TotalDamage=87.5` |

## Limits
- **Multi-target area damage was not demonstrated.** The authored Elimination rosters spawn 18–20 studs apart, which is wider than the 9-stud GL-22 radius, so every blast legitimately hit one target. The loop is written for radius coverage but only single-target hits were observed.
- Launchers are hitscan-with-blast, not travelling projectiles; the spec says "ballistic/projectile max range", so rocket travel time and arcing are not modelled.
- No rocket/Launch audio, no ammo-type distinction.
- Shotgun pellet count (`8 pellets` in the spec) remains a single-ray weapon — pre-existing, not addressed here.
- Solo only.
