# Burst cadence and Heavy recovery timed (build 449)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client. Inter-arrival times measured from `EnemyFired` on the client over 18 s, with the player positioned **from the Server datamodel**.

## First, a false alarm I caused myself
An earlier attempt in this batch showed `EnemyFired` silence and `GF_EnemiesEngaged = 0`, which looked like enemy fire had broken. It hadn't. I had moved the character with `root.CFrame = ...` **from the Client datamodel**, which does not replicate — the server still had the player at the station, so nothing engaged. Positioning the same character from the **Server** datamodel produced immediate fire.

`GF_EnemiesEngaged` stayed `0` even while 12 hits landed, so that attribute is not a reliable "is anyone attacking" signal.

## Measured cadences
| Archetype | Events | Gaps (s) | Reading |
|---|---|---|---|
| Rifleman | 6 | 0.17, 1.10, 0.20, 0.18, 0.17 | **3-shot bursts at ~0.18 s**, ~1.1 s between bursts |
| Officer | 8 | 1.55–2.03 (×6), 5.27 | **2-shot volleys 2 s apart**, longer gap between volleys |
| Heavy | 3 | **6.10, 6.05** | one blast every ~6.1 s |

This matches the authored patterns: Rifleman `8 × 3, 0.18 s interval`; Officer `12 × 2, 2 s gap`; Heavy `cooldown 2.6 + recovery 4.0 = 6.6 s`, observed at 6.05–6.10 (the 0.2 s AI tick and the 1.4 s charge shift it slightly).

So the Heavy's 4 s recovery — untimed since build 444 — is now measured in the same interval, and the burst loop is confirmed at the authored interval rather than merely "more than one hit".

## Limits
- Rifleman gaps of 0.17–0.20 s imply three shots, but the fourth slot of the authored `8 × 3` is inferred from the 1.1 s gap that follows, not directly observed.
- Officer gaps alternate 1.55 / 2.03 / 2.03 rather than a clean 2.0; the fire-slot cap and 0.2 s tick both perturb timing.
- One player, one mission, ~40 s of observation total.
- `GF_EnemiesEngaged` reads 0 during active fire and should be treated as unreliable until fixed.
