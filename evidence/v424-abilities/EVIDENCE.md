# Abilities and grenades in the armory; the client stops hardcoding them (build 424)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## Two defects, one change
1. **The armory had no ability or grenade surface.** `profile.selectedLoadout.ability1/2` and `.grenade` existed and nothing could change them.
2. **The client hardcoded which ability each slot fires.** `HUD` did `action == "Ability1" and "Airstrike" or "DomeShield"` and `Controller` fired literal `"Airstrike"`/`"DomeShield"`. Even if the armory had changed the loadout, nothing would have fired differently — `ability1` and `ability2` were read by **no script at all**.

## Implemented
- `ArmoryService.equipAbility(player, slot, id)`: slot 1/2, ability must be owned, writes `selectedLoadout.abilityN`, publishes `GF_Ability<N>`.
- `ArmoryService.equipGrenade(player, id)`: validates against `Economy.Grenades`, writes `selectedLoadout.grenade`, publishes `GF_GrenadeEquipped`.
- `state.abilities` (id, name, owned) and `state.grenades` (EMP, Frag) in the armory payload; both slots republished whenever state is built, so a fresh join has them.
- `HUD` and `Controller` now read `GF_Ability1` / `GF_Ability2` with the old literal as a fallback.
- Armory UI: two `ABILITY n · <current>` rows with `USE` buttons for owned alternatives, plus a `GRENADE` row per type with `EQUIP`.

## Measured
| Check | Result |
|---|---|
| `state.abilities` | 6 abilities, `Airstrike+` and `DomeShield+` owned |
| `state.grenades` | `EMP`, `Frag` |
| Equip `Sentry` into slot 1 | refused `ability not owned` |
| Equip `DomeShield` into slot 1 | `ok`, `GF_AbilityEquipped = "1:DomeShield"`, `GF_Ability1 = "DomeShield"` |
| Equip `EMP` | `ok`, `GF_GrenadeEquipped = "EMP"` |
| Cast the equipped slot | fired `DomeShield` from the attribute value → `GFDebug.AbilityCastRequests = 1` and a `DomeShield` part spawned at the player |

That last row is the important one: the id came from the published attribute, not a literal, and the server accepted and executed it.

## Limits
- The armory `USE`/`EQUIP` buttons were **not clicked**; the remote path is verified. Rows sit at LayoutOrder 5–7, inside the 286 px viewport, so a click test is possible next batch.
- Nothing prevents both slots holding the same ability — measured: slot 2 was already `DomeShield`, so equipping slot 1 to `DomeShield` produced a duplicate. No guard exists.
- No ability purchases; only owned abilities can be equipped. Four of six abilities are unobtainable.
- Grenade behaviour itself (`EMP` vs `Frag` effects) was not exercised — only the selection.
