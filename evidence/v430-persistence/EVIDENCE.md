# Persistence across a server restart, and a rejoin wardrobe bug (build 430)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`. Two full Play sessions (stop → start = new server), same user.

## Persistence measured
Snapshot taken in session 1, then the server was stopped and a **fresh server** started, and the same state was read again:

| Field | Before restart | After restart |
|---|---|---|
| Credits | 39,590 | 39,590 |
| Rank / XP | 15 / 123,700 | 15 / 123,700 |
| Owned augments | 36 | 36 |
| Owned armour | STANDARD, RECON, SIEGE, VANGUARD, TROPHY, BLACKSTAR | identical |
| Owned abilities | Airstrike, DomeShield, Sentry, OrbitalStrike | identical |
| Loadout | SMG03 / P01 · DomeShield / Airstrike · Frag · socket 1 BeltFeed | identical |
| Caches held | Rare × 1 | Rare × 1 |

Every field matched. Durable progression survives a server restart.

Then a **change** was made (equip VANGUARD), the server restarted again, and the profile still read `armor = VANGUARD` — so the write path survives too, not just the load.

## A real bug the restart exposed
After the rejoin the profile said `VANGUARD` but the character was wearing **STANDARD** (`GF_ArmorSuit = "STANDARD"`, chest plate 222/222/214).

Cause: `AppearanceService` dresses the character at spawn, and the DataStore profile is not loaded yet at that moment, so it fell back to `STANDARD` and never re-dressed. Every rejoin would have shown the wrong suit until the player re-equipped it manually.

Fixed with a bounded retry: after dressing, a background loop checks the profile every 0.5 s (up to 20 tries) and re-dresses once the armour id is available.

Measured after the fix on a fresh server: `GF_ArmorSuit = "VANGUARD"`, 12 kit parts, chest plate `198, 206, 224` — the VANGUARD palette, matching the profile.

## Limits
- Only one account and one place; no cross-place or multi-server test.
- No crash-between-save-and-confirm test, no reconnect during a live mission, no receipt/idempotency check (`S14-017`, `S14-019`).
- The retry is bounded to 10 seconds; a very slow DataStore load would still show the default suit. Nothing surfaces that failure to the player.
- Settings, war credits and the transaction journal were not read back after the restart.
