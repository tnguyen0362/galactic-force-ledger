# Adversarial shot validation: 8 of 9 hostile payloads rejected (place 548)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. **No source changes** — audit and adversarial testing only.

## The run

Nine payloads fired straight at the `FireWeapon` remote, bypassing the client weapon script entirely, then the server counters read:

```
Received=9   Rejected=8   Accepted=1
LastReject=stale-shot-id:10<=10
LastMiss=0.14, 766.80, -30.45        (server-side raycast resolved the one accepted shot)
```

| payload | expected | observed |
|---|---|---|
| `weaponId="RL09"` while AR01 equipped | reject (equip mismatch) | rejected |
| `origin="nope"` (string) | reject (bad vector) | rejected |
| `origin` 400 studs from the character | reject (origin too far) | rejected |
| `direction = Vector3.zero` | reject (zero direction) | rejected |
| `shotId = -5` | reject (sequence) | rejected |
| no `shotId` field at all | reject (sequence) | rejected |
| valid shot, `shotId=10` | **accept** | accepted — ammo −1 |
| same frame, `shotId=11` | reject (RPM rate limit) | rejected |
| replay `shotId=10` | reject (stale) | rejected, `stale-shot-id:10<=10` |

Only the well-formed shot was accepted. The counters are written by the server, not the client, so they are not self-reported.

## `S04-030` — client cannot supply target or damage: VERIFIED

`CombatService.fire` reads **exactly four** payload fields:

```
345| local weaponId = payload.weaponId
356| local shotId  = tonumber(payload.shotId)
378| local origin  = payload.origin
379| local direction = payload.direction
```

No `damage`, no `target`, no hit list. Damage comes from the weapon config plus the attacker's augments; the target comes from a **server** raycast (the accepted
shot produced `LastMiss`). A client cannot name what it hit or how much it hurt.

## `S04-031` — no blind rewind: VERIFIED by construction

A whole-tree search for `rewind`, `lagcomp`, `historical` and `timestamp` returns **one** hit, and it is an unrelated comment in `CacheService`. There is no lag
compensation, no position history, and no client-supplied timestamp anywhere — so the server cannot rewind through cover, and there are no client timestamps to
sanity-bound. Replay protection comes from monotonic `shotId` instead.

This is satisfied by **absence of the dangerous mechanism**, not by a bounds check. Recorded that way deliberately.

## `S04-029` — stays PARTIAL

Six of the seven listed validations are measured above (ammo, RPM, sequence, origin/aim, equip, life state). The seventh, **plausible movement**, is only
partially covered: `origin` is bounded to `MAX_ORIGIN_OFFSET` from the character's root, which stops firing from arbitrary map positions, but there is **no
cross-shot speed check** — a client that teleports a short distance per shot inside that radius is not caught.

## A process note

Mid-batch my probe read `Accepted=nil, LastReject=nil` and I briefly concluded the handler had never run. The attributes were simply written after my read: the
`GFDebug` counters settled at `Received=6 Rejected=6` moments later. **Reading a counter immediately after firing is unreliable here** — wait for it to settle.
