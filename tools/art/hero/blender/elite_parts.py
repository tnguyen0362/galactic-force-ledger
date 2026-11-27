"""Elite (Spectre / Revenant) humanoid parts. exec'd into gen_hero_v12's namespace (needs loft/arcshell/rbox/cyl/new_bm,
_neck/_core/_prof/_shell/_ring/_finish, V, math). Material slots: 0 suit 1 plate 2 trim(bronze) 3 strap 4 skin(=IVORY) 5 dark.
Spectre  = Halo-ODST special-ops: matte obsidian, wide flush visor band, bronze notch, heavy shoulders.
Revenant = Warframe-style: sleek swept shell, ivory faceplate, bronze trim, violet energy slit, blade crests."""

# ------------------------------------------------------------------ palettes (slot -> linear rgb), used by get_mats + bake
ELITE_PAL = {
    "spectre":  {"suit": (0.030, 0.028, 0.036), "plate": (0.050, 0.047, 0.060), "trim": (0.155, 0.098, 0.048),
                 "strap": (0.040, 0.038, 0.044), "skin": (0.090, 0.086, 0.105), "dark": (0.014, 0.014, 0.020)},
    "revenant": {"suit": (0.034, 0.030, 0.044), "plate": (0.060, 0.054, 0.076), "trim": (0.155, 0.098, 0.048),
                 "strap": (0.040, 0.036, 0.048), "skin": (0.640, 0.590, 0.450), "dark": (0.014, 0.012, 0.022)},
}
ELITE_SPEC = {   # bake overrides (hero_bake.SPEC keys) -> dict(base=...) merged
    "spectre": {"suit": dict(base=(0.034, 0.032, 0.042)), "plate": dict(base=(0.058, 0.055, 0.070), wc=(0.22, 0.21, 0.26)),
                "trim": dict(base=(0.200, 0.125, 0.060), wc=(0.55, 0.40, 0.22)), "strap": dict(base=(0.045, 0.043, 0.050)),
                "skin": dict(base=(0.100, 0.096, 0.115), rough=0.5, metal=0.3), "dark": dict(base=(0.016, 0.016, 0.024))},
    "revenant": {"suit": dict(base=(0.038, 0.033, 0.050)), "plate": dict(base=(0.066, 0.059, 0.084), wc=(0.24, 0.22, 0.30)),
                 "trim": dict(base=(0.200, 0.125, 0.060), wc=(0.55, 0.40, 0.22)), "strap": dict(base=(0.045, 0.040, 0.054)),
                 "skin": dict(base=(0.700, 0.650, 0.500), rough=0.38, metal=0.15, wc=(0.80, 0.76, 0.62), grime=0.18, panel=0.0),
                 "dark": dict(base=(0.016, 0.014, 0.026))},
}

_ZSR = [1.660, 1.692, 1.726, 1.762, 1.800, 1.840, 1.880, 1.915, 1.940]


def _glow_band(g, z0, z1, a, rx, ry, n, th=0.006, mat=5):
    arcshell(g, [_ring(z0, rx, ry, n=n), _ring(z1, rx, ry, n=n)], segs=8, a0=-a, a1=a, th=th, mat=mat)


def head_spectre(role):
    bm = new_bm()
    _neck(bm, 1.2)
    _core(bm)
    rx = [.074, .090, .100, .106, .108, .106, .098, .072, .036]
    ry = [.092, .110, .124, .132, .135, .132, .123, .094, .058]
    if role == "weapons":
        rx = [r * 1.06 for r in rx]
        ry = [r * 1.04 for r in ry]
    visor = (1.700, 1.792, 1.30)
    if role == "weapons":
        visor = (1.684, 1.806, 1.18)
    if role == "precision":
        visor = (1.708, 1.786, 1.05)
    if role == "support":
        visor = (1.704, 1.790, 1.22)
    _shell(bm, _prof(ZS, rx, ry, n=2.6),
           paints=[(visor[0], visor[1], lambda a, z, w=visor[2]: abs(a) < w, 5),
                   (1.655, 1.699, lambda a, z: abs(a) < 1.05, 3)], segs=24)
    # heavy brow shroud + bronze notch
    arcshell(bm, [_ring(1.795, .112, .142), _ring(1.828, .109, .138)], segs=6, a0=-1.35, a1=1.35, th=0.016, mat=1)
    rbox(bm, V((0, 0.140, 1.806)), (0.032, 0.014, 0.022), bevel=0, mat=2)
    # vented mouth guard
    for zz in (1.684, 1.668):
        rbox(bm, V((0, 0.110, zz)), (0.080, 0.014, 0.007), bevel=0, mat=5)
    rbox(bm, V((0, 0.118, 1.642)), (0.070, 0.030, 0.026), rot=(0.30, 0, 0), bevel=0, mat=1)
    # ear cups + rails + top ridge
    for sx in (-1, 1):
        rbox(bm, V((sx * 0.110, -0.004, 1.730)), (0.030, 0.070, 0.074), bevel=0.010, mat=1)
        rbox(bm, V((sx * 0.126, -0.004, 1.730)), (0.004, 0.044, 0.046), bevel=0, mat=2)
        rbox(bm, V((sx * 0.100, 0.030, 1.822)), (0.012, 0.090, 0.016), bevel=0, mat=3)
    rbox(bm, V((0, 0.004, 1.898)), (0.020, 0.176, 0.012), bevel=0, mat=3)
    g = new_bm()
    _glow_band(g, visor[0] + 0.040, visor[0] + 0.056, min(visor[2] * 0.85, 1.02), .1055, .1335, 2.6)
    # ---- role features
    if role == "leader":
        rbox(bm, V((0, -0.030, 1.926)), (0.018, 0.150, 0.056), rot=(0.18, 0, 0), bevel=0, mat=1)   # command fin
        rbox(bm, V((0, 0.060, 1.930)), (0.020, 0.040, 0.024), bevel=0, mat=2)
        for sx in (-1, 1):
            cyl(bm, V((sx * 0.114, -0.040, 1.790)), V((sx * 0.130, -0.080, 1.990)), 0.0045, segs=5, mat=5)
            rbox(bm, V((sx * 0.060, 0.132, 1.828)), (0.060, 0.012, 0.014), rot=(0, 0, sx * 0.30), bevel=0, mat=2)
    elif role == "assault":
        for sx in (-1, 1):
            rbox(bm, V((sx * 0.060, 0.128, 1.846)), (0.060, 0.052, 0.020), rot=(-0.55, 0, sx * -0.20), bevel=0.003, mat=1)  # breach lugs
            rbox(bm, V((sx * 0.100, 0.060, 1.690)), (0.020, 0.090, 0.070), rot=(0, 0, sx * -0.25), bevel=0.005, mat=1)       # cheek guard
        rbox(bm, V((0, 0.118, 1.640)), (0.090, 0.040, 0.024), rot=(0.20, 0, 0), bevel=0, mat=2)
    elif role == "weapons":
        cyl(bm, V((0.018, 0.118, 1.634)), V((0.018, 0.150, 1.626)), 0.030, segs=8, mat=1)           # breather canister
        cyl(bm, V((0.018, 0.150, 1.626)), V((0.018, 0.158, 1.624)), 0.020, segs=8, mat=5)
        cyl(bm, V((0.062, 0.090, 1.650)), V((0.116, -0.060, 1.690)), 0.008, segs=5, mat=3)          # hose to pack side
        rbox(bm, V((0, 0.118, 1.838)), (0.140, 0.040, 0.040), rot=(-0.12, 0, 0), bevel=0.006, mat=1)  # visor hood
    elif role == "precision":
        cyl(bm, V((0.056, 0.112, 1.742)), V((0.056, 0.150, 1.742)), 0.020, segs=8, mat=1)           # rangefinder ocular
        cyl(bm, V((0.056, 0.150, 1.742)), V((0.056, 0.155, 1.742)), 0.014, segs=8, mat=5)
        cyl(bm, V((0.112, -0.040, 1.800)), V((0.112, -0.075, 2.030)), 0.0045, segs=5, mat=5)       # whip antenna
        rbox(bm, V((-0.056, 0.126, 1.836)), (0.062, 0.020, 0.012), bevel=0, mat=2)
        rbox(g, V((0.056, 0.1562, 1.742)), (0.012, 0.003, 0.012), bevel=0, mat=5)
    elif role == "support":
        cyl(bm, V((0, -0.010, 1.900)), V((0, -0.010, 1.940)), 0.050, segs=10, mat=1)                # radome
        cyl(bm, V((0, -0.010, 1.940)), V((0, -0.010, 1.956)), 0.030, segs=10, mat=5)
        for sx in (-1, 1):
            rbox(bm, V((sx * 0.128, 0.0, 1.790)), (0.014, 0.090, 0.030), rot=(0, 0, sx * 0.40), bevel=0, mat=1)
            rbox(bm, V((sx * 0.060, 0.132, 1.828)), (0.040, 0.012, 0.012), bevel=0, mat=2)
    return _finish({"Head": bm, "Glow_Head": g}, k=1.46)


def head_revenant(role):
    """Warframe-style: angular dark shell, stepped ivory mask plates (real geometry, not paint), slanted energy eyes, bronze trim, swept crest."""
    bm = new_bm()
    _neck(bm, 1.05)
    _core(bm)
    rx = [.060, .078, .090, .097, .098, .094, .086, .064, .032]
    ry = [.088, .106, .120, .130, .134, .131, .122, .094, .056]
    if role == "weapons":
        rx = [r * 1.14 for r in rx]
    if role == "defense":
        rx = [r * 1.10 for r in rx]
        ry = [r * 1.04 for r in ry]
    N = 2.7
    _shell(bm, _prof(_ZSR, rx, ry, n=N), paints=[(1.650, 1.700, lambda a, z: abs(a) < 1.5, 5)], segs=24)

    def sh(z):   # shell half-extents at height z (matches _prof interpolation closely enough for plate seating)
        zs = _ZSR
        for i in range(len(zs) - 1):
            if zs[i] <= z <= zs[i + 1]:
                t = (z - zs[i]) / (zs[i + 1] - zs[i])
                return rx[i] + (rx[i + 1] - rx[i]) * t + 0.003, ry[i] + (ry[i + 1] - ry[i]) * t + 0.003
        return rx[-1], ry[-1]
    wide = 0.66 if role == "defense" else 0.52
    tiers = [(1.746, 1.806, wide, 4), (1.700, 1.746, wide * 0.80, 4), (1.656, 1.700, wide * 0.50, 4)]
    for (z0, z1, aw, m) in tiers:
        x0, y0 = sh(z0)
        x1, y1 = sh(z1)
        arcshell(bm, [_ring(z0, x0, y0, n=N), _ring(z1, x1, y1, n=N)], segs=4, a0=-aw, a1=aw, th=0.012, mat=m)
    # bronze mask edging + nose ridge
    x, y = sh(1.746)
    arcshell(bm, [_ring(1.808, *sh(1.808), n=N), _ring(1.816, *sh(1.816), n=N)], segs=4, a0=-wide, a1=wide, th=0.013, mat=2)
    rbox(bm, V((0, 0.146, 1.736)), (0.016, 0.020, 0.052), rot=(0.12, 0, 0), bevel=0, mat=4)
    # forehead frontlet (layered helm plate above the mask)
    arcshell(bm, [_ring(1.822, *sh(1.822), n=N), _ring(1.880, *sh(1.880), n=N)], segs=6, a0=-0.46, a1=0.46, th=0.016, mat=1)
    rbox(bm, V((0, 0.128, 1.880)), (0.026, 0.020, 0.020), bevel=0, mat=2)
    # slanted eye slits (dark recess + energy)
    g = new_bm()
    for sx in (-1, 1):
        rbox(bm, V((sx * 0.034, 0.1385, 1.768)), (0.052, 0.008, 0.016), rot=(0, sx * -0.40, 0), bevel=0, mat=5)
        rbox(g, V((sx * 0.034, 0.1425, 1.768)), (0.044, 0.003, 0.008), rot=(0, sx * -0.40, 0), bevel=0, mat=5)
    # angular cheek wings + ears
    for sx in (-1, 1):
        rbox(bm, V((sx * 0.102, 0.030, 1.712)), (0.016, 0.130, 0.070), rot=(0, 0, sx * -0.45), bevel=0.003, mat=1)
        rbox(bm, V((sx * 0.122, 0.030, 1.712)), (0.004, 0.130, 0.014), rot=(0, 0, sx * -0.45), bevel=0, mat=2)
        rbox(bm, V((sx * 0.104, -0.026, 1.762)), (0.020, 0.060, 0.070), bevel=0.006, mat=1)
    # swept crest (thick, stepped)
    rbox(bm, V((0, -0.040, 1.935)), (0.024, 0.190, 0.058), rot=(0.24, 0, 0), bevel=0, mat=1)
    rbox(bm, V((0, -0.125, 1.905)), (0.018, 0.100, 0.046), rot=(0.55, 0, 0), bevel=0, mat=2)
    if role == "leader":
        for sx in (-1, 1):
            rbox(bm, V((sx * 0.058, -0.030, 1.924)), (0.018, 0.170, 0.060), rot=(0.20, 0, sx * -0.42), bevel=0, mat=1)
            cyl(bm, V((sx * 0.112, -0.020, 1.800)), V((sx * 0.150, -0.070, 1.995)), 0.0055, segs=5, mat=2)
        rbox(bm, V((0, 0.100, 1.836)), (0.034, 0.050, 0.026), rot=(-0.35, 0, 0), bevel=0, mat=2)
    elif role == "assault":
        for sx in (-1, 1):
            rbox(bm, V((sx * 0.058, 0.120, 1.880)), (0.022, 0.150, 0.026), rot=(-0.62, 0, sx * -0.25), bevel=0, mat=1)
            rbox(bm, V((sx * 0.040, 0.150, 1.640)), (0.018, 0.070, 0.026), rot=(0.9, 0, sx * -0.3), bevel=0, mat=2)
    elif role == "weapons":
        for sx in (-1, 1):
            rbox(bm, V((sx * 0.142, 0.010, 1.790)), (0.034, 0.110, 0.064), bevel=0.008, mat=1)
            rbox(bm, V((sx * 0.160, 0.010, 1.790)), (0.004, 0.076, 0.034), bevel=0, mat=2)
        rbox(bm, V((0, -0.010, 1.965)), (0.060, 0.120, 0.022), bevel=0.004, mat=1)
    elif role == "precision":
        rbox(bm, V((0, -0.090, 1.945)), (0.016, 0.320, 0.040), rot=(0.34, 0, 0), bevel=0, mat=1)
        cyl(bm, V((0.050, 0.126, 1.768)), V((0.050, 0.152, 1.768)), 0.026, segs=10, mat=2)
        cyl(bm, V((0.050, 0.152, 1.768)), V((0.050, 0.158, 1.768)), 0.016, segs=10, mat=5)
        rbox(g, V((0.050, 0.1595, 1.768)), (0.016, 0.003, 0.016), bevel=0, mat=5)
    elif role == "defense":
        arcshell(bm, [_ring(1.836, *sh(1.836), n=N), _ring(1.876, *sh(1.876), n=N)], segs=8, a0=-1.35, a1=1.35, th=0.020, mat=1)
        for sx in (-1, 1):
            rbox(bm, V((sx * 0.114, 0.056, 1.696)), (0.018, 0.110, 0.110), rot=(0, 0, sx * -0.30), bevel=0.006, mat=1)
        rbox(bm, V((0, 0.138, 1.872)), (0.044, 0.020, 0.032), bevel=0, mat=2)
    return _finish({"Head": bm, "Glow_Head": g}, k=1.42)


# ------------------------------------------------------------------ torso (pre-xscale coords: x is multiplied by WT=1.75 later)
def elite_torso(bm, v):
    div, role = v["div"], v["role"]
    # backpack (all elites)
    pk = {"leader": (0.22, 0.10, 0.34), "assault": (0.26, 0.11, 0.30), "weapons": (0.30, 0.15, 0.40),
          "precision": (0.18, 0.08, 0.26), "support": (0.26, 0.12, 0.34), "defense": (0.30, 0.13, 0.36)}[role]
    rbox(bm, V((0, -0.150, 1.320)), pk, bevel=0.018, mat=3 if div == "spectre" else 1)
    cyl(bm, V((-0.110, -0.158, 1.515)), V((0.110, -0.158, 1.515)), 0.030, segs=8, mat=3)
    if div == "spectre":
        # ODST chest: slab shell + bronze notch + side canisters, high gorget
        arcshell(bm, [ring(1.20, .200, .128, .008), ring(1.32, .212, .136, .010), ring(1.45, .205, .126, .008)],
                 segs=8, a0=-1.15, a1=1.15, th=0.028, mat=1)
        loft(bm, [dict(c=V((0, 0.0, 1.50)), rx=.112, ry=.092), dict(c=V((0, 0.0, 1.575)), rx=.090, ry=.078)],
             segs=10, cap0=False, cap1=False, mat=1)
        rbox(bm, V((0, 0.178, 1.405)), (0.050, 0.010, 0.034), bevel=0, mat=2)                 # bronze notch
        rbox(bm, V((0, 0.178, 1.250)), (0.140, 0.010, 0.018), bevel=0.002, mat=2)
        for sx in (-1, 1):
            cyl(bm, V((sx * 0.100, 0.150, 1.175)), V((sx * 0.100, 0.170, 1.175)), 0.030, segs=8, mat=3)   # chest canisters
            rbox(bm, V((sx * 0.062, 0.150, 1.165)), (0.056, 0.036, 0.076), bevel=0.006, mat=3)
    else:
        # Revenant: sleek plated chest, ivory vane, bronze lines, spine blades
        arcshell(bm, [ring(1.22, .192, .124, .008), ring(1.33, .202, .131, .010), ring(1.44, .196, .121, .008)],
                 segs=8, a0=-0.9, a1=0.9, th=0.020, mat=1)
        rbox(bm, V((0, 0.168, 1.350)), (0.070, 0.026, 0.160), rot=(0.06, 0, 0), bevel=0.008, mat=4)          # ivory vane
        rbox(bm, V((0, 0.182, 1.350)), (0.012, 0.004, 0.140), bevel=0, mat=2)
        for sx in (-1, 1):
            rbox(bm, V((sx * 0.100, 0.158, 1.330)), (0.012, 0.030, 0.210), rot=(0, sx * 0.42, 0), bevel=0, mat=2)
            rbox(bm, V((sx * 0.060, -0.200, 1.420)), (0.010, 0.060, 0.240), rot=(-0.35, 0, sx * 0.20), bevel=0, mat=1)   # spine blades
        loft(bm, [dict(c=V((0, 0.0, 1.50)), rx=.100, ry=.088), dict(c=V((0, 0.0, 1.570)), rx=.080, ry=.074)],
             segs=10, cap0=False, cap1=False, mat=1)
    # ---- role extras
    if role == "leader":
        rbox(bm, V((0.105, -0.17, 1.62)), (0.012, 0.012, 0.32), bevel=0, mat=2)          # command mast
        cyl(bm, V((0.105, -0.17, 1.78)), V((0.105, -0.17, 1.99)), 0.005, segs=5, mat=5)
        rbox(bm, V((0, 0.150, 1.250)), (0.160, 0.030, 0.030), bevel=0.005, mat=2)       # rank sash
    elif role == "assault":
        for sx in (-1, 1):
            cyl(bm, V((sx * 0.100, -0.200, 1.250)), V((sx * 0.100, -0.290, 1.200)), 0.034, segs=8, mat=1)   # mobility nozzles
            cyl(bm, V((sx * 0.100, -0.290, 1.200)), V((sx * 0.100, -0.300, 1.195)), 0.024, segs=8, mat=5)
    elif role == "weapons":
        cyl(bm, V((-0.100, -0.250, 1.380)), V((0.100, -0.250, 1.380)), 0.070, segs=10, mat=3)               # ammo drum
        for sx in (-1, 1):
            rbox(bm, V((sx * 0.215, 0.040, 1.20)), (0.050, 0.100, 0.130), bevel=0, mat=3)
            rbox(bm, V((sx * 0.215, 0.092, 1.20)), (0.040, 0.004, 0.100), bevel=0.001, mat=2)
    elif role == "precision":
        rbox(bm, V((-0.10, 0.110, 1.38)), (0.05, 0.05, 0.10), bevel=0.008, mat=3)                           # drape pouch
        cyl(bm, V((0.105, -0.17, 1.50)), V((0.105, -0.17, 1.96)), 0.005, segs=5, mat=5)
    elif role in ("support", "defense"):
        for sx in (-1, 1):
            rbox(bm, V((sx * 0.120, -0.200, 1.330)), (0.050, 0.090, 0.160), rot=(0, 0, sx * 0.12), bevel=0.006, mat=1)   # emitter pods
            rbox(bm, V((sx * 0.120, -0.246, 1.330)), (0.034, 0.006, 0.100), bevel=0, mat=2)
        if role == "defense":
            rbox(bm, V((0, 0.190, 1.340)), (0.130, 0.020, 0.200), bevel=0.006, mat=1)                       # aegis plate
            rbox(bm, V((0, 0.201, 1.340)), (0.100, 0.003, 0.012), bevel=0, mat=2)
