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
import bpy, bmesh, math, sys, os, zlib
from mathutils import Vector, Matrix, Euler

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.join(os.path.dirname(os.path.abspath(__file__)), "out_kit")
ONLY = set(argv[1:])
os.makedirs(OUT, exist_ok=True)
S = 3.57  # metres -> studs at game character scale


def hexc(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def ramp(c, lo=0.58, hi=1.12):
    return (tuple(min(255, int(v * lo)) for v in c), tuple(min(255, int(v * hi)) for v in c))


PAL = {
    "Human": [ramp(hexc("#252D35"), 0.85, 1.7), ramp(hexc("#3B4D60")), ramp(hexc("#83909B"), 0.6, 1.1),
              ramp(hexc("#D8DCD9"), 0.62, 1.0), ramp(hexc("#58C8F0"), 0.5, 1.1),
              ramp((150, 124, 70), 0.55, 1.05), ramp((38, 40, 44), 0.7, 1.4), ramp((112, 114, 112), 0.6, 1.1)],
    "Ascendancy": [ramp(hexc("#24212A"), 1.0, 2.1), ramp(hexc("#51465E"), 0.75, 1.3), ramp(hexc("#967854"), 0.55, 1.1),
                   ramp(hexc("#D6CBB4"), 0.6, 1.0), ramp(hexc("#A963E9"), 0.45, 0.9),
                   ramp((62, 58, 66), 0.9, 1.6), ramp((104, 84, 58), 0.55, 1.0), ramp((92, 90, 94), 0.6, 1.1)],
}
G, N, ST, CE, CY, GO, RB, CO = range(8)  # human column names
OB, VG, BR, IV, VI, DS, AB, AS = range(8)  # ascendancy column names


def make_palette(faction):
    W = H = 128
    px = [0.0] * (W * H * 4)
    for y in range(H):
        t = y / (H - 1)
        for x in range(W):
            d, l = PAL[faction][min(7, x // 16)]
            i = (y * W + x) * 4
            for k in range(3):
                px[i + k] = (d[k] + (l[k] - d[k]) * t) / 255.0
            px[i + 3] = 1.0
    img = bpy.data.images.new(f"GF_{faction}Kit_Palette", W, H, alpha=False)
    img.pixels = px
    img.pack()
    return img


def make_material(faction, img):
    m = bpy.data.materials.new(f"GF_Kit_{faction}")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    bsdf.inputs["Roughness"].default_value = 0.9
    bsdf.inputs["Metallic"].default_value = 0.0
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return m


class K:
    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")

    def _quad(self, vs, col):
        try:
            f = self.bm.faces.new(vs)
        except ValueError:
            return
        f.material_index = col
        f.smooth = False

    def box(self, c, size, col, rot=(0, 0, 0)):
        R = Euler(rot, "XYZ").to_matrix()
        c = Vector(c)
        hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
        vs = []
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    vs.append(self.bm.verts.new(c + R @ Vector((sx * hx, sy * hy, sz * hz))))
        # index = (sx,sy,sz) -> 4*i_sx + 2*i_sy + i_sz
        v = lambda a, b, d: vs[4 * a + 2 * b + d]
        for q in ([v(0, 0, 0), v(0, 1, 0), v(1, 1, 0), v(1, 0, 0)], [v(0, 0, 1), v(1, 0, 1), v(1, 1, 1), v(0, 1, 1)],
                  [v(0, 0, 0), v(1, 0, 0), v(1, 0, 1), v(0, 0, 1)], [v(0, 1, 0), v(0, 1, 1), v(1, 1, 1), v(1, 1, 0)],
                  [v(0, 0, 0), v(0, 0, 1), v(0, 1, 1), v(0, 1, 0)], [v(1, 0, 0), v(1, 1, 0), v(1, 1, 1), v(1, 0, 1)]):
            self._quad(q, col)

    def wedge(self, c, sx, sy, zb, ztf, ztb, col, rotz=0.0):
        """Box with sloped top: front (-y) top height ztf, back (+y) top height ztb, bottom zb. c = (x,y)."""
        R = Euler((0, 0, rotz), "XYZ").to_matrix()
        c = Vector((c[0], c[1], 0))
        P = lambda x, y, z: self.bm.verts.new(c + R @ Vector((x, y, z)))
        hx, hy = sx / 2, sy / 2
        b = [P(-hx, -hy, zb), P(hx, -hy, zb), P(hx, hy, zb), P(-hx, hy, zb)]
        t = [P(-hx, -hy, ztf), P(hx, -hy, ztf), P(hx, hy, ztb), P(-hx, hy, ztb)]
        self._quad([b[0], b[3], b[2], b[1]], col)
        self._quad([t[0], t[1], t[2], t[3]], col)
        for i in range(4):
            j = (i + 1) % 4
            self._quad([b[i], b[j], t[j], t[i]], col)

    def loft(self, p0, p1, r0, r1, sides, col, rot0=0.0, cap=True):
        p0, p1 = Vector(p0), Vector(p1)
        d = (p1 - p0).normalized()
        ref = Vector((1, 0, 0)) if abs(d.x) < 0.9 else Vector((0, 1, 0))
        a = d.cross(ref).normalized()
        b = d.cross(a).normalized()
        rings = []
        for p, r in ((p0, r0), (p1, r1)):
            ring = []
            for s in range(sides):
                ang = rot0 + 2 * math.pi * s / sides
                ring.append(self.bm.verts.new(p + (a * math.cos(ang) + b * math.sin(ang)) * r))
            rings.append(ring)
        for s in range(sides):
            s2 = (s + 1) % sides
            self._quad([rings[0][s], rings[0][s2], rings[1][s2], rings[1][s]], col)
        if cap:
            self._quad(list(reversed(rings[0])), col)
            self._quad(rings[1], col)

    def cyl(self, cx, cy, z0, r, h, sides, col, r2=None):
        self.loft((cx, cy, z0), (cx, cy, z0 + h), r, r if r2 is None else r2, sides, col)

    def beam(self, p0, p1, tx, col, ty=None):
        """Square-section beam between two points (tx x ty cross-section)."""
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        L = d.length
        z = d.normalized()
        ref = Vector((0, 0, 1)) if abs(z.z) < 0.95 else Vector((1, 0, 0))
        x = ref.cross(z).normalized()
        y = z.cross(x).normalized()
        R = Matrix((x, y, z)).transposed()
        e = R.to_euler("XYZ")
        self.box((p0 + p1) / 2, (tx, ty or tx, L), col, (e.x, e.y, e.z))

    def prism(self, prof, x0, x1, col):
        """Extrude (y,z) profile along x from x0 to x1."""
        A = [self.bm.verts.new((x0, y, z)) for (y, z) in prof]
        B = [self.bm.verts.new((x1, y, z)) for (y, z) in prof]
        self._quad(list(reversed(A)), col)
        self._quad(B, col)
        n = len(prof)
        for i in range(n):
            j = (i + 1) % n
            self._quad([A[i], A[j], B[j], B[i]], col)

    def finish(self, name, material):
        bm = self.bm
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        zmin = min(v.co.z for v in bm.verts)
        xs = [v.co.x for v in bm.verts]
        ys = [v.co.y for v in bm.verts]
        cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
        for v in bm.verts:
            v.co = Vector(((v.co.x - cx) * S, (v.co.y - cy) * S, (v.co.z - zmin) * S))
        zmax = max(v.co.z for v in bm.verts)
        for f in bm.faces:
            col = f.material_index
            for l in f.loops:
                t = max(0.0, min(1.0, l.vert.co.z / max(zmax, 1e-5)))
                l[self.uv].uv = ((col + 0.5) / 8.0, 0.04 + 0.92 * t)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(material)
        for p in me.polygons:
            p.material_index = 0
            p.use_smooth = False
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


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
def a_monolith(k):
    for i, (w, d, z) in enumerate(((5.0, 2.4, 0.5), (4.0, 1.9, 0.5), (3.2, 1.5, 0.5))):
        k.box((0, 0, 0.25 + 0.5 * i), (w, d, z), DS)
    k.box((0, 0, 7.6), (2.5, 1.0, 12.0), OB)
    k.wedge((0, 0), 2.5, 1.0, 13.6, 13.75, 14.4, OB)
    k.box((0, 0.53, 7.4), (0.14, 0.05, 8.6), BR)                    # bronze inlay (both faces)
    k.box((0, -0.53, 7.4), (0.14, 0.05, 8.6), BR)
    for z in (3.8, 11.0):
        k.box((0, 0.53, z), (2.2, 0.05, 0.12), BR)
        k.box((0, -0.53, z), (2.2, 0.05, 0.12), BR)
    k.box((0, 0.52, 8.8), (0.07, 0.04, 2.4), VI)                    # restrained violet slit
    k.box((0, -0.52, 8.8), (0.07, 0.04, 2.4), VI)
    for sx in (-1, 1):
        k.box((sx * 1.3, 0, 6.2), (0.22, 1.2, 9.0), VG)             # side buttress fins
    for z in (2.2, 5.6, 9.4):
        k.box((0, 0, z), (2.62, 1.12, 0.3), VG)                     # masonry course bands
    k.box((0, 0, 13.35), (2.7, 1.2, 0.2), IV)


def a_gate(k):
    for sx in (-1, 1):
        k.box((sx * 5.4, 0, 0.45), (3.4, 3.4, 0.9), DS)
        k.box((sx * 5.4, 0, 6.6), (2.2, 2.2, 11.4), OB)
        k.box((sx * 5.4, 1.12, 6.0), (0.14, 0.05, 8.0), BR)
        k.box((sx * 5.4, -1.12, 6.0), (0.14, 0.05, 8.0), BR)
        k.box((sx * 5.4, 0, 12.5), (2.7, 2.7, 0.5), VG)
        for z in (2.6, 5.4, 8.2, 10.6):
            k.box((sx * 5.4, 0, z), (2.36, 2.36, 0.26), VG)
    k.box((0, 0, 11.7), (13.2, 2.6, 1.9), OB)                       # lintel
    k.box((0, 0, 12.8), (14.0, 2.9, 0.35), VG)
    k.box((0, 1.32, 11.7), (12.0, 0.06, 0.16), BR)
    k.box((0, -1.32, 11.7), (12.0, 0.06, 0.16), BR)
    k.box((0, -1.35, 11.7), (0.9, 0.07, 1.1), IV)                    # keystone plaque
    k.box((0, 0, 0.1), (8.2, 3.0, 0.2), AS)                          # threshold slab


def a_bulwark(k):
    k.box((0, 0, 0.3), (8.4, 1.8, 0.6), DS)
    for i, x in enumerate((-2.9, 0.0, 2.9)):
        tilt = math.radians(7 if i % 2 == 0 else -7)
        k.box((x, 0, 2.9), (2.6, 0.95, 4.6), OB, (tilt, 0, 0))
        k.box((x, 0, 5.3), (2.8, 1.1, 0.18), BR, (tilt, 0, 0))
        k.box((x, 0, 3.0), (2.7, 1.04, 0.22), VG, (tilt, 0, 0))
    k.box((0, 0, 0.7), (8.0, 1.5, 0.2), AB)


def a_spire(k):
    for i, r in enumerate((3.4, 2.8, 2.3)):
        k.loft((0, 0, i * 0.55), (0, 0, (i + 1) * 0.55), r, r * 0.95, 4, DS if i < 2 else VG, rot0=math.pi / 4)
    k.loft((0, 0, 1.65), (0, 0, 8.0), 1.7, 1.12, 4, OB, rot0=math.pi / 4)
    k.loft((0, 0, 8.0), (0, 0, 15.0), 1.12, 0.55, 4, VG, rot0=math.pi / 4)
    for z, r in ((5.0, 1.45), (9.0, 1.12), (12.5, 0.8)):
        k.loft((0, 0, z), (0, 0, z + 0.22), r * 1.08, r * 1.08, 4, BR, rot0=math.pi / 4)
    k.loft((0, 0, 15.0), (0, 0, 16.4), 0.55, 0.12, 4, VG, rot0=math.pi / 4)
    k.box((0.0, -0.62, 7.0), (0.08, 0.05, 3.0), VI)


def a_rubble_block(k):
    k.wedge((-1.2, 0), 2.6, 2.0, 0.0, 1.9, 2.5, OB, 0.2)
    k.wedge((1.6, 0.6), 2.0, 1.6, 0.0, 1.2, 1.6, VG, -0.35)
    k.wedge((0.1, 1.9), 1.8, 1.4, 0.0, 0.8, 1.0, OB, 0.6)
    k.box((-1.2, -1.05, 1.9), (2.0, 0.06, 0.1), BR, (0, 0, 0.2))


KITS = {
    "Human": [("Wall", h_wall), ("Pillar", h_pillar), ("Bunker", h_bunker), ("Watchtower", h_tower),
              ("Barrier", h_barrier), ("Hedgehog", h_hedgehog), ("Crate", h_crate), ("Crates", h_crates),
              ("FuelTank", h_tank), ("Generator", h_generator), ("CommMast", h_mast)],
    "Ascendancy": [("Monolith", a_monolith), ("Gate", a_gate), ("Bulwark", a_bulwark), ("Spire", a_spire),
                   ("Rubble", a_rubble_block)],
}


def clear_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)


def export_one(ob, path):
    for o in bpy.data.objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True, export_texcoords=True,
                              export_normals=True, export_materials="EXPORT", export_cameras=False,
                              export_lights=False)


def tri_count(ob):
    me = ob.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


def render_sheet(faction, row, width):
    import numpy as np
    sc = bpy.context.scene
    cam = bpy.data.cameras.new("cam")
    cam.lens = 45
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    sc.camera = co
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.render.resolution_x = 520
    sc.render.resolution_y = 520
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.display.shading.show_shadows = True
    sc.display.shading.show_cavity = True
    sc.world = bpy.data.worlds.new("w")
    sc.world.color = (0.55, 0.62, 0.70)
    for o in row:
        o.hide_render = True
    tiles = []
    for idx, o in enumerate(row):
        o.hide_render = False
        d = o.dimensions
        dist = max(d.x, d.y, d.z) * 1.9 + 4
        tgt = Vector((o.location.x, 0, d.z * 0.45))
        co.location = tgt + Vector((dist * 0.62, -dist * 0.78, dist * 0.22))
        co.rotation_euler = (tgt - co.location).to_track_quat("-Z", "Y").to_euler()
        p = os.path.join(OUT, f"_tile_{idx}.png")
        sc.render.filepath = p
        bpy.ops.render.render(write_still=True)
        o.hide_render = True
        img = bpy.data.images.load(p)
        a = np.array(img.pixels[:]).reshape(520, 520, 4)
        tiles.append(a)
        bpy.data.images.remove(img)
        os.remove(p)
    cols = 4
    rows = (len(tiles) + cols - 1) // cols
    sheet = np.ones((rows * 520, cols * 520, 4), dtype=np.float32)
    for i, t in enumerate(tiles):
        r, c = divmod(i, cols)
        sheet[(rows - 1 - r) * 520:(rows - r) * 520, c * 520:(c + 1) * 520] = t
    out = bpy.data.images.new("sheet", cols * 520, rows * 520, alpha=False)
    out.pixels = sheet.flatten().tolist()
    out.filepath_raw = os.path.join(OUT, f"sheet_{faction}.png")
    out.file_format = "PNG"
    out.save()
    bpy.data.objects.remove(co, do_unlink=True)


def main():
    report = []
    for faction, pieces in KITS.items():
        if ONLY and faction not in ONLY:
            continue
        mat = make_material(faction, make_palette(faction))
        row = []
        for pid, fn in pieces:
            k = K()
            fn(k)
            name = f"Kit_{faction}_{pid}"
            ob = k.finish(name, mat)
            path = os.path.join(OUT, name + ".glb")
            export_one(ob, path)
            d = ob.dimensions
            report.append((name, tri_count(ob), round(d.x, 1), round(d.y, 1), round(d.z, 1), os.path.getsize(path)))
            row.append(ob)
        x = 0.0
        for ob in row:
            ob.location = Vector((x + ob.dimensions.x * 0.5, 0, 0))
            x += ob.dimensions.x + 6
        if os.environ.get("GF_PREVIEW"):
            render_sheet(faction, row, x)
        for ob in row:
            bpy.data.objects.remove(ob, do_unlink=True)
    print("KIT_REPORT")
    for r in report:
        print("  %-28s tris=%5d dims(studs)=%.1f x %.1f x %.1f glb=%d B" % r)


clear_scene()
main()
