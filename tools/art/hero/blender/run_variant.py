"""Run in Blender via exec with VARIANT set: build -> UV -> bake -> export GLB + data luau. One call per variant."""
import io, contextlib, os, bpy
B = r"C:\gf-art-build\blender"
log = io.StringIO()
with contextlib.redirect_stdout(log):
    ns = {"VARIANT": VARIANT, "__name__": "x"}
    exec(open(B + r"\gen_hero_v12.py", encoding="utf-8").read(), ns)
    sc = ns["VAR"]["scale"]
    exec(open(B + r"\hero_uv.py", encoding="utf-8").read())
    exec(open(B + r"\hero_bake.py", encoding="utf-8").read())
    _div = ns["VAR"].get("div")
    if _div:
        for _k, _v in ns["ELITE_SPEC"][_div].items():
            SPEC[_k].update(_v)
    setup()
    for p_ in ("albedo", "ao", "rough", "height", "mask", "metal"):
        run_pass(p_)
    composite(0.55)
    exec(open(B + r"\hero_export.py", encoding="utf-8").read())
    S = 4.0 * sc
    GLB = os.path.join(OUTD, "Hero_Ascendancy_%s_v12.glb" % VARIANT)
    LUA = r"C:\galactic-force\tools\art\hero\%s_data.luau" % VARIANT.lower()
    src = open(B + r"\gen_hero_v12.py", encoding="utf-8").read()
    head = src[:src.index("# ---------------------------------------------------------------- parts")]
    jn = {}
    exec(head, jn)
    collapse()
    parts_, piv_ = export(jn["J"], jn["PARENT"])
    bpy.ops.wm.save_as_mainfile(filepath=B + r"\hero_wip\squad_%s_baked.blend" % VARIANT, copy=True)
out = log.getvalue().splitlines()
print("\n".join(l for l in out if l.startswith(("exported", "height", "TOTAL")) or "Error" in l or "Traceback" in l))
