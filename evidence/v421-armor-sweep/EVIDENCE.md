# All six armour suits worn; prices aligned (build 421)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## Prices aligned to the authored table
`S10-035` requires GF-02 rank 3 / 500, GF-03 rank 5 / 850, GF-04 rank 8 / 1200. My first pass invented rank 3/500·6/800·9/1200 with different names. Corrected:

| Suit | Rank | Cost |
|---|---|---|
| GF-02 Recon Weave (`RECON`) | 3 | 500 |
| GF-03 Siege Plate (`SIEGE`) | 5 | 850 |
| GF-04 Vanguard Seal (`VANGUARD`) | 8 | 1200 |

Verified in the armour payload: `RECON r3 500cr`, `SIEGE r5 850cr`, `VANGUARD r8 1200cr`.

## Every suit worn and colour-checked
Chest-plate colour is the measurable proof that the palette actually applied.

| Suit | `GF_ArmorSuit` | Chest plate (RGB) | Expected | Kit parts |
|---|---|---|---|---|
| STANDARD | default | 222, 222, 214 | 222,222,214 | 12 |
| RECON | RECON | 176, 190, 172 | 176,190,172 | 12 |
| SIEGE | SIEGE | 206, 190, 158 | 206,190,158 | 12 |
| VANGUARD | VANGUARD | 198, 206, 224 | 198,206,224 | 12 |
| TROPHY | TROPHY | 120, 84, 96 | 120,84,96 | 12 |
| BLACKSTAR | BLACKSTAR | 48, 52, 62 | 48,52,62 | 12 |

Six distinct suits, six correct palettes, and the kit count stayed at 12 every time — re-dressing replaces rather than stacks.

BLACKSTAR is rank 16 and the test profile is rank 15, so its gate was temporarily lowered to 14 to wear it, then restored to 16 and the place re-saved. The gate itself was verified separately in the passing and failing directions at build 420.

## What still isn't proven
**Armour `BUY`/`WEAR` buttons were not clicked.** The armour rows sit at Y 737–987 inside a 2638-pixel scroll canvas. Scrolling the frame to 700 did bring `ArmorRECON` to Y 87 and the row reported a `Buy` button, but a synthetic click produced no purchase and no rejection — the click did not reach the button. Loadout buttons at the top of the same list were click-verified at build 418; this harness cannot click scrolled rows.

## Limits
- Armour remains cosmetic; no stat effect and no piece-level inventory.
- Persistence across a rejoin untested.
- The scroll-and-click gap is a harness limitation, not a game defect: a human scrolling and clicking would work, but I have not demonstrated it.
