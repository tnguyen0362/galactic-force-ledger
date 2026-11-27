import bpy, os
from mathutils import Vector


def render_views(coll="HERO8_SRC", tag="v8", views=("front", "side", "q34"), res=(700, 900), target=(0, 0.1, 1.0), lens=70):
    sc = bpy.context.scene
    for o in bpy.data.objects:
        if o.type == "MESH":
            keep = bool(o.users_collection) and o.users_collection[0].name == coll or o.name == "HERO_Floor"
            o.hide_render = not keep
            o.hide_viewport = not keep
    cam = bpy.data.objects["HERO_Cam"]
    sc.camera = cam
    cam.data.lens = lens
    # mirrored front/side per character facing +Y
    P = {"front": Vector((0, 6.0, 1.2)), "back": Vector((0, -6.0, 1.2)), "side": Vector((6.0, 0.1, 1.2)),
         "q34": Vector((4.2, 4.2, 1.45)), "q34b": Vector((-4.2, 4.2, 1.45)), "close": Vector((1.7, 2.2, 1.55)),
         "head": Vector((0.9, 1.5, 1.8)), "top": Vector((0.6, 2.2, 3.3)), "foot": Vector((1.5, 0.6, 0.35)),
         "face": Vector((0.4, 1.1, 1.75))}
    T = {"foot": Vector((0, 0.05, 0.12)), "face": Vector((0, 0.0, 1.70)),"close": Vector((0, 0.1, 1.35)), "head": Vector((0, 0, 1.72)), "top": Vector((0, 0.15, 1.3))}
    outdir = r"C:\gf-art-build\blender\hero_wip\shots"
    os.makedirs(outdir, exist_ok=True)
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.image_settings.file_format = "PNG"
    paths = []
    for k in views:
        p = P[k]
        cam.location = p
        d = T.get(k, Vector(target)) - p
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        fp = os.path.join(outdir, f"{tag}_{k}.png")
        sc.render.filepath = fp
        bpy.ops.render.render(write_still=True)
        paths.append(fp)
    return paths
