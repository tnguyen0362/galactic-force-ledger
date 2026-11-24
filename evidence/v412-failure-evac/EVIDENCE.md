# Failed primary now offers emergency extraction (build 412)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client, attributes read from the Server datamodel.

## The hole
`powerFail` set `GF_ObjectiveFailed` and fired an `ObjectiveComplete{success=false}` message, and then **nothing**. The objective could never complete, no evac was offered, and the squad was left in a dead mission. The spec requires: "failure at object destruction ends primary, offers emergency evacuation; no automatic full rewards."

## The fix
`powerFail` now calls `ExtractionService.emergency()` after the failure flag. That path already existed for the soft deadline (verified earlier at build 276) — it was simply never reached by an objective failure.

Also added a server-side mirror of extraction state (`GF_ExtractionCalled`, `GF_ExtractionLanded`, `GF_ExtractionRemaining`, `GF_ExtractionEmergency`) inside `publish()`. The live state lives in the module, and a tool VM `require` returns a **separate instance** — so every attempt to read `ExtractionService.isLanded()` from a test returned `false` regardless of reality. The attributes are the honest instrument.

## Measured
Set `GF_EmergencyGraceOverride = 6`, deployed `DEFENSE_POWER` on Normal, restored the generator, then destroyed it.

| Moment | `failed` | `emergency` | `called` | `remaining` | `landed` |
|---|---|---|---|---|---|
| At destruction | true | true | true | 6 | false |
| After the grace | true | — | true | 0 | **true** |

So: primary failed → emergency extraction offered → countdown → dropship on the ground, with the objective never marked complete.

## Limits
- Boarding, debrief and reward withholding on a failed extraction were **not** exercised this run; only the offer and arrival were measured.
- The failure→emergency handoff exists only for `DEFENSE_POWER`; other templates cannot fail yet (no failure trigger), so the same call has no other entry point.
- Only the `Normal` difficulty was used.

## Process note
This is the fourth time this session that a single-value or wrong-instrument read produced a false negative (augment purchases, cache drops, boss cache, extraction state). The pattern is consistent: the tool VM gets its own module instance, and one attribute cannot record a sequence. Attributes that mirror real module state, and counters rather than last-value fields, are the fix.
