# gf-geo acquisition: stitch Terrarium tiles into a single elevation grid.
# Provenance: AWS Open Data "Terrain Tiles" (registry.opendata.aws/terrain-tiles)
# US coverage = USGS 3DEP - public domain. Documented per spec section 8.
import urllib.request, io, math, os, sys, time
from PIL import Image
import numpy as np

CACHE = r'C:\Users\tnguy\gf-geo\tilecache'
os.makedirs(CACHE, exist_ok=True)

def deg2tilef(lat, lon, z):
    n = 2.0**z
    xf = (lon + 180) / 360 * n
    yf = (1 - math.log(math.tan(math.radians(lat)) + 1/math.cos(math.radians(lat))) / math.pi) / 2 * n
    return xf, yf

def tile_bounds(x, y, z):
    n = 2.0**z
    lon0 = x / n * 360 - 180
    lon1 = (x+1) / n * 360 - 180
    lat0 = math.degrees(math.atan(math.sinh(math.pi * (1 - 2*(y+1)/n))))
    lat1 = math.degrees(math.atan(math.sinh(math.pi * (1 - 2*y/n))))
    return lat0, lon0, lat1, lon1

def fetch_tile(z, x, y):
    key = f"{z}_{x}_{y}.png"
    path = os.path.join(CACHE, key)
    if not os.path.exists(path):
        url = f"https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        data = urllib.request.urlopen(req, timeout=30).read()
        open(path, 'wb').write(data)
        time.sleep(0.1)
    img = Image.open(path).convert('RGB')
    arr = np.array(img).astype(np.float32)
    return arr[:,:,0]*256 + arr[:,:,1] + arr[:,:,2]/256 - 32768

def acquire(lat0, lon0, lat1, lon1, z, outname):
    # fetch all tiles covering bbox, stitch, then crop exactly to bbox
    xf0, yf1 = deg2tilef(lat0, lon0, z)   # note lat0<lat1: yf inversion
    xf1, yf0 = deg2tilef(lat1, lon1, z)
    x0, x1 = int(math.floor(xf0)), int(math.floor(xf1))
    y0, y1 = int(math.floor(yf0)), int(math.floor(yf1))
    print(f"tiles x {x0}..{x1} y {y0}..{y1} z{z}")
    rows = []
    for ty in range(y0, y1+1):
        rowtiles = []
        for tx in range(x0, x1+1):
            rowtiles.append(fetch_tile(z, tx, ty))
        rows.append(np.concatenate(rowtiles, axis=1))
    grid = np.concatenate(rows, axis=0)
    print(f"stitched: {grid.shape} relief={grid.max()-grid.min():.0f}m")
    np.save(rf'C:\Users\tnguy\gf-geo\{outname}_raw.npy', grid)
    # save tile-grid origin metadata for exact cropping later
    meta = dict(x0=x0, y0=y0, z=z, lat0=lat0, lon0=lon0, lat1=lat1, lon1=lon1,
                xf0=xf0, yf0=yf0, xf1=xf1, yf1=yf1)
    import json
    json.dump(meta, open(rf'C:\Users\tnguy\gf-geo\{outname}_meta.json','w'))
    return grid, meta

if __name__ == '__main__':
    # Grand Teton / Jackson Hole patch: Teton front + Jackson Hole valley floor
    # ~43.65-43.85N, -111.05--110.65W  (~24x30km at z13 preview scale)
    acquire(43.62, -111.05, 43.88, -110.62, 13, 'teton')
