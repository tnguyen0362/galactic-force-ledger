# Geographical Foundation Provenance

## foundation_v1 — Grand Teton front
- Source: USGS 3D Elevation Program (3DEP) data via AWS Open Data "Terrain Tiles"
  (registry.opendata.aws/terrain-tiles), Terrarium format z13
- License: USGS 3DEP is public domain (US government work)
- Region: Grand Teton front / Jackson Hole edge, Wyoming, USA (~43.7N, -110.8W)
- Window: source grid rows 1740-2160, cols 1560-1980 of the stitched teton_raw grid
- Real extent: ~5.8km x 5.8km mapped to 5000x5000 studs (compression 4.14x, slope-preserving)
- Vertical: relief 1471m real -> 1132 studs in-game; final height range 24..1156 studs
- Processing: robust quantile clip (0.5/99.5), multiresolution decomposition
  (macro sigma 28px preserved 1.0, meso 1.0, micro 0.8), bilinear resample to 1250x1250
- Bake: fractional-occupancy WriteVoxels, shell-fill 8 voxels, per-tile adaptive vertical
  bounds. Verified 7/7 raycast probes match heightfield within 2 studs.
- Place version: baked + saved as v763/v764
