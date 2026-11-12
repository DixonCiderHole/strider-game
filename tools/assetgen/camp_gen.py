"""Cave base props + lake dock for Strider (camp_props.glb, dock.glb).
Every prop is its own node, standing on the floor at its origin, front = +Z."""
import math, numpy as np
from meshlib import *
from textures import (hull_panels, grating, fabric, wood_planks, screen, pcb,
                      moss_patch, grass_card)
from building_gen import vcol, _card

R = np.random.default_rng(5)

# ---------------------------------------------------------------- helpers
def sheet(F, nu, nv, uv_scale=(1, 1)):
    """Grid surface F(u, v) -> point, u, v in [0, 1]; smooth normals + UVs."""
    G = np.array([[F(i / nu, j / nv) for i in range(nu + 1)] for j in range(nv + 1)], float)
    Nn = np.zeros_like(G)
    for j in range(nv + 1):
        for i in range(nu + 1):
            du = G[j, min(nu, i + 1)] - G[j, max(0, i - 1)]
            dv = G[min(nv, j + 1), i] - G[max(0, j - 1), i]
            n = np.cross(dv, du); l = np.linalg.norm(n)
            Nn[j, i] = n / l if l > 1e-9 else (0, 1, 0)
    m = Mesh()
    for j in range(nv):
        for i in range(nu):
            a, b, c, d = G[j, i], G[j, i + 1], G[j + 1, i + 1], G[j + 1, i]
            uv = lambda ii, jj: (ii / nu * uv_scale[0], jj / nv * uv_scale[1])
            for tri in ((a, b, c, (i, j), (i + 1, j), (i + 1, j + 1)), (a, c, d, (i, j), (i + 1, j + 1), (i, j + 1))):
                p0, p1, p2, q0, q1, q2 = tri
                n0, n1, n2 = Nn[q0[1], q0[0]], Nn[q1[1], q1[0]], Nn[q2[1], q2[0]]
                if np.dot(np.cross(p1 - p0, p2 - p0), n0 + n1 + n2) < 0:
                    m.P += [p0, p2, p1]; m.N += [n0, n2, n1]; m.UV += [uv(*q0), uv(*q2), uv(*q1)]
                else:
                    m.P += [p0, p1, p2]; m.N += [n0, n1, n2]; m.UV += [uv(*q0), uv(*q1), uv(*q2)]
    return m

def screen_quad(c, w, h, n=(0, 0, 1), up=(0, 1, 0)):
    m = Mesh(); _card(m, c, (w, h), n, up); return m

def bb(size, c, bev=0.02):
    return bevel_box(size, bev, c)

def rot(m, M, t=(0, 0, 0)):
    return m.transform(M, t)

class Prop:
    """Collects parts by material for one node."""
    def __init__(self):
        self.parts = {}
    def add(self, mat, m):
        self.parts.setdefault(mat, Mesh()).extend(m)
        return m

GRIME = {"Panel", "Olive", "White", "DarkMetal", "Steel", "Wood", "Trim", "Grate"}

def emit(g, name, prop, translation=None, uvs=None, seed=0):
    parts = []
    for mat, m in prop.parts.items():
        if not m.P: continue
        P, N = m.arrays()
        col = None
        if mat in GRIME and len(m.UV) != len(m.P):
            col = vcol(P * 2.2, None, seed, N)
            col[:, :3] = 0.55 + col[:, :3] * 0.45     # lighter touch indoors
        parts.append((m, mat, col, (uvs or {}).get(mat, 1.6)))
    return g.mesh_node(name, parts, translation=translation)

def materials(g, small=512):
    pa, pn, pm = hull_panels(1024, seed=31, base=(0.36, 0.37, 0.4), plate=(128, 96))
    g.material("Panel", albedo_tex=g.image(pa, "panel_a"), normal_tex=g.image(pn, "panel_n"), mr_tex=g.image(pm, "panel_mr"), metal=0.8, rough=1.0)
    oa, on, om = hull_panels(1024, seed=32, base=(0.3, 0.33, 0.24), plate=(128, 192))
    g.material("Olive", albedo_tex=g.image(oa, "olive_a"), normal_tex=g.image(on, "olive_n"), mr_tex=g.image(om, "olive_mr"), metal=0.6, rough=1.0)
    wa, wn, wm = hull_panels(1024, seed=33, base=(0.84, 0.85, 0.86), plate=(96, 128))
    g.material("White", albedo_tex=g.image(wa, "white_a"), normal_tex=g.image(wn, "white_n"), mr_tex=g.image(wm, "white_mr"), metal=0.2, rough=0.9)
    g.material("DarkMetal", color=(0.16, 0.17, 0.19, 1), albedo_tex=g.image(pa, "dm_a") if False else 0, normal_tex=1, mr_tex=2, metal=1.0, rough=0.8)
    g.material("Steel", color=(0.62, 0.63, 0.66, 1), normal_tex=1, metal=1.0, rough=0.38)
    g.material("Trim", color=(0.85, 0.6, 0.15, 1), albedo_tex=0, normal_tex=1, mr_tex=2, metal=0.4, rough=0.9)
    ga, gn, gm = grating(512)
    g.material("Grate", albedo_tex=g.image(ga, "grate_a"), normal_tex=g.image(gn, "grate_n"), mr_tex=g.image(gm, "grate_mr"), metal=1.0, rough=1.0)
    da, dn, dm = wood_planks(1024, seed=34, base=(0.45, 0.31, 0.19), weather=0.25)
    g.material("Wood", albedo_tex=g.image(da, "wood_a"), normal_tex=g.image(dn, "wood_n"), mr_tex=g.image(dm, "wood_mr"), rough=1.0)
    for name, col, quilt, stripe, seed in [("Mattress", (0.2, 0.26, 0.32), 64, None, 35), ("Blanket", (0.36, 0.33, 0.27), 0, (0.55, 0.14, 0.1), 36),
                                           ("Pillow", (0.78, 0.77, 0.72), 0, None, 37), ("Rug", (0.3, 0.2, 0.15), 0, (0.6, 0.45, 0.2), 38),
                                           ("Leather", (0.3, 0.17, 0.1), 0, None, 39)]:
        a, n, mr = fabric(small, seed=seed, color=col, quilt=quilt, stripe=stripe)
        g.material(name, albedo_tex=g.image(a, name + "_a"), normal_tex=g.image(n, name + "_n"), mr_tex=g.image(mr, name + "_mr"), rough=1.0, double=True)
    for si, (kind, tint) in enumerate([("data", (0.35, 0.85, 1.0)), ("med", (0.4, 1.0, 0.75)), ("droid", (0.35, 0.8, 1.0)), ("map", (1.0, 0.75, 0.35))]):
        a, e = screen(512, seed=50 + si, tint=tint, kind=kind)
        g.material("Screen_" + kind, albedo_tex=g.image(a, kind + "_a"), emissive_tex=g.image(e, kind + "_e"),
                   emissive=(1, 1, 1), emissive_strength=2.2, rough=0.2)
    pa2, pn2, pm2 = pcb(512)
    g.material("PCB", albedo_tex=g.image(pa2, "pcb_a"), normal_tex=g.image(pn2, "pcb_n"), mr_tex=g.image(pm2, "pcb_mr"), rough=1.0, metal=1.0)
    g.material("Glass", color=(0.5, 0.7, 0.75, 0.3), metal=0.0, rough=0.05, blend=True, double=True)
    g.material("Rubber", color=(0.05, 0.05, 0.055, 1), rough=0.85)
    g.material("Cable", color=(0.07, 0.07, 0.08, 1), rough=0.6)
    g.material("Red", color=(0.6, 0.05, 0.04, 1), emissive=(1.0, 0.1, 0.05), emissive_strength=1.2)
    g.material("RedPaint", color=(0.55, 0.06, 0.05, 1), rough=0.6)
    for name, c, s in [("Cyan", (0.35, 0.85, 1.0), 3.0), ("Green", (0.35, 1.0, 0.45), 2.5), ("Amber", (1.0, 0.6, 0.15), 3.0),
                       ("Warm", (1.0, 0.85, 0.6), 4.0), ("Core", (0.3, 0.75, 1.0), 4.5)]:
        g.material(name, color=(c[0] * 0.3, c[1] * 0.3, c[2] * 0.3, 1), emissive=c, emissive_strength=s)
    ma, mn = moss_patch(512, seed=40)
    g.material("Moss", albedo_tex=g.image(ma, "moss_a"), normal_tex=g.image(mn, "moss_n"), rough=0.95, mask=True)
    g.material("Grass", albedo_tex=g.image(grass_card(512, seed=41), "grass_a"), rough=0.85, mask=True, cutoff=0.4, double=True)
    g.material("Rope", color=(0.62, 0.52, 0.36, 1), albedo_tex=g.image(fabric(256, seed=42, color=(0.8, 0.75, 0.6), quilt=0)[0], "rope_a"), rough=1.0)

# ---------------------------------------------------------------- props
def bed():
    p = Prop()
    L, W = 2.08, 0.96
    for sx in (-1, 1):
        p.add("Panel", bb((0.07, 0.1, L), (sx * W / 2, 0.36, 0), 0.02))
        for sz in (-1, 1):
            p.add("DarkMetal", bb((0.07, 0.34, 0.07), (sx * (W / 2 - 0.02), 0.17, sz * (L / 2 - 0.08)), 0.015))
            p.add("Rubber", cyl(0.05, 0.03, 12, (sx * (W / 2 - 0.02), 0.015, sz * (L / 2 - 0.08))))
        p.add("DarkMetal", rot(bb((0.04, 0.04, L * 0.8), (0, 0, 0), 0.01), rotx(0.0), (sx * (W / 2 - 0.02), 0.14, 0)))
    for k in range(9):
        p.add("Steel", bb((W - 0.08, 0.025, 0.06), (0, 0.39, -L / 2 + 0.15 + k * (L - 0.3) / 8), 0.008))
    # head unit: padded board, cubby, reading light, status LED
    p.add("Panel", bb((W + 0.1, 0.62, 0.09), (0, 0.66, -L / 2 - 0.02), 0.03))
    p.add("Trim", bb((W + 0.12, 0.05, 0.1), (0, 0.98, -L / 2 - 0.02), 0.015))
    p.add("Mattress", blob((W - 0.2, 0.3, 0.06), 0.3, 16, 8, (0, 0.72, -L / 2 + 0.05)))
    p.add("DarkMetal", bb((0.22, 0.14, 0.12), (W / 2 - 0.16, 0.86, -L / 2 + 0.06), 0.02))
    p.add("Warm", bb((0.16, 0.02, 0.06), (W / 2 - 0.16, 0.79, -L / 2 + 0.07), 0.005))
    p.add("Green", bb((0.03, 0.03, 0.01), (-W / 2 + 0.12, 0.88, -L / 2 + 0.03), 0.004))
    p.add("Panel", bb((W + 0.1, 0.22, 0.06), (0, 0.5, L / 2 + 0.02), 0.02))
    # mattress, pillow, blanket + turned-down sheet
    p.add("Mattress", blob((W - 0.04, 0.17, L - 0.06), 0.18, 32, 10, (0, 0.495, 0)))
    pil = blob((0.62, 0.15, 0.36), 0.5, 24, 10, squash=lambda x, z: -0.25 * (1 - x * x) * (1 - z * z))
    p.add("Pillow", rot(pil, roty(0.06) @ rotz(0.03), (0.02, 0.645, -L / 2 + 0.3)))
    top = 0.585; half = W / 2 - 0.02
    def blanket(u, v):
        t = u * 2 - 1
        z = -0.25 + v * (L / 2 + 0.25 + 0.04)
        wr = 0.006 * math.sin(z * 23 + t * 3) + 0.01 * math.sin(z * 7.0 + 1.3) * (1 - abs(t))
        if abs(t) < 0.78:
            x = t / 0.78 * half; y = top + 0.012 + wr
        else:
            k = (abs(t) - 0.78) / 0.22
            x = math.copysign(half + 0.03 + 0.01 * k, t); y = top + 0.01 - k * 0.27 + 0.01 * math.sin(z * 17)
        if v > 0.93:   # over the foot end
            k = (v - 0.93) / 0.07
            z = L / 2 - 0.02 + 0.02 * k; y = min(y, top + 0.01 - k * 0.2)
        return (x, y, z)
    p.add("Blanket", sheet(blanket, 28, 40, (1.6, 2.0)))
    def fold(u, v):
        t = u * 2 - 1
        x = t * (half + 0.035)
        z = -0.4 + v * 0.17
        y = top + 0.03 + 0.012 * math.sin(v * math.pi) - (0.0 if abs(t) < 0.9 else (abs(t) - 0.9) * 1.5)
        return (x, y, z)
    p.add("Pillow", sheet(fold, 20, 4, (1.6, 0.3)))
    return p

def armory_locker():
    p = Prop()
    W, H, D = 1.24, 2.06, 0.62
    p.add("DarkMetal", bb((W + 0.04, 0.08, D + 0.04), (0, 0.04, 0), 0.02))
    # carcass (open front box)
    p.add("Olive", bb((W, H - 0.08, 0.05), (0, H / 2 + 0.04, -D / 2 + 0.025), 0.01))
    for sx in (-1, 1):
        p.add("Olive", bb((0.05, H - 0.08, D), (sx * (W / 2 - 0.025), H / 2 + 0.04, 0), 0.015))
    p.add("Olive", bb((W, 0.06, D), (0, H - 0.03, 0), 0.015))
    p.add("Olive", bb((W, 0.05, D), (0, 0.105, 0), 0.01))
    p.add("Trim", bb((W + 0.06, 0.07, D + 0.06), (0, H + 0.02, 0), 0.02))
    p.add("DarkMetal", bb((0.03, H - 0.2, D - 0.06), (0, H / 2, 0), 0.008))     # divider
    # left bay: rifle rack behind a glazed door
    p.add("DarkMetal", bb((W / 2 - 0.08, 0.04, D - 0.1), (-W / 4, 0.5, -0.02), 0.01))
    p.add("DarkMetal", bb((W / 2 - 0.08, 0.06, 0.08), (-W / 4, 1.55, -D / 2 + 0.1), 0.01))
    for k in range(3):
        x = -W / 2 + 0.16 + k * 0.15
        r = Prop()
        r.add("DarkMetal", bb((0.05, 0.26, 0.11), (0, 0.13, 0), 0.015))        # stock
        r.add("Panel", bb((0.06, 0.48, 0.1), (0, 0.5, 0), 0.015))              # receiver
        r.add("DarkMetal", bb((0.04, 0.12, 0.1), (0, 0.42, 0.06), 0.01))       # magazine
        r.add("Steel", cyl(0.016, 0.42, 10, (0, 0.94, -0.01)))                 # barrel
        r.add("DarkMetal", cyl(0.028, 0.18, 10, (0, 0.62, -0.06)))              # scope
        r.add("Red", bb((0.062, 0.03, 0.02), (0, 0.55, 0.05), 0.004))
        for mat, m in r.parts.items():
            p.add(mat, m.transform(rotx(-0.08), (x, 0.56, -0.08)))
    for k in range(2):   # ammo cans on the floor of the bay
        p.add("Olive", bb((0.24, 0.16, 0.3), (-W / 4 + (k - 0.5) * 0.26, 0.21, 0.02), 0.02))
        p.add("Trim", bb((0.245, 0.03, 0.305), (-W / 4 + (k - 0.5) * 0.26, 0.24, 0.02), 0.005))
    # glazed door (frame + glass + mesh)
    dz = D / 2 + 0.02; dx = -W / 4
    for (sx, sy, cx, cy) in [(W / 2 - 0.04, 0.08, dx, 0.18), (W / 2 - 0.04, 0.08, dx, H - 0.12), (0.07, H - 0.3, -W / 2 + 0.055, H / 2 + 0.03), (0.07, H - 0.3, -0.055, H / 2 + 0.03)]:
        p.add("Olive", bb((sx, sy, 0.04), (cx, cy, dz), 0.012))
    p.add("Glass", screen_quad((dx, H / 2 + 0.03, dz - 0.005), W / 2 - 0.16, H - 0.36))
    for k in range(9):
        p.add("DarkMetal", bb((W / 2 - 0.16, 0.008, 0.008), (dx, 0.32 + k * 0.18, dz + 0.01), 0.002))
    # solid door with vents, keypad, hazard band
    dx = W / 4
    p.add("Olive", bb((W / 2 - 0.04, H - 0.18, 0.04), (dx, H / 2 + 0.03, dz), 0.015))
    for k in range(6):
        p.add("DarkMetal", bb((0.36, 0.02, 0.02), (dx, 0.3 + k * 0.05, dz + 0.02), 0.004))
    p.add("Trim", bb((W / 2 - 0.05, 0.07, 0.045), (dx, 1.3, dz + 0.003), 0.008))
    for k in range(5):
        p.add("DarkMetal", rot(bb((0.03, 0.08, 0.01), (0, 0, 0), 0.002), rotz(0.6), (dx - 0.22 + k * 0.11, 1.3, dz + 0.027)))
    p.add("DarkMetal", bb((0.12, 0.18, 0.03), (0.08, 1.05, dz + 0.03), 0.01))
    p.add("Red", bb((0.07, 0.03, 0.01), (0.08, 1.11, dz + 0.047), 0.004))
    for k in range(6):
        p.add("Steel", bb((0.025, 0.02, 0.008), (0.06 + (k % 3) * 0.02 - 0.0, 1.02 - (k // 3) * 0.035, dz + 0.047), 0.003))
    p.add("Steel", bb((0.03, 0.22, 0.04), (0.05, 0.85, dz + 0.04), 0.01))
    p.add("Steel", bb((0.03, 0.22, 0.04), (-0.05, 0.85, dz + 0.04), 0.01))
    # beacon
    p.add("DarkMetal", cyl(0.07, 0.04, 16, (W / 2 - 0.15, H + 0.075, 0)))
    p.add("Amber", cyl(0.05, 0.06, 16, (W / 2 - 0.15, H + 0.125, 0), r2=0.035))
    return p

def med_bench():
    p = Prop()
    W, D, Ht = 1.62, 0.66, 0.86
    p.add("White", bb((W, Ht - 0.1, D), (0, (Ht - 0.1) / 2 + 0.06, 0), 0.03))
    p.add("DarkMetal", bb((W - 0.06, 0.06, D - 0.06), (0, 0.03, 0), 0.01))
    p.add("Panel", bb((W + 0.05, 0.05, D + 0.05), (0, Ht - 0.02, 0), 0.015))
    for c in range(3):    # drawer fronts
        for r in range(3 if c != 1 else 1):
            hh = (Ht - 0.22) / (3 if c != 1 else 1)
            cx = -W / 3 + c * W / 3; cy = 0.14 + hh * (r + 0.5)
            p.add("White", bb((W / 3 - 0.05, hh - 0.04, 0.03), (cx, cy, D / 2 + 0.012), 0.012))
            p.add("Steel", bb((0.18, 0.025, 0.03), (cx, cy + hh / 2 - 0.07, D / 2 + 0.035), 0.008))
    p.add("Red", bb((0.06, 0.18, 0.02), (0, 0.5, D / 2 + 0.03), 0.005))
    p.add("Red", bb((0.18, 0.06, 0.02), (0, 0.5, D / 2 + 0.03), 0.005))
    # back panel with screen, emblem and vial shelf
    bz = -D / 2 + 0.04
    p.add("White", bb((W, 1.0, 0.08), (0, Ht + 0.5, bz), 0.03))
    p.add("DarkMetal", bb((0.78, 0.5, 0.03), (-0.32, Ht + 0.55, bz + 0.05), 0.01))
    p.add("Screen_med", screen_quad((-0.32, Ht + 0.55, bz + 0.067), 0.72, 0.44))
    p.add("RedPaint", bb((0.06, 0.2, 0.01), (0.55, Ht + 0.8, bz + 0.045), 0.003))
    p.add("RedPaint", bb((0.2, 0.06, 0.01), (0.55, Ht + 0.8, bz + 0.045), 0.003))
    p.add("Panel", bb((0.6, 0.03, 0.16), (0.42, Ht + 0.42, bz + 0.1), 0.008))
    for k in range(6):
        x = 0.18 + k * 0.095
        p.add("Glass", cyl(0.028, 0.12, 12, (x, Ht + 0.5, bz + 0.1)))
        p.add(["Cyan", "Red", "Green"][k % 3], cyl(0.022, 0.07 + 0.02 * (k % 2), 12, (x, Ht + 0.475 + 0.01 * (k % 2), bz + 0.1)))
        p.add("Steel", cyl(0.03, 0.02, 12, (x, Ht + 0.57, bz + 0.1)))
    # articulated scanner arm
    p.add("Steel", tube([(-0.7, Ht + 1.0, bz), (-0.7, Ht + 1.15, bz + 0.05), (-0.62, Ht + 1.22, bz + 0.25), (-0.5, Ht + 1.1, bz + 0.5)], 0.03, 10))
    p.add("DarkMetal", blob((0.09, 0.09, 0.09), 0.6, 12, 8, (-0.7, Ht + 1.0, bz)))
    p.add("White", bb((0.32, 0.08, 0.2), (-0.5, Ht + 1.06, bz + 0.52), 0.03))
    p.add("Green", bb((0.24, 0.01, 0.12), (-0.5, Ht + 1.017, bz + 0.52), 0.004))
    # medkit case and stims on the worktop
    p.add("White", bb((0.42, 0.14, 0.28), (0.35, Ht + 0.07, 0.08), 0.03))
    p.add("RedPaint", bb((0.05, 0.005, 0.15), (0.35, Ht + 0.143, 0.08), 0.002))
    p.add("RedPaint", bb((0.15, 0.005, 0.05), (0.35, Ht + 0.143, 0.08), 0.002))
    p.add("DarkMetal", bb((0.1, 0.03, 0.04), (0.35, Ht + 0.08, 0.23), 0.01))
    for k in range(3):
        st = cyl(0.015, 0.14, 10, (0, 0, 0), axis='x')
        p.add("Steel", st.transform(roty(0.3 + k * 0.2), (-0.05 + k * 0.06, Ht + 0.015, 0.18 - k * 0.03)))
        p.add("Green", cyl(0.012, 0.04, 8, (0, 0, 0), axis='x').transform(roty(0.3 + k * 0.2), (-0.05 + k * 0.06, Ht + 0.015, 0.18 - k * 0.03)))
    p.add("Green", bb((0.04, 0.04, 0.01), (W / 2 - 0.1, Ht + 0.92, bz + 0.045), 0.005))
    return p

def droid_bench():
    p = Prop()
    W, D, Ht = 1.9, 0.82, 0.9
    p.add("Grate", bb((W, 0.06, D), (0, Ht - 0.03, 0), 0.015))
    p.add("Trim", bb((W + 0.02, 0.05, 0.05), (0, Ht - 0.04, D / 2), 0.01))
    p.add("Cyan", bb((W - 0.2, 0.012, 0.02), (0, Ht - 0.075, D / 2 - 0.02), 0.004))
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.add("DarkMetal", bb((0.07, Ht - 0.06, 0.07), (sx * (W / 2 - 0.06), (Ht - 0.06) / 2, sz * (D / 2 - 0.06)), 0.015))
    p.add("Panel", bb((W - 0.1, 0.04, D - 0.1), (0, 0.25, 0), 0.01))
    # parts bins on the lower shelf
    for k in range(3):
        x = -0.6 + k * 0.55
        p.add("Olive", bb((0.45, 0.2, 0.5), (x, 0.37, 0), 0.02))
        p.add(["Steel", "PCB", "Cable"][k], bb((0.38, 0.03, 0.42), (x, 0.45, 0), 0.01))
    # pegboard + tools
    bz = -D / 2 + 0.02
    p.add("Grate", bb((W, 1.05, 0.04), (0, Ht + 0.55, bz), 0.01))
    for sx in (-1, 1):
        p.add("DarkMetal", bb((0.06, 1.1, 0.06), (sx * (W / 2 - 0.03), Ht + 0.55, bz), 0.015))
    for k in range(4):   # wrenches
        w = Mesh()
        w.extend(bb((0.022, 0.24 + k * 0.03, 0.01), (0, 0, 0), 0.004))
        w.extend(hull_of([(-0.04, 0.12 + k * 0.015, -0.005), (0.04, 0.12 + k * 0.015, -0.005), (-0.035, 0.17 + k * 0.015, -0.005), (0.035, 0.17 + k * 0.015, -0.005),
                          (-0.04, 0.12 + k * 0.015, 0.005), (0.04, 0.12 + k * 0.015, 0.005), (-0.035, 0.17 + k * 0.015, 0.005), (0.035, 0.17 + k * 0.015, 0.005)]))
        p.add("Steel", w.transform(None, (-0.85 + k * 0.08, Ht + 0.6, bz + 0.03)))
    for k in range(5):   # drivers
        p.add("Steel", cyl(0.006, 0.12, 8, (-0.4 + k * 0.05, Ht + 0.55, bz + 0.035)))
        p.add(["RedPaint", "Trim", "Olive", "RedPaint", "Rubber"][k], cyl(0.016, 0.1, 10, (-0.4 + k * 0.05, Ht + 0.66, bz + 0.035)))
    p.add("DarkMetal", bb((0.6, 0.38, 0.05), (0.5, Ht + 0.72, bz + 0.05), 0.015))
    p.add("Screen_droid", screen_quad((0.5, Ht + 0.72, bz + 0.077), 0.54, 0.33))
    # droid head being repaired
    hx, hz = -0.35, 0.05
    p.add("Panel", blob((0.36, 0.28, 0.32), 0.55, 24, 12, (hx, Ht + 0.15, hz)))
    p.add("DarkMetal", blob((0.24, 0.1, 0.06), 0.4, 16, 8, (hx, Ht + 0.17, hz + 0.15)))
    p.add("Cyan", blob((0.07, 0.07, 0.03), 0.6, 12, 8, (hx + 0.05, Ht + 0.17, hz + 0.18)))
    p.add("Steel", cyl(0.006, 0.18, 6, (hx - 0.1, Ht + 0.36, hz - 0.05)))
    p.add("Red", cyl(0.014, 0.02, 8, (hx - 0.1, Ht + 0.455, hz - 0.05)))
    p.add("Panel", bb((0.13, 0.04, 0.13), (hx + 0.25, Ht + 0.02, hz + 0.12), 0.01))   # removed panel
    p.add("Cable", tube([(hx + 0.1, Ht + 0.1, hz - 0.1), (hx + 0.3, Ht + 0.02, hz - 0.2), (hx + 0.55, Ht + 0.02, hz - 0.15), (0.45, Ht + 0.45, bz + 0.05)], 0.01, 6))
    p.add("RedPaint", tube([(hx + 0.12, Ht + 0.12, hz - 0.08), (hx + 0.35, Ht + 0.015, hz + 0.0), (hx + 0.5, Ht + 0.015, hz + 0.25)], 0.008, 6))
    # a manipulator arm laid out in pieces
    ax, az = 0.45, 0.12
    segs = [((ax - 0.25, 0, az), (ax - 0.02, 0, az + 0.05)), ((ax + 0.02, 0, az + 0.06), (ax + 0.28, 0, az + 0.18))]
    for a, b in segs:
        a = np.array(a) + (0, Ht + 0.04, 0); b = np.array(b) + (0, Ht + 0.04, 0)
        p.add("Panel", tube([a, b], 0.035, 12))
        p.add("DarkMetal", blob((0.08, 0.08, 0.08), 0.6, 12, 8, tuple(a)))
    p.add("DarkMetal", blob((0.09, 0.09, 0.09), 0.6, 12, 8, (ax + 0.29, Ht + 0.04, az + 0.19)))
    for k in range(3):
        p.add("Steel", rot(bb((0.1, 0.012, 0.02), (0, 0, 0), 0.004), roty(0.4 - k * 0.4), (ax + 0.37 + 0.02 * k, Ht + 0.04, az + 0.2 + (k - 1) * 0.03)))
    # circuit boards, a wheel, magnifier lamp
    for k in range(3):
        p.add("PCB", rot(bb((0.22, 0.012, 0.16), (0, 0, 0), 0.003), roty(0.2 * k - 0.2), (0.05 + k * 0.03, Ht + 0.006 + k * 0.012, 0.25 - k * 0.04)))
    wheel = lathe([(0.0, -0.035), (0.11, -0.035), (0.13, -0.02), (0.13, 0.02), (0.11, 0.035), (0.0, 0.035)], 24, axis='y')
    p.add("Rubber", wheel.transform(None, (0.8, Ht + 0.035, 0.2)))
    p.add("Steel", cyl(0.05, 0.075, 16, (0.8, Ht + 0.04, 0.2), axis='y'))
    p.add("DarkMetal", cyl(0.08, 0.03, 16, (-0.8, Ht + 0.015, -0.15)))
    p.add("Steel", tube([(-0.8, Ht + 0.03, -0.15), (-0.8, Ht + 0.4, -0.15), (-0.7, Ht + 0.55, 0.0), (-0.62, Ht + 0.5, 0.12)], 0.012, 8))
    p.add("DarkMetal", cyl(0.07, 0.03, 20, (-0.62, Ht + 0.48, 0.14)))
    p.add("Warm", cyl(0.06, 0.005, 20, (-0.62, Ht + 0.463, 0.14)))
    return p

def craft_bench(level):
    p = Prop()
    if level == 0:   # materials stacked ready
        for i in range(5):
            p.add("Wood", rot(bb((1.4, 0.05, 0.18), (0, 0, 0), 0.01), roty(R.uniform(-0.15, 0.15)), (R.uniform(-0.05, 0.05), 0.03 + i * 0.052, -0.3 + (i % 3) * 0.22)))
        for k in range(6):
            p.add("Panel", rot(bb((R.uniform(0.15, 0.35), 0.02, R.uniform(0.1, 0.25)), (0, 0, 0), 0.005), rotx(R.uniform(-0.3, 0.3)) @ roty(R.uniform(0, 3)), (0.45 + R.normal(0, 0.12), 0.05, 0.35 + R.normal(0, 0.1))))
        return p
    W, D, Ht = 1.8, 0.8, 0.9
    top = "Wood" if level == 1 else "Grate"
    p.add(top, bb((W, 0.07, D), (0, Ht - 0.035, 0), 0.015))
    p.add("Trim", bb((W + 0.02, 0.04, 0.05), (0, Ht - 0.05, D / 2), 0.01))
    for sx in (-1, 1):   # A-frame trestles
        for sz in (-1, 1):
            leg = hull_of([(sx * (W / 2 - 0.12), 0, sz * (D / 2 - 0.02)), (sx * (W / 2 - 0.06), 0, sz * (D / 2 - 0.02)),
                           (sx * (W / 2 - 0.12), Ht - 0.07, sz * (D / 2 - 0.15)), (sx * (W / 2 - 0.06), Ht - 0.07, sz * (D / 2 - 0.15)),
                           (sx * (W / 2 - 0.12), 0, sz * (D / 2 - 0.08)), (sx * (W / 2 - 0.06), 0, sz * (D / 2 - 0.08)),
                           (sx * (W / 2 - 0.12), Ht - 0.07, sz * (D / 2 - 0.21)), (sx * (W / 2 - 0.06), Ht - 0.07, sz * (D / 2 - 0.21))])
            p.add("DarkMetal", leg)
        p.add("DarkMetal", bb((0.06, 0.05, D - 0.2), (sx * (W / 2 - 0.09), 0.3, 0), 0.01))
    p.add("Wood" if level == 1 else "Panel", bb((W - 0.24, 0.03, D - 0.25), (0, 0.32, 0), 0.008))
    # vise
    p.add("DarkMetal", bb((0.2, 0.12, 0.18), (-0.65, Ht + 0.06, 0.25), 0.02))
    p.add("Steel", bb((0.22, 0.08, 0.04), (-0.65, Ht + 0.15, 0.17), 0.01))
    p.add("Steel", bb((0.22, 0.08, 0.04), (-0.65, Ht + 0.15, 0.3), 0.01))
    p.add("Steel", cyl(0.012, 0.3, 8, (-0.65, Ht + 0.1, 0.42), axis='z'))
    # hand tools, scrap
    p.add("Steel", rot(bb((0.03, 0.02, 0.26), (0, 0, 0), 0.005), roty(0.5), (-0.2, Ht + 0.01, 0.15)))
    p.add("Wood", rot(cyl(0.02, 0.12, 8, (0, 0, 0), axis='z'), roty(0.5), (-0.27, Ht + 0.02, 0.27)))
    p.add("DarkMetal", rot(bb((0.1, 0.05, 0.04), (0, 0, 0), 0.01), roty(0.5), (-0.13, Ht + 0.025, 0.03)))
    for k in range(4):
        p.add("Panel", rot(bb((R.uniform(0.1, 0.25), 0.015, R.uniform(0.08, 0.2)), (0, 0, 0), 0.004), roty(R.uniform(0, 3)), (0.1 + k * 0.12, Ht + 0.01 + k * 0.004, -0.2 + R.normal(0, 0.05))))
    if level >= 2:   # bench fabricator, power cell, task light
        p.add("Panel", bb((0.5, 0.45, 0.45), (0.55, Ht + 0.225, -0.12), 0.04))
        p.add("DarkMetal", bb((0.36, 0.2, 0.05), (0.55, Ht + 0.2, 0.11), 0.015))
        p.add("Cyan", bb((0.3, 0.012, 0.012), (0.55, Ht + 0.32, 0.12), 0.003))
        p.add("Screen_data", screen_quad((0.55, Ht + 0.37, 0.104), 0.3, 0.12))
        p.add("Trim", bb((0.52, 0.04, 0.47), (0.55, Ht + 0.47, -0.12), 0.01))
        p.add("DarkMetal", cyl(0.09, 0.03, 16, (0.05, Ht + 0.015, -0.22)))
        p.add("Glass", cyl(0.07, 0.2, 16, (0.05, Ht + 0.13, -0.22)))
        p.add("Core", cyl(0.045, 0.18, 12, (0.05, Ht + 0.13, -0.22)))
        p.add("DarkMetal", cyl(0.09, 0.03, 16, (0.05, Ht + 0.245, -0.22)))
        p.add("Steel", tube([(-0.8, Ht, -0.3), (-0.8, Ht + 0.7, -0.3), (-0.6, Ht + 0.8, -0.1)], 0.015, 8))
        p.add("DarkMetal", bb((0.25, 0.06, 0.12), (-0.55, Ht + 0.78, -0.08), 0.02))
        p.add("Warm", bb((0.2, 0.01, 0.08), (-0.55, Ht + 0.745, -0.08), 0.003))
    return p

def generator():
    p = Prop()
    p.add("DarkMetal", bb((1.1, 0.12, 0.8), (0, 0.06, 0), 0.02))
    p.add("Olive", bb((1.0, 0.7, 0.7), (0, 0.47, 0), 0.05))
    for k in range(9):   # radiator fins
        p.add("DarkMetal", bb((0.02, 0.5, 0.74), (-0.4 + k * 0.1, 0.47, 0), 0.004))
    p.add("Panel", cyl(0.2, 0.55, 24, (0, 1.05, 0)))
    p.add("Glass", cyl(0.17, 0.4, 24, (0, 1.05, 0.0)))
    p.add("Core", cyl(0.08, 0.38, 16, (0, 1.05, 0)))
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        p.add("Panel", bb((0.04, 0.42, 0.04), (math.cos(a) * 0.19, 1.05, math.sin(a) * 0.19), 0.01))
    p.add("Panel", cyl(0.23, 0.06, 24, (0, 1.34, 0)))
    p.add("Panel", cyl(0.23, 0.06, 24, (0, 0.8, 0)))
    p.add("DarkMetal", bb((0.3, 0.25, 0.06), (0.3, 0.55, 0.37), 0.02))
    p.add("Screen_data", screen_quad((0.3, 0.58, 0.402), 0.24, 0.14))
    p.add("Green", bb((0.03, 0.03, 0.01), (0.2, 0.45, 0.405), 0.004))
    p.add("Amber", bb((0.03, 0.03, 0.01), (0.25, 0.45, 0.405), 0.004))
    p.add("Trim", bb((1.02, 0.06, 0.72), (0, 0.15, 0), 0.01))
    p.add("Cable", tube([(-0.5, 0.3, 0.1), (-0.65, 0.05, 0.2), (-1.2, 0.02, 0.5), (-2.0, 0.02, 0.6)], 0.03, 8))
    p.add("Cable", tube([(-0.5, 0.35, -0.1), (-0.7, 0.04, -0.2), (-1.4, 0.02, -0.5)], 0.025, 8))
    return p

def work_lamp():
    p = Prop()
    for k in range(3):
        a = k * 2 * math.pi / 3
        p.add("DarkMetal", tube([(math.cos(a) * 0.45, 0.0, math.sin(a) * 0.45), (math.cos(a) * 0.05, 0.9, math.sin(a) * 0.05)], 0.018, 8))
        p.add("Rubber", cyl(0.03, 0.03, 8, (math.cos(a) * 0.45, 0.015, math.sin(a) * 0.45)))
    p.add("Steel", cyl(0.022, 1.0, 10, (0, 1.35, 0)))
    p.add("Trim", cyl(0.04, 0.08, 12, (0, 0.9, 0)))
    head = Prop()
    head.add("DarkMetal", bb((0.36, 0.24, 0.14), (0, 0, 0), 0.03))
    head.add("Warm", screen_quad((0, 0, 0.072), 0.3, 0.18))
    for k in range(4):
        head.add("DarkMetal", bb((0.36, 0.01, 0.02), (0, -0.09 + k * 0.06, 0.08), 0.003))
    head.add("Steel", bb((0.42, 0.04, 0.04), (0, -0.16, -0.02), 0.01))
    for mat, m in head.parts.items():
        p.add(mat, m.transform(rotx(0.45), (0, 1.9, 0.02)))
    p.add("Cable", tube([(0, 1.8, -0.05), (0.03, 1.2, -0.06), (0.05, 0.6, -0.1), (0.2, 0.02, -0.4), (0.6, 0.02, -0.8)], 0.012, 6))
    return p

def shelf():
    p = Prop()
    W, D, H = 1.2, 0.45, 1.85
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.add("DarkMetal", bb((0.04, H, 0.04), (sx * (W / 2 - 0.02), H / 2, sz * (D / 2 - 0.02)), 0.008))
    levels = [0.12, 0.6, 1.08, 1.56]
    for y in levels:
        p.add("Grate", bb((W, 0.03, D), (0, y, 0), 0.006))
        p.add("Trim", bb((W, 0.04, 0.02), (0, y, D / 2), 0.005))
    for li, y in enumerate(levels):
        x = -W / 2 + 0.08
        while x < W / 2 - 0.15:
            kind = R.integers(4)
            if kind == 0:
                w = R.uniform(0.2, 0.32); h = R.uniform(0.14, 0.3)
                p.add(R.choice(["Olive", "Panel", "White"]), bb((w, h, D * 0.7), (x + w / 2, y + 0.015 + h / 2, 0), 0.02)); x += w + 0.03
            elif kind == 1:
                r = R.uniform(0.05, 0.08); h = R.uniform(0.15, 0.3)
                p.add(R.choice(["Steel", "RedPaint", "Olive"]), cyl(r, h, 14, (x + r, y + 0.015 + h / 2, R.uniform(-0.08, 0.08))))
                p.add("DarkMetal", cyl(r * 0.6, 0.03, 10, (x + r, y + 0.03 + h, 0))); x += 2 * r + 0.03
            elif kind == 2:
                for k in range(3):
                    p.add("Trim" if k % 2 else "Olive", bb((0.16, 0.05, 0.11), (x + 0.08, y + 0.04 + k * 0.05, 0.05), 0.01))
                x += 0.2
            else:
                p.add("Rope", lathe([(0.06, -0.04), (0.12, -0.05), (0.13, 0.0), (0.12, 0.05), (0.06, 0.04), (0.05, 0.0), (0.06, -0.04)], 20, axis='y').transform(None, (x + 0.13, y + 0.065, 0)))
                x += 0.28
    return p

def purifier():
    p = Prop()
    p.add("Panel", cyl(0.29, 0.86, 28, (0, 0.445, 0)))
    for y in (0.03, 0.28, 0.63, 0.87):
        p.add("DarkMetal", cyl(0.305, 0.04, 28, (0, y, 0)))
    p.add("White", cyl(0.17, 0.25, 20, (0, 1.0, 0)))
    p.add("Glass", cyl(0.12, 0.18, 16, (0, 1.0, 0.07)))
    p.add("Cyan", cyl(0.09, 0.12, 16, (0, 0.99, 0.07)))
    p.add("DarkMetal", cyl(0.19, 0.04, 20, (0, 1.14, 0)))
    p.add("Steel", tube([(0.25, 0.25, 0.0), (0.36, 0.25, 0.0), (0.38, 0.2, 0.0)], 0.02, 8))
    p.add("RedPaint", cyl(0.025, 0.03, 8, (0.33, 0.29, 0)))
    p.add("Trim", cyl(0.295, 0.04, 28, (0, 0.45, 0)))
    p.add("Steel", cyl(0.1, 0.12, 16, (-0.45, 0.06, 0.2)))   # cup
    return p

def cook_pot():
    p = Prop()
    top = 1.35
    for k in range(3):
        a = k * 2 * math.pi / 3 + 0.4
        p.add("DarkMetal", tube([(math.cos(a) * 0.9, 0.0, math.sin(a) * 0.9), (0, top, 0)], 0.022, 8))
    p.add("DarkMetal", blob((0.08, 0.08, 0.08), 0.6, 10, 6, (0, top, 0)))
    for k in range(6):   # chain links
        p.add("Steel", lathe([(0.012, 0), (0.012, 0.06)], 6, axis='y').transform(rotx(k % 2 * 0.3), (0, top - 0.06 - k * 0.07, 0)))
    pot = lathe([(0.0, 0.0), (0.12, 0.0), (0.2, 0.04), (0.22, 0.12), (0.21, 0.22), (0.23, 0.24), (0.215, 0.25), (0.2, 0.23)], 28, axis='y')
    p.add("DarkMetal", pot.transform(None, (0, top - 0.9, 0)))
    p.add("Steel", tube([(-0.22, top - 0.64, 0), (-0.15, top - 0.5, 0), (0, top - 0.48, 0), (0.15, top - 0.5, 0), (0.22, top - 0.64, 0)], 0.008, 6))
    p.add("Leather", cyl(0.2, 0.01, 24, (0, top - 0.7, 0)))   # stew surface
    return p

def rug():
    p = Prop()
    def f(u, v):
        x = (u - 0.5) * 2.4; z = (v - 0.5) * 1.5
        return (x, 0.01 + 0.008 * math.sin(u * 9 + v * 4) * math.sin(v * 7), z)
    p.add("Rug", sheet(f, 24, 16, (2.4, 1.5)))
    return p

def radio():
    p = Prop()
    p.add("Olive", bb((0.5, 0.3, 0.28), (0, 0.15, 0), 0.03))
    p.add("DarkMetal", bb((0.46, 0.26, 0.02), (0, 0.15, 0.14), 0.01))
    p.add("Screen_data", screen_quad((-0.09, 0.2, 0.152), 0.2, 0.1))
    for k in range(3):
        p.add("Steel", cyl(0.025, 0.03, 14, (0.08 + k * 0.06, 0.2, 0.16), axis='z'))
    for k in range(5):
        p.add("Rubber", bb((0.2, 0.008, 0.008), (-0.09, 0.07 + k * 0.016, 0.155), 0.002))
    p.add("Steel", tube([(0.2, 0.3, -0.08), (0.22, 0.75, -0.1)], 0.006, 6))
    p.add("Red", cyl(0.012, 0.015, 8, (0.22, 0.755, -0.1)))
    p.add("Amber", bb((0.03, 0.02, 0.01), (0.19, 0.08, 0.155), 0.003))
    p.add("Cable", tube([(-0.25, 0.08, 0.05), (-0.35, 0.03, 0.12), (-0.45, 0.06, 0.1)], 0.008, 6))
    p.add("DarkMetal", bb((0.08, 0.12, 0.04), (-0.47, 0.06, 0.1), 0.015))   # handset
    return p

def datapad():
    p = Prop()
    p.add("DarkMetal", bb((0.2, 0.014, 0.28), (0, 0.007, 0), 0.006))
    p.add("Screen_data", screen_quad((0, 0.0145, 0.0), 0.17, 0.23, n=(0, 1, 0), up=(0, 0, -1)))
    p.add("Trim", bb((0.2, 0.016, 0.02), (0, 0.008, 0.13), 0.004))
    return p

def journal():
    p = Prop()
    p.add("Leather", bb((0.18, 0.012, 0.25), (0, 0.006, 0), 0.004))
    p.add("Pillow", bb((0.17, 0.03, 0.24), (0.003, 0.027, 0), 0.006))
    p.add("Leather", bb((0.18, 0.012, 0.25), (0, 0.048, 0), 0.004))
    p.add("Leather", bb((0.012, 0.054, 0.25), (-0.09, 0.027, 0), 0.004))
    p.add("RedPaint", bb((0.006, 0.002, 0.16), (0.02, 0.055, 0.04), 0.001))
    return p

def holo_map():
    p = Prop()
    p.add("DarkMetal", cyl(0.45, 0.08, 32, (0, 0.04, 0)))
    p.add("Panel", cyl(0.18, 0.75, 20, (0, 0.45, 0), r2=0.12))
    p.add("Panel", cyl(0.5, 0.06, 32, (0, 0.85, 0)))
    p.add("Trim", cyl(0.52, 0.025, 32, (0, 0.82, 0)))
    p.add("Screen_map", screen_quad((0, 0.885, 0), 0.62, 0.62, n=(0, 1, 0), up=(0, 0, -1)))
    return p

def supply_crate():
    """1.0 x 0.7 x 0.7 rugged cargo case."""
    p = Prop()
    W, H, D = 1.0, 0.7, 0.7
    p.add("Olive", bb((W - 0.04, H - 0.1, D - 0.04), (0, H / 2, 0), 0.04))
    p.add("DarkMetal", bb((W, 0.08, D), (0, 0.04, 0), 0.02))
    p.add("DarkMetal", bb((W, 0.1, D), (0, H - 0.05, 0), 0.025))
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.add("DarkMetal", bb((0.09, H, 0.09), (sx * (W / 2 - 0.035), H / 2, sz * (D / 2 - 0.035)), 0.02))
    for k in (-1, 0, 1):
        p.add("DarkMetal", bb((0.06, H - 0.16, D + 0.01), (k * 0.3, H / 2, 0), 0.01))
    p.add("Trim", bb((W - 0.2, 0.06, D + 0.012), (0, H * 0.62, 0), 0.008))
    for sx in (-1, 1):
        p.add("Steel", bb((0.08, 0.1, 0.03), (sx * 0.15, H - 0.12, D / 2 + 0.01), 0.01))
        p.add("DarkMetal", bb((0.03, 0.05, 0.26), (sx * (W / 2 + 0.02), H * 0.6, 0), 0.01))
    p.add("Amber", bb((0.06, 0.03, 0.01), (0, H - 0.12, D / 2 + 0.006), 0.003))
    return p

def loot_crate():
    """Field supply case (0.9 x 0.5 x 0.6), open-topped body with contents; the
    lid is a separate node hinged on the back edge."""
    body, lid, lock = Prop(), Prop(), Prop()
    W, H, D, T = 0.9, 0.44, 0.6, 0.045
    body.add("DarkMetal", bb((W, 0.05, D), (0, 0.025, 0), 0.015))
    for sx in (-1, 1):
        body.add("Olive", bb((T, H, D), (sx * (W / 2 - T / 2), H / 2, 0), 0.012))
    for sz in (-1, 1):
        body.add("Olive", bb((W, H, T), (0, H / 2, sz * (D / 2 - T / 2)), 0.012))
    body.add("Panel", bb((W - 2 * T, 0.02, D - 2 * T), (0, 0.06, 0), 0.005))
    for sx in (-1, 1):       # corner guards
        for sz in (-1, 1):
            body.add("DarkMetal", bb((0.07, H + 0.02, 0.07), (sx * (W / 2 - 0.02), H / 2, sz * (D / 2 - 0.02)), 0.018))
        body.add("DarkMetal", bb((0.03, 0.06, 0.24), (sx * (W / 2 + 0.02), H * 0.62, 0), 0.01))           # handles
        body.add("Steel", cyl(0.012, 0.22, 8, (sx * (W / 2 + 0.035), H * 0.62, 0), axis='z'))
    for k in (-1, 1):        # ribs (outside faces only)
        for sz in (-1, 1):
            body.add("DarkMetal", bb((0.04, H - 0.08, 0.02), (k * 0.2, H / 2, sz * (D / 2 + 0.004)), 0.006))
    for sz in (-1, 1):
        body.add("Trim", bb((W - 0.16, 0.05, 0.016), (0, H * 0.3, sz * (D / 2 + 0.005)), 0.004))
    for k in range(5):
        body.add("DarkMetal", rot(bb((0.022, 0.06, 0.006), (0, 0, 0), 0.002), rotz(0.6), (-0.3 + k * 0.05, H * 0.3, D / 2 + 0.006)))
    body.add("DarkMetal", bb((0.16, 0.12, 0.03), (0, H * 0.62, D / 2 + 0.012), 0.012))
    lock.add("Amber", bb((0.08, 0.025, 0.012), (0, H * 0.66, D / 2 + 0.03), 0.004))
    # contents
    body.add("Olive", bb((0.26, 0.16, 0.2), (-0.18, 0.15, -0.08), 0.02))
    body.add("Trim", bb((0.265, 0.03, 0.205), (-0.18, 0.18, -0.08), 0.004))
    body.add("White", bb((0.22, 0.1, 0.16), (0.16, 0.12, 0.1), 0.02))
    body.add("RedPaint", bb((0.04, 0.003, 0.1), (0.16, 0.171, 0.1), 0.001))
    body.add("RedPaint", bb((0.1, 0.003, 0.04), (0.16, 0.171, 0.1), 0.001))
    body.add("DarkMetal", cyl(0.05, 0.03, 14, (0.18, 0.085, -0.13)))
    body.add("Glass", cyl(0.042, 0.13, 14, (0.18, 0.165, -0.13)))
    body.add("Core", cyl(0.025, 0.12, 10, (0.18, 0.165, -0.13)))
    body.add("Cyan", bb((W - 0.14, 0.012, 0.012), (0, H - 0.04, -(D / 2 - T - 0.008)), 0.003))
    # lid, local to its hinge at the back top edge (0, H, -D/2)
    lid.add("Olive", bb((W + 0.02, 0.07, D + 0.02), (0, 0.035, D / 2), 0.02))
    lid.add("Panel", bb((W - 0.24, 0.03, D - 0.2), (0, 0.08, D / 2), 0.012))
    lid.add("DarkMetal", bb((W + 0.03, 0.025, D + 0.03), (0, 0.012, D / 2), 0.006))
    for sx in (-1, 1):
        lid.add("DarkMetal", bb((0.08, 0.09, 0.08), (sx * (W / 2 - 0.02), 0.045, D - 0.02), 0.02))
        lid.add("DarkMetal", bb((0.08, 0.09, 0.08), (sx * (W / 2 - 0.02), 0.045, 0.02), 0.02))
        lid.add("Steel", bb((0.07, 0.06, 0.025), (sx * 0.22, 0.0, D + 0.02), 0.008))     # latches
        lid.add("DarkMetal", cyl(0.018, 0.12, 10, (sx * 0.3, 0.0, -0.005), axis='x'))     # hinges
    lid.add("Trim", bb((0.5, 0.012, 0.06), (0, 0.098, D / 2), 0.004))
    return body, lid, lock

def lily_texture(n=512, seed=91):
    """Lily pad: waxy green with radial veins and a sun-bleached rim."""
    from textures import _tile_noise, _normal_from_height, _img
    from scipy import ndimage
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:n, 0:n] / n - 0.5
    r = np.hypot(xx, yy) * 2; a = np.arctan2(yy, xx)
    veins = np.abs(np.sin(a * 13 + r * 1.5)) ** 18
    nz = _tile_noise(n, 8, rng, 4)
    H = 0.6 - veins * 0.25 + nz * 0.15
    c = np.dstack([0.16 + 0.07 * nz, 0.34 + 0.12 * nz, 0.1 + 0.04 * nz])
    c += veins[..., None] * np.array([0.05, 0.08, 0.02])
    rim = np.clip((r - 0.86) * 8, 0, 1)
    c = c * (1 - rim[..., None]) + np.array([0.42, 0.32, 0.12]) * rim[..., None]
    spots = (_tile_noise(n, 30, rng, 2) > 0.8) * 0.25
    c *= (1 - spots[..., None])
    return _img(c), Image.fromarray(_normal_from_height(ndimage.gaussian_filter(H, 1.0), 4))

def lily_pads():
    p = Prop()
    pads = Mesh(); placed = []
    for k in range(40):
        if len(placed) >= 12: break
        a = R.uniform(0, 2 * math.pi); d = R.uniform(0.0, 1.6) ** 0.8
        cx, cz = math.cos(a) * d, math.sin(a) * d
        rad = R.uniform(0.18, 0.42); rot0 = R.uniform(0, 2 * math.pi)
        if any(math.hypot(cx - px, cz - pz) < (rad + pr) * 0.8 for px, pz, pr in placed): continue
        placed.append((cx, cz, rad))
        notch = 0.35
        segs = 28
        centre = np.array([cx, 0.004 * k, cz])
        for i in range(segs):
            t0 = notch / 2 + (2 * math.pi - notch) * i / segs
            t1 = notch / 2 + (2 * math.pi - notch) * (i + 1) / segs
            def rp(t, f=1.0):
                curl = 0.02 * (f ** 4)
                return centre + np.array([math.cos(t + rot0) * rad * f, curl, math.sin(t + rot0) * rad * f])
            def uv(t, f=1.0): return (0.5 + 0.5 * f * math.cos(t), 0.5 + 0.5 * f * math.sin(t))
            for f0, f1 in ((0.0, 0.7), (0.7, 1.0)):
                a0, b0 = rp(t0, f0), rp(t1, f0); a1, b1 = rp(t0, f1), rp(t1, f1)
                pads.quad_uv(a0, a1, b1, b0, uv(t0, f0), uv(t0, f1), uv(t1, f1), uv(t1, f0), n=np.array([0, 1.0, 0]))
    # fix winding to face up
    for t in range(0, len(pads.P), 3):
        a, b, c = pads.P[t:t + 3]
        if np.cross(b - a, c - a)[1] < 0:
            pads.P[t + 1], pads.P[t + 2] = pads.P[t + 2], pads.P[t + 1]
            pads.UV[t + 1], pads.UV[t + 2] = pads.UV[t + 2], pads.UV[t + 1]
    p.add("LilyPad", pads)
    for k in range(3):
        px, pz, pr = placed[k * 3 % len(placed)]
        c = np.array([px + pr * 0.2, 0.03, pz])
        for layer, (cnt, ln, tilt, mat) in enumerate(((10, 0.16, 0.45, "LilyPetal"), (8, 0.13, 0.8, "LilyPetal"), (6, 0.09, 1.1, "LilyPetalPale"))):
            for i in range(cnt):
                th = 2 * math.pi * i / cnt + layer * 0.3
                d0 = np.array([math.cos(th), 0, math.sin(th)])
                up = np.array([0, 1.0, 0])
                tipdir = d0 * math.cos(tilt) + up * math.sin(tilt)
                side = np.cross(up, d0) * 0.032
                base = c + np.array([0, 0.005 * layer, 0])
                mid = base + tipdir * ln * 0.55
                tip = base + tipdir * ln
                for tri in ((base, mid - side, tip), (base, tip, mid + side)):
                    n = np.cross(tri[1] - tri[0], tri[2] - tri[0])
                    if n[1] < 0: tri = (tri[0], tri[2], tri[1]); n = -n
                    n = n / (np.linalg.norm(n) + 1e-9)
                    for q in tri:
                        p.parts.setdefault(mat, Mesh()).P.append(q); p.parts[mat].N.append(n)
        p.add("LilyCentre", blob((0.05, 0.03, 0.05), 0.7, 10, 6, tuple(c + np.array([0, 0.02, 0]))))
    return p

# ---------------------------------------------------------------- dock
def dock():
    p = Prop()
    Lw, Wd = 6.6, 2.3        # walkway, along -Z from the shore (z=0)
    Lp, Wp = 2.2, 3.8        # end platform
    z_end = -Lw - Lp
    # frame: stringers, cross beams, pylons
    for sx in (-1, 1):
        p.add("Panel", bb((0.14, 0.24, Lw + Lp), (sx * (Wd / 2 - 0.25), -0.2, -(Lw + Lp) / 2), 0.02))
    for k in range(6):
        z = -0.5 - k * (Lw / 5)
        p.add("DarkMetal", bb((Wd - 0.1, 0.12, 0.12), (0, -0.14, z), 0.02))
    for x in (-Wp / 2 + 0.3, -0.6, 0.6, Wp / 2 - 0.3):
        p.add("Panel", bb((0.14, 0.22, Lp), (x, -0.2, -Lw - Lp / 2), 0.02))
    pyl = [(sx * (Wd / 2 - 0.25), -0.8 - k * (Lw / 3)) for sx in (-1, 1) for k in range(3)]
    pyl += [(sx * (Wp / 2 - 0.3), z) for sx in (-1, 1) for z in (-Lw - 0.2, z_end + 0.25)]
    for (x, z) in pyl:
        p.add("Panel", cyl(0.13, 2.4, 16, (x, -1.35, z)))
        p.add("Trim", cyl(0.15, 0.12, 16, (x, -0.42, z)))
        p.add("DarkMetal", cyl(0.17, 0.08, 16, (x, -0.68, z)))
        for k in range(4):
            p.add("Steel", cyl(0.02, 0.03, 6, (x + 0.13 * math.cos(k * 1.57), -0.42, z + 0.13 * math.sin(k * 1.57)), axis='x' if k % 2 == 0 else 'z'))
    # deck planks: across the walkway, some missing / broken / sagging
    planks = []
    z = -0.05
    while z > -Lw:
        w = 0.2 + R.uniform(-0.015, 0.015)
        if R.random() > 0.06:
            if R.random() < 0.08:   # broken short plank
                ln = R.uniform(0.7, 1.3); x0 = R.choice([-1, 1]) * (Wd - ln) / 2
                planks.append(((ln, 0.06, w), (x0, -0.03, z - w / 2), R.normal(0, 0.06)))
            else:
                planks.append(((Wd + R.uniform(-0.05, 0.08), 0.06, w), (R.normal(0, 0.03), -0.03 + R.normal(0, 0.006), z - w / 2), R.normal(0, 0.02)))
        z -= w + 0.022
    z = -Lw
    while z > z_end:
        w = 0.2 + R.uniform(-0.015, 0.015)
        planks.append(((Wp + R.uniform(-0.05, 0.05), 0.06, w), (R.normal(0, 0.03), -0.03 + R.normal(0, 0.006), z - w / 2), R.normal(0, 0.015)))
        z -= w + 0.022
    plank_cols = []
    pm = Mesh()
    for (size, c, yaw) in planks:
        m = rot(bb(size, (0, 0, 0), 0.012), roty(yaw), c)
        P, N = m.arrays()
        tone = R.uniform(0.72, 1.08); green = R.random() < 0.25
        col = vcol(P * 1.5, None, int(R.integers(100)), N)
        col[:, :3] *= tone
        if green: col[:, :3] *= np.array([0.85, 1.0, 0.8])
        plank_cols.append(col); pm.extend(m)
        for sx in (-0.35, 0.35):   # bolts
            pass
    p.parts["Wood"] = pm
    p.wood_cols = np.vstack(plank_cols)
    # metal edge kick-rails with hazard caps
    for sx in (-1, 1):
        p.add("DarkMetal", bb((0.08, 0.08, Lw), (sx * (Wd / 2 + 0.02), 0.02, -Lw / 2), 0.015))
    for sz in (-1,):
        p.add("Trim", bb((Wp, 0.08, 0.08), (0, 0.02, z_end - 0.02), 0.015))
    # broken railing along one side
    for k in range(5):
        z = -0.4 - k * 1.5
        h = 1.0 if k != 3 else 0.55
        p.add("Steel", cyl(0.03, h, 10, (Wd / 2 + 0.02, h / 2, z)))
        if k < 4 and k != 2:
            p.add("Steel", tube([(Wd / 2 + 0.02, 0.95, z), (Wd / 2 + 0.02, 0.95, z - 1.5)], 0.022, 8))
    p.add("Steel", tube([(Wd / 2 + 0.02, 0.95, -3.4), (Wd / 2 + 0.25, 0.4, -3.9), (Wd / 2 + 0.35, -0.2, -4.1)], 0.022, 8))  # snapped rail hanging
    # gangway plate up to the shore
    p.add("Grate", rot(bb((Wd - 0.2, 0.05, 1.7), (0, 0, 0), 0.01), rotx(0.22), (0, 0.16, 0.82)))
    for sx in (-1, 1):
        p.add("Trim", rot(bb((0.06, 0.07, 1.7), (0, 0, 0), 0.01), rotx(0.22), (sx * (Wd / 2 - 0.12), 0.19, 0.82)))
    # bollards, lamp post, rope, crate
    for sx in (-1, 1):
        bx, bz = sx * (Wp / 2 - 0.25), z_end + 0.25
        p.add("DarkMetal", lathe([(0.0, 0.0), (0.12, 0.0), (0.1, 0.05), (0.08, 0.3), (0.12, 0.34), (0.12, 0.38), (0.0, 0.38)], 20, axis='y').transform(None, (bx, 0.0, bz)))
        p.add("Trim", cyl(0.085, 0.05, 20, (bx, 0.22, bz)))
    coil = Mesh()
    for k in range(3):
        coil.extend(lathe([(0.15 + k * 0.035, -0.02), (0.15 + k * 0.035 + 0.03, 0.0), (0.15 + k * 0.035, 0.02), (0.15 + k * 0.035 - 0.0, 0.0)], 24, axis='y'))
    p.add("Rope", coil.transform(None, (-Wp / 2 + 0.7, 0.03, z_end + 0.6)))
    p.add("Rope", tube([(-Wp / 2 + 0.25, 0.33, z_end + 0.25), (-Wp / 2 + 0.4, 0.1, z_end + 0.4), (-Wp / 2 + 0.55, 0.04, z_end + 0.55)], 0.02, 6))
    lx, lz = Wp / 2 - 0.35, -Lw - 0.25
    p.add("DarkMetal", bb((0.3, 0.06, 0.3), (lx, 0.03, lz), 0.02))
    p.add("Panel", cyl(0.05, 2.5, 12, (lx, 1.3, lz)))
    p.add("Panel", tube([(lx, 2.5, lz), (lx - 0.1, 2.68, lz), (lx - 0.5, 2.72, lz)], 0.035, 10))
    p.add("DarkMetal", bb((0.32, 0.1, 0.2), (lx - 0.55, 2.65, lz), 0.03))
    p.add("Cyan", screen_quad((lx - 0.55, 2.594, lz), 0.26, 0.14, n=(0, -1, 0), up=(1, 0, 0)))
    p.add("Trim", cyl(0.06, 0.15, 12, (lx, 0.15, lz)))
    p.add("Olive", bb((0.6, 0.45, 0.45), (0.9, 0.225, -Lw + 0.6), 0.03))
    p.add("Trim", bb((0.61, 0.05, 0.46), (0.9, 0.32, -Lw + 0.6), 0.01))
    # algae and moss on the frame, grass at the shore end
    for k in range(18):
        x = R.uniform(-Wp / 2, Wp / 2); z = R.uniform(z_end, -0.4)
        if abs(x) > Wd / 2 and z > -Lw: continue
        s = R.uniform(0.25, 0.6)
        m = Mesh(); _card(m, (x, 0.006 + 0.0007 * k, z), (s, s), (0, 1, 0), (math.cos(k), 0, math.sin(k))); p.add("Moss", m)
    for k in range(14):
        x = R.uniform(-1.6, 1.6); z = R.uniform(0.3, 1.8)
        if abs(x) < Wd / 2 - 0.1: continue
        h = R.uniform(0.3, 0.7)
        for j in range(3):
            a = j * math.pi / 3 + k
            m = Mesh(); _card(m, (x, h / 2 + 0.1, z), (h, h), (math.cos(a), 0, math.sin(a)), (0, 1, 0)); p.add("Grass", m)
    return p

# ---------------------------------------------------------------- export
PROPS = {
    "Bed": bed, "ArmoryLocker": armory_locker, "MedBench": med_bench, "DroidBench": droid_bench,
    "CraftBench0": lambda: craft_bench(0), "CraftBench1": lambda: craft_bench(1), "CraftBench2": lambda: craft_bench(2),
    "Generator": generator, "WorkLamp": work_lamp, "Shelf": shelf, "Purifier": purifier, "CookPot": cook_pot,
    "Rug": rug, "Radio": radio, "SupplyCrate": supply_crate, "Datapad": datapad, "Journal": journal, "HoloMap": holo_map,
}

def export_props(path):
    g = GLB(); materials(g)
    for i, (name, fn) in enumerate(PROPS.items()):
        p = fn()
        emit(g, name, p, translation=(i * 3.0, 0, 0), seed=i)
    la, ln = lily_texture()
    g.material("LilyPad", albedo_tex=g.image(la, "lily_a"), normal_tex=g.image(ln, "lily_n"), rough=0.35, double=True)
    g.material("LilyPetal", color=(0.98, 0.62, 0.78, 1), rough=0.6, double=True)
    g.material("LilyPetalPale", color=(1.0, 0.9, 0.94, 1), rough=0.6, double=True)
    g.material("LilyCentre", color=(1.0, 0.8, 0.2, 1), emissive=(0.4, 0.3, 0.05), emissive_strength=0.4, rough=0.8)
    emit(g, "LilyPads", lily_pads(), translation=(len(PROPS) * 3.0 + 3.0, 0, 0), seed=80)
    b, l, k = loot_crate()
    emit(g, "LootCrate", b, translation=(len(PROPS) * 3.0, 0, 0), seed=77)
    emit(g, "LootCrateLid", l, translation=(len(PROPS) * 3.0, 0.44, -0.3), seed=78)
    emit(g, "LootCrateLock", k, translation=(len(PROPS) * 3.0, 0, 0), seed=79)
    g.save(path); print("props ok")

def export_dock(path):
    g = GLB(); materials(g)
    p = dock()
    parts = []
    for mat, m in p.parts.items():
        if not m.P: continue
        P, N = m.arrays()
        col = None
        if mat == "Wood":
            col = p.wood_cols
        elif mat in GRIME and len(m.UV) != len(m.P):
            col = vcol(P * 1.5, None, 3, N)
            wet = np.clip((-0.35 - P[:, 1]) * 1.5, 0, 1)       # algae below the waterline
            col[:, :3] = col[:, :3] * (1 - wet[:, None] * 0.7) + np.array([0.2, 0.28, 0.12]) * wet[:, None]
        parts.append((m, mat, col, {"Wood": 0.45}.get(mat, 1.2)))
    g.mesh_node("Dock", parts)
    g.empty("LampLight", translation=(3.8 / 2 - 0.35 - 0.55, 2.45, -6.6 - 0.25))
    g.save(path); print("dock ok")

if __name__ == "__main__":
    export_props("camp_props.glb")
    export_dock("dock.glb")
