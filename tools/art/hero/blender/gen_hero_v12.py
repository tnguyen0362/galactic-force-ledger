"""gen_hero_v8: anatomical Ascendancy rifleman (human proportions, ~1.86 m).
Run inside Blender:  exec(open(path).read())
Builds collection HERO8_SRC with one object per rig part (names = Roblox rig part names with Left/Right).
"""
import bpy, bmesh, math, json, os, sys, importlib
from mathutils import Vector, Matrix, Euler

sys.path.insert(0, r"C:\Users\tnguy\gf-art-build\blender")
import hero_lib as H
importlib.reload(H)
from hero_lib import *

_rbox_full = rbox


def rbox(bm, center, size, rot=(0, 0, 0), bevel=0.006, mat=1):
    """Triangle budget: bevel (44 tris/box) only where it can be seen; tiny trim boxes stay 12-tri cubes."""
    if bevel < 0.0055 or min(size) < 0.02:
        bevel = 0
    return _rbox_full(bm, center, size, rot=rot, bevel=bevel, mat=mat)


V = Vector
S = 3.57
WT = 1.75   # R15-style body width (owner: "body width like an R15 character")
WA = 1.14   # pauldron only
WUA = 1.70
WFA = 1.60
WH = 1.25
WL = 1.50

# Squad variants: one shared body/skeleton/theme (charcoal + amber), rank read from silhouette + trim + head.
VARIANTS = {
    #               head        shoulder wing   torso      rifle   rank  scale
    "Rifleman": dict(head="helmet6",   shoulder=1.00, wing=False, torso="ref6",    rifle="std",  rank=1, scale=1.00),
    "Scout":    dict(head="goggles",   shoulder=0.00, wing=False, torso="light",   rifle="std",  rank=1, scale=0.96),
    "Marksman": dict(head="angular",   shoulder=0.62, wing=False, torso="light2",  rifle="long", rank=2, scale=1.00),
    "Heavy":    dict(head="fullvisor", shoulder=1.45, wing=False, torso="heavy",   rifle="std",  rank=3, scale=1.10),
    "Officer":  dict(head="dome",      shoulder=1.20, wing=True,  torso="harness", rifle="std",  rank=4, scale=1.05),
    # ---- elites: Spectre (Halo ODST special-ops) / Revenant (Warframe-style). head builders live in elite_parts.py
    "SpectreLeader":    dict(head="spectre", div="spectre", role="leader",    shoulder=1.50, wing=True,  torso="elite", rifle="std",  rank=3, scale=1.17),
    "SpectreAssault":   dict(head="spectre", div="spectre", role="assault",   shoulder=1.55, wing=False, torso="elite", rifle="std",  rank=2, scale=1.12),
    "SpectreWeapons":   dict(head="spectre", div="spectre", role="weapons",   shoulder=1.80, wing=False, torso="elite", rifle="lmg",  rank=2, scale=1.20),
    "SpectrePrecision": dict(head="spectre", div="spectre", role="precision", shoulder=1.10, wing=False, torso="elite", rifle="long", rank=2, scale=1.13),
    "SpectreSupport":   dict(head="spectre", div="spectre", role="support",   shoulder=1.45, wing=False, torso="elite", rifle="std",  rank=2, scale=1.10),
    "RevenantLeader":    dict(head="revenant", div="revenant", role="leader",    shoulder=1.30, wing=True,  blade=True, torso="elite", rifle="std",  rank=3, scale=1.20),
    "RevenantAssault":   dict(head="revenant", div="revenant", role="assault",   shoulder=1.15, wing=False, blade=True, torso="elite", rifle="std",  rank=2, scale=1.14),
    "RevenantWeapons":   dict(head="revenant", div="revenant", role="weapons",   shoulder=1.60, wing=False, blade=True, torso="elite", rifle="lmg",  rank=2, scale=1.20),
    "RevenantPrecision": dict(head="revenant", div="revenant", role="precision", shoulder=0.90, wing=False, blade=True, torso="elite", rifle="long", rank=2, scale=1.16),
    "RevenantDefense":   dict(head="revenant", div="revenant", role="defense",   shoulder=1.70, wing=False, blade=True, torso="elite", rifle="std",  rank=2, scale=1.20),
}
VAR = dict(VARIANTS["Rifleman"])

# ---------------------------------------------------------------- materials
PAL = {   # v11: matte charcoal / near-black (owner references), thin amber accent
    "suit":  (0.070, 0.074, 0.082),
    "plate": (0.120, 0.126, 0.140),
    "trim":  (0.700, 0.470, 0.110),
    "strap": (0.055, 0.052, 0.050),
    "skin":  (0.560, 0.410, 0.330),
    "dark":  (0.028, 0.030, 0.036),
}


def get_mats():
    out = []
    pal = ELITE_PAL.get(VAR.get("div")) or PAL
    for k in ("suit", "plate", "trim", "strap", "skin", "dark"):
        nm = "H8_" + k
        m = bpy.data.materials.get(nm) or bpy.data.materials.new(nm)
        m.use_nodes = True
        b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        b.inputs["Base Color"].default_value = (*pal[k], 1)
        b.inputs["Roughness"].default_value = {"suit": 0.85, "plate": 0.45, "trim": 0.35, "strap": 0.8, "skin": 0.6, "dark": 0.6}[k]
        b.inputs["Metallic"].default_value = {"plate": 0.25, "trim": 0.7}.get(k, 0.0)
        out.append(m)
    return out


def lerp_prof(p0, p1, prof, fwd=None):
    p0, p1 = V(p0), V(p1)
    rings = []
    for (t, rx, ry, ox, oy) in prof:
        r = dict(c=p0.lerp(p1, t), rx=rx, ry=ry, ox=ox, oy=oy)
        rings.append(r)
    return rings


# ---------------------------------------------------------------- skeleton (metres)
J = {}
J["HumanoidRootPart"] = V((0, 0, 0.90))
J["LowerTorso"] = V((0, 0, 0.97))
J["UpperTorso"] = V((0, 0, 1.10))
J["Head"] = V((0, 0, 1.54))
J["RightUpperLeg"] = V((0.095 * WL, 0, 0.94))
J["RightLowerLeg"] = V((0.115 * WL, -0.01, 0.51))
J["RightFoot"] = V((0.125 * WL, -0.09, 0.09))
J["LeftUpperLeg"] = V((-0.095 * WL, 0, 0.94))
J["LeftLowerLeg"] = V((-0.115 * WL, 0.09, 0.51))
J["LeftFoot"] = V((-0.125 * WL, 0.14, 0.09))
SH_R, SH_L = V((0.185 * WT, 0, 1.46)), V((-0.185 * WT, 0, 1.46))
L1, L2, HAND = 0.31, 0.28, 0.075

RIFLE_D = V((-0.08, 1, -0.03)).normalized()
RIFLE_UP = V((0, 0, 1))
RIFLE_UP = (RIFLE_UP - RIFLE_D * RIFLE_UP.dot(RIFLE_D)).normalized()
RIFLE_X = RIFLE_D.cross(RIFLE_UP)  # right of rifle
H_R = V((0.08, 0.24, 1.28))
RIFLE_A = H_R + RIFLE_UP * 0.07 + RIFLE_D * 0.035
H_L = RIFLE_A + RIFLE_D * 0.17 + V((0, 0, -0.04))


def two_bone(S0, target, pole, l1=L1, l2=L2):
    """Return elbow for wrist target; hand direction is handled by caller."""
    d = (target - S0)
    dist = min(d.length, l1 + l2 - 1e-4)
    dn = d.normalized()
    a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(l1 * l1 - a * a, 0))
    pp = pole - dn * pole.dot(dn)
    pp.normalize()
    return S0 + dn * a + pp * h


def solve_arm(shoulder, hand_center, pole):
    f = (hand_center - shoulder).normalized()
    wrist = hand_center - f * HAND
    for _ in range(3):
        elbow = two_bone(shoulder, wrist, pole)
        f = (hand_center - elbow).normalized()
        wrist = hand_center - f * HAND
    elbow = two_bone(shoulder, wrist, pole)
    f = (wrist - elbow).normalized()
    return elbow, wrist, f


EL_R, WR_R, F_R = solve_arm(SH_R, H_R, V((0.12, -0.35, -1)))
EL_L, WR_L, F_L = solve_arm(SH_L, H_L, V((-0.15, -0.3, -1)))
J["RightUpperArm"], J["RightLowerArm"], J["RightHand"] = SH_R, EL_R, WR_R
J["LeftUpperArm"], J["LeftLowerArm"], J["LeftHand"] = SH_L, EL_L, WR_L
J["Rifle"] = H_R

PARENT = {
    "HumanoidRootPart": None, "LowerTorso": "HumanoidRootPart", "UpperTorso": "LowerTorso", "Head": "UpperTorso",
    "RightUpperArm": "UpperTorso", "RightLowerArm": "RightUpperArm", "RightHand": "RightLowerArm",
    "LeftUpperArm": "UpperTorso", "LeftLowerArm": "LeftUpperArm", "LeftHand": "LeftLowerArm",
    "Rifle": "RightHand",
    "RightUpperLeg": "LowerTorso", "RightLowerLeg": "RightUpperLeg", "RightFoot": "RightLowerLeg",
    "LeftUpperLeg": "LowerTorso", "LeftLowerLeg": "LeftUpperLeg", "LeftFoot": "LeftLowerLeg",
}


# ---------------------------------------------------------------- parts
def part_legs(side):
    s = 1 if side == "Right" else -1
    hip, knee, ank = J[side + "UpperLeg"], J[side + "LowerLeg"], J[side + "Foot"]
    parts = {}
    # --- upper leg
    bm = new_bm()
    prof = [(-0.10, .088, .094, 0, 0), (0.0, .092, .100, 0, 0), (0.25, .089, .098, 0, .005), (0.55, .075, .085, 0, .004),
            (0.85, .061, .069, 0, 0), (1.0, .056, .062, 0, 0), (1.07, .048, .052, 0, 0)]
    loft(bm, lerp_prof(hip, knee, prof), segs=8, mat=0)
    # cargo pocket on outer thigh
    outer = V((s * 0.083, 0.0, 0))
    pc = hip.lerp(knee, 0.45) + outer
    rbox(bm, pc, (0.024, 0.075, 0.095), bevel=0.008, mat=0)
    # thigh plate strip (front)
    arcshell(bm, lerp_prof(hip, knee, [(0.12, .090, .098, 0, .004), (0.40, .090, .099, 0, .005), (0.62, .078, .088, 0, .004)]),
             segs=4, a0=-0.55, a1=0.55, th=0.010, mat=1)
    parts[side + "UpperLeg"] = bm
    # --- lower leg
    bm = new_bm()
    prof = [(-0.06, .054, .058, 0, 0), (0.0, .056, .060, 0, 0), (0.18, .058, .068, 0, -.012), (0.45, .052, .062, 0, -.008),
            (0.8, .041, .046, 0, 0), (1.0, .038, .042, 0, 0), (1.04, .036, .040, 0, 0)]
    loft(bm, lerp_prof(knee, ank, prof), segs=8, mat=0)
    # shin guard
    arcshell(bm, lerp_prof(knee, ank, [(0.10, .058, .066, 0, .004), (0.34, .056, .066, 0, .003), (0.62, .046, .056, 0, 0)]),
             segs=5, a0=-0.95, a1=0.95, th=0.014, mat=1)
    # knee pad
    rbox(bm, knee + V((0, 0.056, 0.01)), (0.095, 0.048, 0.100), bevel=0.016, mat=1)
    rbox(bm, knee + V((0, 0.080, 0.012)), (0.060, 0.012, 0.060), bevel=0.004, mat=2)
    parts[side + "LowerLeg"] = bm
    # --- boot
    bm = new_bm()
    A = V((0, 0, 0))
    # (y, full height above ground, half width)  ground = -0.09 local; instep ~ankle height, toe low
    prof_b = [(-0.078, .090, .036), (-0.040, .112, .048), (0.020, .108, .054), (0.085, .080, .058),
              (0.150, .056, .056), (0.205, .044, .048), (0.232, .034, .034)]
    rings = [dict(c=V((0, dy, -0.09 + h / 2)), rx=rx, ry=h / 2, n=2.8) for (dy, h, rx) in prof_b]
    loft(bm, rings, segs=8, fwd=V((0, 0, 1)), mat=5)
    # shaft
    shaft = [dict(c=V((0, -0.012, zz - 0.09)), rx=rx, ry=ry) for (zz, rx, ry) in
             [(0.07, .050, .056), (0.14, .051, .058), (0.205, .052, .060), (0.245, .056, .064)]]
    loft(bm, shaft, segs=8, mat=5)
    # sole
    sole = [dict(c=V((0, dy, -0.09 + 0.011)), rx=rx, ry=0.011, n=3.2) for (dy, rx) in
            [(-0.080, .037), (-0.040, .052), (0.085, .061), (0.15, .059), (0.208, .051), (0.236, .036)]]
    loft(bm, sole, segs=8, fwd=V((0, 0, 1)), mat=3)
    # strap
    arcshell(bm, [dict(c=V((0, -0.012, 0.19 - 0.09 + 0.0)), rx=.052, ry=.060), dict(c=V((0, -0.012, 0.215 - 0.09)), rx=.053, ry=.062)],
             segs=4, a0=-1.2, a1=1.2, th=0.008, mat=2)
    yaw = math.radians(-12 * s)
    R = Matrix.Translation(ank) @ Matrix.Rotation(yaw, 4, "Z")
    bmesh.ops.transform(bm, matrix=R, verts=bm.verts[:])
    parts[side + "Foot"] = bm
    return parts


def part_torso():
    parts = {}
    # --- lower torso (pelvis)
    bm = new_bm()
    ring = lambda z, rx, ry, oy=0: dict(c=V((0, oy, z)), rx=rx, ry=ry)
    loft(bm, [ring(0.88, .150, .095), ring(0.94, .172, .108, -.004), ring(1.02, .166, .105), ring(1.10, .150, .098),
              ring(1.16, .148, .095)], segs=12, mat=0, cap0=True, cap1=False)
    # belt
    loft(bm, [ring(1.03, .180, .115), ring(1.10, .180, .115)], segs=12, cap0=False, cap1=False, mat=3)
    rbox(bm, V((0, 0.116, 1.065)), (0.075, 0.020, 0.052), bevel=0.006, mat=2)
    for sx in (-1, 1):
        rbox(bm, V((sx * 0.085, 0.118, 1.07)), (0.052, 0.040, 0.085), bevel=0.008, mat=3)   # mag pouches
        rbox(bm, V((sx * 0.158, 0.060, 1.00)), (0.030, 0.070, 0.070), bevel=0.006, mat=3)
    # hip armour wings
    for sx in (-1, 1):
        arcshell(bm, [ring(0.93, .176, .112), ring(1.00, .172, .108)], segs=3,
                 a0=(0.9 if sx > 0 else -1.4), a1=(1.4 if sx > 0 else -0.9), th=0.012, mat=1)
    parts["LowerTorso"] = bm
    # --- upper torso
    bm = new_bm()
    loft(bm, [ring(1.08, .150, .095), ring(1.18, .160, .102, .005), ring(1.30, .180, .112, .008), ring(1.40, .195, .118, .010),
              ring(1.47, .175, .104, .006), ring(1.505, .125, .086, 0.0), ring(1.535, .078, .072, 0.0)], segs=12, mat=0)
    # plate carrier: front + back plates
    fr = [ring(1.22, .186, .121, .008), ring(1.32, .197, .128, .010), ring(1.43, .192, .119, .008)]
    arcshell(bm, fr, segs=8, a0=-1.0, a1=1.0, th=0.022, mat=1)
    arcshell(bm, [ring(1.25, .182, .114, .004), ring(1.34, .196, .122, .006), ring(1.44, .190, .112, .004)], segs=8,
             a0=math.pi - 1.0, a1=math.pi + 1.0, th=0.022, mat=1)
    # cummerbund
    loft(bm, [ring(1.115, .166, .107, .004), ring(1.215, .171, .112, .006)], segs=12, cap0=False, cap1=False, mat=3)
    # chest pouch rack (front)
    for i, sx in enumerate((-1, 0, 1)):
        rbox(bm, V((sx * 0.062, 0.146, 1.165)), (0.056, 0.036, 0.076), bevel=0.008, mat=3)
    # shoulder straps
    for sx in (-1, 1):
        rbox(bm, V((sx * 0.120, 0.0, 1.492)), (0.052, 0.150, 0.012), rot=(0, sx * 0.25, 0), bevel=0.003, mat=3)
    # collar / gorget
    loft(bm, [dict(c=V((0, 0.0, 1.495)), rx=.088, ry=.078), dict(c=V((0, 0.0, 1.545)), rx=.070, ry=.064)],
         segs=12, cap0=False, cap1=False, mat=1)
    rbox(bm, V((0, 0.062, 1.50)), (0.050, 0.014, 0.030), bevel=0.003, mat=2)
    # backpack + hydration roll + antenna
    T = VAR["torso"]
    if T in ("ref6", "heavy", "harness"):
        big = 1.25 if T == "heavy" else 1.0
        rbox(bm, V((0, -0.150, 1.325)), (0.270 * big, 0.115 * big, 0.360), bevel=0.022, mat=3)
        cyl(bm, V((-0.115, -0.158, 1.515)), V((0.115, -0.158, 1.515)), 0.032, segs=8, mat=3)
        cyl(bm, V((0.105, -0.17, 1.50)), V((0.105, -0.17, 1.80 if T == "harness" else 1.72)), 0.006, segs=5, mat=5)
    if T in ("ref6", "heavy"):
        # v11 (ref 6): two wide strapped chest plates + diagonal sling + shoulder-strap buckles
        if T == "ref6":   # heavy has the slab shell instead (tri budget)
            rbox(bm, V((0, 0.158, 1.420)), (0.150, 0.026, 0.050), bevel=0.008, mat=1)
            rbox(bm, V((0, 0.160, 1.345)), (0.158, 0.028, 0.052), bevel=0.008, mat=1)
            for zz in (1.420, 1.345):
                rbox(bm, V((0, 0.174, zz)), (0.150, 0.004, 0.008), bevel=0.001, mat=3)           # strap seam
                for sx in (-1, 1):
                    rbox(bm, V((sx * 0.068, 0.176, zz)), (0.012, 0.005, 0.012), bevel=0.001, mat=2)   # rivets
        rbox(bm, V((0.03, 0.150, 1.30)), (0.020, 0.030, 0.30), rot=(0, 0.55, 0), bevel=0.004, mat=3)   # sling
        # trim stripe on plate
        rbox(bm, V((0, 0.152, 1.28)), (0.10, 0.012, 0.012), bevel=0.003, mat=2)
    if T in ("light", "light2"):   # scout / marksman: slim rig, small pack, one plate (ref 5)
        rbox(bm, V((0, -0.140, 1.310)), (0.200, 0.085, 0.240), bevel=0.016, mat=3)
        rbox(bm, V((0, 0.160, 1.380)), (0.160, 0.028, 0.110), bevel=0.008, mat=1)
        rbox(bm, V((0, 0.176, 1.380)), (0.150, 0.004, 0.008), bevel=0.001, mat=3)
        rbox(bm, V((0.03, 0.150, 1.28)), (0.020, 0.030, 0.30), rot=(0, 0.55, 0), bevel=0.004, mat=3)   # sling
        rbox(bm, V((0, 0.152, 1.24)), (0.10, 0.012, 0.012), bevel=0.003, mat=2)
        if T == "light2":   # marksman: cowl collar + sniper drape pouch
            loft(bm, [dict(c=V((0, 0.0, 1.46)), rx=.125, ry=.100), dict(c=V((0, 0.0, 1.52)), rx=.095, ry=.082)],
                 segs=10, cap0=False, cap1=False, mat=3)
            rbox(bm, V((-0.10, 0.110, 1.38)), (0.05, 0.05, 0.10), bevel=0.008, mat=3)
    if T == "heavy":    # heavy: slab chest shell + high gorget + side ammo cans (ref 2)
        arcshell(bm, [ring(1.20, .200, .128, .008), ring(1.32, .212, .136, .010), ring(1.45, .205, .126, .008)],
                 segs=8, a0=-1.15, a1=1.15, th=0.030, mat=1)
        loft(bm, [dict(c=V((0, 0.0, 1.50)), rx=.115, ry=.095), dict(c=V((0, 0.0, 1.58)), rx=.092, ry=.080)],
             segs=10, cap0=False, cap1=False, mat=1)
        for sx in (-1, 1):
            rbox(bm, V((sx * 0.215, 0.040, 1.20)), (0.050, 0.100, 0.130), bevel=0, mat=3)
            rbox(bm, V((sx * 0.215, 0.092, 1.20)), (0.040, 0.004, 0.100), bevel=0.001, mat=2)
        rbox(bm, V((0, 0.178, 1.26)), (0.150, 0.010, 0.020), bevel=0.003, mat=2)
    if T == "harness":   # officer: exposed command harness w/ amber slots (ref 1)
        rbox(bm, V((0, 0.150, 1.350)), (0.150, 0.050, 0.150), bevel=0.010, mat=5)
        for sx in (-1, 1):
            rbox(bm, V((sx * 0.036, 0.178, 1.345)), (0.014, 0.008, 0.060), bevel=0.001, mat=2)
            rbox(bm, V((sx * 0.085, 0.142, 1.400)), (0.012, 0.030, 0.220), rot=(0, sx * 0.55, 0), bevel=0.003, mat=3)
            cyl(bm, V((sx * 0.100, 0.060, 1.470)), V((sx * 0.140, 0.060, 1.470)), 0.030, segs=8, mat=5)
            cyl(bm, V((sx * 0.136, 0.060, 1.470)), V((sx * 0.146, 0.060, 1.470)), 0.033, segs=8, mat=2)
        rbox(bm, V((0, 0.150, 1.248)), (0.160, 0.030, 0.030), bevel=0.005, mat=1)
        rbox(bm, V((0, 0.168, 1.248)), (0.120, 0.004, 0.010), bevel=0.001, mat=2)
    if T == "elite":
        elite_torso(bm, VAR)
    parts["UpperTorso"] = bm
    # glow panel (chest)
    bm = new_bm()
    rbox(bm, V((0, 0.158, 1.30)), (0.040, 0.008, 0.052), bevel=0.003, mat=5)
    parts["Glow_UpperTorso"] = bm
    return parts


def part_arm(side, elbow, wrist, f):
    s = 1 if side == "Right" else -1
    sh = SH_R if side == "Right" else SH_L
    parts = {}
    bm = new_bm()
    prof = [(-0.12, .058, .060, 0, 0), (0.0, .062, .064, 0, 0), (0.3, .057, .058, 0, 0), (0.65, .048, .050, 0, 0),
            (1.0, .043, .045, 0, 0), (1.08, .040, .040, 0, 0)]
    prof = [(t, rx * WUA, ry * WUA, ox, oy) for (t, rx, ry, ox, oy) in prof]
    loft(bm, lerp_prof(sh, elbow, prof), segs=8, mat=0, fwd=V((0, 1, 0)))
    # pauldron (small, layered)
    sphere(bm, sh, 0.060 * WUA, segs=8, rings=5, mat=0)   # sleeve cap under the armour
    # v11 (ref 6): layered shoulder armour - upper dome + lower flared lames, trim edge line
    ox = s * 0.022
    k = VAR["shoulder"]
    if k > 0:
        loft(bm, [dict(c=sh + V((ox, 0, 0.060 * k)), rx=.040 * k, ry=.055 * k, n=2.4),
                  dict(c=sh + V((ox, 0, 0.040 * k)), rx=.082 * k, ry=.090 * k, n=2.4),
                  dict(c=sh + V((ox, 0, 0.000)), rx=.094 * k, ry=.098 * k, n=2.4),
                  dict(c=sh + V((ox, 0, -0.030 * k)), rx=.088 * k, ry=.092 * k, n=2.4)], segs=8, mat=1)
        loft(bm, [dict(c=sh + V((ox * 1.5, 0, -0.026 * k)), rx=.100 * k, ry=.104 * k, n=2.4),
                  dict(c=sh + V((ox * 1.5, 0, -0.072 * k)), rx=.093 * k, ry=.098 * k, n=2.4)], segs=8, cap0=False, cap1=True, mat=1)
        loft(bm, [dict(c=sh + V((ox, 0, -0.027 * k)), rx=.097 * k, ry=.101 * k), dict(c=sh + V((ox, 0, -0.033 * k)), rx=.097 * k, ry=.101 * k)],
             segs=8, cap0=True, cap1=True, mat=2)                                    # trim edge line
        if VAR["wing"]:   # officer: flared shoulder wing (ref 1)
            rbox(bm, sh + V((s * 0.115 * k, 0.0, 0.050)), (0.085, 0.150, 0.014), rot=(0, s * 0.30, 0), bevel=0.006, mat=1)
            rbox(bm, sh + V((s * 0.150 * k, 0.0, 0.040)), (0.012, 0.150, 0.016), rot=(0, s * 0.30, 0), bevel=0.003, mat=2)
    if VAR.get("blade") and k > 0:   # revenant: swept pauldron blade
        rbox(bm, sh + V((s * 0.060 * k, -0.040, 0.075 * k)), (0.020, 0.200 * k, 0.016), rot=(0.35, 0, s * -0.55), bevel=0, mat=1)
        rbox(bm, sh + V((s * 0.075 * k, -0.040, 0.082 * k)), (0.008, 0.200 * k, 0.010), rot=(0.35, 0, s * -0.55), bevel=0, mat=2)
    # rank bars (amber) on the outer upper arm: 1 standard .. 4 officer
    for i in range(VAR["rank"]):
        rbox(bm, sh.lerp(elbow, 0.40) + V((s * 0.080, 0.0, 0.0 - i * 0.021)), (0.010, 0.056, 0.012), bevel=0, mat=2)
    parts[side + "UpperArm"] = bm
    bm = new_bm()
    prof = [(-0.08, .043, .044, 0, 0), (0.0, .044, .046, 0, 0), (0.20, .046, .049, 0, 0), (0.6, .037, .037, 0, 0),
            (1.0, .030, .026, 0, 0), (1.10, .028, .025, 0, 0)]
    prof = [(t, rx * WFA, ry * WFA, ox, oy) for (t, rx, ry, ox, oy) in prof]
    loft(bm, lerp_prof(elbow, wrist, prof), segs=8, mat=0)
    sphere(bm, elbow + V(0, 0, 0), 0.050, segs=8, rings=4, mat=1) if False else None
    arcshell(bm, lerp_prof(elbow, wrist, [(0.0, .047 * WFA, .050 * WFA, 0, 0), (0.12, .050 * WFA, .053 * WFA, 0, 0), (0.30, .048 * WFA, .052 * WFA, 0, 0)]),
             segs=5, a0=math.pi - 1.1, a1=math.pi + 1.1, th=0.012, mat=1)       # elbow pad (rear)
    arcshell(bm, lerp_prof(elbow, wrist, [(0.45, .040 * WFA, .041 * WFA, 0, 0), (0.75, .033 * WFA, .033 * WFA, 0, 0), (0.92, .030 * WFA, .028 * WFA, 0, 0)]),
             segs=6, a0=-1.3, a1=1.3, th=0.008, mat=1)                          # bracer
    # v11 (ref 6): heavier forearm guard + wrist unit on the support (left) arm
    arcshell(bm, lerp_prof(elbow, wrist, [(0.38, .044 * WFA, .045 * WFA, 0, 0), (0.62, .038 * WFA, .038 * WFA, 0, 0),
                                          (0.86, .032 * WFA, .031 * WFA, 0, 0)]),
             segs=6, a0=-2.2, a1=2.2, th=0.012, mat=1)
    if side == "Left":
        mid = elbow.lerp(wrist, 0.55) + V((-0.050 * WFA, 0.0, 0.012))
        rbox(bm, mid, (0.030, 0.062, 0.078), bevel=0.006, mat=5)
        rbox(bm, mid + V((-0.016, 0.0, 0.0)), (0.004, 0.044, 0.056), bevel=0.001, mat=2)
    parts[side + "LowerArm"] = bm
    return parts


def hand_frame(f, hint):
    f = f.normalized()
    n = (hint - f * hint.dot(f)).normalized()
    return f, n


def part_hand(side, wrist, f, hint, curl=3.1, R=0.030):
    f, n = hand_frame(f, hint)
    c = f.cross(n).normalized()
    bm = new_bm()
    # palm
    pal = [dict(c=wrist + f * t, rx=rx, ry=ry, n=2.5) for (t, rx, ry) in
           [(-0.02, .031, .022), (0.02, .036, .023), (0.055, .043, .025), (0.088, .046, .025)]]
    for r in pal:
        r["fwd"] = n
    loft(bm, pal, segs=8, mat=5, fwd=n)
    # curled fingers: arc around axis c, centre K - n*R
    K = wrist + f * 0.088
    cen = K - n * R
    steps = 5
    fin = []
    for i in range(steps):
        th = curl * i / (steps - 1)
        p = cen + n * (R * math.cos(th)) + f * (R * math.sin(th))
        fin.append(dict(c=p, rx=.044 - 0.001 * i, ry=.0105, n=3.0, fwd=n))
    loft(bm, fin, segs=8, mat=5, fwd=n)
    # thumb along palm side, pointing forward (side direction = c * s)
    base = wrist + f * 0.030 + c * (0.040 * (-1 if side == "Right" else 1)) - n * 0.004
    th_rings = []
    for i, (a, b) in enumerate([(0, 0), (0.030, 0.006), (0.058, 0.014), (0.080, 0.026)]):
        p = base + f * a - n * b
        th_rings.append(dict(c=p, rx=.0125 - .0012 * i, ry=.0125 - .0012 * i))
    loft(bm, th_rings, segs=6, mat=5)
    # cuff
    loft(bm, [dict(c=wrist - f * 0.020, rx=.034, ry=.030), dict(c=wrist + f * 0.020, rx=.036, ry=.032)], segs=8,
         cap0=False, cap1=False, mat=3, fwd=n)
    # knuckle guard
    rbox(bm, wrist + f * 0.078 + n * 0.022, (0.062, 0.030, 0.010), rot=(0, 0, 0), bevel=0.003, mat=1)
    return {side + "Hand": bm}


def part_rifle():
    bm = new_bm()
    A, D, U, X = RIFLE_A, RIFLE_D, RIFLE_UP, RIFLE_X
    M = Matrix(((X.x, D.x, U.x, A.x), (X.y, D.y, U.y, A.y), (X.z, D.z, U.z, A.z), (0, 0, 0, 1)))
    tmp = new_bm()
    # receiver / body
    rbox(tmp, V((0, 0.00, 0.0)), (0.062, 0.300, 0.088), bevel=0.012, mat=1)
    rbox(tmp, V((0, 0.02, 0.052)), (0.034, 0.320, 0.016), bevel=0.003, mat=5)         # top rail
    # handguard
    loft(tmp, [dict(c=V((0, 0.14, 0.0)), rx=.036, ry=.036, n=2.6), dict(c=V((0, 0.40, 0.0)), rx=.032, ry=.032, n=2.6)],
         segs=8, fwd=V((0, 0, 1)), mat=1)
    rbox(tmp, V((0, 0.27, 0.039)), (0.026, 0.25, 0.012), bevel=0.002, mat=5)
    # barrel + muzzle
    cyl(tmp, V((0, 0.40, 0.0)), V((0, 0.62, 0.0)), 0.011, segs=8, mat=5)
    cyl(tmp, V((0, 0.58, 0.0)), V((0, 0.66, 0.0)), 0.019, segs=8, mat=1)
    # stock
    loft(tmp, [dict(c=V((0, -0.12, 0.012)), rx=.026, ry=.042, n=2.6), dict(c=V((0, -0.19, -0.003)), rx=.030, ry=.060, n=2.6)],
         segs=8, fwd=V((0, 0, 1)), mat=3)
    rbox(tmp, V((0, -0.205, -0.005)), (0.036, 0.016, 0.130), bevel=0.004, mat=5)
    # pistol grip (tilted)
    rbox(tmp, V((0, -0.032, -0.085)), (0.034, 0.040, 0.100), rot=(math.radians(-18), 0, 0), bevel=0.008, mat=3)
    # magazine
    rbox(tmp, V((0, 0.045, -0.105)), (0.030, 0.050, 0.150), rot=(math.radians(8), 0, 0), bevel=0.006, mat=5)
    # optic
    cyl(tmp, V((0, 0.02, 0.085)), V((0, 0.14, 0.085)), 0.022, segs=8, mat=5)
    rbox(tmp, V((0, 0.02, 0.063)), (0.030, 0.080, 0.030), bevel=0.004, mat=1)
    # trim accent
    rbox(tmp, V((0, 0.0, 0.0)), (0.066, 0.012, 0.092), bevel=0.003, mat=2)
    # v11 (ref 6): side rails, foregrip, weapon light, yellow mag marking, ejection port
    for sx in (-1, 1):
        rbox(tmp, V((sx * 0.037, 0.26, 0.0)), (0.012, 0.22, 0.020), bevel=0.002, mat=5)
    rbox(tmp, V((0, 0.30, -0.060)), (0.026, 0.030, 0.075), rot=(math.radians(-12), 0, 0), bevel=0.006, mat=3)   # foregrip
    cyl(tmp, V((0.046, 0.30, 0.004)), V((0.046, 0.37, 0.004)), 0.014, segs=6, mat=5)                           # light
    rbox(tmp, V((0, 0.046, -0.152)), (0.032, 0.040, 0.016), rot=(math.radians(8), 0, 0), bevel=0.002, mat=2)   # mag stripe
    rbox(tmp, V((0.033, 0.03, 0.012)), (0.006, 0.060, 0.030), bevel=0.002, mat=5)                              # ejection port
    if VAR["rifle"] == "lmg":   # elite weapons: shrouded heavy barrel, drum mag, bipod
        cyl(tmp, V((0, 0.40, 0.0)), V((0, 0.70, 0.0)), 0.026, segs=8, mat=1)
        cyl(tmp, V((0, 0.70, 0.0)), V((0, 0.76, 0.0)), 0.034, segs=8, mat=5)
        cyl(tmp, V((-0.030, 0.050, -0.110)), V((0.030, 0.050, -0.110)), 0.060, segs=10, mat=3)
        for sx in (-1, 1):
            cyl(tmp, V((sx * 0.020, 0.50, -0.020)), V((sx * 0.060, 0.62, -0.090)), 0.006, segs=5, mat=5)
    if VAR["rifle"] == "long":   # marksman: long barrel + big scope
        cyl(tmp, V((0, 0.62, 0.0)), V((0, 0.95, 0.0)), 0.010, segs=8, mat=5)
        cyl(tmp, V((0, 0.90, 0.0)), V((0, 1.00, 0.0)), 0.018, segs=8, mat=1)
        cyl(tmp, V((0, -0.04, 0.100)), V((0, 0.24, 0.100)), 0.030, segs=8, mat=5)
        cyl(tmp, V((0, 0.235, 0.100)), V((0, 0.255, 0.100)), 0.034, segs=8, mat=2)
        rbox(tmp, V((0, 0.10, 0.068)), (0.030, 0.120, 0.030), bevel=0, mat=1)
    bmesh.ops.transform(tmp, matrix=M, verts=tmp.verts[:])
    me = bpy.data.meshes.new("__tmp")
    tmp.to_mesh(me)
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    tmp.free()
    # glow strip
    g = new_bm()
    tg = new_bm()
    rbox(tg, V((0, 0.26, -0.044)), (0.010, 0.22, 0.008), bevel=0.002, mat=5)
    bmesh.ops.transform(tg, matrix=M, verts=tg.verts[:])
    me = bpy.data.meshes.new("__tmp2")
    tg.to_mesh(me)
    g.from_mesh(me)
    bpy.data.meshes.remove(me)
    tg.free()
    return {"Rifle": bm, "Glow_Rifle": g}


def head_helmet6():
    """v11 (ref 6): enclosed tactical helmet - faceted shell, cheek guards, framed visor, lower mask, camera mount, ear cups."""
    parts = {}
    bm = new_bm()
    # neck gaiter
    loft(bm, [dict(c=V((0, 0, 1.50)), rx=.060, ry=.062), dict(c=V((0, 0.006, 1.60)), rx=.054, ry=.058),
              dict(c=V((0, 0.012, 1.64)), rx=.054, ry=.058)], segs=8, cap0=False, cap1=False, mat=0)
    # dark core under the shell (fills any gap behind visor/mask)
    def hr(z, rx, ry, oy):
        return dict(c=V((0, oy, z)), rx=rx, ry=ry, n=2.2)
    loft(bm, [hr(1.625, .030, .035, 0.060), hr(1.665, .066, .082, 0.032), hr(1.735, .078, .102, 0.008),
              hr(1.805, .076, .104, 0.0), hr(1.855, .044, .066, -0.006)], segs=10, mat=5)
    # faceted helmet shell (low cheek coverage, high crown)
    loft(bm, [dict(c=V((0, -0.002, 1.695)), rx=.086, ry=.108, n=2.4), dict(c=V((0, -0.004, 1.742)), rx=.095, ry=.121, n=2.4),
              dict(c=V((0, -0.004, 1.790)), rx=.096, ry=.125, n=2.4), dict(c=V((0, -0.006, 1.832)), rx=.086, ry=.114, n=2.4),
              dict(c=V((0, -0.008, 1.868)), rx=.058, ry=.082, n=2.4), dict(c=V((0, -0.008, 1.884)), rx=.030, ry=.050, n=2.4)],
         segs=10, mat=1)
    # nape guard
    arcshell(bm, [dict(c=V((0, -0.012, 1.742)), rx=.092, ry=.116), dict(c=V((0, -0.020, 1.680)), rx=.080, ry=.106)],
             segs=6, a0=math.pi - 1.2, a1=math.pi + 1.2, th=0.013, mat=1)
    # cheek guards (angled side plates)
    for sx in (-1, 1):
        ang = (0.95, 2.05) if sx > 0 else (-2.05, -0.95)
        arcshell(bm, [dict(c=V((0, 0.002, 1.700)), rx=.090, ry=.112), dict(c=V((0, 0.012, 1.648)), rx=.074, ry=.098)],
                 segs=3, a0=ang[0], a1=ang[1], th=0.012, mat=1)
    # brow ridge + visor frame + tinted visor
    rbox(bm, V((0, 0.110, 1.797)), (0.168, 0.034, 0.020), rot=(-0.10, 0, 0), bevel=0.006, mat=1)
    rbox(bm, V((0, 0.117, 1.756)), (0.164, 0.022, 0.070), rot=(0.06, 0, 0), bevel=0.010, mat=1)
    rbox(bm, V((0, 0.129, 1.757)), (0.138, 0.010, 0.050), rot=(0.06, 0, 0), bevel=0.008, mat=5)
    # lower face mask + filter
    arcshell(bm, [dict(c=V((0, 0.054, 1.634)), rx=.054, ry=.066, n=2.2), dict(c=V((0, 0.034, 1.665)), rx=.077, ry=.095, n=2.2),
                  dict(c=V((0, 0.016, 1.700)), rx=.085, ry=.107, n=2.2)], segs=8, a0=-1.35, a1=1.35, th=0.010, mat=3)
    rbox(bm, V((0, 0.126, 1.668)), (0.040, 0.020, 0.030), bevel=0.005, mat=1)
    rbox(bm, V((0, 0.137, 1.668)), (0.032, 0.004, 0.022), bevel=0.001, mat=5)
    # ear cups + side rails
    for sx in (-1, 1):
        rbox(bm, V((sx * 0.101, -0.004, 1.728)), (0.024, 0.058, 0.056), bevel=0.008, mat=1)
        rbox(bm, V((sx * 0.100, -0.004, 1.728)), (0.004, 0.034, 0.034), bevel=0.001, mat=2)
        rbox(bm, V((sx * 0.097, 0.020, 1.802)), (0.010, 0.080, 0.014), bevel=0.002, mat=3)
    # top ridge + front camera mount (ref 6)
    rbox(bm, V((0, 0.004, 1.884)), (0.022, 0.170, 0.012), bevel=0.003, mat=3)
    rbox(bm, V((0, 0.108, 1.842)), (0.056, 0.044, 0.042), bevel=0.006, mat=5)
    rbox(bm, V((0, 0.132, 1.842)), (0.030, 0.006, 0.026), bevel=0.002, mat=1)
    parts["Head"] = bm
    # visor slit + camera lens glow
    g = new_bm()
    rbox(g, V((0, 0.136, 1.758)), (0.112, 0.004, 0.012), bevel=0.002, mat=5)
    rbox(g, V((0, 0.137, 1.842)), (0.016, 0.003, 0.016), bevel=0.001, mat=5)
    parts["Glow_Head"] = g
    for b_ in (bm, g):   # seat head lower so the neck reads short and natural
        bmesh.ops.translate(b_, vec=V((0, 0, -0.022)), verts=b_.verts[:])
    return parts


def _neck(bm, thick=1.0):
    """Short thick gorget; the chin guard overlaps it so no bare 'tube neck' shows."""
    loft(bm, [dict(c=V((0, 0, 1.47)), rx=.088 * thick, ry=.082 * thick), dict(c=V((0, 0.006, 1.54)), rx=.072 * thick, ry=.070 * thick),
              dict(c=V((0, 0.012, 1.62)), rx=.066 * thick, ry=.070 * thick)], segs=12, cap0=False, cap1=False, mat=0)


def _core(bm):
    def hr(z, rx, ry, oy):
        return dict(c=V((0, oy, z)), rx=rx, ry=ry, n=2.2)
    loft(bm, [hr(1.625, .034, .040, 0.060), hr(1.665, .070, .086, 0.032), hr(1.735, .078, .100, 0.008),
              hr(1.805, .076, .102, 0.0), hr(1.855, .044, .066, -0.006)], segs=10, mat=5)


def _cr(p0, p1, p2, p3, t):
    return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3)


def _prof(zs, rxs, rys, n=2.3, oy=-0.004, up=2):
    """Profile rings, Catmull-Rom upsampled `up`x so the helmet shell is smooth (head gets the biggest tri share)."""
    def ext(a):
        return [a[0]] + list(a) + [a[-1]]
    ez, ex, ey = ext(zs), ext(rxs), ext(rys)
    out = []
    for i in range(len(zs) - 1):
        for k in range(up):
            t = k / up
            out.append(dict(c=V((0, oy, _cr(ez[i], ez[i + 1], ez[i + 2], ez[i + 3], t))), rx=_cr(ex[i], ex[i + 1], ex[i + 2], ex[i + 3], t),
                            ry=_cr(ey[i], ey[i + 1], ey[i + 2], ey[i + 3], t), n=n))
    out.append(dict(c=V((0, oy, zs[-1])), rx=rxs[-1], ry=rys[-1], n=n))
    return out


def _shell(bm, rings, paints=(), segs=24):
    """Helmet shell loft; faces are then PAINTED (material index) so visors/masks are flush with the shell, not floating bands.
    paints = [(z0, z1, fn(ang, z) -> bool, mat)]  ang = 0 at front, +/- toward the sides."""
    before = set(bm.faces)
    loft(bm, rings, segs=segs, mat=1)
    for f in [f for f in bm.faces if f not in before]:
        c = f.calc_center_median()
        ang = math.atan2(c.x, c.y)
        for (z0, z1, fn, mat) in paints:
            if z0 <= c.z <= z1 and fn(ang, c.z):
                f.material_index = mat


def _ring(z, rx, ry, oy=-0.004, n=2.3):
    return dict(c=V((0, oy, z)), rx=rx, ry=ry, n=n)


def _finish(parts, k=1.35, dz=-0.048):
    """Helmets read BIGGER than a bare head in all the refs: scale about the neck base, then seat low on the collar."""
    M = Matrix.Translation(V((0, 0, 1.60)))
    for b_ in parts.values():
        bmesh.ops.scale(b_, vec=(k, k, k * 0.97), space=M.inverted(), verts=b_.verts[:])
        bmesh.ops.translate(b_, vec=V((0, 0, dz)), verts=b_.verts[:])
    return parts


ZS = [1.660, 1.690, 1.722, 1.756, 1.790, 1.822, 1.852, 1.880, 1.900]


def head_tactical():
    """Rifleman (ref 8): faceted ballistic helmet, flush dark visor under a heavy brow shroud, vented mouth guard, crown camera pod."""
    bm = new_bm()
    _neck(bm, 1.1)
    _core(bm)
    _shell(bm, _prof(ZS, [.072, .088, .098, .104, .106, .104, .096, .070, .036], [.090, .108, .122, .130, .133, .131, .122, .092, .058], n=3.0),
           paints=[(1.714, 1.796, lambda a, z: abs(a) < 0.95, 5),
                   (1.655, 1.713, lambda a, z: abs(a) < 1.30, 3)], segs=24)
    arcshell(bm, [_ring(1.790, .108, .138), _ring(1.820, .105, .134)], segs=6, a0=-1.3, a1=1.3, th=0.014, mat=1)   # brow shroud
    for i in (-1, 0, 1):
        rbox(bm, V((i * 0.026, 0.104, 1.678)), (0.012, 0.016, 0.034), bevel=0, mat=5)
    rbox(bm, V((0.040, 0.092, 1.872)), (0.066, 0.078, 0.052), bevel=0.008, mat=5)
    cyl(bm, V((0.040, 0.128, 1.872)), V((0.040, 0.148, 1.872)), 0.019, segs=8, mat=1)
    for sx in (-1, 1):
        rbox(bm, V((sx * 0.108, -0.004, 1.730)), (0.030, 0.070, 0.074), bevel=0.010, mat=1)
        rbox(bm, V((sx * 0.124, -0.004, 1.730)), (0.004, 0.044, 0.046), bevel=0, mat=2)
        rbox(bm, V((sx * 0.100, 0.030, 1.818)), (0.012, 0.090, 0.016), bevel=0, mat=3)
    rbox(bm, V((0, 0.004, 1.898)), (0.020, 0.176, 0.012), bevel=0, mat=3)
    g = new_bm()
    rbox(g, V((0.040, 0.150, 1.872)), (0.014, 0.003, 0.014), bevel=0, mat=5)
    rbox(g, V((-0.116, 0.040, 1.700)), (0.004, 0.012, 0.012), bevel=0, mat=5)
    return _finish({"Head": bm, "Glow_Head": g}, k=1.46)


def head_goggles():
    """Scout (ref 5 left / ref 6): low round helmet, flush amber goggle band + black face wrap, NVG shroud, side rails, headset."""
    bm = new_bm()
    _neck(bm, 1.0)
    _core(bm)
    _shell(bm, _prof(ZS, [.074, .090, .098, .100, .100, .098, .090, .064, .030], [.094, .112, .124, .128, .129, .126, .116, .084, .046], n=2.1),
           paints=[(1.732, 1.786, lambda a, z: abs(a) < 1.15, 2),
                   (1.655, 1.731, lambda a, z: abs(a) < 1.45, 5)], segs=24)
    arcshell(bm, [_ring(1.790, .103, .132), _ring(1.728, .103, .132)], segs=3, a0=-1.22, a1=-1.12, th=0.006, mat=5)   # goggle frame L
    arcshell(bm, [_ring(1.790, .103, .132), _ring(1.728, .103, .132)], segs=3, a0=1.12, a1=1.22, th=0.006, mat=5)    # goggle frame R
    loft(bm, [dict(c=V((0, 0.0, 1.756)), rx=.1035, ry=.1325), dict(c=V((0, 0.0, 1.772)), rx=.1035, ry=.1325)],
         segs=12, cap0=False, cap1=False, mat=3)
    rbox(bm, V((0, 0.108, 1.856)), (0.062, 0.056, 0.046), bevel=0.008, mat=5)
    rbox(bm, V((0, 0.138, 1.856)), (0.040, 0.008, 0.028), bevel=0, mat=1)
    rbox(bm, V((0, 0.004, 1.890)), (0.020, 0.150, 0.010), bevel=0, mat=3)
    for sx in (-1, 1):
        rbox(bm, V((sx * 0.102, -0.002, 1.795)), (0.012, 0.100, 0.020), bevel=0, mat=3)
        rbox(bm, V((sx * 0.104, 0.004, 1.730)), (0.024, 0.056, 0.056), bevel=0.008, mat=5)
    cyl(bm, V((-0.112, 0.004, 1.716)), V((-0.092, 0.116, 1.676)), 0.0045, segs=5, mat=5)
    g = new_bm()
    rbox(g, V((0, 0.143, 1.856)), (0.012, 0.003, 0.012), bevel=0, mat=5)
    return _finish({"Head": bm, "Glow_Head": g}, k=1.42)


def head_angular():
    """Marksman (ref 3): tall egg helmet, dark front panel split by a raised blade, V panel lines, glow slits, long chin mask, one whip antenna."""
    bm = new_bm()
    _neck(bm, 1.05)
    _core(bm)
    zs = [1.655, 1.690, 1.725, 1.762, 1.800, 1.838, 1.876, 1.912, 1.938, 1.956]
    _shell(bm, _prof(zs, [.070, .084, .095, .101, .102, .098, .090, .072, .046, .024],
                     [.090, .106, .120, .129, .132, .128, .120, .102, .072, .042], n=2.2),
           paints=[(1.690, 1.930, lambda a, z: abs(a) < 0.62, 5),
                   (1.650, 1.700, lambda a, z: abs(a) < 1.35, 3)], segs=24)
    rbox(bm, V((0, 0.128, 1.812)), (0.030, 0.024, 0.240), rot=(-0.05, 0, 0), bevel=0.006, mat=1)       # raised front blade
    for sx in (-1, 1):
        rbox(bm, V((sx * 0.050, 0.120, 1.862)), (0.010, 0.012, 0.130), rot=(0, sx * 0.34, 0), bevel=0, mat=1)   # V panel lines
        rbox(bm, V((sx * 0.112, 0.020, 1.770)), (0.020, 0.060, 0.090), bevel=0.006, mat=3)               # side comms
        rbox(bm, V((sx * 0.123, 0.020, 1.770)), (0.004, 0.034, 0.050), bevel=0, mat=2)
    rbox(bm, V((0, 0.116, 1.646)), (0.050, 0.044, 0.060), rot=(0.25, 0, 0), bevel=0.008, mat=1)          # pointed chin
    cyl(bm, V((0.108, -0.040, 1.800)), V((0.108, -0.070, 1.990)), 0.0045, segs=5, mat=5)
    g = new_bm()
    for sx in (-1, 1):
        rbox(g, V((sx * 0.034, 0.140, 1.790)), (0.008, 0.004, 0.130), rot=(0, sx * 0.22, 0), bevel=0, mat=5)
    return _finish({"Head": bm, "Glow_Head": g}, k=1.42)


def head_fullvisor():
    """Heavy (ref 2): big helmet, notched visor cap, huge flush bubble visor, angular chin, round comm unit."""
    bm = new_bm()
    _neck(bm, 1.25)
    _core(bm)
    _shell(bm, _prof(ZS, [.078, .096, .106, .110, .110, .108, .100, .072, .036], [.098, .118, .132, .138, .140, .137, .128, .096, .060], n=2.4),
           paints=[(1.682, 1.806, lambda a, z: abs(a) < 1.10, 5),
                   (1.655, 1.681, lambda a, z: abs(a) < 0.80, 3)], segs=24)
    for sx in (-1, 1):   # visor cap with a notch in the middle (ref 2)
        rbox(bm, V((sx * 0.062, 0.100, 1.852)), (0.092, 0.058, 0.060), rot=(-0.12, 0, 0), bevel=0.008, mat=1)
    rbox(bm, V((0, 0.110, 1.856)), (0.034, 0.040, 0.046), bevel=0, mat=5)
    arcshell(bm, [_ring(1.812, .1115, .1425), _ring(1.800, .1115, .1425)], segs=8, a0=-1.15, a1=1.15, th=0.012, mat=1)   # visor top lip
    rbox(bm, V((0, 0.118, 1.648)), (0.130, 0.058, 0.048), rot=(0.18, 0, 0), bevel=0.012, mat=1)         # chin guard
    rbox(bm, V((0, 0.130, 1.620)), (0.056, 0.034, 0.034), rot=(0.30, 0, 0), bevel=0.006, mat=3)         # breather
    for sx in (-1, 1):
        cyl(bm, V((sx * 0.104, 0.0, 1.738)), V((sx * 0.140, 0.0, 1.738)), 0.036, segs=8, mat=1)
        cyl(bm, V((sx * 0.138, 0.0, 1.738)), V((sx * 0.146, 0.0, 1.738)), 0.024, segs=8, mat=2)
    g = new_bm()
    rbox(g, V((0, 0.132, 1.868)), (0.026, 0.003, 0.012), bevel=0, mat=5)
    return _finish({"Head": bm, "Glow_Head": g}, k=1.44)


def head_dome():
    """Officer (ref 1): smooth dome, thin amber brow trim, small side fins, ribbed ear cups, flush copper V-visor tapering to a dark chin mask."""
    bm = new_bm()
    _neck(bm, 1.15)
    _core(bm)
    vis = lambda a, z: abs(a) < (0.30 + 0.80 * min(1.0, max(0.0, (z - 1.655) / 0.14)))
    _shell(bm, _prof(ZS, [.074, .090, .099, .102, .102, .100, .092, .068, .034], [.094, .112, .124, .129, .130, .128, .119, .090, .052], n=2.0),
           paints=[(1.700, 1.796, vis, 2),
                   (1.652, 1.699, lambda a, z: abs(a) < 1.10, 5)], segs=24)
    loft(bm, [_ring(1.799, .1035, .1325, n=2.0), _ring(1.812, .1035, .1325, n=2.0)], segs=14, cap0=True, cap1=True, mat=2)   # brow trim
    for sx in (-1, 1):
        for i in range(3):
            rbox(bm, V((sx * 0.112, -0.004, 1.716 + i * 0.022)), (0.034, 0.064, 0.016), bevel=0, mat=5)
        rbox(bm, V((sx * 0.131, -0.004, 1.738)), (0.004, 0.044, 0.050), bevel=0, mat=2)
    rbox(bm, V((0, -0.004, 1.905)), (0.016, 0.200, 0.018), bevel=0.004, mat=2)   # amber command crest
    cyl(bm, V((-0.116, 0.014, 1.690)), V((-0.074, 0.114, 1.644)), 0.0045, segs=5, mat=5)
    g = new_bm()
    rbox(g, V((0, 0.142, 1.700)), (0.050, 0.004, 0.010), bevel=0, mat=5)
    return _finish({"Head": bm, "Glow_Head": g}, k=1.42)


exec(open(os.path.join(os.path.dirname(H.__file__), "elite_parts.py"), encoding="utf-8").read(), globals())
ring = lambda z, rx, ry, oy=0: dict(c=V((0, oy, z)), rx=rx, ry=ry)


def part_head():
    if VAR["head"] == "spectre":
        return head_spectre(VAR["role"])
    if VAR["head"] == "revenant":
        return head_revenant(VAR["role"])
    return {"helmet6": head_tactical, "goggles": head_goggles, "angular": head_angular,
            "fullvisor": head_fullvisor, "dome": head_dome}[VAR["head"]]()


def build(collection_name="HERO8_SRC", variant=None):
    # clear old
    if collection_name in bpy.data.collections:
        c = bpy.data.collections[collection_name]
        for o in list(c.objects):
            bpy.data.objects.remove(o, do_unlink=True)
    else:
        c = bpy.data.collections.new(collection_name)
        bpy.context.scene.collection.children.link(c)
    if variant:
        VAR.clear()
        VAR.update(VARIANTS[variant])
    mats = get_mats()
    allparts = {}
    allparts.update(part_torso())
    allparts.update(part_legs("Right"))
    allparts.update(part_legs("Left"))
    allparts.update(part_arm("Right", EL_R, WR_R, F_R))
    allparts.update(part_arm("Left", EL_L, WR_L, F_L))
    allparts.update(part_hand("Right", WR_R, F_R, V((1, 0, 0))))
    allparts.update(part_hand("Left", WR_L, F_L, V((-0.5, 0, -1))))
    allparts.update(part_rifle())
    allparts.update(part_head())
    # ---- widening (post-build): torso family about x=0, leg segments about their own joint x
    def xscale(bm, f, cx):
        M = Matrix.Translation((cx, 0, 0)) @ Matrix.Diagonal((f, 1, 1, 1)) @ Matrix.Translation((-cx, 0, 0))
        bmesh.ops.transform(bm, matrix=M, verts=bm.verts[:])
    for n_ in ("LowerTorso", "UpperTorso", "Glow_UpperTorso"):
        xscale(allparts[n_], WT, 0.0)
    for side_, wr_ in (("Right", WR_R), ("Left", WR_L)):
        bmesh.ops.scale(allparts[side_ + "Hand"], vec=(WH, WH, WH), space=Matrix.Translation(-wr_), verts=allparts[side_ + "Hand"].verts[:])
    for side_ in ("Right", "Left"):
        for seg_ in ("UpperLeg", "LowerLeg", "Foot"):
            xscale(allparts[side_ + seg_], WL, J[side_ + seg_].x)
    objs = {}
    for name, bm in allparts.items():
        glow = name.startswith("Glow_")
        ob = to_object(name, bm, c, mats, smooth=True, edge_split_deg=58)
        objs[name] = ob
    return objs


if __name__ == "__main__" or True:
    OBJS = build(variant=globals().get("VARIANT", "Rifleman"))
    tot = 0
    for n, o in OBJS.items():
        t = tri_count(o)
        tot += t
        print(f"{n:16s} {t}")
    print("TOTAL tris", tot)
    print("elbowR", EL_R, "wristR", WR_R, "elbowL", EL_L, "wristL", WR_L)
    print("rifleA", RIFLE_A, "H_L", H_L)
