# Scan for the ideal foundation window: high relief + meaningful flat fraction + front character
import numpy as np
from hillshade import render

elev = np.load(r'C:\Users\tnguy\gf-geo\teton_raw.npy')
H, W = elev.shape
gy, gx = np.gradient(elev, 13.8)
slope = np.degrees(np.arctan(np.sqrt(gx**2+gy**2)))

S = 420  # ~5.8km windows
best = []
for r0 in range(0, H-S, 60):
    for c0 in range(0, W-S, 60):
        slp = slope[r0:r0+S, c0:c0+S]
        el = elev[r0:r0+S, c0:c0+S]
        relief = el.max()-el.min()
        flat = (slp < 8).mean()
        steep = (slp > 25).mean()
        # ideal: big relief, substantial flat valley floor AND substantial steep mountain
        score = min(relief, 1300)/1300 * min(flat,0.35)/0.35 * min(steep,0.3)/0.3
        if relief > 700 and flat > 0.18 and steep > 0.15:
            best.append((score, r0, c0, relief, flat, steep))
best.sort(reverse=True)
for score, r0, c0, relief, flat, steep in best[:6]:
    print(f"r{r0} c{c0}: score={score:.2f} relief={relief:.0f}m flat={flat*100:.0f}% steep={steep*100:.0f}%")
if best:
    _, r0, c0, *_ = best[0]
    render(elev[r0:r0+S, c0:c0+S], r'C:\Users\tnguy\gf-geo\crop_best.png')
    print("best crop rendered: rows", r0, "cols", c0)
    # render runner-up too
    if len(best) > 1:
        _, r1, c1, *_ = best[1]
        render(elev[r1:r1+S, c1:c1+S], r'C:\Users\tnguy\gf-geo\crop_second.png')
        print("second: rows", r1, "cols", c1)
