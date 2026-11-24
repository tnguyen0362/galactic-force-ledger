# DECISIONS

**Moved.** The single source of truth is `.goal/DECISIONS.md` (now through D15).
Historical root-only entries are preserved at `.goal/legacy-DECISIONS.md`.

Do not append here; split decision logs produce contradictory rationales.

## D-21 ArmoryService is the single writer of loadout state
Purchases and equips go through `ArmoryService` only; `CombatService` reads the profile and never mutates it. Rejected the alternative of letting the client tell the server "now carry weapon X" — `CombatService.equip` accepting an arbitrary id from the client is exactly how the 3000-credit ER-16 was free, so the ownership check now lives server-side next to the config lookup, and the armory selection is pushed by the server rather than requested by the client.

## Template-driven objectives instead of three services
One `ObjectiveService` dispatching on `mission.objectiveTemplate`, rather than three objective services.
Reason: the relay was already 80% of the machinery (ground snap, terminal interact, publish, complete
FX); the templates differ in **object built** and **completion rule**, not in plumbing. Three services
would triple the surface the deploy path has to keep in sync.
Consequence accepted: `complete()` gates its explosion FX on template id, so a new template must say
whether it explodes.

## EnvironmentSpecularScale is 0 in every lighting preset (v303)

Measured A/B on the concourse deck, same camera, same lights, same session:

| EnvironmentSpecularScale | EnvironmentDiffuseScale | result |
|---|---|---|
| 0.04 | 0.18 | solid orange wash covering the entire floor and tinting the character (V354) |
| 0.00 | 0.00 | clean dark deck (V355) |
| 0.00 | 0.18 | clean dark deck, environment diffuse still present (V356, V357) |

Cause: this place sits under a saturated orange/magenta nebula sky, and Roblox samples the sky for specular on `Metal`. A large
flat Metal deck mirrors it at grazing angles. The earlier "DiamondPlate is banned on the deck" rule was this same problem seen
through a different material — 0.04 specular was enough to produce it on plain Metal too.

Consequence for future art work: any large flat surface in this place must either use a matte material or accept that specular is
globally disabled. Do not raise `EnvironmentSpecularScale` to "add gloss" without re-checking the deck at grazing angles.
