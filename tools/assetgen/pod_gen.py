"""Crashed escape pod (models/escape_pod.glb), lying on its side where it
ploughed in. Nodes: Pod (hull, solid), Chute (parachute + cords, no collision),
Ground (scorch, dirt clods, debris), Beacon (blinking light lens).
Local frame: pod axis along +Z (heat shield at -Z), ground at y = 0."""
import math, numpy as np
from PIL import Image
from scipy import ndimage
from meshlib import *
from textures import hull_panels, grating, fabric, _tile_noise, _normal_from_height, _img, crack_decal
from camp_gen import sheet, bb, screen_quad, Prop, rot
from building_gen import _card

R = np.random.default_rng(31)
L0, L1 = -2.2, 2.3          # shield end .. nose (along Z)
K = 20                       # ring sides
HATCH = (0.95, 2.05, -0.75, 0.55)   # theta range (rad) and z range of the blown hatch

def radius(z):
    zs = [L0, L0 + 0.25, -1.4, 0.6, 1.5, 2.0, L1]
    rs = [1.18, 1.36, 1.32, 1.28, 1.05, 0.72, 0.38]
    return float(np.interp(z, zs, rs))

def ring_pt(r, th, z):
    # slightly faceted (chamfered 10-gon look) via a soft polygon modulation
    f = 1.0 - 0.025 * (0.5 + 0.5 * math.cos(th * 10))
    return np.array([r * f * math.cos(th), r * f * math.sin(th), z])

def hull():
    """Outer skin + inner lining, open where the hatch blew out, with a
    thickness rim round the opening."""
    zs = list(np.linspace(L0 + 0.25, L1, 22))
    outer, inner, rim = Mesh(), Mesh(), Mesh()
    def ang(k): return 2 * math.pi * k / K
    def hole(th, z):
        th = th % (2 * math.pi)
        return HATCH[0] <= th <= HATCH[1] and HATCH[2] <= z <= HATCH[3]
    T = 0.07
    G = [[ring_pt(radius(z), ang(k), z) for k in range(K)] for z in zs]
    Gi = [[ring_pt(radius(z) - T, ang(k), z) for k in range(K)] for z in zs]
    for i in range(len(zs) - 1):
        for k in range(K):
            k2 = (k + 1) % K
            th_c = ang(k) + math.pi / K; z_c = (zs[i] + zs[i + 1]) / 2
            if hole(th_c, z_c):
                # rim faces on edges that border kept faces
                for (a, b, ai, bi, nb) in (((i, k), (i + 1, k), None, None, (th_c - 2 * math.pi / K, z_c)),
                                           ((i, k2), (i + 1, k2), None, None, (th_c + 2 * math.pi / K, z_c)),
                                           ((i, k), (i, k2), None, None, (th_c, z_c - (zs[1] - zs[0]))),
                                           ((i + 1, k), (i + 1, k2), None, None, (th_c, z_c + (zs[1] - zs[0])))):
                    if hole(*nb): continue
                    p0, p1 = G[a[0]][a[1]], G[b[0]][b[1]]
                    q0, q1 = Gi[a[0]][a[1]], Gi[b[0]][b[1]]
                    rim.quad(p0, p1, q1, q0); rim.quad(p0, q0, q1, p1)
                continue
            a, b, c, d = G[i][k], G[i][k2], G[i + 1][k2], G[i + 1][k]
            outer.quad(a, b, c, d) if np.dot(np.cross(b - a, c - a), a - np.array([0, 0, a[2]])) > 0 else outer.quad(a, d, c, b)
            a, b, c, d = Gi[i][k], Gi[i][k2], Gi[i + 1][k2], Gi[i + 1][k]
            inner.quad(a, d, c, b) if np.dot(np.cross(b - a, c - a), a - np.array([0, 0, a[2]])) > 0 else inner.quad(a, b, c, d)
    # smooth the outer normals round the ring (keeps facets readable but soft)
    for m, sgn in ((outer, 1), (inner, -1)):
        for t in range(len(m.P)):
            p = m.P[t]; n = np.array([p[0], p[1], 0.0]); l = np.linalg.norm(n)
            if l > 1e-6:
                dz = (radius(p[2] - 0.05) - radius(p[2] + 0.05)) / 0.1
                n = n / l + np.array([0, 0, dz * 0.6]); n /= np.linalg.norm(n)
                m.N[t] = n * sgn
    # nose cap
    nose = lathe([(0.38, 0.0), (0.3, 0.12), (0.16, 0.2), (0.0, 0.23)], K).transform(None, (0, 0, L1))
    outer.extend(nose)
    return outer, inner, rim

def heat_shield():
    prof = [(0.0, -0.55), (0.5, -0.5), (0.95, -0.38), (1.22, -0.18), (1.32, 0.0), (1.36, 0.27)]
    return lathe(prof, 40).transform(None, (0, 0, L0))

def char_texture(n=1024, seed=5):
    """Charred ablative tiles with ember-glowing cracks: albedo, normal, emission."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:n, 0:n].astype(float)
    cell = 96
    gx, gy = (xx % cell), ((yy + (xx // cell % 2) * cell / 2) % cell)
    seam = np.minimum(np.minimum(gx, cell - gx), np.minimum(gy, cell - gy))
    H = np.clip(seam / 6, 0, 1) * 0.6 + _tile_noise(n, 24, rng, 4) * 0.4
    crack_a, _ = crack_decal(512, seed=seed)
    cr = np.asarray(crack_a.resize((n, n)), float)[..., 3] / 255
    cr = np.maximum(cr, np.roll(cr, n // 2, axis=0) * np.roll(cr, n // 3, axis=1))
    blister = _tile_noise(n, 40, rng, 3)
    c = np.dstack([0.07 + 0.05 * H, 0.065 + 0.045 * H, 0.06 + 0.04 * H]) * (0.7 + 0.6 * blister[..., None])
    c *= (1 - 0.6 * cr[..., None])
    soot = _tile_noise(n, 5, rng, 3)
    c += np.array([0.12, 0.07, 0.04]) * np.clip(soot - 0.6, 0, 1)[..., None]
    H -= cr * 0.5
    glow = cr * np.clip(_tile_noise(n, 6, rng, 3) * 1.6 - 0.75, 0, 1)
    em = np.dstack([glow, glow * 0.35, glow * 0.06])
    em = np.clip(em + ndimage.gaussian_filter(em, (3, 3, 0)) * 0.8, 0, 1)
    nrm = _normal_from_height(ndimage.gaussian_filter(H, 1.0, mode='wrap'), 8)
    return _img(c), Image.fromarray(nrm), _img(em)

def scorch_texture(n=512, seed=6):
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:n, 0:n] / n - 0.5
    r = np.hypot(xx * 1.0, yy * 1.6) * 2
    nz = _tile_noise(n, 6, rng, 5)
    a = np.clip((1.0 - r) * 1.5 + (nz - 0.5) * 1.2, 0, 1)
    c = np.dstack([0.05 + 0.06 * nz, 0.045 + 0.05 * nz, 0.04 + 0.04 * nz])
    return _img(np.dstack([c, (a > 0.25).astype(float) * np.clip(a * 1.6, 0, 1)]))

def build():
    pod, chute, ground, beacon = Prop(), Prop(), Prop(), Prop()
    outer, inner, rim = hull()
    pod.add("PodHull", outer); pod.add("Interior", inner); pod.add("DarkMetal", rim)
    pod.add("Shield", heat_shield())
    # reinforcement rings and an orange survival stripe
    for z in (-1.55, -0.95, 0.95):
        r = radius(z)
        band = lathe([(r + 0.0, -0.06), (r + 0.05, -0.04), (r + 0.05, 0.04), (r, 0.06)], K).transform(None, (0, 0, z))
        band_cut = Mesh()
        for t in range(0, len(band.P), 3):
            c = (band.P[t] + band.P[t + 1] + band.P[t + 2]) / 3
            th = math.atan2(c[1], c[0]) % (2 * math.pi)
            if not (HATCH[0] - 0.05 <= th <= HATCH[1] + 0.05 and HATCH[2] - 0.1 <= c[2] <= HATCH[3] + 0.1):
                band_cut.P += band.P[t:t + 3]; band_cut.N += band.N[t:t + 3]
        pod.add("DarkMetal", band_cut)
    stripe = Mesh()
    for k in range(K):
        th0, th1 = 2 * math.pi * k / K, 2 * math.pi * (k + 1) / K
        if HATCH[0] - 0.05 <= (th0 + th1) / 2 <= HATCH[1] + 0.05: continue
        for z0, z1 in ((1.12, 1.3), (-0.2, -0.05)):
            a, b = ring_pt(radius(z0) + 0.012, th0, z0), ring_pt(radius(z0) + 0.012, th1, z0)
            c, d = ring_pt(radius(z1) + 0.012, th1, z1), ring_pt(radius(z1) + 0.012, th0, z1)
            stripe.quad(a, b, c, d) if np.dot(np.cross(b - a, c - a), a - np.array([0, 0, a[2]])) > 0 else stripe.quad(a, d, c, b)
    pod.add("Orange", stripe)
    # hatch frame round the opening + hinge stubs
    def hp(th, z, out=0.03): return ring_pt(radius(z) + out, th, z)
    frame = []
    for t in np.linspace(HATCH[0] - 0.06, HATCH[1] + 0.06, 9):
        frame.append(hp(t, HATCH[2] - 0.06));
    for z in np.linspace(HATCH[2] - 0.06, HATCH[3] + 0.06, 7):
        frame.append(hp(HATCH[1] + 0.06, z))
    for t in np.linspace(HATCH[1] + 0.06, HATCH[0] - 0.06, 9):
        frame.append(hp(t, HATCH[3] + 0.06))
    for z in np.linspace(HATCH[3] + 0.06, HATCH[2] - 0.06, 7):
        frame.append(hp(HATCH[0] - 0.06, z))
    pod.add("Trim", tube(frame + [frame[0]], 0.045, 8))
    for z in (HATCH[2] + 0.15, HATCH[3] - 0.15):
        p = hp(HATCH[1] + 0.1, z, 0.05)
        pod.add("DarkMetal", bb((0.14, 0.14, 0.18), tuple(p), 0.03))
    # interior: seat, harness, console glow, loose cable
    pod.add("Pillow", rot(blob((0.6, 0.12, 0.7), 0.35, 16, 8), rotz(0.4), (-0.25, -0.55, -0.15)))
    pod.add("Pillow", rot(blob((0.6, 0.6, 0.12), 0.35, 16, 8), rotz(0.4), (-0.6, -0.15, -0.15)))
    pod.add("Orange", rot(bb((0.06, 0.55, 0.02), (0, 0, 0), 0.01), rotz(0.4), (-0.48, -0.12, 0.0)))
    pod.add("Orange", rot(bb((0.06, 0.55, 0.02), (0, 0, 0), 0.01), rotz(0.4), (-0.48, -0.12, -0.3)))
    pod.add("DarkMetal", rot(bb((0.5, 0.3, 0.08), (0, 0, 0), 0.02), rotz(0.4), (-0.35, 0.2, 0.75)))
    pod.add("Screen_data", screen_quad((-0.32, 0.18, 0.705), 0.38, 0.2, n=(0, 0, -1)))
    pod.add("Cable", tube([(0.3, 0.6, 0.3), (0.5, 0.75, 0.1), (0.75, 1.05, -0.2), (1.0, 1.35, -0.1)], 0.02, 6))
    # retro thrusters round the shield end
    for k in range(4):
        th = k * math.pi / 2 + math.pi / 4
        p = ring_pt(1.3, th, L0 + 0.55)
        out = np.array([math.cos(th), math.sin(th), 0])
        housing = bb((0.3, 0.22, 0.42), (0, 0, 0), 0.05).transform(np.column_stack([np.cross(out, [0, 0, 1]), out, [0, 0, 1]]), p + out * 0.05)
        pod.add("DarkMetal", housing)
        nz = lathe([(0.03, 0.21), (0.11, 0.2), (0.13, 0.18), (0.09, 0.08), (0.05, 0.0)], 14)
        pod.add("Steel", nz.transform(rotx(math.pi), p + out * 0.12 - np.array([0, 0, 0.2])))
    # stubby stabiliser fins
    for th in (math.pi * 0.25, math.pi * 1.25, math.pi * 1.75):
        out = np.array([math.cos(th), math.sin(th), 0])
        base = [ring_pt(radius(z), th, z) for z in (-1.5, -0.4)]
        pts = [base[0], base[1], base[0] + out * 0.55 + np.array([0, 0, 0.25]), base[1] + out * 0.4]
        side = np.cross(out, [0, 0, 1]) * 0.04
        pod.add("PodHull", hull_of([p + side for p in pts] + [p - side for p in pts]))
    # antenna + beacon lens (beacon is its own node so the game can blink it)
    top = ring_pt(radius(1.7), 2.9, 1.7)
    out = np.array([math.cos(2.9), math.sin(2.9), 0])
    pod.add("Steel", tube([top, top + out * 0.6 + np.array([0, 0, 0.1])], 0.015, 6))
    pod.add("DarkMetal", cyl(0.07, 0.08, 14, tuple(ring_pt(radius(1.2), 2.5, 1.2) + np.array([math.cos(2.5), math.sin(2.5), 0]) * 0.03)))
    bpos = ring_pt(radius(1.2) + 0.1, 2.5, 1.2)
    beacon.add("Red", blob((0.12, 0.12, 0.12), 0.7, 14, 8, tuple(bpos)))
    # vents and hull detail panels
    for k in range(6):
        th = R.uniform(0, 2 * math.pi); z = R.uniform(-1.3, 1.0)
        if HATCH[0] - 0.3 <= th <= HATCH[1] + 0.3: continue
        n = np.array([math.cos(th), math.sin(th), 0])
        M = np.column_stack([np.cross(n, [0, 0, 1]), n, [0, 0, 1]])
        pod.add("DarkMetal", bb((0.3, 0.05, 0.22), (0, 0, 0), 0.015).transform(M, ring_pt(radius(z), th, z)))
    return pod, chute, ground, beacon

def placed(prop, M, t):
    for mat, m in prop.parts.items():
        m.transform(M, t)

def scene():
    pod, chute, ground, beacon = build()
    # lay it down: on its side, nose up a little, dug into the dirt
    M = rotx(-0.16) @ rotz(-0.35)
    t = np.array([0.0, 0.95, 0.0])
    placed(pod, M, t); placed(beacon, M, t)
    nose = M @ np.array([0, 0, L1 + 0.1]) + t
    # parachute: dragged canopy behind the nose, with cords back to the pod
    cx, cz = 0.6, 6.0
    def canopy(u, v):
        x = (u - 0.5) * 3.4; z = cz + (v - 0.5) * 4.2
        bump = 0.28 * math.sin(u * math.pi) * math.sin(v * math.pi) * (0.6 + 0.4 * math.sin(u * 9 + v * 4))
        fold = 0.07 * math.sin(u * 23 + v * 3) + 0.05 * math.sin(v * 17)
        return (cx + x + 0.25 * math.sin(v * 3), 0.03 + max(0.0, bump + fold), z)
    chute.add("Chute", sheet(canopy, 30, 34, (3.0, 3.6)))
    for k in range(6):
        u = (k + 0.5) / 6
        a = np.array(canopy(u, 0.02))
        mid = (a + nose) / 2 + np.array([R.normal(0, 0.15), -0.2, 0])
        mid[1] = max(mid[1], 0.04)
        chute.add("Cable", tube([nose, mid, a], 0.008, 4))
    # scorched earth + plough berm + dirt clods + torn panels
    m = Mesh(); _card(m, (0, 0.012, -1.2), (6.5, 9.5), (0, 1, 0), (0, 0, 1)); ground.add("Scorch", m)
    for k in range(26):
        a = R.uniform(-1.2, 1.2) + math.pi; d = R.uniform(2.3, 4.0)
        p = (math.sin(a) * d * 0.9, R.uniform(-0.05, 0.1), math.cos(a) * d - 0.5)
        s = R.uniform(0.25, 0.7)
        clod = blob((s, s * 0.5, s * 0.8), 0.95, 12, 7, (0, 0, 0))
        ground.add("Dirt", clod.transform(roty(R.uniform(0, 6.3)) @ rotz(R.uniform(-0.3, 0.3)), p))
    for k in range(5):
        p = (R.uniform(-3.5, 3.5), 0.03, R.uniform(-4, 2))
        if abs(p[0]) < 1.6 and -2.5 < p[2] < 2.5: continue
        ground.add("PodHull", rot(bb((R.uniform(0.4, 0.9), 0.04, R.uniform(0.3, 0.6)), (0, 0, 0), 0.01), rotx(R.uniform(-0.3, 0.3)) @ roty(R.uniform(0, 3)), p))
    # the blown hatch door lying on the ground
    door = Mesh()
    door.extend(blob((1.15, 0.12, 1.25), 0.25, 18, 6))
    door.extend(bb((0.2, 0.08, 0.5), (0.35, 0.08, 0), 0.02))
    ground.add("PodHull", door.transform(rotx(0.12) @ roty(0.7), (2.6, 0.12, 1.1)))
    ground.add("Orange", bb((0.9, 0.02, 0.12), (0, 0, 0), 0.005).transform(rotx(0.12) @ roty(0.7), (2.6, 0.19, 1.1)))
    return pod, chute, ground, beacon

def export(path):
    g = GLB()
    a, n, mr = hull_panels(1024, seed=81, base=(0.78, 0.78, 0.76), plate=(160, 128))
    g.material("PodHull", albedo_tex=g.image(a, "pod_a"), normal_tex=g.image(n, "pod_n"), mr_tex=g.image(mr, "pod_mr"), metal=0.5, rough=0.9)
    ia, inn, imr = hull_panels(512, seed=82, base=(0.3, 0.31, 0.33), plate=(96, 96))
    g.material("Interior", albedo_tex=g.image(ia, "podint_a"), normal_tex=g.image(inn, "podint_n"), mr_tex=g.image(imr, "podint_mr"), metal=0.7, rough=1.0)
    g.material("DarkMetal", color=(0.17, 0.18, 0.2, 1), albedo_tex=0, normal_tex=1, mr_tex=2, metal=1.0, rough=0.8)
    g.material("Steel", color=(0.55, 0.56, 0.58, 1), normal_tex=1, metal=1.0, rough=0.4)
    g.material("Trim", color=(0.85, 0.6, 0.15, 1), albedo_tex=0, normal_tex=1, mr_tex=2, metal=0.4, rough=0.9)
    g.material("Orange", color=(0.95, 0.38, 0.06, 1), normal_tex=1, rough=0.6)
    ca, cn, ce = char_texture()
    g.material("Shield", albedo_tex=g.image(ca, "shield_a"), normal_tex=g.image(cn, "shield_n"), emissive_tex=g.image(ce, "shield_e"),
               emissive=(1, 1, 1), emissive_strength=1.6, rough=1.0)
    fa, fn, fm = fabric(512, seed=83, color=(0.92, 0.9, 0.86), quilt=0, stripe=(0.95, 0.4, 0.08))
    g.material("Chute", albedo_tex=g.image(fa, "chute_a"), normal_tex=g.image(fn, "chute_n"), rough=0.9, double=True)
    pa, pn, pm = fabric(256, seed=84, color=(0.25, 0.27, 0.3), quilt=32)
    g.material("Pillow", albedo_tex=g.image(pa, "seat_a"), normal_tex=g.image(pn, "seat_n"), rough=1.0)
    g.material("Cable", color=(0.08, 0.08, 0.09, 1), rough=0.6)
    sa, se = __import__("textures").screen(256, seed=85, kind="data", tint=(1.0, 0.45, 0.2))
    g.material("Screen_data", albedo_tex=g.image(sa, "podscr_a"), emissive_tex=g.image(se, "podscr_e"), emissive=(1, 1, 1), emissive_strength=2.0)
    g.material("Red", color=(0.6, 0.05, 0.03, 1), emissive=(1.0, 0.1, 0.05), emissive_strength=4.0)
    g.material("Scorch", albedo_tex=g.image(scorch_texture(), "scorch_a"), rough=1.0, mask=True, cutoff=0.4)
    rr = np.random.default_rng(86)
    dh = _tile_noise(256, 16, rr, 5); dc = _tile_noise(256, 4, rr, 3)
    dirt = np.dstack([0.3 + 0.12 * dc, 0.22 + 0.09 * dc, 0.15 + 0.06 * dc]) * (0.75 + 0.4 * dh[..., None])
    g.material("Dirt", albedo_tex=g.image(_img(dirt), "dirt_a"), normal_tex=g.image(Image.fromarray(_normal_from_height(dh, 6)), "dirt_n"), rough=1.0)
    pod, chute, ground, beacon = scene()
    hot = np.array([0, 0.8, L0 - 0.3])
    def parts(prop, uvs=1.2):
        out = []
        for mat, m in prop.parts.items():
            if not m.P: continue
            P, N = m.arrays()
            col = None
            if mat in ("PodHull", "DarkMetal", "Trim", "Orange", "Interior") and len(m.UV) != len(m.P):
                from building_gen import vcol
                col = vcol(P * 1.3, hot, 4, N)
            out.append((m, mat, col, uvs))
        return out
    g.mesh_node("Pod", parts(pod))
    g.mesh_node("Beacon", parts(beacon))
    g.mesh_node("Chute", parts(chute))
    g.mesh_node("Ground", parts(ground))
    g.save(path); print("pod ok")

if __name__ == "__main__":
    export("escape_pod.glb")
