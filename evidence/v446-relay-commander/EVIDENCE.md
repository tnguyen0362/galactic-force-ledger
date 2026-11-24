# Relay commander call fires in ordinary play (build 446)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## Correcting my own claim from build 445
I wrote that "the sabotage mission has a relay but no Officer" and called it a content gap. That was a **two-sample conclusion**: `EncounterDirector.standardIds()` *does* include Officer, and whether one spawns is random among four patrol slots. Two missions happened to roll none (Rifleman 3 + Marksman 4, then Rifleman 4 + Marksman 5).

The real problem was reliability, not absence: a rule that only fires ~59% of the time, and never when the roll goes the other way, is not testable and not dependable.

## Implemented
`EncounterDirector.beginMission` now spawns **one guaranteed Officer at the relay** when the template is `SABOTAGE_RELAY` (10 studs offset), and records `GF_RelayCommander`. The random patrol rolls are untouched.

## Measured in ordinary play — no test scaffolding
| Reading | Value |
|---|---|
| `GF_RelayCommander` | `true` |
| Officer distance to relay | **11 studs** |
| `GF_CallState` | `Officer:pending ×3` |
| After the 2 s call | `GF_Reinforcements = **6**`, `GF_LastCall = "Officer:reinforcements"` |
| Rifleman count | **7** |

No hidden marker part, no forced positions — the call started during a plain deployment and spawned reinforcements on its own.

## A balance risk this exposes
**Three Officers each called once and each spawned two Riflemen**: 6 extra hostiles from a single mission, doubling the patrol population. The spec says "a 2 s call" per commander and says nothing about stacking. With the guaranteed commander plus two random Officers, the mission can over-spawn. That needs a cap — one call per mission, or one call per relay — before this is balanced.

## Limits
- Only one mission was observed end to end; the 2 s window was not timed precisely.
- The reinforcement wave was not fought, so its difficulty impact is unmeasured.
- `GF_LastCall` remains a single stale-prone attribute.
