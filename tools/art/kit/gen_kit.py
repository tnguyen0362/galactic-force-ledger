"""
GALACTIC FORCE Phase 15 - hard-surface architecture kit generator (Blender, headless).

Usage:
  blender -b --factory-startup --python gen_kit.py -- <out_dir> [Human|Ascendancy]

Two independent kits (NOT recolours of each other - different silhouettes and construction logic):
  Human       - Super-Earth-style fortified field outpost: graphite/navy/steel/ceramic, cyan lights, muted gold
                stencil. Chunky, functional, bolted, sandbagged.
  Ascendancy  - restrained, imposing monolithic masonry: obsidian/violet-gray with bronze inlay, ivory accents,
                a few thin violet slits. No horns, crystals, capes or ornamental spikes.
One mesh + one material + one embedded 128x128 palette PNG per faction (8 columns, vertical dark->light
gradient so hard surfaces get free base-darkening). Designed in metres, scaled x3.57 so 1 Blender unit = 1 stud at
the game's character scale. Origin = bottom centre. Names: Kit_<Faction>_<Piece>.
Deterministic. Poly budget per piece is kept low (props 100-900 tris, buildings < 2500).
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kitlib import *


# ======================================================================== HUMAN KIT
def h_wall(k):
    k.box((0, 0, 0.25), (8.0, 1.2, 0.5), CO)                         # plinth
    k.box((0, 0, 1.75), (7.6, 0.7, 2.5), G)                          # main panel
    for x in (-3.6, 0, 3.6):
        k.box((x, 0, 1.75), (0.34, 0.95, 2.5), N)                    # ribs
    for x in (-1.8, 1.8):
        k.box((x, 0, 1.45), (1.6, 0.76, 0.9), ST)                   # armour inserts
    k.box((0, 0, 3.12), (8.0, 1.0, 0.24), ST)                        # cap
    k.box((0, 0.37, 2.5), (7.0, 0.05, 0.07), CY)                     # light strip (both faces)
    k.box((0, -0.37, 2.5), (7.0, 0.05, 0.07), CY)
    for x in (-3.0, 3.0):
        k.box((x, -0.4, 0.8), (0.9, 0.04, 0.35), GO)                # stencil


def h_pillar(k):
    k.box((0, 0, 0.3), (1.9, 1.9, 0.6), CO)
    k.box((0, 0, 2.2), (1.4, 1.4, 3.2), G)
    for a in (0, 1, 2, 3):
        k.box((0.72 * math.cos(a * math.pi / 2), 0.72 * math.sin(a * math.pi / 2), 2.2),
              (0.18 if a % 2 == 0 else 1.0, 1.0 if a % 2 == 0 else 0.18, 3.0), N)
    k.box((0, 0, 3.95), (1.7, 1.7, 0.3), ST)
    k.cyl(0, 0, 4.1, 0.28, 0.35, 8, CY)                             # beacon lamp
    k.cyl(0, 0, 4.45, 0.2, 0.12, 8, ST)


def h_bunker(k):
    k.box((0, 0, 0.3), (9.4, 7.4, 0.6), CO)
    k.box((0, 0, 1.9), (9.0, 7.0, 2.6), CO)
    k.box((0, 0, 1.9), (9.2, 6.2, 2.4), G)                           # side armour bands
    k.box((0, 0, 1.9), (8.2, 7.2, 2.4), G)
    k.wedge((0, 0), 9.4, 7.8, 3.1, 3.35, 3.55, ST)                  # roof slab
    k.box((0, -3.55, 2.3), (4.0, 0.22, 0.7), RB)                     # firing slit (front)
    k.box((0, -3.62, 2.3), (4.2, 0.08, 0.1), CY)
    k.box((-3.3, -3.52, 1.3), (1.4, 0.26, 2.1), N)                   # door
    k.box((-3.3, -3.66, 1.3), (1.1, 0.06, 1.8), RB)
    k.box((3.4, -3.52, 1.6), (1.2, 0.18, 1.2), ST)                   # vent plate
    k.box((0, 0, 3.7), (9.0, 7.4, 0.14), CE)                         # ceramic roof stripe frame
    k.box((0, -3.65, 3.0), (8.6, 0.14, 0.14), GO)
    k.box((2.8, 1.5, 4.0), (1.6, 1.6, 0.9), N)                       # roof unit
    k.cyl(-2.8, 1.2, 3.75, 0.15, 3.4, 6, ST)                         # antenna
    k.cyl(-2.8, 1.2, 7.0, 0.3, 0.12, 8, CY)
    for i in range(7):                                               # sandbag wall front
        for r in range(2):
            x = -4.2 + i * 1.35 + (0.65 if r else 0)
            if abs(x) < 4.6:
                k.box((x, -4.7, 0.2 + r * 0.38), (1.2, 0.8, 0.36), GO, (0, 0, math.radians(2 if (i + r) % 2 else -2)))


def h_tower(k):
    for sx in (-1, 1):
        for sy in (-1, 1):
            k.beam((sx * 1.9, sy * 1.9, 0), (sx * 1.35, sy * 1.35, 9.0), 0.34, G)
    for z0, z1 in ((0.0, 4.5), (4.5, 9.0)):
        w0 = 1.9 - 0.55 * z0 / 9.0
        w1 = 1.9 - 0.55 * z1 / 9.0
        for s in (-1, 1):
            k.beam((-w0, s * w0, z0), (w1, s * w1, z1), 0.14, ST)
            k.beam((w0, s * w0, z0), (-w1, s * w1, z1), 0.14, ST)
            k.beam((s * w0, -w0, z0), (s * w1, w1, z1), 0.14, ST)
            k.beam((s * w0, w0, z0), (s * w1, -w1, z1), 0.14, ST)
    k.box((0, 0, 0.2), (4.6, 4.6, 0.4), CO)
    k.box((0, 0, 9.15), (4.0, 4.0, 0.3), ST)                         # platform
    k.box((0, 0, 10.35), (3.2, 3.2, 2.1), G)                         # cabin
    k.box((0, -1.62, 10.5), (2.8, 0.06, 0.5), CY)                    # window band
    k.box((0, 1.62, 10.5), (2.8, 0.06, 0.5), CY)
    k.box((1.62, 0, 10.5), (0.06, 2.8, 0.5), CY)
    k.box((-1.62, 0, 10.5), (0.06, 2.8, 0.5), CY)
    k.wedge((0, 0), 4.0, 4.0, 11.4, 11.6, 11.9, N)                   # roof
    for sx in (-1, 1):                                               # rails
        k.box((sx * 1.95, 0, 9.75), (0.08, 3.9, 0.08), CE)
        k.box((0, sx * 1.95, 9.75), (3.9, 0.08, 0.08), CE)
    k.cyl(1.3, -1.3, 11.9, 0.35, 0.45, 8, ST)                        # searchlight
    k.cyl(1.3, -1.3, 12.35, 0.28, 0.1, 8, CY)
    k.cyl(-1.2, 1.2, 11.9, 0.1, 3.0, 6, ST)                          # mast
    k.beam((-1.45, -0.6, 0.4), (-1.3, -0.6, 9.0), 0.06, CE)          # ladder rails
    k.beam((-1.15, -0.6, 0.4), (-1.0, -0.6, 9.0), 0.06, CE)
    for i in range(1, 16):
        z = i * 0.56
        k.box((-1.22 + 0.15 * z / 9.0, -0.6, z), (0.4, 0.05, 0.05), CE)


def h_barrier(k):
    prof = [(-0.5, 0.0), (0.5, 0.0), (0.42, 0.28), (0.18, 0.9), (0.1, 1.0), (-0.1, 1.0), (-0.18, 0.9), (-0.42, 0.28)]
    for i in range(3):
        x0 = -3.6 + i * 2.45
        k.prism(prof, x0, x0 + 2.35, CO)
        k.box((x0 + 1.175, 0, 1.02), (2.0, 0.22, 0.08), GO)         # hazard top stripe
    k.box((0, 0, 1.12), (7.4, 0.28, 0.14), RB)


def h_hedgehog(k):
    for ax in ((1, 0.55, 0.3), (-1, 0.55, 0.3), (0.2, 1, 0.5)):
        v = Vector(ax).normalized() * 1.5
        k.beam((-v.x, -v.y, 1.3 - v.z), (v.x, v.y, 1.3 + v.z), 0.22, ST)
    k.box((0, 0, 1.3), (0.5, 0.5, 0.5), N)


def h_crate(k):
    k.box((0, 0, 0.55), (1.7, 1.2, 1.1), G)
    for x in (-0.7, 0.7):
        k.box((x, 0, 0.55), (0.14, 1.28, 1.16), ST)
    k.box((0, 0, 0.55), (1.76, 1.24, 0.14), ST)
    k.box((0, -0.62, 0.6), (0.9, 0.03, 0.4), GO)


def h_crates(k):
    k.box((-0.9, 0, 0.5), (1.7, 1.2, 1.0), G)
    k.box((0.95, 0.1, 0.4), (1.4, 1.0, 0.8), N)
    k.box((-0.7, 0.05, 1.45), (1.2, 1.0, 0.9), ST)
    k.box((0.9, 0.1, 1.15), (0.9, 0.8, 0.6), G, (0, 0, math.radians(12)))
    for p in ((-0.9, 0, 0.5), (-0.7, 0.05, 1.45)):
        k.box((p[0], p[1] - 0.62, p[2] + 0.05), (0.8, 0.03, 0.3), GO)


def h_tank(k):
    k.cyl(0, 0, 0.0, 1.6, 0.3, 12, CO)
    k.cyl(0, 0, 0.3, 1.35, 3.0, 12, ST)
    k.cyl(0, 0, 3.3, 1.35, 0.45, 12, ST, r2=0.7)
    k.cyl(0, 0, 3.75, 0.55, 0.25, 8, G)
    for z in (0.9, 2.3):
        k.cyl(0, 0, z, 1.42, 0.14, 12, GO)
    k.beam((1.0, -1.0, 0.3), (1.0, -1.0, 3.3), 0.1, G)
    k.beam((1.0, -1.0, 3.3), (0.2, -0.2, 3.75), 0.1, G)


def h_generator(k):
    k.box((0, 0, 0.15), (3.2, 2.0, 0.3), CO)
    k.box((0, 0, 1.0), (2.8, 1.6, 1.4), G)
    k.box((0, -0.82, 1.1), (1.6, 0.06, 0.8), N)
    k.box((0.8, -0.84, 1.2), (0.5, 0.04, 0.25), CY)
    k.box((-0.8, -0.84, 1.2), (0.5, 0.04, 0.25), GO)
    k.wedge((0, 0), 3.0, 1.8, 1.7, 1.8, 2.0, ST)
    k.cyl(-0.9, 0.3, 1.9, 0.18, 1.1, 8, RB)
    k.cyl(-0.9, 0.3, 3.0, 0.24, 0.08, 8, ST)
    k.cyl(0.8, 0.3, 1.9, 0.14, 0.7, 8, RB)


def h_mast(k):
    H = 14.0
    legs = []
    for i in range(3):
        a = i * 2 * math.pi / 3 + math.pi / 6
        legs.append((math.cos(a), math.sin(a)))
    for (lx, ly) in legs:
        k.beam((lx * 1.1, ly * 1.1, 0), (lx * 0.28, ly * 0.28, H), 0.16, G)
    for z0 in (0.0, 3.5, 7.0, 10.5):
        z1 = z0 + 3.5
        r0 = 1.1 - 0.82 * z0 / H
        r1 = 1.1 - 0.82 * z1 / H
        for i in range(3):
            a, b = legs[i], legs[(i + 1) % 3]
            k.beam((a[0] * r0, a[1] * r0, z0), (b[0] * r1, b[1] * r1, z1), 0.07, ST)
            k.beam((b[0] * r0, b[1] * r0, z0), (a[0] * r1, a[1] * r1, z1), 0.07, ST)
            k.beam((a[0] * r1, a[1] * r1, z1), (b[0] * r1, b[1] * r1, z1), 0.08, ST)
    k.box((0, 0, 0.2), (3.0, 3.0, 0.4), CO)
    k.cyl(0, 0, H, 0.12, 2.6, 6, ST)
    k.cyl(0, 0, H + 2.6, 0.2, 0.18, 8, CY)
    k.loft((0.5, -0.4, H - 3.0), (1.6, -1.2, H - 2.3), 0.12, 1.4, 12, CE)  # dish
    k.beam((0.0, 0.0, H - 3.0), (0.5, -0.4, H - 3.0), 0.12, ST)


# ======================================================================== ASCENDANCY KIT
def a_bulwark(k):
    k.box((0, 0, 0.3), (8.4, 1.8, 0.6), DS)
    for i, x in enumerate((-2.9, 0.0, 2.9)):
        tilt = math.radians(7 if i % 2 == 0 else -7)
        k.box((x, 0, 2.9), (2.6, 0.95, 4.6), OB, (tilt, 0, 0))
        k.box((x, 0, 5.3), (2.8, 1.1, 0.18), BR, (tilt, 0, 0))
        k.box((x, 0, 3.0), (2.7, 1.04, 0.22), VG, (tilt, 0, 0))
    k.box((0, 0, 0.7), (8.0, 1.5, 0.2), AB)




def ashlar(k, cx, cy, w, d, z0, h, rows, col=None, seed=0):
    """Dark joint lines + staggered vertical joints on all four faces of a prismatic mass: reads as cut stone courses."""
    col = AS if col is None else col
    rh = h / rows
    for r in range(1, rows):
        k.box((cx, cy, z0 + r * rh), (w + 0.05, d + 0.05, 0.05), col)
    n = max(2, int(w / 1.1))
    for r in range(rows):
        off = 0.5 if (r + seed) % 2 else 0.0
        for i in range(n):
            x = cx - w / 2 + (i + off) * (w / n)
            if abs(x - cx) < w / 2 - 0.1:
                zc = z0 + (r + 0.5) * rh
                k.box((x, cy + d / 2, zc), (0.05, 0.05, rh), col)
                k.box((x, cy - d / 2, zc), (0.05, 0.05, rh), col)


def a_monolith(k):
    for i, (w, d, z) in enumerate(((5.2, 2.6, 0.5), (4.2, 2.1, 0.5), (3.3, 1.6, 0.5))):
        k.box((0, 0, 0.25 + 0.5 * i), (w, d, z), DS if i != 1 else AS)
    k.box((0, 0, 7.6), (2.5, 1.0, 12.0), VG)                         # main shaft: violet-gray stone
    ashlar(k, 0, 0, 2.5, 1.0, 1.6, 12.0, 8, AS)
    k.box((0, 0, 7.6), (1.9, 1.04, 10.4), OB)                        # recessed obsidian face panel
    k.box((0, 0, 7.6), (1.9, 1.08, 0.12), BR)                        # panel mid band
    k.wedge((0, 0), 2.5, 1.0, 13.6, 13.7, 14.5, OB)                  # canted crown
    k.box((0, 0, 13.45), (2.7, 1.2, 0.2), IV)                        # ivory cap course
    k.box((0, 0.56, 8.9), (0.09, 0.05, 3.2), VI)                     # restrained violet slit
    k.box((0, -0.56, 8.9), (0.09, 0.05, 3.2), VI)
    for sx in (-1, 1):
        k.box((sx * 1.36, 0, 6.0), (0.3, 1.3, 8.8), OB)              # buttress fins
        k.box((sx * 1.36, 0, 10.6), (0.34, 1.34, 0.22), BR)
    for z in (2.4, 11.9):
        k.box((0, 0.54, z), (2.3, 0.05, 0.12), BR)
        k.box((0, -0.54, z), (2.3, 0.05, 0.12), BR)


def a_gate(k):
    for sx in (-1, 1):
        k.box((sx * 5.4, 0, 0.45), (3.6, 3.6, 0.9), DS)
        k.box((sx * 5.4, 0, 6.6), (2.2, 2.2, 11.4), VG)
        ashlar(k, sx * 5.4, 0, 2.2, 2.2, 0.9, 11.4, 9, AS, seed=sx)
        k.box((sx * 5.4, 1.13, 6.0), (0.9, 0.05, 8.4), OB)           # recessed face inlay
        k.box((sx * 5.4, -1.13, 6.0), (0.9, 0.05, 8.4), OB)
        k.box((sx * 5.4, 1.15, 6.0), (0.12, 0.04, 8.2), BR)
        k.box((sx * 5.4, -1.15, 6.0), (0.12, 0.04, 8.2), BR)
        k.box((sx * 5.4, 0, 12.5), (2.8, 2.8, 0.5), OB)
        k.box((sx * 5.4, 0, 12.85), (2.5, 2.5, 0.2), IV)
    k.box((0, 0, 11.6), (13.2, 2.6, 1.6), VG)                        # lintel
    ashlar(k, 0, 0, 13.2, 2.6, 10.8, 1.6, 2, AS, seed=1)
    k.box((0, 0, 12.7), (14.0, 2.9, 0.4), OB)
    k.box((0, 0, 13.05), (13.4, 2.6, 0.2), IV)
    k.box((0, 1.33, 11.6), (11.6, 0.05, 0.14), BR)
    k.box((0, -1.33, 11.6), (11.6, 0.05, 0.14), BR)
    k.box((0, -1.36, 11.6), (1.0, 0.07, 1.1), IV)
    k.box((0, 1.36, 11.6), (1.0, 0.07, 1.1), IV)
    k.box((0, 0, 0.1), (8.2, 3.0, 0.2), AS)


def a_spire(k):
    for i, r in enumerate((3.4, 2.8, 2.3)):
        k.loft((0, 0, i * 0.55), (0, 0, (i + 1) * 0.55), r, r * 0.95, 4, DS if i < 2 else VG, rot0=math.pi / 4)
    k.loft((0, 0, 1.65), (0, 0, 8.0), 1.7, 1.12, 4, OB, rot0=math.pi / 4)
    k.loft((0, 0, 8.0), (0, 0, 15.0), 1.12, 0.55, 4, VG, rot0=math.pi / 4)
    for z, r in ((5.0, 1.45), (9.0, 1.12), (12.5, 0.8)):
        k.loft((0, 0, z), (0, 0, z + 0.22), r * 1.08, r * 1.08, 4, BR, rot0=math.pi / 4)
    for z, r in ((3.3, 1.58), (6.9, 1.28), (10.8, 0.96), (13.8, 0.68)):
        k.loft((0, 0, z), (0, 0, z + 0.1), r * 1.04, r * 1.04, 4, AS, rot0=math.pi / 4)
    k.loft((0, 0, 15.0), (0, 0, 16.4), 0.55, 0.12, 4, IV, rot0=math.pi / 4)
    k.box((0.0, -0.62, 7.0), (0.08, 0.05, 3.0), VI)


def a_rubble_block(k):
    k.box((-1.3, 0.0, 0.45), (2.8, 2.0, 0.9), OB, (0.05, 0.12, 0.2))
    k.box((-1.1, 0.1, 1.15), (2.2, 1.7, 0.8), VG, (-0.1, 0.08, 0.35))
    k.box((1.7, 0.7, 0.55), (2.0, 1.6, 1.1), OB, (0.1, -0.15, -0.4))
    k.box((0.2, 2.0, 0.35), (1.8, 1.3, 0.7), VG, (0.2, 0.1, 0.7))
    k.box((2.4, -0.9, 0.2), (1.2, 0.9, 0.4), DS, (0, 0.2, 0.9))
    k.box((-2.5, 1.5, 0.18), (1.0, 0.8, 0.36), AS, (0.1, 0, 1.2))
    k.box((0.6, -1.4, 0.15), (0.8, 0.6, 0.3), DS, (0.2, 0.1, 0.3))
    k.box((-1.1, -0.9, 1.55), (1.6, 0.06, 0.12), BR, (-0.1, 0.08, 0.35))


def a_wall(k):
    k.box((0, 0, 0.3), (8.6, 1.8, 0.6), DS)
    k.box((0, 0, 1.7), (8.0, 1.2, 2.2), VG)
    ashlar(k, 0, 0, 8.0, 1.2, 0.6, 2.2, 3, AS)
    k.box((0, 0, 2.9), (8.4, 1.5, 0.3), OB)
    k.box((0, 0, 3.12), (8.0, 1.2, 0.14), IV)
    for x in (-3.9, 3.9):
        k.box((x, 0, 1.9), (0.5, 1.5, 2.6), OB)
    k.box((0, 0.62, 1.7), (5.6, 0.05, 0.1), BR)
    k.box((0, -0.62, 1.7), (5.6, 0.05, 0.1), BR)



KITS = {
    "Human": [("Wall", h_wall), ("Pillar", h_pillar), ("Bunker", h_bunker), ("Watchtower", h_tower),
              ("Barrier", h_barrier), ("Hedgehog", h_hedgehog), ("Crate", h_crate), ("Crates", h_crates),
              ("FuelTank", h_tank), ("Generator", h_generator), ("CommMast", h_mast)],
    "Ascendancy": [("Monolith", a_monolith), ("Gate", a_gate), ("Bulwark", a_bulwark), ("Spire", a_spire),
                   ("Rubble", a_rubble_block), ("Wall", a_wall)],
}


if __name__ == "__main__":
    clear_scene()
    run_kits(KITS)
