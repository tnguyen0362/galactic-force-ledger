# Render dumped battlefield stream as PNG heightmaps with layout overlays.
import sys, pathlib
import numpy as np
from PIL import Image, ImageDraw


def parse_stream(path):
    blocks = []
    cur = None
    for ln in pathlib.Path(path).read_text().splitlines():
        if ln.startswith("BEGIN "):
            meta = dict(kv.split("=") for kv in ln[6:].split())
            cur = {"meta": meta, "nodes": {}, "insts": [], "routes": {}, "heights": []}
        elif ln == "END" and cur:
            blocks.append(cur); cur = None
        elif cur is not None:
            if ln.startswith("node "):
                _, k, x, z = ln.split()
                cur["nodes"][k] = (float(x), float(z))
            elif ln.startswith("inst "):
                _, k, x, z, fp = ln.split()
                cur["insts"].append((k, float(x), float(z), float(fp)))
            elif ln.startswith("route "):
                parts = ln.split()
                cur["routes"][parts[1]] = [tuple(map(float, pp.split(","))) for pp in parts[2:]]
            elif ln.startswith("cover "):
                _, k, x, z = ln.split()
                cur.setdefault("cover", []).append((k, float(x), float(z)))
            elif ln.startswith("zone "):
                _, k, x, z, r = ln.split()
                cur.setdefault("zones", []).append((k, float(x), float(z), float(r)))
            elif ln == "heights":
                cur["inheights"] = True
            elif cur.get("inheights"):
                cur["heights"].append([float(v) for v in ln.split()])
    return blocks

def render_block(b, out):
    meta = b["meta"]
    nx, nz, extent = int(meta["nx"]), int(meta["nz"]), float(meta["extent"])
    H = np.array(b["heights"][:nx])
    hn = (H - H.min()) / max(1e-6, H.max() - H.min())
    gy, gx = np.gradient(hn)
    shade = np.clip(0.55 + gx * 6 - gy * 3, 0, 1)
    img = (hn * 0.55 + shade * 0.45)
    rgb = np.zeros((H.shape[0], H.shape[1], 3), np.uint8)
    rgb[..., 0] = np.clip(img * 255 * (0.75 + hn * 0.5), 0, 255)
    rgb[..., 1] = np.clip(img * 255 * (0.85 + hn * 0.3), 0, 255)
    rgb[..., 2] = np.clip(img * 255 * (0.7 + (1 - hn) * 0.35), 0, 255)
    im = Image.fromarray(rgb).resize((900, 900), Image.NEAREST)
    d = ImageDraw.Draw(im)
    sc = 900 / extent
    def px(x, z):
        return ((x / extent + 0.5) * 900, (z / extent + 0.5) * 900)
    for rname, pts in b["routes"].items():
        col = (255, 255, 80) if rname == "primary" else (80, 200, 255)
        xy = [px(x, z) for x, z in pts]
        if len(xy) > 1:
            d.line(xy, fill=col, width=5 if rname == "primary" else 3)
    for k, x, z, fp in b["insts"]:
        cx, cz = px(x, z)
        rr = max(4, fp * sc / 2)
        d.ellipse([cx - rr, cz - rr, cx + rr, cz + rr], outline=(255, 120, 40), width=3)
    for k, x, z in b.get("cover", []):
        cx, cz = px(x, z)
        col = (110, 90, 70) if k == "rock" else (90, 110, 70)
        d.ellipse([cx - 2.5, cz - 2.5, cx + 2.5, cz + 2.5], fill=col)
    zcol = {"garrison": (255, 160, 0), "patrol_route": (0, 200, 200), "checkpoint": (200, 200, 0), "reinforcement": (200, 0, 200), "quiet": (120, 120, 120), "extraction_pressure": (255, 0, 128)}
    for k, x, z, r in b.get("zones", []):
        cx, cz = px(x, z)
        rr = max(3, r * sc)
        col = zcol.get(k, (180, 180, 180))
        d.ellipse([cx - rr, cz - rr, cx + rr, cz + rr], outline=col, width=1)
    for k, (x, z) in b["nodes"].items():
        cx, cz = px(x, z)
        col = {"lz": (0, 255, 0), "primary": (255, 0, 0), "extraction": (255, 0, 255)}.get(k, (255, 255, 255))
        d.ellipse([cx - 10, cz - 10, cx + 10, cz + 10], fill=col)
    im.save(out)
    print("rendered", out)

blocks = parse_stream(sys.argv[1])
for b in blocks:
    out = str(pathlib.Path(sys.argv[1]).parent / ("map_" + b["meta"]["arch"] + ".png"))
    render_block(b, out)
print("total blocks:", len(blocks))
