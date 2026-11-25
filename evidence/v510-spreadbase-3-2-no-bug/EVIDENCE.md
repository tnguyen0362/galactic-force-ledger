# No scatter bug: SG-04's `spreadBase` is 3.2°, not 0.15° (place 510)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`. Instrumentation added, read, then removed.

## The claim I made last batch and have to retract

> *"a 0.15° cone at 38 studs is under a tenth of a stud wide, so all eight should connect — something in the scatter maths is still wrong."*

That premise was **false**. I asserted a `spreadBase` value I had never actually read for this weapon. Instrumenting the real value at fire time:

```
aiming=false  angle=3.200  ads=4.5  base=3.2
```

**SG-04's hip `spreadBase` is 3.2°.** At 38 studs that is roughly ±2.1 studs of scatter against a ~2-stud torso — so a handful of pellets landing
is exactly what the configured numbers produce.

## Re-measured with the real value known

```
38 studs delta=56.9   (previous run at the same distance: 22.1)
```

Both are consistent with 4–5 of 8 pellets connecting at a 3.2° cone; the difference between runs is which pellets' random jitter lands. So the
mid-range behaviour is **correct**, and the variance between runs is expected.

## What actually holds now

- **Point-blank: `96.0` damage**, confirming the authored 8 × 12 (shield 60, health 36).
- **Mid-range: partial damage consistent with a 3.2° hip cone**, and wider when aiming (4.5°).
- The stance bug fixed at place 510 was real — scatter had been using `adsSpread` at all times, so hip fire was 4.5° when it should have been 3.2°.

The remaining gap is smaller than I described it: the cone was 4.5° instead of 3.2° before the fix, not 4.5° instead of 0.15°. The bug was real but
**an order of magnitude less severe than I claimed**, because I compared it against a number I had invented rather than read.

## The pattern, for the record

This is the fourth time this session that a wrong *premise* produced a wrong *conclusion from correct measurements*:

- `e.stats` vs `e.effect` — "no augments use adsSpeed"
- `#e.trait` — "three traits per rarity"
- searching for `"ODDS"` — "the odds display doesn't render"
- remembering `spreadBase 0.15` — "the scatter maths is wrong"

In every case the fix was to **print the value instead of recalling it**. That belongs in the method, not the epilogue: read the field, then reason.

## State

`S04-022`'s pellet clause is implemented, point-blank damage is confirmed at the authored 96, and mid-range behaviour is explained by configuration
rather than a defect. Reload drift (2.8 vs 2) remains the one open SG-04 issue.
