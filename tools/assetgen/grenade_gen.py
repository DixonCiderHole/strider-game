"""Grenade models (models/grenades.glb), one node per type, each centred on
its own origin, Y up, metres (real hand-grenade sizes, ~9-11 cm tall):

  Frag       ribbed fragmentation shell, fuse head, spoon lever and pin ring
  Flashbang  vented canister with a white charge band
  Smoke      tall canister with a perforated vent crown, teal band
  Stun       arc coil core inside two gimbal rings, blue glow
  Thermal    armoured sphere, raised red charge band and arming panel

python3 grenade_gen.py ../../models/grenades.glb
"""
import sys, math, numpy as np
from meshlib import *
from textures import hull_panels
from reach_gen import add, smooth_normals, flat_normals, outward_from, merge


def solid(profile, seg=28, smooth=True):
    """Lathe around Y, faces out, soft or hard shaded."""
    m = lathe(profile, seg, axis='y', flat=not smooth)
    outward_from(m, lambda f: np.array([0.0, f[1], 0.0]))
    if smooth:
        smooth_normals(m)
    else:
        flat_normals(m)
    return m


def ring(R, r, y=0.0, seg=28, rs=8, tilt=None):
    """Torus of radius R (tube radius r) around Y at height y."""
    prof = [(R + r * math.cos(t), r * math.sin(t)) for t in np.linspace(0, 2 * math.pi, rs + 1)]
    m = lathe(prof, seg, axis='y', flat=True)
    outward_from(m, lambda f: np.array([f[0], 0.0, f[2]]) / max(1e-9, math.hypot(f[0], f[2])) * R)
    smooth_normals(m)
    if tilt is not None:
        m.transform(tilt)
    m.transform(None, (0, y, 0))
    return m


def band(r, h, y):
    return solid([(r * 0.97, y - h / 2), (r, y - h / 2 + h * 0.2), (r, y + h / 2 - h * 0.2), (r * 0.97, y + h / 2)], 32, smooth=False)


def box(sx, sy, sz, c, rot=None):
    b = bevel_box((sx, sy, sz), min(sx, sy, sz) * 0.2)
    if rot is not None:
        b.transform(rot)
    b.transform(None, c)
    flat_normals(b)
    return b


def fuse_head(y0):
    """Fuse cap, spoon lever and pull ring, shared by the canister grenades."""
    parts = {"metal": [], "dark": []}
    parts["dark"].append(solid([(0.0, y0), (0.012, y0), (0.013, y0 + 0.004), (0.013, y0 + 0.012), (0.009, y0 + 0.017), (0.0, y0 + 0.017)], 20, smooth=False))
    # Spoon: a curved strip down one side.
    secs = []
    for i in range(9):
        t = i / 8
        y = y0 + 0.014 - t * 0.05
        x = 0.016 + 0.012 * math.sin(t * math.pi * 0.5) + (0.0 if t < 0.85 else (t - 0.85) * 0.04)
        secs.append(np.array([[x, y, -0.006], [x, y, 0.006], [x + 0.003, y, 0.006], [x + 0.003, y, -0.006]]))
    sp = loft(secs, closed=True)
    flat_normals(sp)
    parts["metal"].append(sp)
    parts["metal"].append(ring(0.008, 0.0013, 0.0, 16, 6, rotz(math.pi / 2)).transform(None, (-0.0175, y0 + 0.008, 0)))
    return parts


def frag():
    p = {"metal": [], "dark": [], "glow": []}
    body = solid([(0.0, -0.046), (0.022, -0.045), (0.032, -0.036), (0.036, -0.018), (0.037, 0.0), (0.035, 0.018),
                  (0.029, 0.033), (0.018, 0.042), (0.011, 0.045), (0.0, 0.045)], 32)
    p["dark"].append(body)
    # Raised fragmentation ribs (horizontal and vertical) over the shell.
    for y in (-0.026, -0.009, 0.009, 0.026):
        r = 0.0365 * math.sqrt(max(0.0, 1.0 - (y / 0.047) ** 2)) + 0.001
        p["dark"].append(ring(r, 0.0018, y, 32, 6))
    for k in range(8):
        a = k * math.pi / 4
        rib = []
        for i in range(10):
            t = -0.04 + i * 0.0085
            rr = 0.0372 * math.sqrt(max(0.05, 1.0 - (t / 0.047) ** 2))
            rib.append((rr * math.cos(a), t, rr * math.sin(a)))
        p["dark"].append(tube(rib, 0.0016, 5))
    p["glow"].append(band(0.0378, 0.003, 0.0))
    fh = fuse_head(0.043)
    p["metal"] += fh["metal"]
    p["dark"] += fh["dark"]
    return p


def flashbang():
    p = {"metal": [], "dark": [], "glow": []}
    h = 0.084
    p["metal"].append(solid([(0.0, -h / 2), (0.022, -h / 2), (0.026, -h / 2 + 0.004), (0.026, h / 2 - 0.004), (0.022, h / 2), (0.0, h / 2)], 32, smooth=False))
    for y in (-0.03, 0.03):
        p["dark"].append(band(0.0272, 0.007, y))
    p["glow"].append(band(0.0268, 0.005, -0.012))
    # Vent slots round the upper body.
    for k in range(8):
        a = k * math.pi / 4 + 0.2
        p["dark"].append(box(0.004, 0.014, 0.008, (math.cos(a) * 0.026, 0.012, math.sin(a) * 0.026), roty(-a)))
    fh = fuse_head(h / 2)
    p["metal"] += fh["metal"]
    p["dark"] += fh["dark"]
    return p


def smoke():
    p = {"metal": [], "dark": [], "glow": []}
    h = 0.1
    p["metal"].append(solid([(0.0, -h / 2), (0.024, -h / 2), (0.028, -h / 2 + 0.005), (0.028, h / 2 - 0.016),
                             (0.024, h / 2 - 0.01), (0.0, h / 2 - 0.01)], 32, smooth=False))
    p["glow"].append(band(0.0285, 0.006, 0.0))
    p["dark"].append(band(0.0287, 0.01, -0.036))
    # Vent crown: a short perforated drum on top.
    p["dark"].append(solid([(0.0, h / 2 - 0.011), (0.02, h / 2 - 0.011), (0.02, h / 2 + 0.002), (0.0, h / 2 + 0.002)], 24, smooth=False))
    for k in range(10):
        a = k * math.pi / 5
        p["metal"].append(cyl(0.0035, 0.004, 8, (0, 0, 0), 'x').transform(roty(-a)).transform(None, (math.cos(a) * 0.0205, h / 2 - 0.004, math.sin(a) * 0.0205)))
    fh = fuse_head(h / 2 + 0.002)
    p["metal"] += fh["metal"]
    p["dark"] += fh["dark"]
    return p


def stun():
    p = {"metal": [], "dark": [], "glow": []}
    core = blob((0.052, 0.052, 0.052), e=1.0, nu=24, nv=16)
    smooth_normals(core)
    p["glow"].append(core)
    # Coil wrapped round the core.
    pts = [(0.027 * math.cos(t * 6), 0.022 * (t / math.pi - 1.0), 0.027 * math.sin(t * 6)) for t in np.linspace(0, 2 * math.pi, 90)]
    p["dark"].append(tube(pts, 0.0022, 6))
    p["metal"].append(ring(0.036, 0.0035, 0.0, 36, 8, rotx(math.pi / 2)))
    p["metal"].append(ring(0.036, 0.0035, 0.0, 36, 8, rotz(math.pi / 2)))
    # Grip cap on top where the rings meet.
    p["dark"].append(solid([(0.0, 0.034), (0.011, 0.034), (0.012, 0.04), (0.008, 0.046), (0.0, 0.046)], 20, smooth=False))
    p["dark"].append(solid([(0.0, -0.046), (0.008, -0.046), (0.012, -0.04), (0.011, -0.034), (0.0, -0.034)], 20, smooth=False))
    return p


def thermal():
    p = {"metal": [], "dark": [], "glow": []}
    sph = blob((0.074, 0.074, 0.074), e=1.0, nu=32, nv=20)
    smooth_normals(sph)
    p["dark"].append(sph)
    # Raised charge band round the equator, glowing seam inside it.
    p["metal"].append(band(0.0385, 0.012, 0.0))
    p["glow"].append(band(0.0392, 0.003, 0.0))
    # Panel seams at the shoulders.
    for y in (-0.024, 0.024):
        p["metal"].append(ring(math.sqrt(0.037 ** 2 - y ** 2) + 0.0005, 0.0012, y, 36, 6))
    # Arming panel with three keys.
    p["metal"].append(box(0.012, 0.022, 0.03, (0.036, 0.0, 0.0)))
    for k, z in enumerate((-0.008, 0.0, 0.008)):
        p["glow"].append(box(0.004, 0.005, 0.005, (0.0425, 0.004 if k == 1 else -0.002, z)))
    # Top trigger knob.
    p["metal"].append(solid([(0.0, 0.035), (0.009, 0.035), (0.009, 0.043), (0.006, 0.046), (0.0, 0.046)], 20, smooth=False))
    return p


def main(path, spread=False):
    g = GLB()
    cnt = [0]
    def _x():
        cnt[0] += 1
        return (cnt[0] - 3) * 0.11
    ha, hn, hm = hull_panels(512, seed=21, base=(0.6, 0.61, 0.63), plate=(64, 32))
    th = (g.image(ha, "metal_a"), g.image(hn, "metal_n"), g.image(hm, "metal_mr"))
    g.material("GunMetal", color=(0.36, 0.37, 0.39, 1), albedo_tex=th[0], normal_tex=th[1], mr_tex=th[2], metal=0.9, rough=0.55)
    g.material("Shell", color=(0.16, 0.18, 0.15, 1), normal_tex=th[1], metal=0.6, rough=0.6)
    g.material("ShellPale", color=(0.72, 0.74, 0.76, 1), albedo_tex=th[0], normal_tex=th[1], mr_tex=th[2], metal=0.5, rough=0.5)
    g.material("ShellGreen", color=(0.34, 0.4, 0.36, 1), albedo_tex=th[0], normal_tex=th[1], mr_tex=th[2], metal=0.4, rough=0.6)
    g.material("GlowOrange", color=(0.3, 0.1, 0.02, 1), emissive=(1.0, 0.45, 0.1), emissive_strength=3.0)
    g.material("GlowWhite", color=(0.6, 0.6, 0.6, 1), emissive=(1.0, 0.97, 0.9), emissive_strength=3.0)
    g.material("GlowTeal", color=(0.05, 0.25, 0.25, 1), emissive=(0.2, 1.0, 0.85), emissive_strength=3.0)
    g.material("GlowBlue", color=(0.2, 0.4, 0.8, 0.9), emissive=(0.35, 0.65, 1.0), emissive_strength=3.5, rough=0.1)
    g.material("GlowRed", color=(0.3, 0.02, 0.02, 1), emissive=(1.0, 0.12, 0.08), emissive_strength=3.5)
    add(g, "Frag", frag(), {"dark": "Shell", "metal": "GunMetal", "glow": "GlowOrange"}, uvs=8.0, translation=(_x(), 0, 0) if spread else None)
    add(g, "Flashbang", flashbang(), {"metal": "ShellPale", "dark": "GunMetal", "glow": "GlowWhite"}, uvs=8.0, translation=(_x(), 0, 0) if spread else None)
    add(g, "Smoke", smoke(), {"metal": "ShellGreen", "dark": "GunMetal", "glow": "GlowTeal"}, uvs=8.0, translation=(_x(), 0, 0) if spread else None)
    add(g, "Stun", stun(), {"glow": "GlowBlue", "dark": "GunMetal", "metal": "ShellPale"}, uvs=8.0, translation=(_x(), 0, 0) if spread else None)
    add(g, "Thermal", thermal(), {"dark": "Shell", "metal": "GunMetal", "glow": "GlowRed"}, uvs=8.0, translation=(_x(), 0, 0) if spread else None)
    g.save(path)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "../../models/grenades.glb")
