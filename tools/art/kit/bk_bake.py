"""BASEKIT -> trim-atlas piece builder (runs INSIDE Blender via exec; paths below are this machine's).

exec(open(r"C:\\Users\\tnguy\\galactic-force\\tools\\art\\kit\\bk_bake.py").read())
build_piece("Wall_Solid")                # builds KITOUT collection objects  Kit_<piece> (+ Glow_<piece>)
export_piece("Wall_Solid")               # GLB -> out_kit/GF_BK_<piece>.glb

Rules (see trim_atlas.py for the strip layout, 64 px/stud):
- every non-glow child of the piece root is transformed into root space and JOINED into one mesh;
- hazard stripe cuboid piles are replaced by one flat box UV'd onto the HAZARD strip (texture draws the stripes);
- glow parts (BK_Glow / BK_Cyan) become a separate Glow_<piece> object (installer makes it Neon);
- per-face UV: dominant normal axis -> in-plane axes; the face's LONG axis becomes U (z-long faces: U = +z so
  grime pools at the bottom); V is centred inside the material's strip. Big BK_Panel faces fill a whole plate cell.
"""
import bpy, bmesh, os, math, hashlib
from mathutils import Vector

RES = 1024.0
PPS = 64.0
OUT = r"C:\Users\tnguy\gf-art-build\blender\out_kit"
TEX = os.path.join(OUT, "tex")
STRIPS = {"PLATE": (0, 256), "FRAME": (256, 384), "HAZARD": (384, 512), "VENT": (512, 640),
          "ROOF": (640, 768), "CONCRETE": (768, 896), "GLASS": (896, 1024)}
MAT_STRIP = {"BK_Panel": "PLATE", "BK_Frame": "FRAME", "BK_Hazard": "HAZARD", "BK_Navy": "ROOF",
             "BK_Glass": "GLASS", "BK_Soil": "CONCRETE"}
GLOW_MATS = ("BK_Glow", "BK_Cyan")
ACCENT = (1.0, 0.62, 0.12)        # amber; cyan = (0.2, 0.85, 1.0)  <- single-constant light colour swap


def _img(fn, srgb):
    p = os.path.join(TEX, fn)
    for im in list(bpy.data.images):
        if im.name == fn:
            bpy.data.images.remove(im)
    im = bpy.data.images.load(p, check_existing=False)
    im.name = fn
    im.colorspace_settings.name = "sRGB" if srgb else "Non-Color"
    return im


def pbr_materials():
    for nm in ("GF_Kit_PBR", "GF_Kit_Glow"):
        if nm in bpy.data.materials:
            bpy.data.materials.remove(bpy.data.materials[nm])
    m = bpy.data.materials.new("GF_Kit_PBR")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    N, L = nt.nodes, nt.links
    out = N.new("ShaderNodeOutputMaterial")
    bsdf = N.new("ShaderNodeBsdfPrincipled")
    L.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bc = N.new("ShaderNodeTexImage"); bc.image = _img("GF_Kit_BC.png", True)
    nm_ = N.new("ShaderNodeTexImage"); nm_.image = _img("GF_Kit_N.png", False)
    rm = N.new("ShaderNodeTexImage"); rm.image = _img("GF_Kit_RM.png", False)
    for t in (bc, nm_, rm):
        t.interpolation = "Linear"; t.extension = "REPEAT"
    nmap = N.new("ShaderNodeNormalMap")
    sep = N.new("ShaderNodeSeparateColor")
    L.new(bc.outputs["Color"], bsdf.inputs["Base Color"])
    L.new(nm_.outputs["Color"], nmap.inputs["Color"])
    L.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    L.new(rm.outputs["Color"], sep.inputs["Color"])
    L.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    L.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    g = bpy.data.materials.new("GF_Kit_Glow")
    g.use_nodes = True
    gb = next(n for n in g.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    gb.inputs["Base Color"].default_value = (*ACCENT, 1)
    gb.inputs["Emission Color"].default_value = (*ACCENT, 1)
    gb.inputs["Emission Strength"].default_value = 4.0
    return m, g


def _meshes(o):
    out = [o] if o.type == "MESH" else []
    for c in o.children:
        out += _meshes(c)
    return out


def _strip_for(obj, matname):
    n = obj.name.lower()
    if "vent" in n or "grille" in n or "louvre" in n:
        return "VENT"
    return MAT_STRIP.get(matname, "FRAME")


def _uv_face(f, uvl, strip, cell, big_plate):
    n = f.normal
    ax = max(range(3), key=lambda i: abs(n[i]))
    a_ax, b_ax = [(1, 2), (0, 2), (0, 1)][ax]               # nx -> (y,z) ; ny -> (x,z) ; nz -> (x,y)
    A = [v.co[a_ax] for v in f.verts]; B = [v.co[b_ax] for v in f.verts]
    ea, eb = max(A) - min(A), max(B) - min(B)
    # long axis -> U ; if z is involved and is the long (or tied-long) axis, U = z
    if b_ax == 2:
        long_is_b = eb > ea * 1.001
    else:
        long_is_b = eb > ea * 1.001
    if long_is_b:
        U, V, eu, ev = B, A, eb, ea
    else:
        U, V, eu, ev = A, B, ea, eb
    umin, vmin = min(U), min(V)
    v0, v1 = STRIPS[strip]
    sh = v1 - v0
    for l, u, v in zip(f.loops, U, V):
        if big_plate:
            upx = cell * 512 + 4 + (u - umin) / max(eu, 1e-6) * 504
            vpx = v0 + 4 + (v - vmin) / max(ev, 1e-6) * (sh - 8)
        else:
            sc = min(1.0, (sh - 10) / max(ev * PPS, 1e-6))
            upx = (u - umin) * PPS * sc
            vpx = v0 + (sh - ev * PPS * sc) / 2 + (v - vmin) * PPS * sc
        l[uvl].uv = (upx / RES, vpx / RES)


def build_piece(root_name, collection="KITOUT"):
    root = bpy.data.objects[root_name]
    bpy.context.view_layer.update()
    inv = root.matrix_world.inverted()
    pbr, glow = pbr_materials()
    col = bpy.data.collections.get(collection) or bpy.data.collections.new(collection)
    if col.name not in [c.name for c in bpy.context.scene.collection.children]:
        bpy.context.scene.collection.children.link(col)
    for o in list(col.objects):
        if o.name in ("Kit_" + root_name, "Glow_" + root_name):
            bpy.data.objects.remove(o, do_unlink=True)

    body = bmesh.new(); gl = bmesh.new()
    uvb = body.loops.layers.uv.new("UVMap"); uvg = gl.loops.layers.uv.new("UVMap")
    stats = dict(src_parts=0, hz=0)
    for o in _meshes(root):
        stats["src_parts"] += 1
        mats = [m.name if m else "" for m in o.data.materials]
        M = inv @ o.matrix_world
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
        bm.normal_update()
        for f in bm.faces:
            f.smooth = False
        mat0 = mats[0] if mats else ""
        if mat0 in GLOW_MATS:
            tgt, uvl = gl, uvg
        else:
            tgt, uvl = body, uvb
        if mat0 == "BK_Hazard":
            # collapse the stripe cuboid pile to one box over its bbox; the texture draws the stripes
            xs = [v.co.x for v in bm.verts]; ys = [v.co.y for v in bm.verts]; zs = [v.co.z for v in bm.verts]
            bm.free()
            bm = bmesh.new()
            bmesh.ops.create_cube(bm, size=1.0)
            for v in bm.verts:
                v.co.x = (min(xs) + max(xs)) / 2 + v.co.x * (max(xs) - min(xs))
                v.co.y = (min(ys) + max(ys)) / 2 + v.co.y * (max(ys) - min(ys))
                v.co.z = (min(zs) + max(zs)) / 2 + v.co.z * (max(zs) - min(zs))
            bm.normal_update()
            for f in bm.faces:
                f.smooth = False
            stats["hz"] += 1
        # transfer into the target bmesh
        vmap = {}
        for v in bm.verts:
            vmap[v.index] = tgt.verts.new(v.co)
        tgt.verts.ensure_lookup_table()
        newf = []
        for f in bm.faces:
            try:
                nf = tgt.faces.new([vmap[v.index] for v in f.verts])
            except ValueError:
                continue
            nf.smooth = False
            newf.append((nf, f))
        tgt.normal_update()
        cellsel = int(hashlib.md5(o.name.encode()).hexdigest(), 16) % 2
        if tgt is body:
            strip = _strip_for(o, mat0)
            for nf, of in newf:
                st = strip
                big = False
                if strip == "PLATE":
                    nax = max(range(3), key=lambda i: abs(nf.normal[i]))
                    ab = [(1, 2), (0, 2), (0, 1)][nax]
                    e1 = max(v.co[ab[0]] for v in nf.verts) - min(v.co[ab[0]] for v in nf.verts)
                    e2 = max(v.co[ab[1]] for v in nf.verts) - min(v.co[ab[1]] for v in nf.verts)
                    if min(e1, e2) >= 2.5:
                        big = True
                    else:
                        st = "FRAME"
                _uv_face(nf, uvl, st, cellsel, big)
        else:
            for nf, of in newf:
                for l in nf.loops:
                    l[uvl].uv = (0.5, 0.5)
        bm.free()
    out = []
    for nm, bmx, mat in (("Kit_" + root_name, body, pbr), ("Glow_" + root_name, gl, glow)):
        if not bmx.faces:
            bmx.free(); continue
        bmesh.ops.recalc_face_normals(bmx, faces=bmx.faces)
        me = bpy.data.meshes.new(nm)
        bmx.to_mesh(me); bmx.free()
        me.materials.append(mat)
        ob = bpy.data.objects.new(nm, me)
        col.objects.link(ob)
        out.append(ob)
    print("built", root_name, {o.name: (len(o.data.polygons), sum(len(p.vertices) - 2 for p in o.data.polygons)) for o in out}, stats)
    return out


def export_piece(root_name):
    col = bpy.data.collections["KITOUT"]
    bpy.ops.object.select_all(action="DESELECT")
    objs = [o for o in col.objects if o.name in ("Kit_" + root_name, "Glow_" + root_name)]
    for o in objs:
        o.hide_set(False); o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    path = os.path.join(OUT, "GF_BK_%s.glb" % root_name)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
                              export_texcoords=True, export_normals=True, export_materials="EXPORT", export_cameras=False,
                              export_lights=False)
    print("exported", path, os.path.getsize(path), "bytes")
    return path
