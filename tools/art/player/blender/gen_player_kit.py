"""Player SEAL-style open-face armor kit (Blender 5.x).

Authoring frame per limb: origin = limb centre, X = Roblox +X (right), Y = FRONT (Roblox -Z), Z = up.
(hero_export.rbx_pt maps blender (x,y,z) -> roblox (x, z, -y).)
Every piece is a bevelled box in a colour GROUP; one mesh object per limb x group, e.g. "UpperTorso_carrier".
Face stays visible: helmet is a high-cut cap + nape skirt, nothing crosses the face plane below the brow line.
"""
import bpy, bmesh, math
from mathutils import Vector, Matrix

# default classic R15 limb sizes (x, depth, height) in studs at scale 1; re-fit after measuring the normalised rig
DIM = {
    "Head": (1.2, 1.2, 1.2), "UpperTorso": (2.0, 1.0, 1.6), "LowerTorso": (2.0, 1.0, 0.4),
    "UpperArm": (1.0, 1.0, 1.2), "LowerArm": (1.0, 1.0, 1.1), "Hand": (1.0, 1.0, 0.3),
    "UpperLeg": (1.0, 1.0, 1.2), "LowerLeg": (1.0, 1.0, 1.2), "Foot": (1.0, 1.0, 0.3),
}
# world centres of the neutral-standing proxy (only for the assembled preview)
WORLD = {
    "Head": (0, 0, 5.4), "UpperTorso": (0, 0, 3.9), "LowerTorso": (0, 0, 2.9),
    "UpperArm": (1.5, 0, 4.1), "LowerArm": (1.5, 0, 2.95), "Hand": (1.5, 0, 2.25),
    "UpperLeg": (0.5, 0, 2.1), "LowerLeg": (0.5, 0, 0.9), "Foot": (0.5, 0, 0.15),
}
COLORS = {  # preview only - Roblox colours come from the suit config at runtime
    "carrier": (0.42, 0.35, 0.24), "pouch": (0.20, 0.24, 0.15), "hardware": (0.07, 0.07, 0.08),
    "helmet": (0.50, 0.43, 0.31), "glove": (0.09, 0.09, 0.10), "boot": (0.13, 0.10, 0.08),
}
ONE_SIDED = {  # name -> side the piece lives on (+1 right, -1 left); others mirror
}

CYL = []  # (limb, group, centre, radius, depth, axis, verts)
P = []  # (limb, group, centre, size, bevel, segs, taper, mirror)


def piece(limb, group, c, s, bev=0.05, segs=1, taper=1.0, mirror=False):
    P.append((limb, group, c, s, bev, segs, taper, mirror))


# ------------------------------------------------------------------ HEAD (face stays open; most tris live here)
piece("Head", "helmet", (0, -0.02, 0.52), (1.46, 1.46, 0.48), 0.17, 3, 0.80)           # cap / brim over forehead
piece("Head", "helmet", (0, 0.50, 0.36), (1.12, 0.30, 0.14), 0.05, 1)                  # forehead brim lip
piece("Head", "helmet", (0, -0.55, 0.02), (1.40, 0.34, 0.56), 0.11, 2, 0.84)                 # nape skirt
piece("Head", "helmet", (0.66, -0.05, 0.14), (0.16, 0.92, 0.30), 0.05, 1, mirror=True)  # temple flaps
piece("Head", "hardware", (0, 0.77, 0.50), (0.50, 0.20, 0.30), 0.06, 2)                # NVG shroud
piece("Head", "hardware", (0, 0.70, 0.52), (0.36, 0.08, 0.38), 0.03)                   # shroud mount plate
piece("Head", "hardware", (0.77, -0.02, 0.50), (0.07, 0.92, 0.11), 0.025, 1, mirror=True)  # ARC rails
piece("Head", "hardware", (-0.64, 0.30, -0.20), (0.06, 0.58, 0.06), 0.02)             # boom mic arm
piece("Head", "hardware", (-0.50, 0.60, -0.22), (0.16, 0.10, 0.10), 0.03)              # boom mic tip
piece("Head", "pouch", (0, -0.78, 0.36), (0.82, 0.14, 0.36), 0.05, 1)                  # counterweight pouch
piece("Head", "hardware", (0, -0.78, 0.60), (0.5, 0.12, 0.08), 0.025)                  # rear retention dial block

CYL.append(("Head", "hardware", (0.74, -0.02, -0.05), 0.27, 0.20, "x", 10))              # comms earcups (mirrored)
CYL.append(("Head", "hardware", (0, 0.88, 0.50), 0.12, 0.16, "y", 8))                   # NVG objective barrel

# ------------------------------------------------------------------ UPPER TORSO: plate carrier
piece("UpperTorso", "carrier", (0, 0.58, 0.02), (1.74, 0.24, 1.40), 0.08, 2)           # front plate bag
piece("UpperTorso", "carrier", (0, -0.58, 0.02), (1.74, 0.24, 1.40), 0.08, 2)          # back plate bag
piece("UpperTorso", "carrier", (0, 0, -0.46), (2.06, 1.12, 0.55), 0.08, 1)             # cummerbund
piece("UpperTorso", "carrier", (0.62, 0, 0.74), (0.42, 1.18, 0.14), 0.05, 1, mirror=True)  # shoulder straps
for x in (-0.52, 0.0, 0.52):
    piece("UpperTorso", "pouch", (x, 0.78, -0.34), (0.46, 0.22, 0.56), 0.05, 1)        # triple mag flap
    piece("UpperTorso", "hardware", (x, 0.90, -0.14), (0.20, 0.04, 0.10), 0.015)       # snap tabs
piece("UpperTorso", "pouch", (0.60, 0.72, 0.34), (0.44, 0.20, 0.46), 0.05, 1)          # radio pouch
piece("UpperTorso", "pouch", (-0.50, 0.72, 0.34), (0.62, 0.12, 0.34), 0.04, 1)         # admin panel
piece("UpperTorso", "pouch", (0, -0.74, -0.05), (1.10, 0.18, 0.80), 0.06, 1)           # back hydration panel
piece("UpperTorso", "hardware", (0, -0.74, 0.70), (0.50, 0.10, 0.10), 0.03)            # drag handle

# ------------------------------------------------------------------ LOWER TORSO: battle belt
piece("LowerTorso", "pouch", (0, 0, 0.0), (2.10, 1.10, 0.30), 0.05, 1)                 # belt
piece("LowerTorso", "hardware", (0, 0.56, 0.0), (0.30, 0.08, 0.22), 0.025)             # buckle
piece("LowerTorso", "pouch", (0.40, 0.60, 0.0), (0.30, 0.14, 0.28), 0.04, 1, mirror=True)  # pistol mag pouches
piece("LowerTorso", "pouch", (0, -0.66, -0.04), (0.90, 0.30, 0.42), 0.05, 1)           # dump pouch

# ------------------------------------------------------------------ ARMS / HANDS
piece("UpperArm", "carrier", (0, 0, 0.50), (1.14, 1.14, 0.36), 0.09, 2, mirror=True)   # shoulder cap
piece("LowerArm", "hardware", (0, 0.04, 0.42), (1.10, 1.12, 0.32), 0.07, 1, mirror=True)  # elbow pad
piece("Hand", "glove", (0, 0, 0.0), (1.08, 1.08, 0.34), 0.10, 2, mirror=True)          # tactical glove
piece("Hand", "hardware", (0, 0, 0.19), (1.10, 1.10, 0.10), 0.03, 1, mirror=True)      # cuff

# ------------------------------------------------------------------ LEGS / BOOTS
piece("UpperLeg", "hardware", (0.58, 0.0, -0.10), (0.20, 0.55, 0.80), 0.05, 1)         # right drop-leg holster (R only)
piece("UpperLeg", "pouch", (-0.58, 0.02, -0.05), (0.20, 0.60, 0.60), 0.05, 1)          # left cargo pocket (L only)
piece("LowerLeg", "hardware", (0, 0.55, 0.38), (0.92, 0.22, 0.48), 0.07, 2, mirror=True)  # knee pad
piece("LowerLeg", "boot", (0, 0, -0.40), (1.10, 1.10, 0.55), 0.10, 2, mirror=True)     # boot shaft
piece("Foot", "boot", (0, 0.0, 0.0), (1.10, 1.20, 0.38), 0.08, 2, mirror=True)         # boot foot
piece("Foot", "hardware", (0, 0.05, -0.16), (1.14, 1.26, 0.10), 0.03, 1, mirror=True)  # sole

LIMB_SIDED = {"UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot"}
SIDE_ONLY = {("UpperLeg", "hardware"): 1, ("UpperLeg", "pouch"): -1}  # holster right, pocket left


def mk_box(c, s, bev, segs, taper):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= s[0]
        v.co.y *= s[1]
        v.co.z *= s[2]
        if taper != 1.0 and v.co.z > 0:
            v.co.x *= taper
            v.co.y *= taper
        v.co += Vector(c)
    if bev > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bev, segments=segs, affect="EDGES", profile=0.5)
    return bm


def build(coll_name="PLAYERKIT"):
    for cn in (coll_name, coll_name + "_ASM", coll_name + "_PROXY"):
        if cn in bpy.data.collections:
            for o in list(bpy.data.collections[cn].objects):
                bpy.data.objects.remove(o, do_unlink=True)
            bpy.data.collections.remove(bpy.data.collections[cn])
    src = bpy.data.collections.new(coll_name)
    asm = bpy.data.collections.new(coll_name + "_ASM")
    prox = bpy.data.collections.new(coll_name + "_PROXY")
    for c in (src, asm, prox):
        bpy.context.scene.collection.children.link(c)
    mats = {}
    for g, col in COLORS.items():
        m = bpy.data.materials.get("PK_" + g) or bpy.data.materials.new("PK_" + g)
        m.use_nodes = True
        b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        b.inputs["Base Color"].default_value = (*col, 1)
        b.inputs["Roughness"].default_value = 0.6 if g != "hardware" else 0.4
        mats[g] = m
    # group pieces into (limb[,side], group) bmeshes
    bms = {}
    for limb, grp, c, s, bev, segs, taper, mirror in P:
        sides = [None]
        if limb in LIMB_SIDED:
            only = SIDE_ONLY.get((limb, grp))
            sides = [only] if only else [1, -1]
        for sd in sides:
            cc = list(c)
            if sd == -1 and mirror:
                cc[0] = -cc[0]
            if limb in LIMB_SIDED and not mirror and sd is None:
                pass
            bm = mk_box(cc, s, bev, segs, taper)
            if limb not in LIMB_SIDED and mirror:
                bm2 = mk_box((-cc[0], cc[1], cc[2]), s, bev, segs, taper)
                bmM = bms.setdefault((limb, None, grp), bmesh.new())
                for b_ in (bm, bm2):
                    me = bpy.data.meshes.new("tmp")
                    b_.to_mesh(me)
                    bmM.from_mesh(me)
                    bpy.data.meshes.remove(me)
                    b_.free()
                continue
            key = (limb, sd, grp)
            tgt = bms.setdefault(key, bmesh.new())
            me = bpy.data.meshes.new("tmp")
            bm.to_mesh(me)
            tgt.from_mesh(me)
            bpy.data.meshes.remove(me)
            bm.free()
    for limb, grp, c, r, dp, ax, nv in CYL:
        for sx in ((1, -1) if ax == "x" else (1,)):
            bm = bmesh.new()
            bmesh.ops.create_cone(bm, cap_ends=True, segments=nv, radius1=r, radius2=r * 0.92, depth=dp)
            # cone axis is Z; rotate onto the requested axis
            if ax == "x":
                bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "Y"))
            elif ax == "y":
                bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "X"))
            for v in bm.verts:
                v.co += Vector((c[0] * sx, c[1], c[2]))
            if ax == "x" and sx == -1:
                pass
            me = bpy.data.meshes.new("tmp")
            bm.to_mesh(me)
            tgt = bms.setdefault((limb, None, grp), bmesh.new())
            tgt.from_mesh(me)
            bpy.data.meshes.remove(me)
            bm.free()
    objs = {}
    for (limb, sd, grp), bm in bms.items():
        sname = {None: "", 1: "R", -1: "L"}[sd]
        name = ("%s%s_%s" % (limb, sname, grp))
        me = bpy.data.meshes.new(name)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bmesh.ops.triangulate(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(mats[grp])
        for p in me.polygons:
            p.use_smooth = False
        o = bpy.data.objects.new(name, me)
        src.objects.link(o)
        o["limb"] = limb
        o["side"] = sname
        o["group"] = grp
        objs[name] = o
    # assembled preview: place limb-local meshes at world limb centres (+ proxy mannequin)
    for name, o in objs.items():
        limb = o["limb"]
        side = o["side"]
        w = Vector(WORLD[limb])
        if side == "L":
            w.x = -w.x
        a = bpy.data.objects.new("ASM_" + name, o.data)
        a.location = w
        asm.objects.link(a)
    skin = bpy.data.materials.get("PK_skin") or bpy.data.materials.new("PK_skin")
    skin.use_nodes = True
    next(n for n in skin.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"].default_value = (0.55, 0.38, 0.28, 1)
    fat = bpy.data.materials.get("PK_fatigue") or bpy.data.materials.new("PK_fatigue")
    fat.use_nodes = True
    next(n for n in fat.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"].default_value = (0.28, 0.30, 0.22, 1)
    for limb, d in DIM.items():
        for sd in ([1, -1] if limb in LIMB_SIDED else [None]):
            bm = bmesh.new()
            bmesh.ops.create_cube(bm, size=1.0)
            for v in bm.verts:
                v.co.x *= d[0]
                v.co.y *= d[1]
                v.co.z *= d[2]
            me = bpy.data.meshes.new("proxy_" + limb)
            bm.to_mesh(me)
            bm.free()
            me.materials.append(skin if limb in ("Head",) else fat)
            o = bpy.data.objects.new("PROXY_%s%s" % (limb, {None: "", 1: "R", -1: "L"}[sd]), me)
            w = Vector(WORLD[limb])
            if sd == -1:
                w.x = -w.x
            o.location = w
            prox.objects.link(o)
    # face marks on the proxy head so "face visible" is checkable: eyes + mouth just proud of the front face
    for nm, c, s in (("eyeL", (-0.25, 0.605, 0.10), (0.14, 0.02, 0.10)), ("eyeR", (0.25, 0.605, 0.10), (0.14, 0.02, 0.10)),
                     ("mouth", (0, 0.605, -0.25), (0.34, 0.02, 0.06)), ("brow", (0, 0.605, 0.26), (0.7, 0.02, 0.05))):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        for v in bm.verts:
            v.co.x *= s[0]
            v.co.y *= s[1]
            v.co.z *= s[2]
        me = bpy.data.meshes.new(nm)
        bm.to_mesh(me)
        bm.free()
        dark = bpy.data.materials.get("PK_dark") or bpy.data.materials.new("PK_dark")
        dark.use_nodes = True
        next(n for n in dark.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"].default_value = (0.02, 0.02, 0.02, 1)
        me.materials.append(dark)
        o = bpy.data.objects.new("PROXY_face_" + nm, me)
        o.location = (c[0] + WORLD["Head"][0], c[1] + WORLD["Head"][1], c[2] + WORLD["Head"][2])
        prox.objects.link(o)
    tri = {}
    for n, o in objs.items():
        tri[o["limb"]] = tri.get(o["limb"], 0) + len(o.data.polygons)
    print("tris by limb", tri, "total", sum(tri.values()))
    return objs


if __name__ == "__main__" or True:
    build()
