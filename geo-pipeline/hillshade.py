# Hillshade renderer - the standard terrain visualization. Reveals real landforms.
import numpy as np
from PIL import Image
import sys

def hillshade(elev, azimuth=315, altitude=45, cellsize=13.8):
    az = math.radians(azimuth) if False else np.radians(azimuth)
    alt = np.radians(altitude)
    gy, gx = np.gradient(elev, cellsize)
    slope = np.pi/2 - np.arctan(np.sqrt(gx*gx + gy*gy))
    aspect = np.arctan2(-gx, gy)
    shaded = np.sin(alt)*np.sin(slope) + np.cos(alt)*np.cos(slope)*np.cos((az - np.pi/2) - aspect)
    return np.clip((shaded+1)/2, 0, 1)

def render(elev, outpath, cellsize=13.8, contour=True):
    hs = hillshade(elev, cellsize=cellsize)
    # normalize heights for hypsometric tint
    h = (elev - elev.min()) / max(1e-9, elev.max() - elev.min())
    img = np.zeros((*elev.shape, 3), dtype=np.uint8)
    # hypsometric: lowlands green-tan, midlands tan-grey, highlands pale rock/snow
    img[:,:,0] = np.clip(90 + h*160, 0, 255).astype(np.uint8)
    img[:,:,1] = np.clip(110 + h*140, 0, 255).astype(np.uint8)
    img[:,:,2] = np.clip(80 + h*170, 0, 255).astype(np.uint8)
    shade = (hs*255).astype(np.uint8)
    for c in range(3):
        img[:,:,c] = (img[:,:,c]*0.55 + shade*0.45).astype(np.uint8)
    if contour:
        # contour lines every 100m
        lvl = (elev // 100).astype(np.int32)
        edges = np.zeros_like(elev, dtype=bool)
        edges[1:,:] |= lvl[1:,:] != lvl[:-1,:]
        edges[:,1:] |= lvl[:,1:] != lvl[:,:-1]
        img[edges] = [30, 30, 30]
    Image.fromarray(img).save(outpath)
    print("saved", outpath, img.shape)

if __name__ == '__main__':
    elev = np.load(r'C:\Users\tnguy\gf-geo\teton_raw.npy')
    render(elev, r'C:\Users\tnguy\gf-geo\teton_overview.png')
