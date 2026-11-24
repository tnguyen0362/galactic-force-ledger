# Loadout slots in the Armory UI (build 418)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## Added
`StationArmoryUI` now renders three saved-loadout rows at the top of the armory list, each with a `SAVE` and a `LOAD` button wired to the `SetLoadout` actions added at build 417. `rowButton` gained an x-position argument so two buttons fit in one row, and each row/button is explicitly named (`Loadout1.Save`, `Loadout1.Load`, …) so the elements are addressable.

## Measured
| Check | Result |
|---|---|
| Buttons built | 6 — three `SAVE` at x=300, three `LOAD` at x=400 |
| Element paths | `…GF_Armory.Panel.ScrollingFrame.Loadout1.Save`, `…Loadout1.Load`, `Loadout2.*`, `Loadout3.*` |
| Server actions (build 417 + this build) | save slot 1 → load slot 1 restores the saved weapon; empty slot and slot>3 refused |

## What I could not verify
**The click path is unverified.** I could not open the armory panel to click a button:

- Firing `OpenArmoryPanel` to the player left `Panel.Visible = false`, both from the station spawn and from 12 studs in front of the `ArmoryRack` (open range is 46).
- The panel is built and laid out (`AbsolutePosition = 359.5, 123.5`) and the six buttons exist inside it, so the content is correct; only the open transition did not happen in this session.
- Because the panel was invisible, a synthetic `mouseButtonClick` on `Loadout1.Save` did nothing (`GF_LoadoutSaved` stayed nil).

So the honest state is: **buttons exist and are wired to verified server actions, but no player-visible click has been demonstrated.** The armory-open path itself is an untested dependency — the same remote that was supposed to open it returned without showing the panel.

## Next step
Open the panel the way a player does (walk to the rack, trigger its `OpenArmory` ProximityPrompt) and click `SAVE 1`, then confirm `GF_LoadoutSaved = 1`. If the prompt also fails to open the panel, that is a separate, larger defect in the armory entry point.

## Limits
- Slot occupancy is not shown: every row looks the same whether or not the slot holds anything.
- No "loaded" confirmation beyond the weapon changing in hand.
- Persistence across a rejoin still untested.
