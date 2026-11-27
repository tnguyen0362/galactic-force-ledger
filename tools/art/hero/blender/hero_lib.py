"""hero_lib: bmesh helpers for the anatomical hero rebuild (v8).
Coordinates: metres, Z up, character faces +Y, character's RIGHT is +X.
Export multiplies by S=3.57 studs/m and maps to Roblox as (x*S, z*S, -y*S) (glTF y-up).
"""
import bpy, bmesh, math
from mathutils import Vector, Matrix, Euler

MATS = {"suit": 0, "plate": 1, "trim": 2, "strap": 3, "skin": 4, "dark": 5}


def _frame(path, i, fwd):
    n = len(path)
    a = path[max(i - 1, 0)]
    b = path[min(i + 1, n - 1)]
    t = (b - a)
    if t.length < 1e-9:
        t = Vector((0, 0, 1))
    t.normalize()
    v = fwd - t * fwd.dot(t)
    if v.length < 1e-4:
        alt = Vector((1, 0, 0))
        v = alt - t * alt.dot(t)
    v.normalize()
    u = v.cross(t)  # for t=+Z, v=+Y -> u=+X (character right)
    return u, v, t


def _sq(c, s, n):
    """superellipse coordinate; n=2 ellipse, n>2 squarer."""
    return math.copysign(abs(c) ** (2.0 / n), c)


def ring_points(r, u, v, segs, a0=0.0, a1=None, off=0.0):
    """Points of ring r. theta=0 at +v (front), increasing toward +u (right)."""
    pts = []
    n = r.get("n", 2.0)
    rx = r["rx"] + off
    ry = r["ry"] + off
    ox = r.get("ox", 0.0)
    oy = r.get("oy", 0.0)
    full = a1 is None
    if full:
        a1 = a0 + 2 * math.pi
    cnt = segs if full else segs + 1
    for k in range(cnt):
        th = a0 + (a1 - a0) * (k / segs)
        sx = _sq(math.sin(th), 0, n)
        sy = _sq(math.cos(th), 0, n)
        p = r["c"] + u * (ox + sx * rx) + v * (oy + sy * ry)
        pts.append(p)
    return pts


def loft(bm, rings, segs=12, cap0=True, cap1=True, fwd=Vector((0, 1, 0)), mat=0, flip=False):
    """Closed tube through elliptical rings. Returns list of faces."""
    path = [r["c"] for r in rings]
    grid = []
    for i, r in enumerate(rings):
        u, v, t = _frame(path, i, r.get("fwd", fwd))
        pts = ring_points(r, u, v, segs)
        grid.append([bm.verts.new(p) for p in pts])
    faces = []
    for i in range(len(grid) - 1):
        for k in range(segs):
            k2 = (k + 1) % segs
            vs = [grid[i][k], grid[i][k2], grid[i + 1][k2], grid[i + 1][k]]
            if flip:
                vs.reverse()
            f = bm.faces.new(vs)
            f.material_index = mat
            faces.append(f)
    for idx, cap in ((0, cap0), (len(grid) - 1, cap1)):
        if cap:
            ring = grid[idx]
            cen = sum((v.co for v in ring), Vector()) / len(ring)
            cv = bm.verts.new(cen)
            for k in range(segs):
                k2 = (k + 1) % segs
                vs = [ring[k2], ring[k], cv] if idx == 0 else [ring[k], ring[k2], cv]
                if flip:
                    vs.reverse()
                f = bm.faces.new(vs)
                f.material_index = mat
                faces.append(f)
    return faces


def arcshell(bm, rings, segs=8, a0=-1.0, a1=1.0, th=0.02, fwd=Vector((0, 1, 0)), mat=1):
    """Curved plate hugging the rings between angles a0..a1 (0=front), thickness th."""
    path = [r["c"] for r in rings]
    outer, inner = [], []
    for i, r in enumerate(rings):
        u, v, t = _frame(path, i, r.get("fwd", fwd))
        outer.append([bm.verts.new(p) for p in ring_points(r, u, v, segs, a0, a1, off=th)])
        inner.append([bm.verts.new(p) for p in ring_points(r, u, v, segs, a0, a1, off=0.0)])
    nr = len(rings)
    cols = segs + 1
    out = []

    def quad(a, b, c, d, flip=False):
        vs = [a, b, c, d]
        if flip:
            vs.reverse()
        f = bm.faces.new(vs)
        f.material_index = mat
        out.append(f)

    for i in range(nr - 1):
        for k in range(segs):
            quad(outer[i][k], outer[i][k + 1], outer[i + 1][k + 1], outer[i + 1][k])
            quad(inner[i][k], inner[i][k + 1], inner[i + 1][k + 1], inner[i + 1][k], flip=True)
        # side walls
        quad(outer[i][0], outer[i + 1][0], inner[i + 1][0], inner[i][0])
        quad(outer[i][segs], inner[i][segs], inner[i + 1][segs], outer[i + 1][segs])
    for k in range(segs):
        quad(outer[0][k], inner[0][k], inner[0][k + 1], outer[0][k + 1])
        quad(outer[nr - 1][k], outer[nr - 1][k + 1], inner[nr - 1][k + 1], inner[nr - 1][k])
    return out


def rbox(bm, center, size, rot=(0, 0, 0), bevel=0.006, mat=1):
    """Bevelled box. size = full extents (x,y,z)."""
    ret = bmesh.ops.create_cube(bm, size=1.0)
    vs = ret["verts"]
    M = Matrix.Translation(Vector(center)) @ Euler(rot, "XYZ").to_matrix().to_4x4() @ Matrix.Diagonal(Vector((*size, 1.0)))
    bmesh.ops.transform(bm, matrix=M, verts=vs)
    faces = list({f for v in vs for f in v.link_faces})
    for f in faces:
        f.material_index = mat
    if bevel > 0:
        edges = list({e for v in vs for e in v.link_edges})
        res = bmesh.ops.bevel(bm, geom=edges, offset=bevel, segments=1, affect="EDGES")
        for f in res["faces"]:
            f.material_index = mat
    return faces


def cyl(bm, p0, p1, r0, r1=None, segs=8, mat=1, caps=True):
    p0 = Vector(p0)
    p1 = Vector(p1)
    r1 = r0 if r1 is None else r1
    axis = (p1 - p0)
    return loft(bm, [dict(c=p0, rx=r0, ry=r0), dict(c=p1, rx=r1, ry=r1)], segs=segs, cap0=caps, cap1=caps,
                fwd=Vector((0, 1, 0)) if abs(axis.normalized().y) < 0.9 else Vector((1, 0, 0)), mat=mat)


def sphere(bm, center, r, segs=8, rings=5, mat=1, squash=(1, 1, 1)):
    rs = []
    for i in range(rings + 1):
        a = -math.pi / 2 + math.pi * i / rings
        rr = max(math.cos(a), 0.05)
        rs.append(dict(c=Vector(center) + Vector((0, 0, math.sin(a) * r * squash[2])), rx=rr * r * squash[0], ry=rr * r * squash[1]))
    return loft(bm, rs, segs=segs, cap0=True, cap1=True, mat=mat)


def new_bm():
    return bmesh.new()


def to_object(name, bm, coll, mats, smooth=True, edge_split_deg=38):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = smooth
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    if smooth and edge_split_deg:
        md = ob.modifiers.new("ES", "EDGE_SPLIT")
        md.split_angle = math.radians(edge_split_deg)
        md.use_edge_angle = True
        md.use_edge_sharp = False
    return ob


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)
