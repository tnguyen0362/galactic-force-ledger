# Test: AWS Open Data terrain tiles (Terrarium format) - USGS 3DEP sourced, public domain
# Terrarium height format: elev_m = R*256 + G + B/256 - 32768
import urllib.request, io, math, sys
from PIL import Image
import numpy as np

def deg2tile(lat, lon, z):
    n = 2**z
    x = int((lon + 180) / 360 * n)
    y = int((1 - math.log(math.tan(math.radians(lat)) + 1/math.cos(math.radians(lat))) / math.pi) / 2 * n)
    return x, y

lat, lon, z = 43.74, -110.80, 12
x, y = deg2tile(lat, lon, z)
url = f"https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"
print("fetching:", url)
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
data = urllib.request.urlopen(req, timeout=20).read()
img = Image.open(io.BytesIO(data)).convert('RGB')
arr = np.array(img).astype(np.float32)
elev = arr[:,:,0]*256 + arr[:,:,1] + arr[:,:,2]/256 - 32768
print(f"tile {z}/{x}/{y}: shape={elev.shape} min={elev.min():.0f}m max={elev.max():.0f}m relief={elev.max()-elev.min():.0f}m")
np.save(r'C:\Users\tnguy\gf-geo\test_tile.npy', elev)
print("saved test_tile.npy")
