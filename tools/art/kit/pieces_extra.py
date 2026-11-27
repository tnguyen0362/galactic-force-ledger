"""Extra kit: Human hangar/concourse set (AD-005), planet limb + atmosphere shell (AD-006, Terrain palette, tint via
MeshPart.Color / Neon), Ascendancy turret/stairs/beacon/barricade/crate. Metres in, studs out. Deterministic."""
import math, random
from kitlib import *
from gen_kit import ashlar
from pieces_terrain import sphere_rows, T0, T1, T2, T3, T4, T5, T6, T7


# ------------------------------------------------------------------ Human concourse / hangar (AD-005)
def h_hangar_bulkhead(k):
    """8 m x 6 m hangar wall module: ribbed armour panels, hazard skirting, cable tray, strip light under a heavy header."""
    k.box((0, 0, 0.35), (8.0, 0.9, 0.7), G)
    for i in range(8):                                                  # hazard skirting blocks
        k.box((-3.5 + i, -0.46, 0.35), (0.5, 0.04, 0.5), GO if i % 2 == 0 else G)
    for i in range(4):                                                  # ribbed panels, 2 m each
        x = -3.0 + i * 2.0
        k.box((x, 0, 3.4), (1.9, 0.7, 5.2), N)
        k.box((x, -0.37, 3.4), (1.5, 0.05, 4.6), ST)
        k.box((x, -0.4, 3.4), (1.5, 0.03, 0.12), G)
        k.box((x, -0.4, 1.6), (1.5, 0.03, 0.12), G)
    for x in (-4.0, -2.0, 0.0, 2.0, 4.0):                               # vertical pilasters
        k.box((x, 0, 3.4), (0.28, 0.9, 5.4), G)
    k.box((0, 0, 5.8), (8.0, 0.95, 0.5), G)                              # header
    k.box((0, -0.5, 5.55), (6.4, 0.06, 0.1), CY)                         # strip light
    k.box((0, -0.55, 4.7), (7.0, 0.14, 0.22), RB)                        # cable tray
    for x in (-2.5, 0.0, 2.5):
        k.box((x, -0.56, 4.7), (0.12, 0.2, 0.3), ST)


def h_hangar_mouth(k):
    """10 m wide x 6 m tall hangar opening frame: massive lintel, side pylons, hazard-banded jambs, stencil plate."""
    for sx in (-1, 1):
        x = sx * 4.6
        k.box((x, 0, 3.0), (1.6, 1.4, 6.0), G)
        k.box((x - sx * 0.82, 0, 3.0), (0.1, 1.5, 6.0), N)
        for i in range(6):
            k.box((x - sx * 0.75, -0.72, 0.5 + i * 1.0), (0.1, 0.05, 0.5), GO if i % 2 == 0 else G)
        k.box((x, 0, 6.15), (1.9, 1.7, 0.3), ST)
        k.box((x, -0.72, 3.0), (0.5, 0.05, 4.4), N)
    k.box((0, 0, 6.6), (11.0, 1.6, 1.2), G)                              # lintel
    k.box((0, -0.82, 6.6), (9.0, 0.06, 0.4), N)
    k.box((0, -0.86, 6.6), (3.0, 0.04, 0.22), GO)                        # stencil plate
    for x in (-3.9, 3.9):
        k.box((x, -0.84, 6.6), (0.5, 0.05, 0.5), RB)
    k.box((0, -0.8, 5.95), (8.0, 0.06, 0.1), CY)                         # underside light line
    k.box((0, 0, 0.1), (8.8, 1.4, 0.2), ST)                              # threshold plate


def h_concourse_window(k):
    """8 m x 5 m panoramic viewport: thick armoured frame, five cyan glass panes, mullions, sill + brow light."""
    k.box((0, 0, 0.45), (8.4, 1.0, 0.9), G)                              # sill wall
    k.box((0, -0.52, 0.95), (8.6, 0.3, 0.14), ST)                        # sill ledge
    k.box((0, 0, 5.7), (8.4, 1.0, 0.8), G)                               # header
    for sx in (-1, 1):
        k.box((sx * 4.1, 0, 3.2), (0.6, 1.0, 5.0), G)
    for i in range(5):
        x = -3.2 + i * 1.6
        k.box((x, 0, 3.3), (1.45, 0.08, 4.2), CY)
    for i in range(4):
        k.box((-2.4 + i * 1.6, 0, 3.3), (0.16, 0.5, 4.3), N)
    k.box((0, 0, 1.45), (7.6, 0.5, 0.12), N)
    k.box((0, 0, 5.15), (7.6, 0.5, 0.12), N)
    k.box((0, -0.5, 5.3), (6.0, 0.05, 0.08), CY)
    k.box((-3.6, -0.53, 0.5), (0.5, 0.04, 0.4), GO)


def h_concourse_terminal(k):
    """Standing info/mission console, 1.9 m tall: slanted screen, button deck, base."""
    k.box((0, 0, 0.35), (1.3, 0.9, 0.7), G)
    k.box((0, 0, 0.95), (1.0, 0.7, 0.5), N)
    k.box((0, -0.2, 1.25), (0.9, 0.35, 0.1), ST, (0.35, 0, 0))
    k.box((0, 0.05, 1.5), (1.1, 0.14, 0.9), G, (-0.25, 0, 0))
    k.box((0, -0.04, 1.5), (0.95, 0.04, 0.75), CY, (-0.25, 0, 0))
    for x in (-0.3, 0.0, 0.3):
        k.box((x, -0.24, 1.23), (0.14, 0.1, 0.04), GO if x == 0 else CE, (0.35, 0, 0))
    k.box((0, 0.3, 1.1), (0.7, 0.14, 1.7), N)


def h_cargo_stack(k):
    """Three stacked cargo crates (1.4 m) with straps, stencil patches and corner caps."""
    def crate(cx, cy, z, w, d, h, col, rot=0.0):
        k.box((cx, cy, z + h / 2), (w, d, h), col, (0, 0, rot))
        k.box((cx, cy, z + h / 2), (w + 0.06, d * 0.2, h + 0.06), ST, (0, 0, rot))
        k.box((cx, cy, z + h - 0.02), (w + 0.08, d + 0.08, 0.1), G, (0, 0, rot))
        k.box((cx + math.cos(rot) * w * 0.27, cy + math.sin(rot) * w * 0.27 - d * 0.5 - 0.01, z + h * 0.5), (0.4, 0.03, 0.3), GO, (0, 0, rot))
    crate(-0.8, 0, 0, 1.4, 1.2, 1.3, N)
    crate(0.8, 0.1, 0, 1.4, 1.2, 1.3, G, 0.05)
    crate(0.0, 0.0, 1.3, 1.3, 1.1, 1.2, N, -0.08)


def h_deck_light_bar(k):
    """Ceiling-mounted 4 m light bar with hangers (use Neon for the cyan tube)."""
    k.box((0, 0, 0.0), (4.0, 0.5, 0.18), G)
    k.box((0, 0, -0.1), (3.7, 0.3, 0.08), CY)
    for x in (-1.6, 1.6):
        k.box((x, 0, 0.45), (0.1, 0.1, 0.9), ST)


def h_squad_bench(k):
    """3 m bench with back rail and armour kit lockers behind."""
    k.box((0, 0, 0.45), (3.0, 0.7, 0.14), ST)
    for x in (-1.3, 0.0, 1.3):
        k.box((x, 0, 0.2), (0.14, 0.6, 0.4), G)
    k.box((0, 0.4, 0.95), (3.0, 0.1, 0.5), N)
    for i in range(3):
        k.box((-1.0 + i * 1.0, 0.7, 1.1), (0.8, 0.5, 2.2), G)
        k.box((-1.0 + i * 1.0, 0.44, 1.5), (0.55, 0.04, 1.2), N)
        k.box((-0.85 + i * 1.0, 0.43, 1.2), (0.08, 0.04, 0.3), GO)


HUMAN_EXTRA = [("HangarBulkhead", h_hangar_bulkhead), ("HangarMouth", h_hangar_mouth),
               ("ConcourseWindow", h_concourse_window), ("ConcourseTerminal", h_concourse_terminal),
               ("CargoStack", h_cargo_stack), ("DeckLightBar", h_deck_light_bar), ("SquadBench", h_squad_bench)]


# ------------------------------------------------------------------ planet limb (AD-006), Terrain palette
def _cap(k, R, phi_max, rings, sides, colfun, seed):
    """Spherical cap centred on the origin (pivot = planet centre, 'keep'), apex +Z, outward faces only."""
    rnd = random.Random(seed)
    rows = []
    for r in range(rings + 1):
        phi = phi_max * r / rings
        n = 1 if r == 0 else sides
        ring = []
        for s in range(n):
            th = 2 * math.pi * s / sides
            x, y, z = math.sin(phi) * math.cos(th) * R, math.sin(phi) * math.sin(th) * R, math.cos(phi) * R
            ring.append(k.bm.verts.new((x, y, z)))
        rows.append(ring)
    for r in range(rings):
        a, b = rows[r], rows[r + 1]
        for s in range(sides):
            s2 = (s + 1) % sides
            cc = colfun(r, s, rnd)
            if len(a) == 1:
                k._quad([a[0], b[s2], b[s]], cc)
            else:
                k._quad([a[s], a[s2], b[s2], b[s]], cc)


def p_limb(k):
    """Planet surface cap R=40 m, ~29 deg half-angle. Pivot = planet centre. Neutral palette: ocean T7/T0, land T4/T5,
    ice/cloud T6. Tint with MeshPart.Color; place with sphere centre at the desired planet centre."""
    def col(r, s, rnd):
        v = rnd.random() + 0.5 * math.sin(s * 0.9 + r * 0.7)
        if r >= 8 and rnd.random() < 0.7:
            return T6                                                    # cloud/ice toward the limb
        if v > 0.95:
            return T4 if v < 1.25 else T5
        return T7 if v > 0.35 else T0
    _cap(k, 40.0, 0.55, 11, 36, col, 7)


def p_atmo(k):
    """Atmosphere shell: same pivot, 0.9 m larger radius; use Neon/Transparency ~0.6 with a blue Color."""
    _cap(k, 40.9, 0.62, 10, 36, lambda r, s, rnd: T6, 8)


PLANET = [("PlanetLimb", p_limb, {"origin": "keep"}), ("PlanetAtmo", p_atmo, {"origin": "keep"})]


# ------------------------------------------------------------------ Ascendancy extras
def a_turret_base(k):
    """Fixed emplacement: massive stepped plinth + armoured turntable ring (head sits at z=1.7 m)."""
    k.box((0, 0, 0.3), (3.8, 3.8, 0.6), DS)
    k.box((0, 0, 0.8), (3.2, 3.2, 0.4), AS)
    k.box((0, 0, 1.3), (2.6, 2.6, 0.6), OB)
    ashlar(k, 0, 0, 2.6, 2.6, 1.0, 0.6, 2, AS)
    k.loft((0, 0, 1.6), (0, 0, 1.78), 1.1, 1.05, 8, BR, rot0=math.pi / 8)
    k.box((0, -1.62, 0.8), (0.9, 0.06, 0.3), VI)
    for sx in (-1, 1):
        k.wedge((sx * 1.7, 0), 0.5, 2.8, 0.2, 1.1, 1.3, DS)


def a_turret_head(k):
    """Rotating head, pivot = yaw axis at z=0 (sit it on TurretBase top), barrels toward -Y. Heavy sloped carapace,
    twin obsidian barrels with bronze collars, a single violet sight slit."""
    k.box((0, 0.1, 0.55), (2.0, 2.2, 0.9), OB)
    k.wedge((0, 0.1), 2.0, 2.2, 1.0, 1.2, 1.55, VG)
    k.box((0, 0.7, 0.55), (1.6, 0.8, 0.8), VG)
    k.box((0, -0.95, 0.65), (1.5, 0.4, 0.6), DS)                         # mantlet
    for sx in (-1, 1):
        k.beam((sx * 0.45, -0.9, 0.7), (sx * 0.45, -3.0, 0.7), 0.16, AB)
        k.box((sx * 0.45, -1.6, 0.7), (0.34, 0.2, 0.34), BR)
        k.box((sx * 0.45, -2.95, 0.7), (0.26, 0.2, 0.26), OB)
    k.box((0, -1.17, 1.0), (0.9, 0.05, 0.1), VI)
    k.box((0, 0.1, 1.58), (1.4, 1.5, 0.1), IV)
    for sx in (-1, 1):
        k.box((sx * 1.02, 0.1, 0.55), (0.08, 1.4, 0.4), BR)


def a_stairs(k):
    """Broad ceremonial stairs, 3.2 m wide, 2.0 m rise over 4 m run, side cheek walls."""
    n = 8
    for i in range(n):
        h = 0.25 * (i + 1)
        k.box((0, 0.5 * i + 0.25 - 2.0 + 0.0, h / 2), (3.2, 0.5, h), VG if i % 2 == 0 else AS)
        k.box((0, 0.5 * i + 0.25 - 2.0, h + 0.02), (3.2, 0.5, 0.04), IV if i == n - 1 else DS)
    for sx in (-1, 1):
        k.wedge((sx * 1.75, 0), 0.4, 4.0, 0.0, 0.5, 2.5, OB)
        k.box((sx * 1.75, 1.6, 2.6), (0.5, 0.5, 0.2), BR)


def a_beacon(k):
    """Waist-high signal pylon: masonry stub, bronze collar, ivory cap and one narrow violet light."""
    k.box((0, 0, 0.2), (1.2, 1.2, 0.4), DS)
    k.box((0, 0, 1.3), (0.8, 0.8, 1.8), OB)
    ashlar(k, 0, 0, 0.8, 0.8, 0.4, 1.8, 3, AS)
    k.box((0, 0, 2.3), (1.0, 1.0, 0.2), BR)
    k.box((0, 0, 2.5), (0.7, 0.7, 0.2), IV)
    k.box((0, -0.41, 1.3), (0.06, 0.04, 1.2), VI)


def a_barricade(k):
    """Low heavy cover block, 3 m wide x 1.3 m high, chamfered top, bronze edge and violet seam."""
    k.box((0, 0, 0.2), (3.4, 1.4, 0.4), DS)
    k.box((0, 0, 0.8), (3.0, 1.0, 0.9), VG)
    ashlar(k, 0, 0, 3.0, 1.0, 0.35, 0.9, 2, AS)
    k.wedge((0, 0), 3.0, 1.0, 1.25, 1.35, 1.55, OB)
    k.box((0, -0.52, 1.35), (2.9, 0.05, 0.08), BR)
    k.box((0, -0.51, 0.8), (0.05, 0.04, 0.6), VI)


def a_crate(k):
    """Ascendancy supply crate stack: two sealed obsidian cases with bronze corner bands."""
    for (x, y, z, w, d, h, r) in ((-0.55, 0, 0, 1.2, 1.0, 0.9, 0.05), (0.7, 0.1, 0, 0.9, 0.9, 0.7, -0.1), (-0.5, 0, 0.9, 0.9, 0.8, 0.6, -0.06)):
        k.box((x, y, z + h / 2), (w, d, h), OB, (0, 0, r))
        k.box((x, y, z + h * 0.12), (w + 0.05, d + 0.05, 0.1), BR, (0, 0, r))
        k.box((x, y, z + h * 0.88), (w + 0.05, d + 0.05, 0.1), BR, (0, 0, r))
        k.box((x + 0.02, y - d / 2 - 0.01, z + h * 0.5), (0.05, 0.03, h * 0.5), VI, (0, 0, r))


ASC_EXTRA = [("TurretBase", a_turret_base), ("TurretHead", a_turret_head, {"origin": "keep"}), ("Stairs", a_stairs),
             ("Beacon", a_beacon), ("Barricade", a_barricade), ("Crate", a_crate)]
