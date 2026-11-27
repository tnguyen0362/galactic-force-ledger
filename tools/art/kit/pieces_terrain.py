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


def _col(k, x, y, r, h, rnd, sides=6, shade=0):
    """Sheer faceted rock column: near-vertical sides with a banded strata colour, slanted chisel top."""
    rot = rnd.uniform(0, 1.0)
    lean = (rnd.uniform(-0.12, 0.12) * h, rnd.uniform(-0.12, 0.12) * h)
    bands = [T4, T2, T6, T1, T3, T2]
    z = 0.0
    n = max(2, int(h / 2.2))
    for i in range(n):
        z1 = h * (i + 1) / n
        z0 = h * i / n
        t0, t1 = z0 / h, z1 / h
        r0 = r * (1 - 0.18 * t0)
        r1 = r * (1 - 0.18 * t1)
        k.loft((x + lean[0] * t0, y + lean[1] * t0, z0), (x + lean[0] * t1, y + lean[1] * t1, z1), r0, r1, sides,
               bands[(i + shade) % len(bands)], rot0=rot, cap=False)
    # slanted cap
    top = (x + lean[0], y + lean[1], h)
    k.loft(top, (top[0] + r * 0.15, top[1], h + r * 0.35), r * (1 - 0.18), r * 0.45, sides, T3, rot0=rot)


def _cliff(k, w, d, h, seed, n, hmin=0.55):
    rnd = random.Random(seed)
    cols = []
    for i in range(n):
        u = (i + 0.5) / n
        x = (u - 0.5) * w + rnd.uniform(-0.5, 0.5)
        y = rnd.uniform(-d * 0.3, d * 0.3)
        r = (w / n) * rnd.uniform(0.62, 0.85)
        hh = h * rnd.uniform(hmin, 1.0)
        cols.append((x, y, r, hh))
    cols.sort(key=lambda c: -c[2])
    for x, y, r, hh in cols:
        _col(k, x, y, r, hh, rnd, sides=rnd.choice((5, 6, 7)), shade=rnd.randint(0, 3))
    # rubble apron
    for i in range(max(2, n // 2)):
        blob(k, (rnd.uniform(-w * 0.5, w * 0.5), rnd.uniform(-d * 0.55, -d * 0.2), 0.5), rnd.uniform(0.9, 1.5), rnd.uniform(0.8, 1.2),
             rnd.uniform(0.6, 1.0), seed * 7 + i, [T3, T2, T1, T1, T0])


def cliff_a(k):  # broad cliff face ~14 x 6 x 9 m
    _cliff(k, 14, 6, 9, 100, 6)


def cliff_b(k):  # narrow bluff ~8 x 6 x 11 m
    _cliff(k, 8, 6, 11, 200, 4, 0.7)


def cliff_c(k):  # low mesa ~16 x 10 x 5 m (broad stacked slabs)
    rnd = random.Random(300)
    z = 0.0
    r = 7.0
    for i, th in enumerate((1.8, 1.6, 1.4)):
        k.loft((0, 0, z), (0, 0, z + th), r, r * 0.93, 9, [T4, T2, T6][i], rot0=0.2 + i * 0.35, cap=(i == 2))
        k.loft((0, 0, z + th), (0, 0, z + th + 0.12), r * 0.93, r * 0.86, 9, T3, rot0=0.2 + i * 0.35, cap=(i == 2))
        z += th + 0.1
        r *= 0.86
    for i in range(4):
        a = i * 1.6 + 0.4
        blob(k, (math.cos(a) * 7.0, math.sin(a) * 5.5, 0.5), 1.4, 1.1, 0.9, 310 + i, [T3, T2, T1, T1, T0])


def cliff_d(k):  # sheer wall corner ~10 x 10 x 12 m
    _cliff(k, 10, 4, 12, 400, 5, 0.6)
    rnd = random.Random(401)
    for i in range(3):
        _col(k, 4.5 + rnd.uniform(-0.3, 0.3), 2.0 + i * 1.6, 1.4, 12 * rnd.uniform(0.6, 1.0), rnd, 6, i)


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
