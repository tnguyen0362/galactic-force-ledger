"""
GALACTIC FORCE Phase 15 - procedural vegetation + rock generator (Blender, headless).

Usage:
  blender -b --factory-startup --python gen_veg.py -- <out_dir> [Biome ...]

Per species: one mesh, one material, one embedded 128x128 palette texture per biome
(8 gradient columns; UV u = material column, UV v = normalised height so every species gets a
dark-base -> light-tip tone gradient without needing baked AO). Output: GLB, +Z up in Blender
(exporter converts to Y-up), origin at ground contact, 1 Blender unit = 1 m.
Species ids follow ServerStorage.GF.Art convention: Veg_<Biome>_<Role>_<Letter>.
Deterministic: seeds derive from the species id only.
"""
import bpy, bmesh, math, random, sys, os, zlib
from mathutils import Vector, Matrix, noise

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else os.path.join(os.path.dirname(__file__), "out")
ONLY = set(argv[1:])
os.makedirs(OUT, exist_ok=True)

# ---------------------------------------------------------------- palettes
# columns: 0 bark, 1 leafA, 2 leafB, 3 leafC(accent), 4 rock, 5 rockStrata, 6 groundcover, 7 deadwood
# each entry (dark_rgb, light_rgb) 0-255 sRGB
def P(*pairs):
    return list(pairs)

PALETTES = {
    "Forest": P(((46, 36, 28), (96, 78, 60)),       # bark
                ((24, 52, 34), (70, 118, 62)),       # conifer / leaf A (deep green)
                ((40, 72, 40), (106, 146, 70)),      # leaf B (fresh green)
                ((70, 96, 44), (150, 164, 78)),      # leaf C (olive / sunlit)
                ((70, 70, 66), (128, 124, 114)),     # rock
                ((54, 66, 48), (110, 126, 92)),      # moss strata
                ((52, 80, 40), (120, 150, 70)),      # ground cover
                ((70, 62, 52), (126, 112, 94))),     # deadwood
    "Tundra": P(((48, 42, 40), (98, 88, 82)),
                ((28, 50, 48), (84, 116, 108)),      # frost spruce
                ((36, 60, 62), (108, 140, 138)),
                ((150, 164, 176), (238, 244, 250)),  # snow dusting
                ((82, 88, 98), (150, 158, 170)),
                ((64, 72, 84), (128, 140, 156)),
                ((92, 104, 90), (160, 170, 150)),
                ((78, 72, 68), (136, 126, 118))),
    "Arid": P(((70, 52, 38), (140, 106, 76)),
              ((86, 92, 46), (170, 168, 88)),        # dry olive
              ((100, 90, 48), (192, 168, 92)),
              ((124, 92, 56), (206, 150, 84)),
              ((126, 92, 66), (200, 154, 110)),
              ((112, 70, 52), (190, 124, 88)),       # red strata
              ((130, 112, 62), (206, 184, 106)),
              ((96, 76, 58), (168, 140, 110))),
    "Industrial": P(((40, 38, 36), (86, 80, 74)),
                    ((50, 52, 40), (96, 96, 70)),     # scorched scrub
                    ((60, 58, 44), (112, 106, 78)),
                    ((92, 70, 46), (158, 112, 66)),   # rust accent
                    ((58, 58, 60), (112, 110, 108)),
                    ((88, 62, 48), (150, 100, 70)),   # rusted strata
                    ((70, 70, 56), (120, 116, 88)),
                    ((46, 42, 38), (94, 86, 76))),
}
BARK, LEAF_A, LEAF_B, LEAF_C, ROCK, STRATA, GROUND, DEAD = range(8)


def srgb_to_lin(c):
    c /= 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def make_palette_image(biome):
    W = H = 128
    cols = PALETTES[biome]
    rng = random.Random(zlib.crc32(biome.encode()))
    px = [0.0] * (W * H * 4)
    for y in range(H):
        t = y / (H - 1)
        for x in range(W):
            col = min(7, x // 16)
            d, l = cols[col]
            # detail noise so the map is not a flat gradient (also helps moderation)
            n = (noise.noise(Vector((x * 0.21, y * 0.21, col * 3.7))) * 0.5 + 0.5) * 0.12 - 0.06
            tt = max(0.0, min(1.0, t + n))
            r = d[0] + (l[0] - d[0]) * tt
            g = d[1] + (l[1] - d[1]) * tt
            b = d[2] + (l[2] - d[2]) * tt
            i = (y * W + x) * 4
            px[i] = r / 255.0; px[i + 1] = g / 255.0; px[i + 2] = b / 255.0; px[i + 3] = 1.0
    img = bpy.data.images.new(f"GF_{biome}_Palette", W, H, alpha=False)
    img.pixels = px
    img.pack()
    return img


def make_material(biome, img):
    m = bpy.data.materials.new(f"GF_Veg_{biome}")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Linear"
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Metallic"].default_value = 0.0
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return m


# ---------------------------------------------------------------- geometry builder
class B:
    def __init__(self, seed):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.rng = random.Random(seed)
        self.seed = seed % 997

    def nz(self, p, s=1.0):
        return noise.noise(Vector((p.x * s + self.seed, p.y * s + self.seed * 0.37, p.z * s)))

    def face(self, verts, mat, smooth=True):
        try:
            f = self.bm.faces.new(verts)
        except ValueError:
            return None
        f.material_index = mat
        f.smooth = smooth
        return f

    def tube(self, pts, radii, sides, mat, cap_top=True, smooth=True):
        """Skin around a polyline. pts list[Vector], radii list[float]."""
        rings = []
        dirs = []
        for i in range(len(pts)):
            d = (pts[i + 1] - pts[i]) if i < len(pts) - 1 else (pts[i] - pts[i - 1])
            dirs.append(d.normalized())
        ref = Vector((1, 0, 0)) if abs(dirs[0].x) < 0.9 else Vector((0, 1, 0))
        a = dirs[0].cross(ref).normalized()
        for i, p in enumerate(pts):
            d = dirs[i]
            a = (a - d * a.dot(d))
            if a.length < 1e-5:
                a = d.cross(Vector((1, 0, 0)))
            a.normalize()
            bb = d.cross(a).normalized()
            ring = []
            for s in range(sides):
                ang = 2 * math.pi * s / sides
                wob = 1.0 + 0.06 * self.nz(p * 2.0 + Vector((s * 0.9, 0, 0)), 1.0)
                ring.append(self.bm.verts.new(p + (a * math.cos(ang) + bb * math.sin(ang)) * radii[i] * wob))
            rings.append(ring)
        for i in range(len(rings) - 1):
            for s in range(sides):
                s2 = (s + 1) % sides
                self.face([rings[i][s], rings[i][s2], rings[i + 1][s2], rings[i + 1][s]], mat, smooth)
        if cap_top:
            tip = self.bm.verts.new(pts[-1] + (pts[-1] - pts[-2]).normalized() * radii[-1] * 0.8)
            for s in range(sides):
                self.face([rings[-1][s], rings[-1][(s + 1) % sides], tip], mat, smooth)
        # bottom cap
        c = self.bm.verts.new(pts[0] - Vector((0, 0, radii[0] * 0.3)))
        for s in range(sides):
            self.face([rings[0][(s + 1) % sides], rings[0][s], c], mat, smooth)

    def blob(self, c, rx, ry, rz, mat, sub=2, jag=0.22, smooth=True, droop=0.0, yaw=0.0, terrace=0):
        res = bmesh.ops.create_icosphere(self.bm, subdivisions=sub, radius=1.0)
        verts = res["verts"]
        cy, sy = math.cos(yaw), math.sin(yaw)
        for v in verts:
            u = v.co.copy()
            n = self.nz(u * 1.6 + c, 1.0) * jag + self.nz(u * 3.8 + c, 1.0) * jag * 0.45
            s = 1.0 + n
            uz = u.z
            if terrace:
                uz = uz * 0.45 + (round(uz * terrace) / terrace) * 0.55
                s *= 1.0 + 0.10 * math.cos(uz * terrace * math.pi)  # ledge undercuts
            x, y, z = u.x * rx * s, u.y * ry * s, uz * rz * s
            if droop and z < 0:
                z *= 1.0 + droop
            v.co = Vector((c.x + x * cy - y * sy, c.y + x * sy + y * cy, c.z + z))
        for v in verts:
            for f in v.link_faces:
                f.material_index = mat
                f.smooth = smooth

    def tier(self, z0, z1, r, sides, mat, droop=0.25):
        """Jagged skirt tier: wide drooping rim, narrow raised apex (conifer branch layer)."""
        rim = []
        for s in range(sides):
            ang = 2 * math.pi * s / sides + self.rng.uniform(-0.12, 0.12)
            rr = r * (1.0 + 0.22 * (1 if s % 2 else -1) * self.rng.uniform(0.5, 1.0) + self.rng.uniform(-0.08, 0.08))
            zz = z0 - droop * rr * (0.35 if s % 2 else 0.1)
            rim.append(self.bm.verts.new(Vector((math.cos(ang) * rr, math.sin(ang) * rr, zz))))
        inner = []
        for s in range(sides):
            ang = 2 * math.pi * (s + 0.5) / sides
            inner.append(self.bm.verts.new(Vector((math.cos(ang) * r * 0.16, math.sin(ang) * r * 0.16, z1))))
        apex = self.bm.verts.new(Vector((0, 0, z1 + (z1 - z0) * 0.25)))
        under = self.bm.verts.new(Vector((0, 0, z0 + (z1 - z0) * 0.15)))
        for s in range(sides):
            s2 = (s + 1) % sides
            self.face([rim[s], rim[s2], inner[s]], mat)
            self.face([inner[s], rim[s2], inner[s2]] if False else [rim[s2], inner[s2], inner[s]], mat)
            self.face([inner[s], inner[s2], apex], mat)
            self.face([rim[s2], rim[s], under], mat)

    def blade(self, base, height, width, lean_dir, bend, mat):
        """Tapered curved blade, 3 segments."""
        side = lean_dir.cross(Vector((0, 0, 1))).normalized() if lean_dir.length > 1e-5 else Vector((1, 0, 0))
        rows = []
        n = 3
        for i in range(n + 1):
            t = i / n
            p = base + Vector((0, 0, height * t)) + lean_dir * (bend * height * t * t)
            w = width * (1.0 - t * 0.92) * 0.5
            rows.append((self.bm.verts.new(p - side * w), self.bm.verts.new(p + side * w)))
        for i in range(n):
            self.face([rows[i][0], rows[i][1], rows[i + 1][1], rows[i + 1][0]], mat)
            self.face([rows[i][1], rows[i][0], rows[i + 1][0], rows[i + 1][1]], mat)  # double-sided

    def chunk(self, c, size, mat, tilt):
        """Faceted debris slab (industrial scrap/rubble)."""
        res = bmesh.ops.create_cube(self.bm, size=1.0)
        rot = Matrix.Rotation(tilt[0], 4, "X") @ Matrix.Rotation(tilt[1], 4, "Y") @ Matrix.Rotation(tilt[2], 4, "Z")
        for v in res["verts"]:
            u = v.co.copy()
            u = Vector((u.x * size.x, u.y * size.y, u.z * size.z))
            u += Vector((self.rng.uniform(-1, 1), self.rng.uniform(-1, 1), self.rng.uniform(-1, 1))) * 0.06 * size.length
            v.co = c + rot @ u
            for f in v.link_faces:
                f.material_index = mat
                f.smooth = False

    def finish(self, name, material):
        bm = self.bm
        bm.normal_update()
        # ground-plane the model: min z -> 0 (tip-cap/under vertices included)
        zmin = min(v.co.z for v in bm.verts)
        zmax = max(v.co.z for v in bm.verts)
        for v in bm.verts:
            v.co.z -= zmin
        zmax -= zmin
        # UVs: u = material column centre, v = normalised height gradient
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
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


# ---------------------------------------------------------------- species recipes
def conifer(b, H, leaf, leaf2, spread=1.0, tiers=9, dead_snow=None):
    R = H * 0.20 * spread
    trunk_r = H * 0.028
    pts = [Vector((b.nz(Vector((0, 0, z)), 0.6) * H * 0.012, b.nz(Vector((5, 0, z)), 0.6) * H * 0.012, z))
           for z in [0, H * 0.25, H * 0.5, H * 0.75, H * 0.97]]
    b.tube(pts, [trunk_r, trunk_r * 0.8, trunk_r * 0.55, trunk_r * 0.32, trunk_r * 0.12], 7, BARK)
    z0 = H * 0.16
    for i in range(tiers):
        t = i / max(1, tiers - 1)
        r = R * (1.0 - t) ** 0.85 + R * 0.10
        zb = z0 + (H - z0 - H * 0.12) * t ** 0.95
        hh = H * 0.15 * (1.0 - 0.45 * t)
        m = leaf if i % 2 == 0 else leaf2
        if dead_snow and t > 0.35 and i % 2 == 1:
            m = dead_snow
        b.tier(zb, zb + hh, r, 11 if i < tiers - 3 else 8, m, droop=0.55)


def broadleaf(b, H, leaf, leaf2, leaf3, crown=1.0, forks=4):
    trunk_r = H * 0.05
    tz = H * 0.40
    pts = [Vector((b.nz(Vector((1, 0, z)), 0.5) * H * 0.015, b.nz(Vector((2, 0, z)), 0.5) * H * 0.015, z))
           for z in [0, tz * 0.12, tz * 0.4, tz * 0.75, tz]]
    b.tube(pts, [trunk_r * 1.9, trunk_r * 1.35, trunk_r * 1.1, trunk_r * 0.9, trunk_r * 0.75], 9, BARK)
    top = pts[-1]
    cr = H * 0.30 * crown
    mats = (leaf, leaf2, leaf3, leaf2, leaf)
    for i in range(forks):
        ang = 2 * math.pi * i / forks + b.rng.uniform(-0.3, 0.3)
        d = Vector((math.cos(ang), math.sin(ang), 0))
        rise = H * (0.20 + 0.06 * b.rng.random())
        tip = top + d * cr * 0.75 + Vector((0, 0, rise))
        mid = top + d * cr * 0.32 + Vector((0, 0, rise * 0.45))
        b.tube([top, mid, tip], [trunk_r * 0.65, trunk_r * 0.5, trunk_r * 0.28], 6, BARK, cap_top=False)
        b.blob(tip + Vector((0, 0, cr * 0.10)), cr * 0.66, cr * 0.66, cr * 0.50, mats[i % 5], sub=2, jag=0.24, droop=0.35, yaw=ang)
        # lower skirt lobe tucks the canopy toward the trunk (no lollipop gap)
        b.blob(top + d * cr * 0.45 + Vector((0, 0, rise * 0.55)), cr * 0.5, cr * 0.5, cr * 0.38, mats[(i + 2) % 5], sub=2, jag=0.26, droop=0.3)
    b.blob(top + Vector((0, 0, H * 0.26)), cr * 0.72, cr * 0.72, cr * 0.56, leaf3, sub=2, jag=0.22)


def umbrella(b, H, leaf, leaf2, flat=0.28):
    trunk_r = H * 0.04
    pts = [Vector((b.nz(Vector((3, 0, z)), 0.9) * H * 0.06, b.nz(Vector((4, 0, z)), 0.9) * H * 0.06, z))
           for z in [0, H * 0.3, H * 0.55, H * 0.78]]
    b.tube(pts, [trunk_r * 1.4, trunk_r, trunk_r * 0.7, trunk_r * 0.5], 7, BARK)
    top = pts[-1]
    for i, (ox, oy, k) in enumerate([(0, 0, 1.0), (0.42, 0.1, 0.62), (-0.34, 0.32, 0.58), (0.0, -0.42, 0.6), (-0.3, -0.25, 0.5)]):
        c = top + Vector((ox * H * 0.45, oy * H * 0.45, H * 0.10 + (0.05 * H if i == 0 else 0)))
        b.blob(c, H * 0.38 * k, H * 0.36 * k, H * 0.38 * k * flat, leaf if i % 2 == 0 else leaf2, sub=2, jag=0.26)
        if i:
            b.tube([top, (top + c) * 0.5 + Vector((0, 0, H * 0.04)), c - Vector((0, 0, H * 0.02))],
                   [trunk_r * 0.5, trunk_r * 0.4, trunk_r * 0.25], 5, BARK, cap_top=False)


def snag(b, H, mat, mat2, branches=5):
    trunk_r = H * 0.032
    pts = [Vector((b.nz(Vector((7, 0, z)), 0.8) * H * 0.05, b.nz(Vector((8, 0, z)), 0.8) * H * 0.05, z))
           for z in [0, H * 0.3, H * 0.6, H * 0.85, H]]
    b.tube(pts, [trunk_r * 1.3, trunk_r * 0.95, trunk_r * 0.7, trunk_r * 0.4, trunk_r * 0.12], 6, mat)
    for i in range(branches):
        t = 0.38 + 0.5 * i / max(1, branches - 1)
        base = pts[min(4, int(t * 4))] if False else Vector((0, 0, H * t)) + Vector((b.nz(Vector((7, 0, H * t)), 0.8) * H * 0.05, b.nz(Vector((8, 0, H * t)), 0.8) * H * 0.05, 0))
        ang = b.rng.uniform(0, 2 * math.pi) + i * 2.4
        d = Vector((math.cos(ang), math.sin(ang), 0))
        L = H * (0.28 - 0.16 * (t - 0.38))
        tip = base + d * L + Vector((0, 0, L * 0.45))
        mid = base + d * L * 0.5 + Vector((0, 0, L * 0.12))
        b.tube([base, mid, tip], [trunk_r * 0.45, trunk_r * 0.3, trunk_r * 0.1], 5, mat2)
        tw = tip + d.cross(Vector((0, 0, 1))) * L * 0.3 + Vector((0, 0, L * 0.3))
        b.tube([tip, (tip + tw) * 0.5, tw], [trunk_r * 0.12, trunk_r * 0.09, trunk_r * 0.04], 4, mat2)


def shrub(b, H, mats, n=6, spread=1.0):
    for i in range(n):
        ang = 2 * math.pi * i / n + b.rng.uniform(-0.4, 0.4)
        r = H * 0.28 * spread * (0.4 if i == 0 else 1.0)
        c = Vector((math.cos(ang) * r * (0 if i == 0 else 1), math.sin(ang) * r * (0 if i == 0 else 1), H * (0.34 if i == 0 else 0.26)))
        rad = H * (0.42 if i == 0 else 0.34)
        b.blob(c, rad, rad, rad * 0.78, mats[i % len(mats)], sub=2, jag=0.28)


def rosette(b, H, mats, blades=16):
    for i in range(blades):
        ang = 2 * math.pi * i / blades + b.rng.uniform(-0.15, 0.15)
        tilt = 0.25 + 0.85 * (i % 3) / 3.0
        d = Vector((math.cos(ang), math.sin(ang), 0))
        b.blade(Vector((0, 0, 0)) + d * H * 0.02, H * (0.85 + 0.3 * b.rng.random()), H * 0.16, d, tilt * 1.1, mats[i % len(mats)])


def tuft(b, H, mats, blades=22):
    for i in range(blades):
        ang = b.rng.uniform(0, 2 * math.pi)
        r = b.rng.uniform(0.0, H * 0.28)
        d = Vector((math.cos(ang), math.sin(ang), 0))
        b.blade(d * r, H * b.rng.uniform(0.55, 1.0), H * 0.1, d, b.rng.uniform(0.1, 0.5), mats[i % len(mats)])


def boulder(b, H, mat, mat2, lumps=3, flat=0.65, sub=2, jag=0.32, terrace=3):
    for i in range(lumps):
        ang = 2 * math.pi * i / lumps + b.rng.uniform(-0.5, 0.5)
        k = 1.0 if i == 0 else b.rng.uniform(0.45, 0.7)
        off = 0 if i == 0 else H * 0.5
        c = Vector((math.cos(ang) * off, math.sin(ang) * off, H * 0.2 * k))
        b.blob(c, H * 0.62 * k, H * 0.56 * k, H * 0.5 * k * flat * 1.05, mat if i % 2 == 0 else mat2, sub=sub, jag=jag, smooth=False,
               yaw=b.rng.uniform(0, 3), terrace=terrace)


def debris(b, H, mats):
    n = 6
    for i in range(n):
        ang = b.rng.uniform(0, 2 * math.pi)
        r = b.rng.uniform(0, H * 0.7)
        sz = Vector((H * b.rng.uniform(0.25, 0.65), H * b.rng.uniform(0.18, 0.5), H * b.rng.uniform(0.06, 0.3)))
        c = Vector((math.cos(ang) * r, math.sin(ang) * r, sz.z * 0.5 + H * 0.05 * (i % 3)))
        b.chunk(c, sz, mats[i % len(mats)], (b.rng.uniform(-0.35, 0.35), b.rng.uniform(-0.35, 0.35), b.rng.uniform(0, 3)))


def rubble(b, H, mats):
    boulder(b, H, mats[0], mats[1], lumps=2, flat=0.55, sub=1, jag=0.2)
    debris(b, H * 0.8, mats)


# (id, reference height in metres, builder)
SPECIES = {
    "Forest": [
        ("Canopy_A", 12.0, lambda b, H: conifer(b, H, LEAF_A, LEAF_B, tiers=10)),
        ("Canopy_B", 11.0, lambda b, H: broadleaf(b, H, LEAF_B, LEAF_A, LEAF_C, crown=1.0, forks=4)),
        ("Mid_A", 6.0, lambda b, H: broadleaf(b, H, LEAF_C, LEAF_B, LEAF_A, crown=0.9, forks=3)),
        ("Mid_B", 6.5, lambda b, H: conifer(b, H, LEAF_B, LEAF_A, spread=1.05, tiers=8)),
        ("Scrub_A", 1.5, lambda b, H: shrub(b, H, [LEAF_A, LEAF_B, LEAF_C], n=6)),
        ("Scrub_B", 1.3, lambda b, H: rosette(b, H, [LEAF_B, LEAF_C, LEAF_A], blades=18)),
        ("Ground_A", 0.8, lambda b, H: tuft(b, H, [GROUND, LEAF_C, LEAF_B])),
        ("Rock_A", 2.4, lambda b, H: boulder(b, H, ROCK, STRATA, lumps=3)),
        ("Rock_B", 1.8, lambda b, H: boulder(b, H, STRATA, ROCK, lumps=2, flat=0.55)),
    ],
    "Tundra": [
        ("Canopy_A", 10.5, lambda b, H: conifer(b, H, LEAF_A, LEAF_C, spread=0.8, tiers=11, dead_snow=LEAF_C)),
        ("Canopy_B", 9.0, lambda b, H: snag(b, H, DEAD, DEAD, branches=4)),
        ("Mid_A", 5.0, lambda b, H: conifer(b, H, LEAF_B, LEAF_C, spread=0.75, tiers=8, dead_snow=LEAF_C)),
        ("Scrub_A", 1.0, lambda b, H: shrub(b, H, [GROUND, LEAF_C, LEAF_B], n=5, spread=1.1)),
        ("Ground_A", 0.7, lambda b, H: tuft(b, H, [GROUND, LEAF_C])),
        ("Rock_A", 3.4, lambda b, H: boulder(b, H, ROCK, STRATA, lumps=3, flat=0.8)),
        ("Rock_B", 2.4, lambda b, H: boulder(b, H, STRATA, ROCK, lumps=2, flat=0.7)),
        ("Rock_C", 5.0, lambda b, H: boulder(b, H, ROCK, LEAF_C, lumps=4, flat=1.0, jag=0.26, terrace=5)),
    ],
    "Arid": [
        ("Canopy_A", 7.5, lambda b, H: umbrella(b, H, LEAF_A, LEAF_B)),
        ("Mid_A", 4.0, lambda b, H: umbrella(b, H, LEAF_B, LEAF_C, flat=0.35)),
        ("Scrub_A", 1.2, lambda b, H: shrub(b, H, [LEAF_A, LEAF_B, GROUND], n=5, spread=1.2)),
        ("Scrub_B", 1.4, lambda b, H: rosette(b, H, [LEAF_A, LEAF_C], blades=14)),
        ("Ground_A", 0.7, lambda b, H: tuft(b, H, [GROUND, LEAF_B])),
        ("Rock_A", 3.0, lambda b, H: boulder(b, H, ROCK, STRATA, lumps=3, flat=0.7)),
        ("Rock_B", 2.2, lambda b, H: boulder(b, H, STRATA, ROCK, lumps=2, flat=0.55)),
        ("Rock_C", 4.6, lambda b, H: boulder(b, H, STRATA, ROCK, lumps=4, flat=1.1, jag=0.22, terrace=6)),
    ],
    "Industrial": [
        ("Canopy_A", 8.5, lambda b, H: snag(b, H, DEAD, BARK, branches=4)),
        ("Mid_A", 4.5, lambda b, H: snag(b, H, DEAD, DEAD, branches=3)),
        ("Scrub_A", 1.1, lambda b, H: shrub(b, H, [LEAF_A, LEAF_B, GROUND], n=4)),
        ("Ground_A", 0.9, lambda b, H: debris(b, H, [ROCK, LEAF_C, STRATA])),
        ("Rock_A", 2.6, lambda b, H: rubble(b, H, [ROCK, STRATA, LEAF_C])),
        ("Rock_B", 1.8, lambda b, H: rubble(b, H, [STRATA, ROCK, DEAD])),
    ],
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


def main():
    report = []
    for biome, specs in SPECIES.items():
        if ONLY and biome not in ONLY:
            continue
        img = make_palette_image(biome)
        mat = make_material(biome, img)
        row = []
        for sid, H, fn in specs:
            name = f"Veg_{biome}_{sid}"
            b = B(zlib.crc32(name.encode()))
            fn(b, H)
            ob = b.finish(name, mat)
            tris = tri_count(ob)
            dims = ob.dimensions
            row.append(ob)
            path = os.path.join(OUT, name + ".glb")
            export_one(ob, path)
            report.append((name, tris, round(dims.x, 2), round(dims.y, 2), round(dims.z, 2), os.path.getsize(path)))
        # contact-sheet layout (objects stay for preview render)
        x = 0.0
        for ob in row:
            ob.location = Vector((x + ob.dimensions.x * 0.5, 0, 0))
            x += ob.dimensions.x + 1.2
        if os.environ.get("GF_PREVIEW"):
            render_sheet(biome, row, x)
        for ob in row:
            bpy.data.objects.remove(ob, do_unlink=True)
    print("SPECIES_REPORT")
    for r in report:
        print("  %-26s tris=%5d  dims(m)=%.2f x %.2f x %.2f  glb=%d B" % r)


def render_sheet(biome, row, width):
    sc = bpy.context.scene
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.ortho_scale = max(width * 1.05, 14, max(o.dimensions.z for o in row) * 3.4)
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    co.location = Vector((width / 2, -40, max(o.dimensions.z for o in row) * 0.5))
    co.rotation_euler = (math.radians(90), 0, 0)
    sc.camera = co
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.render.resolution_x = 2000
    sc.render.resolution_y = 700
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.display.shading.show_shadows = True
    sc.display.shading.show_cavity = False
    sc.world = bpy.data.worlds.new("w")
    sc.world.color = (0.55, 0.62, 0.70)
    sc.render.film_transparent = False
    sc.render.filepath = os.path.join(OUT, f"sheet_{biome}.png")
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(co, do_unlink=True)


clear_scene()
main()
