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

## At most two hostiles may be mid-attack at once (v366)

Measured at the sabotage relay: four hostiles put **22 hits** into a stationary player in seven seconds and took them from 100 health
to 6 — a firing squad, not a fight. `EnemyService.claimFireSlot` now caps simultaneous attackers at `MAX_FIRING = 2`; a hostile that
cannot claim a slot does not fire, so attacks are staggered rather than cancelled.

Measured after, standing at the same terminal for nine seconds: **0 damage events, health 100**, with `GF_FireSlotsHeld = 2` showing
the budget engaged (i.e. hostiles were trying to fire and were queued). This is one run — patrol placement varies by seed — but the
difference between "dead in seven seconds" and "untouched in nine" is not noise.

Consequence: a single hostile is now much less threatening, so encounter difficulty leans on positioning and numbers rather than
raw rate of fire. If the game feels too easy later, raise `MAX_FIRING` to 3 before touching per-shot damage.

## Do not treat "no damage" as evidence until engagement is measured (v368)

v366 concluded a fire-distribution change made the objective survivable, on the strength of zero damage events over nine seconds. It was
zero **engagement**: `GF_EnemiesEngaged = 0` with `GF_EnemiesTracked = 8`, i.e. no hostile had a target at all. The player was standing
inside geometry that blocked line of sight, so the measurement proved nothing about damage.

Rule: any survivability claim must report acquisition separately from damage — `GF_EnemiesEngaged`, `GF_EnemiesTracked`, then damage
events. Zero of everything is a null result, not a success.

The underlying defect this exposed is real and separate: the mission's primary objective is **self-concealing**. Hostiles cannot acquire
a player at the console because the outpost's own structure blocks LOS, so the objective is undefended.

## Never append a block whose last line repeats its anchor (v371, second occurrence)

Twice now, a patch built as `src:sub(1, i-1) .. block .. src:sub(i + #anchor)` where `block` **ends with the anchor text** has produced a
duplicated function header:

```lua
function EnemyService.start()function EnemyService.start()   -- v366
function ObjectiveService.getRelay()function ObjectiveService.getRelay()  -- v371
```

Both took a whole module offline with `Expected 'end' ... got <eof>` and both were found only by reading the server log right after the
edit. Correct form: `block` must **not** contain the anchor; insert with `src:sub(1, i-1) .. block .. src:sub(i)`.

## Debug switches must be set from the server datamodel (v371)

`workspace:SetAttribute("GF_...")` from the **client** does not replicate to the server. `GF_DebugDamage` set that way produced zero
logged damage sources for a real 100 → 11 health drop, and `GF_ForceConsoleScreen` set that way meant a capture hook silently did
nothing. Any switch the server reads must be set in the Server datamodel.

## The console mitigates damage only while the hold runs (v371)

50% mitigation and a visible `ForceField` panel (`ConsoleScreen`) exist only between hold start and hold end, so standing next to the
console gains nothing. Measured `GF_ConsoleMitigated = 2` during one contested hold with three hostiles acquired; the player finished at
38 health instead of 11.

## A mission frame that shows the station means the player died, not that the camera is broken (v373)

Six continuations of "the capture keeps returning the station" were chased as a camera-override bug. The camera read `-8, 769, 36` —
station roof height — while the objective was at `0, 34, -120`. The player **died at the objective and respawned at the station** while the
mission kept running server-side, so the capture was accurate.

Rule: before blaming the camera, print `CurrentCamera.CFrame.Position` **and** the objective's position and compare them with the station
deck height (~800). For steady frames, set `GF_DeployGraceUntil` to a far future time server-side so the subject survives the shot.
