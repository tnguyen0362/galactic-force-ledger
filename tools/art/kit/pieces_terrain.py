"""Terrain kit: faceted rocks + cliffs (neutral palette, tint with MeshPart.Color per biome) and the Human war-table dais
+ holographic planet. Deterministic (seeded). Metres in, studs out."""
import math, random
from kitlib import *

T0, T1, T2, T3, T4, T5, T6, T7 = range(8)


def sphere_rows(k, c, rx, ry, rz, rings, sides, rnd=None, jitter=0.0, flat=None):
    cx, cy, cz = c
    rows = []
    for r in range(rings + 1):
        phi = math.pi * r / rings
        n = 1 if r in (0, rings) else sides
        ring = []
        for s in range(n):
            th = 2 * math.pi * s / sides
            j = 1.0
            zj = 1.0
            if rnd is not None:
                th += rnd.uniform(-0.18, 0.18)
                j = 1 + rnd.uniform(-jitter, jitter)
                zj = 1 + rnd.uniform(-jitter, jitter) * 0.6
            x = math.sin(phi) * math.cos(th) * rx * j
            y = math.sin(phi) * math.sin(th) * ry * j
            z = math.cos(phi) * rz * zj
            if flat is not None and z < -rz * (1 - flat):
                z = -rz * (1 - flat)
            ring.append(k.bm.verts.new((cx + x, cy + y, cz + z)))
        rows.append(ring)
    return rows


def skin_rows(k, rows, sides, colfor):
    for r in range(len(rows) - 1):
        cc = colfor(r)
        a, b = rows[r], rows[r + 1]
        if len(a) == 1:
            for s in range(sides):
                k._quad([a[0], b[(s + 1) % sides], b[s]], cc)
        elif len(b) == 1:
            for s in range(sides):
                k._quad([a[s], a[(s + 1) % sides], b[0]], cc)
        else:
            for s in range(sides):
                s2 = (s + 1) % sides
                k._quad([a[s], a[s2], b[s2], b[s]], cc)


def blob(k, c, rx, ry, rz, seed, cols, rings=5, sides=8, jitter=0.22, flat=0.35):
    """Faceted lumpy ellipsoid, bottom flattened so it sits on terrain. cols = per-ring colour list (top->bottom)."""
    rnd = random.Random(seed)
    rows = sphere_rows(k, c, rx, ry, rz, rings, sides, rnd, jitter, flat)
    skin_rows(k, rows, sides, lambda r: cols[min(r, len(cols) - 1)])


def rock_small(k):  # ~1.3 m
    blob(k, (0, 0, 0.55), 0.8, 0.7, 0.6, 11, [T3, T2, T2, T1, T0])


def rock_mid(k):  # ~2 m
    blob(k, (0, 0, 0.9), 1.3, 1.1, 0.95, 23, [T3, T3, T2, T1, T0], jitter=0.25)
    blob(k, (1.1, 0.4, 0.35), 0.6, 0.5, 0.4, 5, [T2, T2, T1, T1, T0])


def rock_big(k):  # ~3.2 m boulder
    blob(k, (0, 0, 1.4), 2.0, 1.7, 1.5, 37, [T3, T3, T2, T2, T0, T0], rings=6, sides=9, jitter=0.28)
    blob(k, (-1.6, 0.8, 0.5), 0.9, 0.8, 0.6, 8, [T2, T2, T1, T1, T0])
    blob(k, (1.5, -1.0, 0.45), 0.7, 0.6, 0.5, 9, [T3, T2, T1, T1, T0])


def rock_slab(k):  # leaning slab ~3.5 m tall, cover-friendly
    k.box((0, 0, 1.7), (2.4, 0.9, 3.4), T2, (0.08, 0.0, 0.15))
    k.box((0.2, 0, 3.45), (2.0, 0.8, 0.3), T3, (0.1, 0, 0.12))
    k.box((0.2, 0.05, 0.3), (2.8, 1.4, 0.6), T1)
    blob(k, (-1.5, 0.3, 0.45), 0.7, 0.6, 0.5, 31, [T2, T2, T1, T1, T0])


def rock_spire(k):  # tall pointed rock ~6 m
    blob(k, (0, 0, 0.9), 1.6, 1.4, 0.9, 41, [T2, T2, T1, T1, T0])
    k.loft((0, 0, 1.2), (0.2, 0.1, 6.0), 1.2, 0.12, 6, T3)
    k.loft((0, 0, 1.2), (0.2, 0.1, 3.8), 1.22, 0.7, 6, T1, rot0=0.3, cap=False)


def rock_cluster(k):  # group of 5 for scatter
    for x, y, r, sd in [(0, 0, 1.0, 51), (1.6, 0.8, 0.7, 52), (-1.4, 0.9, 0.6, 53), (0.4, -1.5, 0.55, 54), (-0.6, -1.0, 0.4, 55)]:
        blob(k, (x, y, r * 0.6), r * 1.1, r, r * 0.8, sd, [T3, T2, T2, T1, T0])


def _mass(k, x, y, rx, ry, h, seed, cols, sides=7, rings=6, jitter=0.2):
    """Big faceted rock mass standing on z=0 (spans z 0..h): lumpy ellipsoid, flat base, strata colour per ring."""
    rz = h / 1.18
    rows = sphere_rows(k, (x, y, rz * 0.4), rx, ry, rz, rings, sides, random.Random(seed), jitter, 0.6)
    for ring in rows:  # plateau top: clamp the crown flat so summits read as buttes, not needles
        for v in ring:
            v.co.z = min(v.co.z, h * random.Random(seed + 5).uniform(0.97, 1.0))
    skin_rows(k, rows, sides, lambda r: cols[min(r, len(cols) - 1)])


_STRATA = [[T3, T4, T2, T6, T1, T0], [T3, T2, T4, T1, T6, T0], [T6, T4, T2, T2, T1, T0], [T3, T6, T2, T4, T1, T1]]


def _wall(k, x0, y0, ang, w, d, h, seed, n, hmin=0.55):
    """Massed cliff wall along direction `ang`: n overlapping rock masses (tallest in the middle-ish), a setback
    summit mass on the tall ones, jutting strata ledges on the face, and a scree apron. Front face is local -Y."""
    rnd = random.Random(seed)
    ca, sa = math.cos(ang), math.sin(ang)
    P = lambda u, v: (x0 + u * ca - v * sa, y0 + u * sa + v * ca)
    for i in range(n):
        u = ((i + 0.5) / n - 0.5) * w + rnd.uniform(-0.4, 0.4)
        v = rnd.uniform(-d * 0.12, d * 0.12)
        rx = (w / n) * rnd.uniform(0.78, 1.0)
        ry = d * rnd.uniform(0.38, 0.5)
        hh = h * (hmin + (1 - hmin) * rnd.random() ** 0.7)
        px, py = P(u, v)
        _mass(k, px, py, rx, ry, hh, seed * 13 + i, rnd.choice(_STRATA), sides=rnd.choice((6, 7, 8)))
        if hh > h * 0.8:  # setback summit
            sx, sy = P(u + rnd.uniform(-0.3, 0.3) * rx, v + d * 0.08)
            _mass(k, sx, sy, rx * 0.55, ry * 0.6, hh * rnd.uniform(1.12, 1.28), seed * 17 + i, [T3, T6, T4, T2, T1, T0], sides=6, jitter=0.25)
        # jutting strata ledge on the front face
        if rnd.random() < 0.85:
            lz = hh * rnd.uniform(0.28, 0.6)
            lx, ly = P(u + rnd.uniform(-0.2, 0.2) * rx, v - ry * 0.85)
            k.box((lx, ly, lz), (rx * 1.05, 0.8, 0.38), rnd.choice((T6, T4, T3)), (rnd.uniform(-0.06, 0.06), 0, ang + rnd.uniform(-0.12, 0.12)))
    for i in range(max(3, n)):  # scree apron + fallen blocks
        u = rnd.uniform(-w * 0.5, w * 0.5)
        v = rnd.uniform(-d * 0.7, -d * 0.35)
        px, py = P(u, v)
        if i % 3 == 0:
            k.box((px, py, 0.35), (rnd.uniform(0.9, 1.5), rnd.uniform(0.8, 1.3), 0.8), rnd.choice((T2, T6)), (0.12, 0.1, rnd.uniform(0, 3)))
        else:
            blob(k, (px, py, 0.4), rnd.uniform(0.7, 1.3), rnd.uniform(0.6, 1.1), rnd.uniform(0.5, 0.8), seed * 7 + i, [T3, T2, T1, T1, T0])


def cliff_a(k):  # broad cliff face ~14 x 6 x 9 m
    _wall(k, 0, 0, 0.0, 14, 6, 9, 100, 5)


def cliff_b(k):  # narrow tall bluff ~8 x 6 x 11 m
    _wall(k, 0, 0, 0.0, 8, 6, 11, 210, 3, 0.7)


def cliff_c(k):  # low mesa ~16 x 10 x 5 m (broad stacked slabs)
    rnd = random.Random(300)
    z = 0.0
    r = 7.0
    for i, th in enumerate((1.8, 1.6, 1.4)):
        k.loft((0, 0, z), (0, 0, z + th), r, r * 0.93, 9, [T4, T2, T6][i], rot0=0.2 + i * 0.35, cap=(i == 2))
        k.loft((0, 0, z + th), (0, 0, z + th + 0.12), r * 0.93, r * 0.86, 9, T3, rot0=0.2 + i * 0.35, cap=(i == 2))
        z += th + 0.12
        r *= 0.86
    for i in range(5):
        a = i * 1.3 + 0.4
        blob(k, (math.cos(a) * 7.0, math.sin(a) * 5.5, 0.5), rnd.uniform(1.2, 1.7), rnd.uniform(1.0, 1.4), rnd.uniform(0.8, 1.1), 310 + i, [T3, T2, T1, T1, T0])
    for i in range(4):  # chipped slab edges
        a = i * 1.7 + 0.9
        k.box((math.cos(a) * 6.3, math.sin(a) * 4.9, 1.1), (1.8, 0.8, 0.5), [T6, T4][i % 2], (0.1, 0.1, a + 1.57))


def cliff_d(k):  # sheer wall corner ~10 x 10 x 12 m (two walls meeting at 90 deg)
    _wall(k, 0, 0, 0.0, 10, 4, 12, 400, 4, 0.6)
    _wall(k, 5.0, 4.5, math.pi / 2, 9, 4, 11, 410, 3, 0.6)
    _mass(k, 4.6, -0.6, 2.4, 2.2, 13.5, 420, [T3, T6, T4, T2, T1, T0], sides=6, jitter=0.24)  # corner buttress tower


# ----------------------------------------------------------------- war table (Human palette)
def h_dais(k):
    """War-table dais 9.5 m octagonal, 1.1 m tall: stepped plinth, cyan groove ring, central projector pedestal."""
    o = math.pi / 8
    k.loft((0, 0, 0), (0, 0, 0.35), 4.75, 4.6, 8, G, rot0=o)
    k.loft((0, 0, 0.35), (0, 0, 0.7), 4.4, 4.25, 8, N, rot0=o)
    k.loft((0, 0, 0.7), (0, 0, 0.8), 4.0, 4.0, 8, CY, rot0=o)
    k.loft((0, 0, 0.8), (0, 0, 1.1), 3.7, 3.7, 8, ST, rot0=o)
    for i in range(8):
        a = i * math.pi / 4
        k.box((math.cos(a) * 4.55, math.sin(a) * 4.55, 0.55), (0.9, 0.3, 0.5), GO, (0, 0, a + math.pi / 2))
    k.loft((0, 0, 1.1), (0, 0, 1.5), 1.2, 1.0, 8, G)
    k.loft((0, 0, 1.5), (0, 0, 1.62), 0.7, 0.7, 8, CY)
    for i in range(3):
        a = i * 2 * math.pi / 3 + 0.5
        k.beam((math.cos(a) * 1.0, math.sin(a) * 1.0, 1.1), (math.cos(a) * 0.5, math.sin(a) * 0.5, 2.0), 0.18, ST)


def h_holo_planet(k):
    """Hologram planet 3 m diameter + tilted ring (use Neon material in Roblox). Origin bbox bottom."""
    r = 1.5
    sides = 14
    rows = sphere_rows(k, (0, 0, r), r, r, r, 8, sides)
    bands = [CY, ST, CY, CE, CY, ST, CY, CY]
    skin_rows(k, rows, sides, lambda i: bands[i])
    seg = 24
    tilt = 0.35

    def P(a):
        return (math.cos(a) * 2.3, math.sin(a) * 2.3 * math.cos(tilt), r + math.sin(a) * 2.3 * math.sin(tilt))

    for i in range(seg):
        k.beam(P(2 * math.pi * i / seg), P(2 * math.pi * (i + 1) / seg), 0.07, CE, 0.03)


def h_holo_slot_ring(k):
    """Low floor ring emitter for war-table squad slots."""
    k.loft((0, 0, 0), (0, 0, 0.12), 0.9, 0.85, 12, G)
    k.loft((0, 0, 0.12), (0, 0, 0.16), 0.75, 0.75, 12, CY)
    k.loft((0, 0, 0.16), (0, 0, 0.2), 0.45, 0.45, 12, ST)


PIECES_TERRAIN = [("RockSmall", rock_small), ("RockMid", rock_mid), ("RockBig", rock_big), ("RockSlab", rock_slab),
                  ("RockSpire", rock_spire), ("RockCluster", rock_cluster),
                  ("CliffA", cliff_a), ("CliffB", cliff_b), ("CliffC", cliff_c), ("CliffD", cliff_d)]
PIECES_WARTABLE = [("WarTableDais", h_dais), ("HoloPlanet", h_holo_planet), ("HoloSlotRing", h_holo_slot_ring)]
