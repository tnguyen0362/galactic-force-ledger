# Production preprocessing: DEM crop -> game-ready heightfield foundation.
# Implements spec section 9: robust normalization, multiresolution decomposition,
# independent horizontal/vertical scaling, band-coefficient control.
import numpy as np
import json
from hillshade import render

def load_crop(r0, c0, s):
    elev = np.load(r'C:\Users\tnguy\gf-geo\teton_raw.npy')
    return elev[r0:r0+s, c0:c0+s].astype(np.float64)

def robust_clip(h, lo=0.5, hi=99.5):
    """clip only true outlier spikes/dips - preserve meaningful peaks per spec"""
    qlo, qhi = np.percentile(h, lo), np.percentile(h, hi)
    return np.clip(h, qlo, qhi), qlo, qhi

def gaussian(h, sigma):
    """separable gaussian blur - no scipy dependency needed if unavailable"""
    try:
        from scipy.ndimage import gaussian_filter
        return gaussian_filter(h, sigma, mode='reflect')
    except ImportError:
        # fallback: box blur approximation (3 passes ~ gaussian)
        k = max(3, int(sigma*2)|1)
        out = h.copy()
        for _ in range(3):
            kernel = np.ones(k)/k
            from numpy import convolve
            pad = k//2
            hp = np.pad(out, ((0,0),(pad,pad)), mode='reflect')
            out = np.apply_along_axis(lambda r: convolve(r, kernel, mode='valid'), 1, hp)
            hp2 = np.pad(out, ((pad,pad),(0,0)), mode='reflect')
            out = np.apply_along_axis(lambda r: convolve(r, kernel, mode='valid'), 0, hp2)
        return out

def decompose(h, sigma_macro=28.0, sigma_meso=6.0):
    """spec section 9: H_macro = G_large*H; H_meso = G_small*H - G_large*H; H_micro = H - G_small*H"""
    g_small = gaussian(h, sigma_meso)
    g_large = gaussian(h, sigma_macro)
    macro = g_large
    meso = g_small - g_large
    micro = h - g_small
    return macro, meso, micro

def analyze(h, name, cellsize):
    gy, gx = np.gradient(h, cellsize)
    slope = np.degrees(np.arctan(np.sqrt(gx**2+gy**2)))
    print(f"{name}: relief={h.max()-h.min():.0f}m mean={h.mean():.0f} slope mean={slope.mean():.1f} p50={np.percentile(slope,50):.0f} p90={np.percentile(slope,90):.0f} p99={np.percentile(slope,99):.0f}")
    return slope

def resample(h, target_n):
    """bilinear resample to target_n x target_n"""
    n = h.shape[0]
    idx = np.linspace(0, n-1, target_n)
    xi = np.floor(idx).astype(int); xf = idx - xi
    xi = np.clip(xi, 0, n-2)
    # bilinear in two passes
    def interp1d(arr, xi, xf, axis):
        a = np.take(arr, xi, axis=axis)
        b = np.take(arr, xi+1, axis=axis)
        xfsh = [1]*arr.ndim; xfsh[axis] = -1
        return a*(1-xf.reshape(xfsh)) + b*xf.reshape(xfsh)
    out = interp1d(h, xi, xf, 0)
    out = interp1d(out, xi, xf, 1)
    return out

if __name__ == '__main__':
    SRC = 420        # source px window
    R0, C0 = 1740, 1560
    GAME_N = 1250    # game samples per side (5000 studs / 4)
    COMP = 4.14      # horizontal compression real->game
    VSCALE = 4.14    # vertical compression (== COMP preserves real slopes)

    crop = load_crop(R0, C0, SRC)
    print("== source ==")
    analyze(crop, "source crop", 13.8)

    clipped, qlo, qhi = robust_clip(crop)
    print(f"quantile clip: {qlo:.0f}..{qhi:.0f}")

    macro, meso, micro = decompose(clipped)
    print(f"bands: macro relief={macro.max()-macro.min():.0f}m meso amp std={meso.std():.1f}m micro std={micro.std():.2f}m")

    # band coefficients: full macro identity, meso preserved, micro slightly damped
    # (micro at 13.8m source scale maps to sub-voxel noise at game scale anyway)
    a_macro, a_meso, a_micro = 1.0, 1.0, 0.8
    recon = a_macro*macro + a_meso*meso + a_micro*micro

    # scale to game: horizontal compression means game meters = real/COMP; vertical = real/VSCALE
    game_m = recon / VSCALE
    game_studs = game_m / 0.28
    print("== game scale ==")
    analyze(game_studs, "game studs (pre-resample)", 13.8/COMP/0.28)

    grid = resample(game_studs, GAME_N)
    analyze(grid, "final 1250-grid", 4.0)  # 4 studs per sample
    # set base: lowest point at 24 studs
    grid = grid - grid.min() + 24.0
    print(f"final height range: {grid.min():.0f}..{grid.max():.0f} studs")
    np.save(r'C:\Users\tnguy\gf-geo\foundation_v1.npy', grid.astype(np.float32))
    # preview render (cellsize in studs - hillshade needs consistent units; scale lighting only)
    render(grid * 0.28, r'C:\Users\tnguy\gf-geo\foundation_v1_preview.png', cellsize=4*0.28)
    json.dump(dict(r0=R0, c0=C0, src=SRC, comp=COMP, vscale=VSCALE, game_n=GAME_N,
                   bands=dict(macro=a_macro, meso=a_meso, micro=a_micro),
                   provenance="USGS 3DEP via AWS Open Data terrain tiles (terrarium z13), public domain",
                   region="Grand Teton front / Jackson Hole edge, Wyoming USA"),
              open(r'C:\Users\tnguy\gf-geo\foundation_v1_meta.json','w'), indent=2)
    print("foundation_v1 exported")
