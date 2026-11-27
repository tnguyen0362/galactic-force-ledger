"""Shared Blender helpers for the GF kit generators (palette, K builder, export, previews)."""
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

    def finish(self, name, material, origin="bbox"):
        """origin: "bbox" = bottom centre of the bounding box (default); "keep" = authored (0,0,0) is the pivot
        (hinges/axes: author the part with its pivot at 0,0,0); "center" = full bbox centre."""
        bm = self.bm
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        xs = [v.co.x for v in bm.verts]
        ys = [v.co.y for v in bm.verts]
        zs = [v.co.z for v in bm.verts]
        if origin == "keep":
            cx = cy = zmin = 0.0
        elif origin == "center":
            cx, cy, zmin = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2, (max(zs) + min(zs)) / 2
        else:
            cx, cy, zmin = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2, min(zs)
        for v in bm.verts:
            v.co = Vector(((v.co.x - cx) * S, (v.co.y - cy) * S, (v.co.z - zmin) * S))
        zmax = max(v.co.z for v in bm.verts)
        zlo = min(v.co.z for v in bm.verts)
        for f in bm.faces:
            col = f.material_index
            for l in f.loops:
                t = max(0.0, min(1.0, (l.vert.co.z - zlo) / max(zmax - zlo, 1e-5)))
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
        mq = bpy.data.objects.new("mannequin", bpy.data.meshes.new("mq"))
        bmq = bmesh.new()
        bmesh.ops.create_cube(bmq, size=1.0)
        bmq.to_mesh(mq.data)
        bmq.free()
        sc.collection.objects.link(mq)
        mq.scale = (1.9, 1.0, 5.7)  # ~1.6 m character in studs (width, depth, height)
        mq.location = (o.location.x - o.dimensions.x * 0.5 - 2.4, -o.dimensions.y * 0.5 - 1.2, 2.85)
        mm = bpy.data.materials.get("mq_mat") or bpy.data.materials.new("mq_mat")
        mm.diffuse_color = (1.0, 0.45, 0.1, 1.0)
        mq.data.materials.append(mm)
        d = o.dimensions
        dist = max(d.x, d.y, d.z) * 1.9 + 8
        tgt = Vector((o.location.x - 1.0, 0, d.z * 0.45))
        co.location = tgt + Matrix.Rotation(math.radians(float(os.environ.get('GF_AZ', '0'))), 3, 'Z') @ Vector((dist * 0.62, -dist * 0.78, dist * 0.22))
        co.rotation_euler = (tgt - co.location).to_track_quat("-Z", "Y").to_euler()
        p = os.path.join(OUT, f"_tile_{idx}.png")
        sc.render.filepath = p
        bpy.ops.render.render(write_still=True)
        o.hide_render = True
        bpy.data.objects.remove(mq, do_unlink=True)
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



def run_kits(kits):
    """kits = {faction: [(piece_id, fn) | (piece_id, fn, {"origin": "keep"})]}. Exports GLBs into OUT (+ sheets if GF_PREVIEW)."""
    report = []
    for faction, pieces in kits.items():
        if ONLY and faction not in ONLY:
            continue
        mat = make_material(faction, make_palette(faction))
        row = []
        for spec in pieces:
            pid, fn = spec[0], spec[1]
            opts = spec[2] if len(spec) > 2 else {}
            k = K()
            fn(k)
            name = f"Kit_{faction}_{pid}"
            ob = k.finish(name, mat, opts.get("origin", "bbox"))
            path = os.path.join(OUT, name + ".glb")
            export_one(ob, path)
            d = ob.dimensions
            report.append((name, tri_count(ob), round(d.x, 1), round(d.y, 1), round(d.z, 1), os.path.getsize(path)))
            row.append(ob)
        x = 0.0
        for ob in row:
            ob.location = Vector((x + ob.dimensions.x * 0.5, 0, 0))
            x += ob.dimensions.x + 10
        if os.environ.get("GF_PREVIEW"):
            render_sheet(faction, row, x)
        for ob in row:
            bpy.data.objects.remove(ob, do_unlink=True)
    print("KIT_REPORT")
    for r in report:
        print("  %-28s tris=%5d dims(studs)=%.1f x %.1f x %.1f glb=%d B" % r)
