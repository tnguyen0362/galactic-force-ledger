# Burn the Arsenal, Silent Archive, and the hacking subsystem — measured evidence (build 397)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client, attributes read from Server.

## Hacking subsystem (new)
`ServerScriptService/GF/Services/HackingService` + `HackState` / `HackAttempt` remotes + an overlay in `MissionHUD`.

- **Server-authoritative hit test.** The client presses a key; the server computes the needle angle from `workspace:GetServerTimeNow()` and its own challenge start, then decides hit or miss. The client cannot report an angle.
- Difficulty table: arc 110/95/85/75°, rotation 1.6/1.3/1.05/0.85 s for Easy/Normal/Hard/Extreme. Normal measured with `arcWidth = 95`, `period = 1.3`.
- Three successes to finish; **a miss loses one stage with a floor of zero** (spec wording), verified: stage went 1 → 0 on a deliberate out-of-arc press.
- One attempt per 0.35 × rotation (latency allowance), plus a 7° arc tolerance.
- Client overlay: 24 tick marks, green for the success arc, rotating needle, `HACK n / 3 <key>` label, hidden when the server says `active = false`.

### Measured
| Step | Result |
|---|---|
| Attempt a hack with 0 hits | `GF_HackStage` 0, state published with `arcStart`/`arcWidth`/`period` |
| Press inside arc ×3 | `GF_HackHits=3`, `GF_HackComplete=1`, overlay closed |
| Press outside arc at stage 1 | `GF_HackMisses=1`, stage 0 (floor zero), challenge continues |
| `GF_LastHackDelta` | 26 at the miss (outside the 47.5° half-arc) |

## Sabotage | Burn the Arsenal (`SABOTAGE_ARSENAL`)
| Step | Result |
|---|---|
| Deploy Normal | stage 1, two charge pads |
| Charge pad A | `GF_ArsenalPads=1`, pad `GFCharged=true`, stage stays 1 |
| Charge pad B | stage 2, 8 s warning |
| Warning timing | stage 2 at 2 s, stage 3 at 9 s — the warning is real, not skipped |
| Detonation | stockpile transparency 1, `GFDestroyed=true`, `GF_ArsenalDetonated=true`, `GF_ObjectiveComplete=true` |

## Recovery | Silent Archive (`RECOVERY_ARCHIVE`)
| Step | Result |
|---|---|
| Deploy Normal | stage 1 (`Reach the intel room`) |
| Walk within 25 studs of console | stage 2, prompt `Break console` |
| Interact | hacking challenge starts |
| Three in-arc presses | stage 3, prompt `Recover archive`, intel case revealed |
| Interact | `GF_ObjectiveComplete=true`, intel case transparency 0 |

## Defects found and fixed
1. **HUD kept the previous mission's completion state.** Captured: a freshly deployed Silent Archive showed `PRIMARY OBJECTIVE COMPLETE` in green while its own objective was running. `setProgress` restored the bar and hint on `complete=false` but never the title or colour. Fixed and verified by scanning `PlayerGui`: before redeploy `PRIMARY OBJECTIVE COMPLETE`, after redeploy `PRIMARY OBJECTIVE`.
2. **A revealed intel case was instantly faded.** `complete()` tweens every `Neon` part in the objective to transparency 1, which erased the case at the moment it appeared. The case is now `Metal`.
3. **Hacking floor was 1, the spec says floor 0.** A miss at the first stage previously cost nothing. Now `max(0, stage - 1)`.
4. **`StationUI` table lost its commas** when entries were appended across batches — six entries were rejected at parse with `Expected '}' ... got '{'`, which killed the whole client script. Fixed; all ten edited scripts now pass `loadstring` before a playtest.

## Limits
- Hacking has no cancel on range, downed, disconnect or explicit exit; only success or abandonment by leaving the game (`S08-040` open).
- No hit/miss audio, only the visual arc and label (`S08-042` partial).
- The hacking overlay is client-drawn and has never been exercised with a real keyboard, gamepad or touch — the test drove the remote directly.
- Solo only; one client.
