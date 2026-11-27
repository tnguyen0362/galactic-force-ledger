"""Stage A: freeze modifiers, single shared UV atlas for all textured parts (not Glow_*)."""
import bpy, bmesh, math

coll = bpy.data.collections["HERO8_SRC"]
objs = [o for o in coll.objects if o.type == "MESH"]
tex_objs = [o for o in objs if not o.name.startswith("Glow_")]

if bpy.context.object and bpy.context.object.mode != "OBJECT":
    bpy.ops.object.mode_set(mode="OBJECT")
bpy.ops.object.select_all(action="DESELECT")

# 1. apply edge split so UV/bake see final topology
for o in objs:
    for m in list(o.modifiers):
        bpy.context.view_layer.objects.active = o
        o.select_set(True)
        bpy.ops.object.modifier_apply(modifier=m.name)
        o.select_set(False)

# 2. unwrap together
for o in tex_objs:
    o.hide_viewport = False
    o.hide_set(False)
    o.select_set(True)
    if o.data.uv_layers:
        for uvl in list(o.data.uv_layers):
            o.data.uv_layers.remove(uvl)
    o.data.uv_layers.new(name="UVMap")
bpy.context.view_layer.objects.active = tex_objs[0]
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.004, area_weight=0.0, correct_aspect=True,
                         scale_to_bounds=False)
bpy.ops.uv.select_all(action="SELECT")
bpy.ops.uv.average_islands_scale()
try:
    bpy.ops.uv.pack_islands(margin=0.004, rotate=True)
except TypeError:
    bpy.ops.uv.pack_islands(margin=0.004)
bpy.ops.object.mode_set(mode="OBJECT")

# 3. report coverage + texel density
tot_uv = 0.0
min_u = min_v = 9
max_u = max_v = -9
dens = []
for o in tex_objs:
    me = o.data
    uv = me.uv_layers[0].data
    for p in me.polygons:
        a3 = p.area
        uvs = [uv[li].uv for li in p.loop_indices]
        # polygon uv area (shoelace)
        a2 = 0.0
        for i in range(len(uvs)):
            x1, y1 = uvs[i]
            x2, y2 = uvs[(i + 1) % len(uvs)]
            a2 += x1 * y2 - x2 * y1
        a2 = abs(a2) / 2
        tot_uv += a2
        if a3 > 1e-7 and a2 > 0:
            dens.append(math.sqrt(a2 / a3))
        for u, v in uvs:
            min_u, max_u, min_v, max_v = min(min_u, u), max(max_u, u), min(min_v, v), max(max_v, v)
dens.sort()
med = dens[len(dens) // 2]
print("uv bounds", round(min_u, 3), round(max_u, 3), round(min_v, 3), round(max_v, 3))
print("uv coverage (fraction of atlas used)", round(tot_uv, 3))
print("texel density @1024: median %.0f px/m, p10 %.0f, p90 %.0f" % (med * 1024, dens[len(dens) // 10] * 1024, dens[len(dens) * 9 // 10] * 1024))
print("tex objs", len(tex_objs))
