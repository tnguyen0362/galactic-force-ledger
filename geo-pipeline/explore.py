# Crop exploration: candidate windows over the stitched grid, stats + hillshade renders.
import numpy as np
from hillshade import render
import sys

elev = np.load(r'C:\Users\tnguy\gf-geo\teton_raw.npy')
H, W = elev.shape
print(f"grid {H}x{W}, px~13.8m -> covers {H*13.8/1000:.1f}km x {W*13.8/1000:.1f}km")

# candidate crops: (name, row0, col0, size_px) - 360px ~= 5km
cands = [
    ("center_front", H//2 - 180, W//2 - 180, 360),   # central range front
    ("west_canyons", H//2 - 100, int(W*0.28), 360),  # western canyon country
    ("north_front", int(H*0.22), W//2 - 180, 360),   # northern front + valley edge
    ("south_lakes", int(H*0.62), W//2 - 200, 360),   # southern moraine lakes area
]
for name, r0, c0, s in cands:
    r0 = max(0, min(H - s, r0)); c0 = max(0, min(W - s, c0))
    crop = elev[r0:r0+s, c0:c0+s]
    relief = crop.max() - crop.min()
    # slope stats at source res
    gy, gx = np.gradient(crop, 13.8)
    slope = np.degrees(np.arctan(np.sqrt(gx**2 + gy**2)))
    print(f"{name}: relief={relief:.0f}m meanSlope={slope.mean():.0f}deg p50={np.percentile(slope,50):.0f} p90={np.percentile(slope,90):.0f}")
    render(crop, rf'C:\Users\tnguy\gf-geo\crop_{name}.png')
