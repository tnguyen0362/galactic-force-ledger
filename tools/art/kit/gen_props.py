"""
GALACTIC FORCE Phase 15 - hero props generator (Blender, headless). Uses kitlib.py.

  blender -b --factory-startup --python gen_props.py -- <abs_out_dir> <Batch> [<Batch> ...]
  (set GF_PREVIEW=1 for contact sheets with a 5.7-stud mannequin in every tile)

Batches (one debt row each, see ASSET_DEBT.csv):
  Pad        AD-011 landing pad          (Human palette)
  Gunship    AD-008 extraction gunship   (Human palette) hull + separate hinged ramp
  Relay      AD-003 Ascendancy relay     (Ascendancy palette)
  (more batches appended below as they are built)

Shapes are inspired by the owner's reference sheets; COLOURS are the canonical palettes (no red/orange accents).
Dimensions are fitted to the live game objects (see PROPS_FIT.md): ExtractionService.buildDropship,
ObjectiveService.buildRelay, StationConcourse, StationWarTable.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kitlib import *
from gen_kit import ashlar
import pieces_human


def poly_edges(k, r, n, w, h, z, col, per_edge=1, rot0=math.pi / 8, skip=None, alt=None):
    """Flat-ish strip boxes laid along the edges of a regular n-gon of circumradius r (metres)."""
    for i in range(n):
        a0 = rot0 + 2 * math.pi * i / n
        a1 = rot0 + 2 * math.pi * (i + 1) / n
        p0 = (math.cos(a0) * r, math.sin(a0) * r)
        p1 = (math.cos(a1) * r, math.sin(a1) * r)
        el = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
        ang = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
        for j in range(per_edge):
            t = (j + 0.5) / per_edge
            c = (p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t, z + h / 2)
            cc = col if alt is None or (i * per_edge + j) % 2 == 0 else alt
            if skip and skip(i, j):
                continue
            k.box(c, (el / per_edge * 0.98, w, h), cc, (0, 0, ang))


# ============================================================================ AD-011 LANDING PAD
def h_pad(k):
    """12 m octagonal deck pad: concrete apron, steel plate, hazard border, gold stencil ring + chevrons toward the
    ramp (+Y), scorched drop-pod scar, cyan edge lights, bollards. Thin (0.45 m): walkable, no gameplay height."""
    k.loft((0, 0, 0), (0, 0, 0.25), 6.4, 6.3, 8, CO, rot0=math.pi / 8)
    k.loft((0, 0, 0.25), (0, 0, 0.33), 5.75, 5.7, 8, ST, rot0=math.pi / 8)
    poly_edges(k, 6.0, 8, 0.45, 0.07, 0.25, GO, per_edge=4, alt=G)           # hazard border
    poly_edges(k, 4.9, 8, 0.12, 0.03, 0.33, GO, per_edge=1)                   # stencil ring
    poly_edges(k, 3.2, 8, 0.07, 0.03, 0.33, CE, per_edge=1)                   # inner ring
    # panel seams across the steel plate
    for x in (-3.3, -1.1, 1.1, 3.3):
        k.box((x, 0, 0.345), (0.05, 9.6 * math.cos(math.radians(30)), 0.02), G)
        k.box((0, x, 0.345), (9.6 * math.cos(math.radians(30)), 0.05, 0.02), G)
    # drop-pod scar: overlapping scorch discs + a cracked rim (broken plate wedges)
    k.loft((0.35, -0.2, 0.33), (0.35, -0.2, 0.365), 2.1, 2.0, 14, RB)
    k.loft((-0.5, 0.5, 0.365), (-0.5, 0.5, 0.385), 1.35, 1.25, 12, G)
    for ang, r in ((0.3, 2.3), (1.9, 2.1), (3.6, 2.4), (5.0, 2.2)):
        k.box((0.35 + math.cos(ang) * r, -0.2 + math.sin(ang) * r, 0.37), (0.55, 0.12, 0.05), G, (0, 0, ang + 1.4))
    # direction chevrons (point +Y toward the ramp)
    for i in range(3):
        y = 1.3 + i * 0.95
        k.box((-0.55, y, 0.35), (1.3, 0.22, 0.03), GO, (0, 0, math.radians(-30)))
        k.box((0.55, y, 0.35), (1.3, 0.22, 0.03), GO, (0, 0, math.radians(30)))
    # cyan edge lights at the 8 corners + bollards on the diagonals
    for i in range(8):
        a = math.pi / 8 + 2 * math.pi * i / 8
        k.box((math.cos(a) * 5.9, math.sin(a) * 5.9, 0.34), (0.35, 0.35, 0.12), CY, (0, 0, a))
    for a in (math.pi / 4, 3 * math.pi / 4, 5 * math.pi / 4, 7 * math.pi / 4):
        x, y = math.cos(a) * 6.15, math.sin(a) * 6.15
        k.cyl(x, y, 0.25, 0.22, 0.75, 6, G)
        k.cyl(x, y, 1.0, 0.24, 0.1, 6, CY)
    # tie-down rings (flat steel blocks)
    for a in (0, math.pi / 2, math.pi, 3 * math.pi / 2):
        k.box((math.cos(a) * 3.9, math.sin(a) * 3.9, 0.365), (0.5, 0.5, 0.06), ST, (0, 0, a))


# ============================================================================ AD-008 GUNSHIP
# Fit (ExtractionService.buildDropship): safe-zone hull ~26 studs long x 16 wide (wings 26), ramp 8 x 12 studs hinged
# at its -Z edge, cargo deck ~4.5 studs above the gear feet, engine glow rear. Modelled nose = -Y, ramp end = +Y.
def h_gunship(k):
    # ---- landing gear (feet at z=0), deck underside at 1.2 m
    for sx in (-1, 1):
        for y in (-2.2, 2.6):
            k.beam((sx * 1.55, y, 0.12), (sx * 1.75, y, 1.25), 0.2, G)
            k.box((sx * 1.55, y, 0.07), (0.55, 0.75, 0.14), RB)
    # ---- fuselage floor + cargo bay (open at +Y)
    k.box((0, 0.1, 1.3), (3.5, 8.2, 0.2), G)                       # keel / floor slab (top at 1.4 m)
    k.box((0, 1.45, 1.43), (2.9, 5.0, 0.06), ST)                    # deck plate in the bay
    for y in (0.4, 1.3, 2.2, 3.1, 3.9):                              # deck seams
        k.box((0, y, 1.47), (2.9, 0.04, 0.02), G)
    for sx in (-1, 1):
        k.box((sx * 1.75, 1.75, 2.75), (0.18, 4.6, 2.5), N)          # bay side walls (interior height 2.5 m)
        k.box((sx * 1.82, 1.75, 2.75), (0.05, 4.6, 2.5), ST)         # outer panel skin
        for y in (-0.2, 0.7, 1.6, 2.5, 3.4, 4.0):                    # frame ribs
            k.box((sx * 1.62, y, 2.75), (0.16, 0.14, 2.4), G)
        k.box((sx * 1.55, 1.75, 1.75), (0.5, 4.0, 0.12), RB)         # fold-down benches
        k.box((sx * 1.62, 1.75, 1.95), (0.1, 4.0, 0.5), RB)          # seat backs
        k.box((sx * 1.45, 1.75, 3.9), (0.1, 4.2, 0.06), CY)          # ceiling light strips
    k.box((0, 1.65, 4.12), (3.7, 4.8, 0.28), G)                      # roof slab
    k.box((0, 1.65, 4.28), (3.2, 4.6, 0.1), ST)
    k.box((0, -0.55, 2.8), (3.5, 0.18, 2.9), G)                      # front bulkhead
    # ---- nose / cockpit (tapering wedges)
    k.wedge((0, -2.2), 3.4, 3.2, 1.2, 3.2, 3.9, N)                   # lower nose block
    k.wedge((0, -2.5), 3.0, 2.6, 3.2, 3.5, 4.1, G)                   # upper nose, sloped glass deck
    k.box((0, -3.0, 3.7), (2.4, 1.2, 0.12), CY, (0.55, 0, 0))        # canopy glass (cyan tint, sloped)
    k.box((0, -2.0, 4.05), (2.4, 0.2, 0.3), ST)                      # canopy brow
    k.box((0, -3.95, 2.0), (2.0, 0.3, 0.9), G, (0.35, 0, 0))         # chin sensor housing
    k.box((0, -4.15, 2.0), (0.6, 0.12, 0.3), CY)
    # ---- dorsal: intake scoops + sensor dome
    for sx in (-1, 1):
        k.wedge((sx * 0.75, 0.2), 0.9, 1.6, 4.1, 4.2, 4.65, N)
    k.cyl(0, -1.15, 4.1, 0.35, 0.25, 8, ST)
    k.cyl(0, -1.15, 4.35, 0.2, 0.18, 8, CY)
    # ---- wings: stub sponsons + engine nacelles
    for sx in (-1, 1):
        k.wedge((sx * 3.1, 0.6), 2.6, 3.8, 2.75, 2.95, 3.2, G)       # swept stub wing
        k.box((sx * 3.1, 0.6, 2.72), (2.5, 3.6, 0.1), ST)             # underside plate
        k.box((sx * 4.25, 0.9, 3.0), (0.2, 3.3, 0.45), N)             # wing-tip fence
        nx, nz = sx * 3.55, 2.55
        k.loft((nx, -1.9, nz), (nx, 1.2, nz), 0.62, 0.55, 8, G)         # nacelle body
        k.loft((nx, -2.05, nz), (nx, -1.9, nz), 0.5, 0.62, 8, CE)       # intake lip
        k.loft((nx, -2.1, nz), (nx, -2.02, nz), 0.4, 0.4, 8, CY)       # intake glow
        k.loft((nx, 1.2, nz), (nx, 1.75, nz), 0.55, 0.42, 8, ST)        # exhaust cone
        k.loft((nx, 1.75, nz), (nx, 1.82, nz), 0.4, 0.4, 8, CY)        # thruster glow
        k.box((nx, 0.1, nz + 0.7), (0.5, 1.4, 0.3), ST)               # pylon block
        # hull side panel lines + gold stencil blocks (marking)
        k.box((sx * 1.86, 1.75, 3.1), (0.04, 3.4, 0.06), G)
        for j in range(3):
            k.box((sx * 1.87, 3.3 - j * 0.35, 2.0), (0.04, 0.2, 0.42), GO)
    # ---- rear: engine pods up top, tail fins
    for sx in (-1, 1):
        k.box((sx * 1.25, 3.6, 4.55), (0.9, 1.3, 0.5), N)
        k.loft((sx * 1.25, 4.25, 4.55), (sx * 1.25, 4.35, 4.55), 0.3, 0.3, 8, CY)
        k.wedge((sx * 1.55, 3.4), 0.12, 1.8, 4.4, 5.3, 4.9, G)         # tail fin
    # ---- hull belly + rear lip
    k.wedge((0, 3.9), 3.4, 0.5, 1.2, 1.3, 1.5, ST)
    k.box((0, 4.0, 1.38), (3.0, 0.3, 0.1), GO)                         # hinge strip (ramp attaches here)


def h_gunship_ramp(k):
    """Flat deployed pose, 2.4 m x 3.4 m x 0.22 m (~8.6 x 12 x 0.8 studs). Origin = bbox centre (same as the live
    Ramp Part). Hinge edge is the -Y edge. Gameplay swaps/tweens exactly like the Part (fold -75 deg about the hinge)."""
    k.box((0, 0, 0.11), (2.4, 3.4, 0.22), ST)
    for sx in (-1, 1):
        k.box((sx * 1.12, 0, 0.28), (0.16, 3.4, 0.12), G)                # side rails
        k.box((sx * 1.12, 0, 0.36), (0.16, 3.4, 0.04), CY)               # edge light strip
    for i in range(9):                                                    # anti-slip chevron plates
        y = -1.45 + i * 0.36
        k.box((-0.48, y, 0.235), (0.9, 0.1, 0.03), G, (0, 0, math.radians(-14)))
        k.box((0.48, y, 0.235), (0.9, 0.1, 0.03), G, (0, 0, math.radians(14)))
    k.box((0, -1.6, 0.22), (2.2, 0.2, 0.26), GO)                          # hinge bar
    k.box((0, 1.62, 0.12), (2.4, 0.2, 0.08), RB)                          # ground lip



# ============================================================================ AD-003 ASCENDANCY RELAY (split spire)
# Fit (ObjectiveService.buildRelay): ArtService.place height=30 studs (8.4 m) on a 15-stud plinth, separate neon core
# (2.2-stud cube) floats at y=16 studs (4.5 m) -> the split gap is centred there. Terminal/interaction are separate parts.
def a_relay(k):
    for i, (w, z0, h) in enumerate(((4.0, 0.0, 0.35), (3.3, 0.35, 0.35), (2.7, 0.7, 0.35))):
        k.box((0, 0, z0 + h / 2), (w, w * 0.92, h), DS if i != 1 else AS)
    for sx in (-1, 1):
        x = sx * 0.95
        k.box((x, 0, 1.9), (1.3, 2.0, 1.7), VG)                      # lower mass
        ashlar(k, x, 0, 1.3, 2.0, 1.05, 1.7, 3, AS)
        k.box((x - sx * 0.12, 0, 3.0), (1.05, 1.7, 0.2), BR)         # bronze collar under the gap
        # inner (gap-facing) panels: thin violet slit + bronze cradle brackets
        k.box((sx * 0.5, 0, 4.5), (0.12, 1.5, 2.6), OB)
        k.box((sx * 0.44, 0, 4.5), (0.04, 0.08, 2.2), VI)
        for z in (3.5, 5.5):
            k.box((sx * 0.62, 0, z), (0.36, 1.2, 0.12), BR)
        # upper shafts: set slightly outward (split) and tapering to a plain cut tip
        k.box((sx * 1.0, 0, 4.4), (0.95, 1.5, 2.9), OB, (0, sx * 0.045, 0))
        k.loft((sx * 1.05, 0, 5.8), (sx * 1.25, 0, 7.7), 0.78, 0.38, 4, VG, rot0=math.pi / 4)
        k.box((sx * 1.27, 0, 7.82), (0.52, 0.52, 0.16), IV)        # ivory cap
        k.box((sx * 1.05, 0.0, 5.82), (1.15, 1.9, 0.18), BR)         # band at the shaft shoulder
    k.box((0, 0, 3.0), (3.4, 1.9, 0.2), BR)                           # lower bridge (under the core)
    k.box((0, 0, 6.12), (3.1, 1.4, 0.22), OB)                         # upper bridge
    k.box((0, 0, 6.28), (3.1, 1.2, 0.1), BR)
    for sy in (-1, 1):                                                  # front/back conduit inlays
        k.box((0, sy * 1.02, 2.0), (0.14, 0.06, 1.6), BR)
        k.box((-1.6 * 0.6, sy * 1.02, 4.5), (0.08, 0.05, 2.0), BR)
        k.box((1.6 * 0.6, sy * 1.02, 4.5), (0.08, 0.05, 2.0), BR)


# ============================================================================ AD-004 ASCENDANCY TOWER / CORNER / PIER
def a_tower(k):
    """5 m footprint, 12 m tall guard tower: battered masonry shaft, recessed gate, slit windows, sloped armoured crown."""
    k.box((0, 0, 0.35), (5.6, 5.6, 0.7), DS)
    k.box((0, 0, 0.8), (5.0, 5.0, 0.2), AS)
    k.box((0, 0, 3.4), (4.4, 4.4, 5.0), VG)
    ashlar(k, 0, 0, 4.4, 4.4, 0.9, 5.0, 5, AS)
    # recessed gate on the -Y face
    k.box((0, -2.22, 1.7), (1.5, 0.12, 2.3), OB)
    k.box((0, -2.28, 2.95), (1.9, 0.18, 0.2), BR)
    k.box((0, -2.26, 1.0), (2.1, 0.2, 0.2), DS)
    for sx in (-1, 1):
        k.box((sx * 0.95, -2.26, 1.9), (0.22, 0.2, 2.6), AB)
    k.box((0, -2.24, 1.7), (0.05, 0.05, 2.2), VI)                      # thin violet seam at the doors
    # mid shaft with slit windows
    k.box((0, 0, 7.2), (3.8, 3.8, 3.2), VG)
    ashlar(k, 0, 0, 3.8, 3.8, 5.6, 3.2, 3, AS, seed=1)
    for z in (6.4, 7.6):
        for sx in (-1, 1):
            k.box((sx * 0.95, -1.92, z), (0.14, 0.06, 0.8), OB)
            k.box((sx * 0.95, 1.92, z), (0.14, 0.06, 0.8), OB)
    k.box((0, -1.93, 7.0), (0.08, 0.05, 1.6), VI)
    k.box((0, 0, 8.9), (4.5, 4.5, 0.3), BR)                             # bronze belt course
    # crown: wider armoured head with sloped plates (no spikes)
    k.box((0, 0, 9.55), (4.4, 4.4, 1.0), OB)
    for sx in (-1, 1):
        k.wedge((sx * 1.7, 0), 1.0, 4.4, 10.0, 10.6, 10.9, VG)
        k.wedge((0, sx * 1.7), 4.4, 1.0, 10.0, 10.6, 10.9, VG, math.pi)
    k.box((0, 0, 10.55), (2.4, 2.4, 0.5), AS)
    k.box((0, 0, 10.9), (1.6, 1.6, 0.14), IV)
    k.box((0, -2.21, 9.55), (3.0, 0.06, 0.2), BR)
    k.box((0, -2.22, 9.55), (0.12, 0.05, 0.5), VI)
    # buttress spurs at the corners
    for sx in (-1, 1):
        for sy in (-1, 1):
            k.wedge((sx * 2.55, sy * 2.55), 0.7, 0.7, 0.7, 4.4, 4.9, DS)


def a_wall_corner(k):
    """90-degree outside corner: two wall arms (same section as Kit_Ascendancy_Wall) meeting at a heavy pier."""
    for sign, (cx, cy, w, d) in enumerate(((2.6, 0.0, 5.2, 1.2), (0.0, 2.6, 1.2, 5.2))):
        k.box((cx, cy, 0.3), (w + (0.6 if sign == 0 else 0.6), d + 0.6, 0.6), DS)
        k.box((cx, cy, 1.7), (w, d, 2.2), VG)
        k.box((cx, cy, 2.9), (w + 0.4, d + 0.3, 0.3), OB)
        k.box((cx, cy, 3.12), (w, d, 0.14), IV)
    ashlar(k, 2.6, 0, 5.2, 1.2, 0.6, 2.2, 3, AS)
    ashlar(k, 0, 2.6, 1.2, 5.2, 0.6, 2.2, 3, AS)
    k.box((0, 0, 0.45), (2.0, 2.0, 0.9), DS)
    k.box((0, 0, 2.3), (1.7, 1.7, 3.2), OB)                              # corner pier
    ashlar(k, 0, 0, 1.7, 1.7, 0.9, 3.2, 3, AS, seed=1)
    k.box((0, 0, 4.0), (2.1, 2.1, 0.3), BR)
    k.box((0, 0, 4.25), (1.5, 1.5, 0.22), IV)
    k.box((0.86, 0.4, 2.3), (0.05, 0.05, 2.4), VI)


def a_pier(k):
    """Free-standing gate pier / wall terminator, 1.9 m square, 5 m tall."""
    k.box((0, 0, 0.3), (2.4, 2.4, 0.6), DS)
    k.box((0, 0, 2.6), (1.7, 1.7, 4.0), OB)
    ashlar(k, 0, 0, 1.7, 1.7, 0.6, 4.0, 4, AS)
    k.box((0, 0, 4.7), (2.1, 2.1, 0.3), BR)
    k.box((0, 0, 4.95), (1.8, 1.8, 0.2), VG)
    k.box((0, 0, 5.15), (1.3, 1.3, 0.2), IV)
    k.box((0, -0.87, 2.6), (0.08, 0.05, 2.6), VI)


# ============================================================================ BATCH TABLE
BATCHES = {
    "HumanInfra": {"Human": list(pieces_human.PIECES)},
    "Pad": {"Human": [("LandingPad", h_pad)]},
    "Gunship": {"Human": [("Gunship", h_gunship), ("GunshipRamp", h_gunship_ramp, {"origin": "center"})]},
    "Relay": {"Ascendancy": [("Relay", a_relay)]},
    "AscArch": {"Ascendancy": [("Tower", a_tower), ("WallCorner", a_wall_corner), ("Pier", a_pier)]},
}


if __name__ == "__main__":
    import bpy
    clear_scene()
    names = [a for a in argv[1:] if a in BATCHES]
    merged = {}
    for n in names:
        for fac, pieces in BATCHES[n].items():
            merged.setdefault(fac, []).extend(pieces)
    ONLY.clear()  # factions handled by batch selection
    run_kits(merged)
