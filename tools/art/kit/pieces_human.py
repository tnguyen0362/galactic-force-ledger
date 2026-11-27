"""Human infrastructure kit pieces (reference sheets: Kit-7 / Kit-11 SHAPES, canonical palette COLOURS).
Grid: 4 m module (14.3 studs). Corridor opening 2.4 x 2.8 m clear (8.6 x 10 studs) vs a 5.7-stud character.
Metres in, studs out (kitlib.K.finish applies x3.57)."""
import math
from kitlib import *


def h_floorplate(k):
    k.box((0, 0, 0.12), (4.0, 4.0, 0.24), ST)
    k.box((0, 0, 0.26), (3.6, 3.6, 0.04), CE)
    for t in (-1.0, 0.0, 1.0):
        k.box((t, 0, 0.29), (0.04, 3.6, 0.02), G)
        k.box((0, t, 0.29), (3.6, 0.04, 0.02), G)
    for sx in (-1, 1):
        for sy in (-1, 1):
            k.cyl(sx * 1.8, sy * 1.8, 0.24, 0.07, 0.06, 6, G)
    k.box((0, -1.97, 0.12), (3.6, 0.06, 0.1), CY)


def h_floorgrate(k):
    k.box((0, 0, 0.12), (4.0, 4.0, 0.24), G)
    for i in range(9):
        k.box((-1.6 + i * 0.4, 0, 0.27), (0.1, 3.7, 0.1), ST)
    for j in (-1.2, 0.0, 1.2):
        k.box((0, j, 0.2), (3.7, 0.12, 0.1), G)
    k.box((0, -1.97, 0.1), (3.6, 0.06, 0.08), GO)


def h_ceilingpanel(k):
    k.box((0, 0, 0.1), (4.0, 4.0, 0.2), G)
    k.box((0, 0, 0.0), (3.7, 3.7, 0.06), ST)
    for sx in (-1, 1):
        k.box((sx * 1.0, 0, -0.04), (0.35, 2.8, 0.05), CY)
    k.box((0, 1.5, -0.04), (2.2, 0.5, 0.05), RB)


def h_column(k):
    k.box((0, 0, 0.25), (1.1, 1.1, 0.5), G)
    k.box((0, 0, 2.0), (0.8, 0.8, 3.0), N)
    for sx in (-1, 1):
        k.box((sx * 0.43, 0, 2.0), (0.06, 0.5, 2.6), ST)
    k.box((0, -0.41, 2.0), (0.14, 0.04, 2.0), CY)
    k.box((0, 0, 3.75), (1.1, 1.1, 0.5), G)
    k.box((0, 0, 3.55), (0.9, 0.9, 0.12), GO)


def h_doorframe(k):
    """4 m module, clear opening 2.4 x 2.8 m. Frame only (leaves = Kit_Human_BlastDoorLeaf)."""
    k.box((-1.6, 0, 1.85), (0.8, 0.9, 3.7), N)
    k.box((1.6, 0, 1.85), (0.8, 0.9, 3.7), N)
    k.box((0, 0, 3.4), (4.0, 0.9, 0.6), G)
    k.box((0, 0, 0.1), (4.0, 0.9, 0.2), G)
    for sx in (-1, 1):
        k.box((sx * 1.2, 0, 1.45), (0.08, 0.96, 2.8), ST)
        k.box((sx * 1.62, -0.47, 1.85), (0.08, 0.06, 3.2), CY)
    k.box((0, -0.47, 3.4), (3.0, 0.06, 0.1), CY)
    k.box((0, 0, 3.72), (4.0, 0.9, 0.12), ST)
    for sx in (-1, 1):
        k.box((sx * 1.6, -0.46, 0.8), (0.4, 0.04, 0.5), GO)


def h_blastdoor_leaf(k):
    """Leaf 1.3 x 0.35 x 2.9 m. PIVOT = hinge edge (origin at 0,0,0, leaf extends +X)."""
    k.box((0.65, 0, 1.45), (1.3, 0.35, 2.9), G)
    k.box((0.65, -0.19, 1.45), (1.1, 0.04, 2.7), N)
    for z in (0.5, 1.45, 2.4):
        k.box((0.65, -0.21, z), (1.0, 0.04, 0.1), ST)
    k.box((1.2, -0.21, 1.45), (0.06, 0.04, 2.5), CY)
    k.box((0.65, -0.2, 2.6), (0.6, 0.04, 0.2), GO)
    k.cyl(0.0, 0.0, 0.0, 0.1, 2.9, 6, ST)


def h_stairs(k):
    """Straight flight 2.4 m wide, rise 3.2 m over 5.6 m run, 16 steps (0.2 m rise)."""
    for i in range(16):
        k.box((0, -2.8 + 0.35 * (i + 0.5), 0.1 + 0.1 * i), (2.4, 0.35, 0.2 + 0.2 * i), ST if i % 2 else CE)
    for sx in (-1, 1):
        k.box((sx * 1.28, 0, 1.6), (0.16, 5.6, 3.2), G)
        k.box((sx * 1.28, 0, 3.25), (0.18, 5.6, 0.1), CY)
    k.box((0, 3.0, 3.1), (2.4, 0.5, 0.3), G)


def h_ramp(k):
    """Ramp 2.4 m wide, 6.4 m run, 1.6 m rise (14 degrees)."""
    k.wedge((0, 0), 2.4, 6.4, 0.0, 0.1, 1.6, ST)
    for sx in (-1, 1):
        k.wedge((sx * 1.28, 0), 0.16, 6.4, 0.0, 0.3, 1.9, G)
        k.wedge((sx * 1.28, 0), 0.18, 6.4, 0.25, 0.42, 2.0, CY)


def h_railing(k):
    """4 m guard rail, 1.05 m high."""
    for x in (-2.0, 0.0, 2.0):
        k.box((x, 0, 0.55), (0.1, 0.1, 1.1), ST)
    k.box((0, 0, 1.08), (4.1, 0.1, 0.08), G)
    k.box((0, 0, 0.7), (4.0, 0.06, 0.06), ST)
    k.box((0, 0, 0.1), (4.0, 0.06, 0.2), G)
    k.box((0, -0.04, 1.08), (3.9, 0.02, 0.03), CY)


def h_catwalk(k):
    """Bridge span 2.4 x 8 m with side trusses and rails; walkable top at ~0.4 m."""
    k.box((0, 0, 0.2), (2.4, 8.0, 0.3), G)
    k.box((0, 0, 0.37), (2.2, 7.8, 0.04), ST)
    for i in range(7):
        k.box((0, -3.6 + i * 1.2, 0.4), (2.2, 0.04, 0.02), G)
    for sx in (-1, 1):
        k.box((sx * 1.1, 0, 1.0), (0.1, 8.0, 0.1), ST)
        for i in range(9):
            k.box((sx * 1.1, -3.8 + i * 0.95, 0.65), (0.07, 0.07, 0.7), ST)
        for i in range(8):
            y0 = -3.6 + i * 0.95
            k.beam((sx * 1.1, y0, 0.05), (sx * 1.1, y0 + 0.95, 0.35), 0.06, G)
        k.box((sx * 1.1, 0, 0.1), (0.12, 8.0, 0.1), N)
        k.box((sx * 1.15, 0, 0.45), (0.04, 8.0, 0.03), CY)
    for y in (-3.9, 3.9):
        k.box((0, y, 0.2), (2.6, 0.3, 0.42), N)


def h_platform(k):
    """Maintenance platform 4 x 6 m deck at 3.2 m on 4 legs; rails on 3 sides (open end -Y for stairs)."""
    k.box((0, 0, 3.05), (4.0, 6.0, 0.25), G)
    k.box((0, 0, 3.2), (3.8, 5.8, 0.04), ST)
    for sx in (-1, 1):
        for sy in (-1, 1):
            k.box((sx * 1.85, sy * 2.75, 1.5), (0.22, 0.22, 3.0), N)
            k.box((sx * 1.85, sy * 2.75, 0.08), (0.5, 0.5, 0.16), G)
        k.beam((sx * 1.85, -2.75, 0.2), (sx * 1.85, 2.75, 2.9), 0.1, ST)
        k.beam((sx * 1.85, 2.75, 0.2), (sx * 1.85, -2.75, 2.9), 0.1, ST)
        k.box((sx * 1.95, 0, 3.75), (0.08, 6.0, 0.08), GO)
        k.box((sx * 1.95, 0, 3.45), (0.06, 6.0, 0.06), GO)
    k.box((0, 2.95, 3.75), (4.0, 0.08, 0.08), GO)
    k.box((0, 2.95, 3.45), (4.0, 0.06, 0.06), GO)


def h_gantry(k):
    """Repair gantry 6 x 6 m portal, 5 m clear height, overhead beams with two static tool arms."""
    for sx in (-1, 1):
        for sy in (-1, 1):
            k.box((sx * 2.8, sy * 2.6, 2.5), (0.55, 0.55, 5.0), N)
            k.box((sx * 2.8, sy * 2.6, 0.12), (0.9, 0.9, 0.24), G)
    for sy in (-1, 1):
        k.box((0, sy * 2.6, 5.15), (6.2, 0.5, 0.5), G)
        k.box((0, sy * 2.6, 5.45), (6.0, 0.4, 0.06), CY)
    for sx in (-1, 1):
        k.box((sx * 2.8, 0, 5.15), (0.5, 5.4, 0.5), ST)
    for ax in (-1.1, 1.1):
        k.box((ax, 0, 4.7), (0.45, 0.45, 0.55), G)
        k.beam((ax, 0, 4.55), (ax + 0.2, 0.7, 3.5), 0.22, ST)
        k.beam((ax + 0.2, 0.7, 3.5), (ax + 0.1, 0.1, 2.6), 0.18, N)
        k.box((ax + 0.1, 0.1, 2.5), (0.3, 0.3, 0.2), GO)
    k.box((0, 0, 0.25), (6.0, 6.0, 0.06), G)


def h_turret_base(k):
    """Hex turret mount 3.2 m across, 1.0 m high; top ring = yaw bearing."""
    k.loft((0, 0, 0), (0, 0, 0.4), 1.8, 1.55, 6, G)
    k.loft((0, 0, 0.4), (0, 0, 0.8), 1.55, 1.3, 6, N)
    k.loft((0, 0, 0.8), (0, 0, 1.0), 1.0, 1.0, 12, ST)
    for i in range(6):
        a = math.pi / 6 + i * math.pi / 3
        k.box((math.cos(a) * 1.6, math.sin(a) * 1.6, 0.35), (0.5, 0.2, 0.1), CY, (0, 0, a))
    k.box((0, 1.5, 0.6), (0.9, 0.12, 0.5), GO)


def h_turret_gun(k):
    """Twin-barrel head. PIVOT = yaw axis on the bearing ring (origin 0,0,0). Barrels point -Y."""
    k.loft((0, 0, 0.0), (0, 0, 0.15), 0.95, 0.9, 12, ST)
    k.box((0, 0.1, 0.55), (1.5, 1.4, 0.8), N)
    k.box((0, 0.35, 0.95), (1.3, 1.0, 0.3), G)
    for sx in (-1, 1):
        k.box((sx * 0.75, -0.1, 0.6), (0.3, 1.0, 0.6), G)
        k.beam((sx * 0.3, -0.3, 0.6), (sx * 0.3, -2.4, 0.6), 0.16, ST)
        k.box((sx * 0.3, -1.1, 0.6), (0.3, 0.5, 0.3), G)
        k.box((sx * 0.3, -2.5, 0.6), (0.2, 0.16, 0.2), RB)
    k.box((0, -0.55, 1.1), (0.7, 0.5, 0.3), CY)
    k.box((0, 0.85, 0.6), (1.2, 0.3, 0.6), G)
    k.box((0, 0.1, 1.17), (1.0, 0.8, 0.06), GO)


def h_power_core(k):
    """Power core 3.2 x 3.2 x 3.8 m: armoured housing around a cyan column."""
    k.box((0, 0, 0.25), (3.2, 3.2, 0.5), G)
    k.loft((0, 0, 0.5), (0, 0, 3.2), 1.0, 1.0, 10, CY)
    for z in (0.9, 2.0, 3.0):
        k.loft((0, 0, z - 0.1), (0, 0, z + 0.1), 1.2, 1.2, 10, ST)
    for ang in range(4):
        a = ang * math.pi / 2 + math.pi / 4
        k.box((math.cos(a) * 1.35, math.sin(a) * 1.35, 1.9), (0.3, 0.3, 2.8), N, (0, 0, a))
        k.beam((math.cos(a) * 1.5, math.sin(a) * 1.5, 0.5), (math.cos(a) * 1.1, math.sin(a) * 1.1, 3.2), 0.2, G)
    k.box((0, 0, 3.45), (3.0, 3.0, 0.3), G)
    k.box((0, 0, 3.65), (2.2, 2.2, 0.12), ST)
    k.box((0, 0, 0.55), (2.8, 2.8, 0.08), GO)


def h_shield_emitter(k):
    """Shield emitter 2.8 m footprint, 5.6 m tall: ceramic-banded pylon with a cyan field column."""
    k.loft((0, 0, 0), (0, 0, 0.5), 1.5, 1.3, 8, G)
    k.loft((0, 0, 0.5), (0, 0, 0.9), 1.3, 1.0, 8, N)
    k.loft((0, 0, 0.9), (0, 0, 4.8), 0.75, 0.75, 8, ST)
    k.loft((0, 0, 1.2), (0, 0, 4.5), 0.5, 0.5, 8, CY)
    for z in (1.1, 2.6, 4.1):
        k.loft((0, 0, z), (0, 0, z + 0.22), 0.9, 0.9, 8, CE)
    for ang in range(3):
        a = ang * 2 * math.pi / 3
        k.beam((math.cos(a) * 1.35, math.sin(a) * 1.35, 0.1), (math.cos(a) * 0.7, math.sin(a) * 0.7, 2.6), 0.2, N)
    k.loft((0, 0, 4.8), (0, 0, 5.2), 0.9, 0.55, 8, G)
    k.loft((0, 0, 5.2), (0, 0, 5.6), 0.3, 0.12, 8, CY)


def h_sensor_tower(k):
    """3-leg lattice sensor tower 9 m tall with antenna arrays and a cyan beacon."""
    for ang in range(3):
        a = ang * 2 * math.pi / 3 + math.pi / 2
        k.beam((math.cos(a) * 1.7, math.sin(a) * 1.7, 0.2), (math.cos(a) * 0.45, math.sin(a) * 0.45, 7.4), 0.22, N)
        k.box((math.cos(a) * 1.9, math.sin(a) * 1.9, 0.1), (0.8, 0.8, 0.2), G, (0, 0, a))
    for z, r in ((2.0, 1.25), (4.0, 0.95), (6.0, 0.65)):
        for ang in range(3):
            a0 = ang * 2 * math.pi / 3 + math.pi / 2
            a1 = (ang + 1) * 2 * math.pi / 3 + math.pi / 2
            k.beam((math.cos(a0) * r, math.sin(a0) * r, z), (math.cos(a1) * r, math.sin(a1) * r, z), 0.07, ST)
    k.loft((0, 0, 7.2), (0, 0, 7.6), 0.8, 0.8, 8, G)
    for ang in range(3):
        a = ang * 2 * math.pi / 3
        k.box((math.cos(a) * 0.65, math.sin(a) * 0.65, 8.1), (0.2, 0.5, 1.2), ST, (0, 0, a + math.pi / 2))
    k.cyl(0, 0, 7.6, 0.14, 1.3, 6, ST)
    k.cyl(0, 0, 8.9, 0.22, 0.2, 8, CY)
    k.box((0, 0, 0.25), (1.2, 1.2, 0.5), G)


def h_dish(k):
    """Comms dish 4.4 m diameter on a yoke, pedestal 1.4 m (static)."""
    k.box((0, 0, 0.25), (2.6, 2.6, 0.5), G)
    k.loft((0, 0, 0.5), (0, 0, 1.5), 0.8, 0.55, 8, N)
    k.box((0, 0, 1.7), (1.2, 0.8, 0.5), ST)
    for sx in (-1, 1):
        k.box((sx * 0.7, 0, 2.3), (0.2, 0.5, 1.2), N)
    k.loft((0, 0.2, 2.5), (0, -0.6, 3.4), 0.2, 2.2, 14, CE, rot0=0.1, cap=False)
    k.beam((0, -0.4, 3.1), (0, -1.9, 4.4), 0.08, ST)
    k.box((0, -1.95, 4.45), (0.3, 0.3, 0.3), CY)
    k.box((0, 0, 0.55), (2.2, 2.2, 0.08), GO)


def h_pipe(k):
    k.loft((-2.0, 0, 0.55), (2.0, 0, 0.55), 0.35, 0.35, 10, ST)
    for x in (-2.0, -0.7, 0.7, 2.0):
        k.loft((x - 0.1, 0, 0.55), (x + 0.1, 0, 0.55), 0.43, 0.43, 10, G)
    k.loft((0, 0, 0.55), (0.3, 0, 0.55), 0.45, 0.45, 10, GO)
    for x in (-1.3, 1.3):
        k.box((x, 0, 0.18), (0.5, 0.7, 0.36), G)


def h_pipe_elbow(k):
    r = 1.3
    path = [(-r + math.sin(math.pi / 2 * i / 6) * r, math.cos(math.pi / 2 * i / 6) * r - r) for i in range(7)]
    for i in range(6):
        k.loft((path[i][0], path[i][1], 0.55), (path[i + 1][0], path[i + 1][1], 0.55), 0.35, 0.35, 10, ST, cap=False)
    k.loft((-r - 0.6, 0, 0.55), (-r, 0, 0.55), 0.35, 0.35, 10, ST)
    k.loft((0, -r, 0.55), (0, -r - 0.6, 0.55), 0.35, 0.35, 10, ST)
    k.loft((-r - 0.1, 0, 0.55), (-r + 0.1, 0, 0.55), 0.43, 0.43, 10, G)
    k.loft((0, -r - 0.1, 0.55), (0, -r + 0.1, 0.55), 0.43, 0.43, 10, G)
    k.box((-0.4, -0.4, 0.15), (0.8, 0.8, 0.3), G)


def h_vent(k):
    k.box((0, 0, 0.6), (1.8, 0.5, 1.2), G)
    for i in range(6):
        k.box((0, -0.26, 0.2 + i * 0.18), (1.5, 0.04, 0.08), RB)
    k.box((0, -0.26, 1.0), (1.7, 0.03, 0.04), CY)
    k.box((0, 0, 1.25), (1.9, 0.6, 0.1), ST)


def h_wall_window(k):
    """4 m wall module with a 2.4 x 1.1 m window (cyan glass slab) for concourse/command rooms."""
    k.box((0, 0, 0.3), (4.0, 0.8, 0.6), G)
    k.box((-1.6, 0, 1.9), (0.8, 0.7, 2.6), N)
    k.box((1.6, 0, 1.9), (0.8, 0.7, 2.6), N)
    k.box((0, 0, 0.95), (2.4, 0.7, 0.7), N)
    k.box((0, 0, 3.0), (4.0, 0.7, 0.8), N)
    k.box((0, 0, 2.2), (2.4, 0.08, 1.1), CY)
    for x in (-0.4, 0.4):
        k.box((x, -0.01, 2.2), (0.08, 0.12, 1.2), ST)
    k.box((0, 0, 3.45), (4.0, 0.8, 0.1), ST)
    k.box((0, -0.4, 2.8), (3.2, 0.04, 0.08), CY)
    k.box((-1.6, -0.37, 1.6), (0.3, 0.04, 0.4), GO)


PIECES = [
    ("FloorPlate", h_floorplate), ("FloorGrate", h_floorgrate), ("CeilingPanel", h_ceilingpanel), ("Column", h_column),
    ("DoorFrame", h_doorframe), ("BlastDoorLeaf", h_blastdoor_leaf, {"origin": "keep"}), ("Stairs", h_stairs),
    ("Ramp", h_ramp), ("Railing", h_railing), ("Catwalk", h_catwalk), ("Platform", h_platform),
    ("RepairGantry", h_gantry), ("TurretBase", h_turret_base), ("TurretGun", h_turret_gun, {"origin": "keep"}),
    ("PowerCore", h_power_core), ("ShieldEmitter", h_shield_emitter), ("SensorTower", h_sensor_tower),
    ("Dish", h_dish), ("Pipe", h_pipe), ("PipeElbow", h_pipe_elbow), ("Vent", h_vent), ("WallWindow", h_wall_window),
]
