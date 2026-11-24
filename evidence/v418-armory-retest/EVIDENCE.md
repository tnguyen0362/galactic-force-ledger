# Armory panel was never broken; loadout UI verified (build 418 retest)

Studio a828ce66-ff1a-43c5-b662-dc096996bcc4, Play mode, one local client.

## Retraction of the previous batch's conclusion
Last batch recorded "the armory panel would not open" and suggested the entry point was broken. **That was wrong, and the cause was my test.**

`StationArmoryUI` closes the panel every Heartbeat frame when the player is farther than `OPEN_RANGE = 46` from the rack. I teleported the character to `rack + (0, 4, -18)` **without anchoring**, and the character fell: measured position `y = 30.2` against a deck at `y = 768` — a 738-stud distance. The panel opened and was immediately closed, exactly as designed.

With the root anchored at 14 studs from the rack (`Anchored = true`, `y = 771`), firing `OpenArmoryPanel` left `Panel.Visible = true`.

## Loadout UI, end to end
| Action | Result |
|---|---|
| Click `Loadout1.Save` (mouse input on the real button) | `GF_LoadoutSaved = 1` |
| Equip `SMG03` via remote, click `Loadout2.Save` | `GF_LoadoutSaved = 2` |
| Equip `AR01` via remote, click `Loadout2.Load` | `GF_LoadoutLoaded = 2`, `GF_LoadoutLoadOk = true` |
| Read profile state afterwards | `loadout.primary = "SMG03"` |

So a player-visible click path exists: the buttons render, are named (`Loadout1.Save` … `Loadout3.Load`), and drive the verified server actions.

## Harness lesson
**Anchor before teleporting onto the station deck.** The station is at ~768 studs and there is no floor under the rack approach; an unanchored teleport drops the character to ~30 and every proximity check then fails silently. This looked like a UI bug for a whole batch. The correct test ritual is: set grace, `root.Anchored = true`, set CFrame, act, then unanchor.

## Limits
- Slot occupancy is still not displayed: all three rows look identical whether or not the slot holds anything.
- Persistence across a rejoin remains untested.
- Only weapons were exercised; class, grenade and armour fields in the copied loadout are unverified.
