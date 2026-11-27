import bpy, sys, os, io, contextlib
BL = r"C:\gf-art-build\blender"
if BL not in sys.path: sys.path.insert(0, BL)
src = open(os.path.join(BL, "gen_hero_v12.py"), encoding="utf-8").read()
XS = {"Rifleman": -7.6, "SpectreLeader": -5.7, "SpectreAssault": -4.75, "SpectreWeapons": -3.8, "SpectrePrecision": -2.85, "SpectreSupport": -1.9, "RevenantLeader": 1.9, "RevenantAssault": 2.85, "RevenantWeapons": 3.8, "RevenantPrecision": 4.75, "RevenantDefense": 5.7, "Heavy": 7.6}
for v in XS:
    cn = "LINEUP_" + v
    if cn in bpy.data.collections:
        c = bpy.data.collections[cn]
        for o in list(c.objects): bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.collections.remove(c)
res = {}
for v, x in XS.items():
    g = {"__name__": "gen", "VARIANT": v}
    with contextlib.redirect_stdout(io.StringIO()):
        exec(compile(src, "gen_hero_v12.py", "exec"), g)
    hc = bpy.data.collections["HERO8_SRC"]
    nc = bpy.data.collections.new("LINEUP_" + v); bpy.context.scene.collection.children.link(nc)
    tot = head = 0
    for o in list(hc.objects):
        hc.objects.unlink(o); nc.objects.link(o)
        o.name = f"{v}__{o.name}"
        o.location.x = x
        if o.type == "MESH":
            n = sum(len(p.vertices) - 2 for p in o.data.polygons)
            tot += n
            if "Head" in o.name: head += n
    res[v] = (tot, head)
print(res)
