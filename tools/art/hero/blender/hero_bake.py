"""Stage B: procedural PBR materials + Cycles bake into one 1024 atlas. Define functions; call run_pass(name)."""
import bpy, math, numpy as np, os

RES = 1024
OUT = r"C:\gf-art-build\blender\out_hero\tex"
os.makedirs(OUT, exist_ok=True)
coll = bpy.data.collections["HERO8_SRC"]
tex_objs = [o for o in coll.objects if o.type == "MESH" and not o.name.startswith("Glow_")]

SPEC = {
    # base, rough, metal, wear_col, wear_rough, wear_metal, fine_bump, panel, grime
    "suit":  dict(base=(0.085, 0.090, 0.100), rough=0.88, metal=0.0, wc=(0.17, 0.18, 0.20), wr=0.75, wm=0.0, fine=0.55, fscale=70, panel=0.0, grime=0.55),
    "plate": dict(base=(0.150, 0.156, 0.172), rough=0.52, metal=0.35, wc=(0.50, 0.52, 0.56), wr=0.28, wm=1.0, fine=0.20, fscale=45, panel=1.0, grime=0.45),
    "trim":  dict(base=(0.700, 0.480, 0.120), rough=0.36, metal=0.85, wc=(0.88, 0.74, 0.46), wr=0.22, wm=1.0, fine=0.10, fscale=60, panel=0.0, grime=0.35),
    "strap": dict(base=(0.075, 0.070, 0.064), rough=0.86, metal=0.0, wc=(0.16, 0.15, 0.13), wr=0.80, wm=0.0, fine=0.60, fscale=110, panel=0.0, grime=0.55),
    "skin":  dict(base=(0.600, 0.430, 0.340), rough=0.62, metal=0.0, wc=(0.66, 0.50, 0.40), wr=0.55, wm=0.0, fine=0.15, fscale=80, panel=0.0, grime=0.10),
    "dark":  dict(base=(0.040, 0.042, 0.052), rough=0.55, metal=0.20, wc=(0.30, 0.31, 0.36), wr=0.35, wm=0.7, fine=0.25, fscale=60, panel=0.0, grime=0.40),
}
ORDER = ["suit", "plate", "trim", "strap", "skin", "dark"]


def build_mat(key, sp, img):
    m = bpy.data.materials.get("H8_" + key)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    N = nt.nodes
    L = nt.links
    x = [0]

    def nd(t, **kw):
        n = N.new(t)
        for k, v in kw.items():
            setattr(n, k, v)
        return n

    def put(sock, v):
        return sock if False else None

    def setin(inp, v):
        if isinstance(v, bpy.types.NodeSocket):
            L.new(v, inp)
        else:
            inp.default_value = v

    def MATH(op, a, b=0.0, c=0.0, clamp=False):
        n = nd("ShaderNodeMath", operation=op, use_clamp=clamp)
        setin(n.inputs[0], a)
        setin(n.inputs[1], b)
        setin(n.inputs[2], c)
        return n.outputs[0]

    def MAPR(v, a0, a1, b0, b1, clamp=True):
        n = nd("ShaderNodeMapRange")
        n.clamp = clamp
        setin(n.inputs[0], v)
        n.inputs[1].default_value = a0
        n.inputs[2].default_value = a1
        n.inputs[3].default_value = b0
        n.inputs[4].default_value = b1
        return n.outputs[0]

    def MIXC(fac, a, b):
        n = nd("ShaderNodeMix", data_type="RGBA", blend_type="MIX")
        setin(n.inputs[0], fac)
        setin(n.inputs[6], a if isinstance(a, bpy.types.NodeSocket) else (*a, 1.0))
        setin(n.inputs[7], b if isinstance(b, bpy.types.NodeSocket) else (*b, 1.0))
        return n.outputs[2]

    def MIXF(fac, a, b):
        n = nd("ShaderNodeMix", data_type="FLOAT")
        setin(n.inputs[0], fac)
        setin(n.inputs[2], a)
        setin(n.inputs[3], b)
        return n.outputs[0]

    tc = nd("ShaderNodeTexCoord")
    P = tc.outputs["Object"]
    xyz = nd("ShaderNodeSeparateXYZ")
    L.new(P, xyz.inputs[0])

    def NOISE(scale, detail=5.0, rough=0.55):
        n = nd("ShaderNodeTexNoise", noise_dimensions="3D")
        L.new(P, n.inputs["Vector"])
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        return n.outputs["Fac"]

    nL = NOISE(7.0, 4.0)
    nM = NOISE(sp["fscale"] * 0.35, 5.0)
    nF = NOISE(sp["fscale"], 6.0, 0.6)

    # edge wear from bevel normal vs geometry normal
    bev = nd("ShaderNodeBevel")
    bev.samples = 8
    bev.inputs["Radius"].default_value = 0.006
    geo = nd("ShaderNodeNewGeometry")
    dot = nd("ShaderNodeVectorMath", operation="DOT_PRODUCT")
    L.new(bev.outputs["Normal"], dot.inputs[0])
    L.new(geo.outputs["Normal"], dot.inputs[1])
    edge = MAPR(dot.outputs["Value"], 0.995, 0.90, 0.0, 1.0)
    breakup = MAPR(nM, 0.35, 0.65, 0.25, 1.0)
    wear = MATH("MULTIPLY", edge, breakup, clamp=True)

    # panel grooves: object-space grid so plates read as segmented armour
    def GRID(coord, period, width):
        v = MATH("PINGPONG", coord, period)
        d = MATH("MINIMUM", v, MATH("SUBTRACT", period, v))
        return MAPR(d, 0.0, width, 1.0, 0.0)

    if sp["panel"] > 0:
        panel = MATH("MAXIMUM", GRID(xyz.outputs["Z"], 0.09, 0.0045), GRID(xyz.outputs["X"], 0.055, 0.0045))
        panel = MATH("MULTIPLY", panel, sp["panel"])
    else:
        panel = 0.0

    # grime: darker toward the ground and in noisy patches
    low = MAPR(xyz.outputs["Z"], 0.05, 0.75, 1.0, 0.0)
    gmask = MATH("MULTIPLY", MATH("ADD", MAPR(nL, 0.35, 0.7, 0.0, 1.0), MATH("MULTIPLY", low, 0.9)), sp["grime"], clamp=True)

    base = sp["base"]
    dark = tuple(c * 0.50 for c in base)
    col = MIXC(MATH("MULTIPLY", MAPR(nM, 0.3, 0.7, 0.0, 0.35), 1.0), base, tuple(c * 1.18 for c in base))   # tonal variation
    col = MIXC(gmask, col, dark)
    col = MIXC(wear, col, sp["wc"])
    if sp["panel"] > 0:
        col = MIXC(MATH("MULTIPLY", panel, 0.55), col, tuple(c * 0.35 for c in base))

    rough = MIXF(wear, MIXF(MAPR(nF, 0.3, 0.7, 0.0, 0.25), sp["rough"], min(1.0, sp["rough"] + 0.18)), sp["wr"])
    rough = MIXF(MATH("MULTIPLY", gmask, 0.5), rough, min(1.0, sp["rough"] + 0.25))
    metal = MIXF(wear, sp["metal"], sp["wm"])
    metal = MIXF(MATH("MULTIPLY", gmask, 0.6), metal, sp["metal"] * 0.4)

    # bump: fine grain + large folds - panel grooves
    h = MATH("MULTIPLY", nF, sp["fine"])
    h = MATH("ADD", h, MATH("MULTIPLY", nM, 0.25))
    h = MATH("SUBTRACT", h, MATH("MULTIPLY", panel, 0.9) if sp["panel"] > 0 else 0.0)
    h = MATH("SUBTRACT", h, MATH("MULTIPLY", wear, 0.15))
    bump = nd("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.9
    bump.inputs["Distance"].default_value = 0.012
    L.new(h, bump.inputs["Height"])

    bsdf = nd("ShaderNodeBsdfPrincipled")
    L.new(col, bsdf.inputs["Base Color"])
    L.new(rough, bsdf.inputs["Roughness"])
    L.new(metal, bsdf.inputs["Metallic"])
    L.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    out = nd("ShaderNodeOutputMaterial")
    out.name = "OUT"
    L.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    # emission output carrying metallic (for baking)
    em = nd("ShaderNodeEmission")
    L.new(metal, em.inputs["Color"])
    oe = nd("ShaderNodeOutputMaterial")
    oe.name = "OUT_EM"
    L.new(em.outputs["Emission"], oe.inputs["Surface"])
    emh = nd("ShaderNodeEmission")
    L.new(h, emh.inputs["Color"])
    oh = nd("ShaderNodeOutputMaterial")
    oh.name = "OUT_H"
    L.new(emh.outputs["Emission"], oh.inputs["Surface"])
    emo = nd("ShaderNodeEmission")
    emo.inputs["Color"].default_value = (1, 1, 1, 1)
    oo = nd("ShaderNodeOutputMaterial")
    oo.name = "OUT_ONE"
    L.new(emo.outputs["Emission"], oo.inputs["Surface"])
    out.is_active_output = True
    oe.is_active_output = False
    oh.is_active_output = False
    oo.is_active_output = False
    # bake target
    ti = nd("ShaderNodeTexImage")
    ti.name = "BAKE_IMG"
    ti.image = img
    ti.location = (-600, -600)
    N.active = ti
    ti.select = True


def new_img(name, srgb=False):
    if name in bpy.data.images:
        bpy.data.images.remove(bpy.data.images[name])
    im = bpy.data.images.new(name, RES, RES, alpha=False, float_buffer=True)
    im.colorspace_settings.name = "Non-Color"
    return im


IM = {}


def setup():
    IM["target"] = new_img("H8_bake_target")
    for k in ORDER:
        build_mat(k, SPEC[k], IM["target"])
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.use_denoising = False
    print("materials rebuilt", [m.name for m in bpy.data.materials if m.name.startswith("H8_")])


def _select():
    bpy.ops.object.select_all(action="DESELECT")
    for o in tex_objs:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = tex_objs[0]


def set_target(img):
    for k in ORDER:
        m = bpy.data.materials["H8_" + k]
        n = m.node_tree.nodes["BAKE_IMG"]
        n.image = img
        m.node_tree.nodes.active = n


def set_active_out(name):
    for k in ORDER:
        m = bpy.data.materials["H8_" + k]
        for o in m.node_tree.nodes:
            if o.type == "OUTPUT_MATERIAL":
                o.is_active_output = (o.name == name)


def run_pass(name, samples=16):
    sc = bpy.context.scene
    sc.cycles.samples = samples
    img = new_img("H8_" + name)
    IM[name] = img
    set_target(img)
    _select()
    kw = dict(margin=10, margin_type="EXTEND", use_clear=True, target="IMAGE_TEXTURES")
    if name == "albedo":
        set_active_out("OUT")
        bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, **kw)
    elif name == "ao":
        set_active_out("OUT")
        bpy.ops.object.bake(type="AO", **kw)
    elif name == "normal":
        set_active_out("OUT")
        bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", normal_r="POS_X", normal_g="POS_Y", normal_b="POS_Z", **kw)
    elif name == "rough":
        set_active_out("OUT")
        bpy.ops.object.bake(type="ROUGHNESS", **kw)
    elif name == "height":
        set_active_out("OUT_H")
        bpy.ops.object.bake(type="EMIT", **kw)
        set_active_out("OUT")
    elif name == "mask":
        set_active_out("OUT_ONE")
        kw["margin"] = 0
        bpy.ops.object.bake(type="EMIT", **kw)
        set_active_out("OUT")
    elif name == "metal":
        set_active_out("OUT_EM")
        bpy.ops.object.bake(type="EMIT", **kw)
        set_active_out("OUT")
    a = np.array(img.pixels[:], dtype=np.float32).reshape(RES, RES, 4)
    print(name, "mean", a[..., :3].mean(axis=(0, 1)).round(3), "min", a[..., :3].min().round(3), "max", a[..., :3].max().round(3))


def to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, 12.92 * c, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def save_png(name, arr, path):
    if name in bpy.data.images:
        bpy.data.images.remove(bpy.data.images[name])
    im = bpy.data.images.new(name, RES, RES, alpha=False, float_buffer=False)
    im.colorspace_settings.name = "Non-Color"
    rgba = np.concatenate([np.clip(arr, 0, 1), np.ones((RES, RES, 1), np.float32)], axis=2)
    im.pixels.foreach_set(rgba.ravel())
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    return im


def _erode(m, n):
    for _ in range(n):
        m = m & np.roll(m, 1, 0) & np.roll(m, -1, 0) & np.roll(m, 1, 1) & np.roll(m, -1, 1)
    return m


def _dilate(m, n):
    for _ in range(n):
        m = m | np.roll(m, 1, 0) | np.roll(m, -1, 0) | np.roll(m, 1, 1) | np.roll(m, -1, 1)
    return m


def _px(name, ch=3):
    return np.array(IM[name].pixels[:], dtype=np.float32).reshape(RES, RES, 4)[..., :ch]


def _extend(img, valid, iters=14):
    img = img.copy()
    valid = valid.copy()
    for _ in range(iters):
        acc = np.zeros_like(img)
        cnt = np.zeros(valid.shape, np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
            v = np.roll(np.roll(valid, dy, 0), dx, 1)
            im = np.roll(np.roll(img, dy, 0), dx, 1)
            acc += im * v[..., None]
            cnt += v
        new = (~valid) & (cnt > 0)
        img[new] = (acc[new] / cnt[new][:, None])
        valid = valid | new
    return img, valid


def _blur(a):
    return (a + np.roll(a, 1, 0) + np.roll(a, -1, 0) + np.roll(a, 1, 1) + np.roll(a, -1, 1)) / 5.0


def composite(nstrength=1.0):
    alb = _px("albedo")
    ao = _px("ao")[..., :1]
    rg = _px("rough")[..., :1]
    mt = _px("metal")[..., :1]
    ht = _px("height")[..., 0]
    mask = _px("mask")[..., 0] > 0.5
    interior = _erode(mask, 2)
    ht = _blur(ht)
    gy, gx = np.gradient(ht)
    gx = gx * interior
    gy = gy * interior
    nx, ny, nz = -gx * nstrength * RES / 64.0, -gy * nstrength * RES / 64.0, np.ones_like(ht)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    nrm = np.stack([nx / ln, ny / ln, nz / ln], axis=2) * 0.5 + 0.5
    bc_lin = alb * (0.42 + 0.58 * ao)
    pack = np.concatenate([bc_lin, rg, mt, nrm], axis=2)
    pack, valid = _extend(pack, mask, 14)
    avg = bc_lin[mask].mean(axis=0)
    pack[~valid] = np.array([*avg, 0.6, 0.0, 0.5, 0.5, 1.0], np.float32)
    bc = to_srgb(pack[..., 0:3])
    rg2, mt2, nrm2 = pack[..., 3:4], pack[..., 4:5], pack[..., 5:8]
    nrm2[..., 2] = np.clip(nrm2[..., 2], 0.5, 1.0)
    rm = np.concatenate([np.ones_like(rg2), np.clip(rg2, 0.04, 1.0), np.clip(mt2, 0, 1)], axis=2)
    save_png("H8_BC", bc, os.path.join(OUT, "GF_Hero_Asc_BC.png"))
    save_png("H8_N", nrm2, os.path.join(OUT, "GF_Hero_Asc_N.png"))
    save_png("H8_RM", rm, os.path.join(OUT, "GF_Hero_Asc_RM.png"))
    print("saved textures; normal xy dev: %.3f" % float(np.abs(nrm[..., :2] - 0.5)[interior].mean()),
          "coverage %.3f" % float(mask.mean()), "unfilled %.4f" % float((~valid).mean()))
