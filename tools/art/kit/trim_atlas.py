"""GALACTIC FORCE Phase 15 - BASEKIT trim atlas (numpy only, deterministic).

One 1024x1024 PBR atlas per faction palette: BC (colour), N (tangent normal, OpenGL +Y), RM (G=rough, B=metal).
Layout = horizontal strips that TILE ALONG U. Texel density 64 px / stud (U period = 16 studs).
V rows are given bottom-up (Blender v = 0 at the bottom); images are flipped when saved.

  strip    v0..v1     use
  PLATE      0..256   wall plate CELL (two 512 variants side by side), NOT tiling - one plate per cell
  FRAME    256..384   graphite frame / posts / plinth / caps (bolts every 2 studs)
  HAZARD   384..512   yellow/black diagonal hazard
  VENT     512..640   louvre / grille slots
  ROOF     640..768   navy corrugated roof panel
  CONCRETE 768..896   floor / pad
  GLASS    896..1024  tinted glass with mullions

Usage: python trim_atlas.py [out_dir] [accent]     accent = amber | cyan   (single constant; light colour swap)
"""
import sys, os, zlib, struct
import numpy as np

RES = 1024
PPS = 64            # px per stud
OUT_DEFAULT = r"C:\Users\tnguy\gf-art-build\blender\out_kit\tex"
STRIPS = {"PLATE": (0, 256), "FRAME": (256, 384), "HAZARD": (384, 512), "VENT": (512, 640),
          "ROOF": (640, 768), "CONCRETE": (768, 896), "GLASS": (896, 1024)}


def srgb(c):
    return np.array(c, dtype=np.float32)


# ------------------------------------------------------------------ noise helpers (periodic -> tiles in U)
def vnoise(h, w, cy, cx, seed):
    """periodic value noise, cy x cx cells, bilinear-smoothstep."""
    r = np.random.default_rng(seed)
    g = r.random((cy, cx)).astype(np.float32)
    yy = (np.arange(h, dtype=np.float32) / h) * cy
    xx = (np.arange(w, dtype=np.float32) / w) * cx
    y0 = np.floor(yy).astype(int); x0 = np.floor(xx).astype(int)
    fy = yy - y0; fx = xx - x0
    fy = fy * fy * (3 - 2 * fy); fx = fx * fx * (3 - 2 * fx)
    y1 = (y0 + 1) % cy; x1 = (x0 + 1) % cx
    y0 %= cy; x0 %= cx
    a = g[np.ix_(y0, x0)]; b = g[np.ix_(y0, x1)]; c = g[np.ix_(y1, x0)]; d = g[np.ix_(y1, x1)]
    top = a + (b - a) * fx[None, :]
    bot = c + (d - c) * fx[None, :]
    return top + (bot - top) * fy[:, None]


def fbm(h, w, cy, cx, seed, octs=4):
    out = np.zeros((h, w), np.float32); amp = 0.5; tot = 0
    for o in range(octs):
        out += amp * vnoise(h, w, max(1, cy * 2 ** o), max(1, cx * 2 ** o), seed + o * 17)
        tot += amp; amp *= 0.5
    return out / tot


def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def disc(U, V, cu, cv, r, soft=1.2):
    d = np.sqrt((U - cu) ** 2 + (V - cv) ** 2)
    return 1.0 - smooth(d, r - soft, r + soft)


def box_sdf_edge(U, V, w, h):
    """distance (px) to the nearest edge of the [0,w]x[0,h] rect, positive inside."""
    return np.minimum(np.minimum(U, w - 1 - U), np.minimum(V, h - 1 - V))


class Atlas:
    def __init__(self):
        self.H = np.zeros((RES, RES), np.float32)          # height in px
        self.C = np.zeros((RES, RES, 3), np.float32)       # sRGB colour
        self.R = np.full((RES, RES), 0.6, np.float32)
        self.M = np.zeros((RES, RES), np.float32)

    def put(self, name, h, c, r, m):
        v0, v1 = STRIPS[name]
        self.H[v0:v1] = h; self.C[v0:v1] = c; self.R[v0:v1] = r; self.M[v0:v1] = m


def grid(h, w):
    V, U = np.mgrid[0:h, 0:w].astype(np.float32)
    return U, V


# ------------------------------------------------------------------ strips
def plate_cell(seed, w=512, h=256):
    """one wall plate, u runs ALONG the plate's long side; u=0 is the BOTTOM of a standing plate (grime pools there)."""
    U, V = grid(h, w)
    e = box_sdf_edge(U, V, w, h)
    H = np.zeros((h, w), np.float32)
    H -= 3.0 * (e < 5)                                   # outer seam groove
    H += 1.2 * ((e >= 5) & (e < 9))                      # bevel lip
    # inset recessed panel
    ins = 30
    ei = box_sdf_edge(U - ins, V - ins, w - 2 * ins, h - 2 * ins)
    inside = (U > ins) & (U < w - ins) & (V > ins) & (V < h - ins)
    H -= 1.8 * (inside & (ei < 3))                       # inner groove
    H -= 0.8 * (inside & (ei >= 3))                      # recessed field
    # rivets along inset ring
    riv = np.zeros_like(H)
    for u in np.linspace(ins + 14, w - ins - 14, 9):
        for v in (ins + 14, h - ins - 14):
            riv = np.maximum(riv, disc(U, V, u, v, 5.0))
    for v in np.linspace(ins + 14, h - ins - 14, 4)[1:-1]:
        for u in (ins + 14, w - ins - 14):
            riv = np.maximum(riv, disc(U, V, u, v, 5.0))
    H += 2.2 * riv
    # raised centre stiffener rib (long way) with a vent slot row
    rib = (np.abs(V - h / 2) < 9) & (U > 90) & (U < w - 90)
    H += 1.4 * rib
    for u in np.arange(130, w - 120, 36):
        slot = (np.abs(U - u) < 11) & (np.abs(V - h / 2) < 3)
        H -= 2.5 * slot
    n1 = fbm(h, w, 6, 12, seed)
    n2 = fbm(h, w, 40, 80, seed + 5, 3)
    H += (n2 - 0.5) * 0.8
    # colour: painted gunmetal grey with wear / grime / streaks
    base = srgb((0.43, 0.45, 0.47))
    col = np.broadcast_to(base, (h, w, 3)).copy()
    col *= (0.88 + 0.22 * n1)[..., None]
    grooves = (H < -2.0).astype(np.float32)
    col *= (1 - 0.55 * grooves)[..., None]
    col *= (1 - 0.30 * (H < -0.5) * (H >= -2.0))[..., None]
    # bottom grime (u small) + vertical drip streaks
    grime = smooth(1.0 - U / 170.0, 0.0, 1.0) * (0.45 + 0.55 * fbm(h, w, 3, 24, seed + 9))
    streak = fbm(h, w, 2, 90, seed + 21, 3)                # stretched along u (rows barely vary in u)
    streak = smooth(streak, 0.55, 0.85) * smooth(1.0 - U / 400.0, 0.0, 0.8)
    dirt = np.clip(grime * 0.8 + streak * 0.5, 0, 1)
    col = col * (1 - 0.62 * dirt)[..., None] + srgb((0.10, 0.085, 0.07)) * (0.62 * dirt)[..., None]
    # edge wear: bare metal on bevel lips + scratches
    wear_m = ((e >= 5) & (e < 9)) * smooth(fbm(h, w, 8, 16, seed + 31), 0.55, 0.75) * 0.55
    scr = np.zeros((h, w), np.float32)
    r = np.random.default_rng(seed + 77)
    for _ in range(14):
        u0 = r.uniform(0, w); v0 = r.uniform(10, h - 10); L = r.uniform(30, 110); ang = r.uniform(-0.25, 0.25)
        for t in np.linspace(0, L, int(L)):
            ui = int(u0 + t * np.cos(ang)); vi = int(v0 + t * np.sin(ang))
            if 0 <= ui < w and 0 <= vi < h:
                scr[vi, ui] = 1.0
    scr = np.clip(scr, 0, 1) * smooth(fbm(h, w, 6, 12, seed + 41), 0.35, 0.6)
    wear = np.clip(wear_m + 0.7 * scr, 0, 1)
    col = col * (1 - wear)[..., None] + srgb((0.50, 0.51, 0.53)) * wear[..., None]
    col[riv > 0.5] *= 0.80
    rough = 0.50 + 0.22 * n1 + 0.18 * dirt
    rough = np.where(wear > 0.4, 0.30, rough)
    metal = np.where(wear > 0.4, 0.9, 0.12)
    return H, col, np.clip(rough, 0.05, 1), metal


def frame_strip(seed, w=1024, h=128):
    U, V = grid(h, w)
    H = np.zeros((h, w), np.float32)
    # panel seams every 256 px, bolts every 128 px on the centre line (v = h/2)
    for u in range(0, w, 256):
        H -= 2.0 * (np.abs(U - u) < 2) * (np.abs(V - h / 2) < h * 0.46)
    bolt = np.zeros((h, w), np.float32)
    for u in np.arange(64, w, 128):
        bolt = np.maximum(bolt, disc(U, V, u, h * 0.5, 8.0))
    H += 3.0 * bolt
    H -= 1.2 * ((np.abs(V - 14) < 2) | (np.abs(V - (h - 14)) < 2))     # double score lines
    n = fbm(h, w, 4, 16, seed)
    H += (fbm(h, w, 40, 160, seed + 3, 3) - 0.5) * 1.2
    base = srgb((0.135, 0.14, 0.155))
    col = np.broadcast_to(base, (h, w, 3)).copy() * (0.80 + 0.40 * n)[..., None]
    col *= (1 - 0.5 * (H < -1.0))[..., None]
    wear = smooth(fbm(h, w, 6, 24, seed + 7), 0.55, 0.78) * (0.35 + 0.65 * smooth(np.abs(V - h / 2), 40, 62))
    wear = np.clip(wear + 0.6 * bolt * smooth(fbm(h, w, 20, 80, seed + 9), 0.45, 0.7), 0, 1)
    col = col * (1 - wear)[..., None] + srgb((0.40, 0.40, 0.42)) * wear[..., None]
    grime = smooth(fbm(h, w, 3, 14, seed + 11), 0.5, 0.8) * 0.5
    col = col * (1 - grime)[..., None] + srgb((0.06, 0.05, 0.04)) * grime[..., None]
    rough = 0.62 + 0.2 * n - 0.3 * wear
    metal = 0.25 + 0.6 * wear
    return H, col, np.clip(rough, 0.05, 1), metal


def hazard_strip(seed, w=1024, h=128):
    U, V = grid(h, w)
    per = 64.0
    d = ((U + V) % per) / per
    stripe = smooth(d, 0.48, 0.52) - smooth(d, 0.98, 1.0)
    stripe = np.clip(stripe, 0, 1)
    H = 0.8 * stripe
    n = fbm(h, w, 4, 16, seed)
    H += (fbm(h, w, 40, 160, seed + 3, 3) - 0.5) * 1.0
    yel = srgb((0.86, 0.66, 0.06)); blk = srgb((0.045, 0.045, 0.05))
    col = blk * (1 - stripe)[..., None] + yel * stripe[..., None]
    col *= (0.78 + 0.35 * n)[..., None]
    chip = smooth(fbm(h, w, 12, 48, seed + 5), 0.62, 0.8)             # paint chipped to bare steel
    col = col * (1 - chip)[..., None] + srgb((0.30, 0.30, 0.32)) * chip[..., None]
    dirt = smooth(fbm(h, w, 3, 14, seed + 11), 0.45, 0.8) * 0.55
    col = col * (1 - dirt)[..., None] + srgb((0.07, 0.06, 0.05)) * dirt[..., None]
    rough = 0.55 + 0.15 * n - 0.25 * chip
    metal = 0.05 + 0.8 * chip
    return H, col, np.clip(rough, 0.05, 1), metal


def vent_strip(seed, w=1024, h=128):
    U, V = grid(h, w)
    H = np.zeros((h, w), np.float32)
    slot = np.zeros((h, w), np.float32)
    for k in range(5):
        v = 14 + k * 25
        for u in np.arange(0, w, 128):
            slot = np.maximum(slot, (np.abs(U - (u + 64)) < 52) * (np.abs(V - v) < 7) * 1.0)
    H -= 5.0 * slot
    H += 1.0 * ((np.abs(U % 128 - 0) < 3) | (np.abs(U % 128 - 127) < 3))
    H += (fbm(h, w, 40, 160, seed + 3, 3) - 0.5) * 1.0
    n = fbm(h, w, 4, 16, seed)
    col = np.broadcast_to(srgb((0.16, 0.165, 0.18)), (h, w, 3)).copy() * (0.8 + 0.4 * n)[..., None]
    col = col * (1 - 0.88 * slot)[..., None] + srgb((0.015, 0.015, 0.02)) * (0.88 * slot)[..., None]
    dirt = smooth(fbm(h, w, 3, 14, seed + 11), 0.45, 0.8) * 0.5
    col = col * (1 - dirt)[..., None] + srgb((0.06, 0.05, 0.04)) * dirt[..., None]
    rough = 0.55 + 0.2 * n
    metal = np.full((h, w), 0.35, np.float32)
    return H, col, np.clip(rough, 0.05, 1), metal


def roof_strip(seed, w=1024, h=128):
    U, V = grid(h, w)
    H = 2.2 * np.sin(2 * np.pi * V / 16.0)                          # corrugation ridges run along U
    for u in range(0, w, 256):
        H -= 3.0 * (np.abs(U - u) < 2)
    H += (fbm(h, w, 40, 160, seed + 3, 3) - 0.5) * 1.0
    n = fbm(h, w, 4, 16, seed)
    col = np.broadcast_to(srgb((0.115, 0.175, 0.29)), (h, w, 3)).copy() * (0.82 + 0.36 * n)[..., None]
    ridge = smooth(np.sin(2 * np.pi * V / 16.0), 0.6, 1.0) * smooth(fbm(h, w, 6, 24, seed + 7), 0.5, 0.75)
    col = col * (1 - ridge)[..., None] + srgb((0.34, 0.36, 0.40)) * ridge[..., None]
    dirt = smooth(fbm(h, w, 3, 14, seed + 11), 0.42, 0.8) * 0.6
    col = col * (1 - dirt)[..., None] + srgb((0.08, 0.065, 0.045)) * dirt[..., None]
    rough = 0.50 + 0.2 * n - 0.2 * ridge
    metal = 0.15 + 0.7 * ridge
    return H, col, np.clip(rough, 0.05, 1), metal


def concrete_strip(seed, w=1024, h=128):
    U, V = grid(h, w)
    H = (fbm(h, w, 8, 32, seed, 5) - 0.5) * 5.0
    for u in range(0, w, 512):
        H -= 3.0 * (np.abs(U - u) < 2)
    H -= 2.0 * (np.abs(V - 64) < 1.5)
    n = fbm(h, w, 5, 20, seed + 2)
    col = np.broadcast_to(srgb((0.36, 0.355, 0.34)), (h, w, 3)).copy() * (0.72 + 0.5 * n)[..., None]
    stain = smooth(fbm(h, w, 3, 10, seed + 4), 0.5, 0.8) * 0.5
    col = col * (1 - stain)[..., None] + srgb((0.14, 0.12, 0.10)) * stain[..., None]
    rough = np.full((h, w), 0.88, np.float32) - 0.1 * n
    metal = np.zeros((h, w), np.float32)
    return H, col, np.clip(rough, 0.05, 1), metal


def glass_strip(seed, w=1024, h=128, accent="amber"):
    U, V = grid(h, w)
    H = np.zeros((h, w), np.float32)
    for u in range(0, w, 256):
        H += 2.0 * (np.abs(U - u) < 4)
    n = fbm(h, w, 2, 6, seed)
    tint = srgb((0.10, 0.34, 0.40))
    col = np.broadcast_to(tint, (h, w, 3)).copy() * (0.7 + 0.5 * n)[..., None]
    for u in range(0, w, 256):
        col[:, max(0, u - 4):u + 4] = srgb((0.07, 0.07, 0.08))
    refl = smooth(np.sin((U + V * 2.0) * 0.045), 0.7, 1.0) * 0.25
    col = np.clip(col + refl[..., None], 0, 1)
    rough = np.full((h, w), 0.08, np.float32)
    metal = np.zeros((h, w), np.float32)
    return H, col, rough, metal


def build(accent="amber"):
    A = Atlas()
    # PLATE: two cells
    for i, seed in enumerate((101, 202)):
        H, C, R, M = plate_cell(seed)
        sl = slice(i * 512, (i + 1) * 512)
        A.H[0:256, sl] = H; A.C[0:256, sl] = C; A.R[0:256, sl] = R; A.M[0:256, sl] = M
    A.put("FRAME", *frame_strip(11))
    A.put("HAZARD", *hazard_strip(23))
    A.put("VENT", *vent_strip(31))
    A.put("ROOF", *roof_strip(41))
    A.put("CONCRETE", *concrete_strip(53))
    A.put("GLASS", *glass_strip(61, accent=accent))
    return A


def normal_map(Hm, strength=0.8):
    # sample neighbours with wrap in U, clamp in V (strips must not bleed into each other: gradients are masked at strip seams)
    dx = (np.roll(Hm, -1, 1) - np.roll(Hm, 1, 1)) * 0.5
    dy = np.zeros_like(Hm)
    dy[1:-1] = (Hm[2:] - Hm[:-2]) * 0.5
    for v0, v1 in STRIPS.values():
        dy[v0] = 0; dy[v1 - 1] = 0
    nx = -dx * strength; ny = -dy * strength; nz = np.ones_like(Hm)
    L = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / L, ny / L, nz / L], -1) * 0.5 + 0.5      # OpenGL: +Y = up (v up)


def save_png(path, arr):
    a = np.clip(np.round(arr * 255), 0, 255).astype(np.uint8)
    a = np.flipud(a)                                             # v-up -> image rows top-down
    if a.ndim == 2:
        a = a[..., None]
    h, w, c = a.shape
    raw = b"".join(b"\x00" + a[y].tobytes() for y in range(h))
    ctype = {1: 0, 3: 2, 4: 6}[c]
    def chunk(t, d):
        x = struct.pack(">I", len(d)) + t + d
        return x + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, ctype, 0, 0, 0)) \
        + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else OUT_DEFAULT
    accent = sys.argv[2] if len(sys.argv) > 2 else "amber"
    os.makedirs(out, exist_ok=True)
    A = build(accent)
    save_png(os.path.join(out, "GF_Kit_BC.png"), A.C)
    save_png(os.path.join(out, "GF_Kit_N.png"), normal_map(A.H))
    rm = np.stack([np.zeros_like(A.R), A.R, A.M], -1)           # G = roughness, B = metalness (hero convention)
    save_png(os.path.join(out, "GF_Kit_RM.png"), rm)
    print("wrote atlas to", out)


if __name__ == "__main__":
    main()
