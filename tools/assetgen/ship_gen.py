import math, numpy as np
from meshlib import *
from textures import hull_panels

rng = np.random.default_rng(11)

def section(w, t, b, z, y0=0.0, sub=1):
    pts = [(0, t), (w*.55, t*.9), (w*.92, t*.45), (w, 0), (w*.9, -b*.55), (w*.55, -b),
           (-w*.55, -b), (-w*.9, -b*.55), (-w, 0), (-w*.92, t*.45), (-w*.55, t*.9)]
    out = []
    for i in range(len(pts)):
        a = np.array(pts[i]); b2 = np.array(pts[(i + 1) % len(pts)])
        for k in range(sub):
            p = a + (b2 - a) * k / sub
            out.append((p[0], p[1] + y0, z))
    return np.array(out)

def dense_profile(step=0.3):
    zs = np.array([p[0] for p in PROFILE])
    out = []
    z = zs[0]
    while z <= zs[-1] + 1e-6:
        w = np.interp(z, zs, [p[1] for p in PROFILE]); t = np.interp(z, zs, [p[2] for p in PROFILE]); b = np.interp(z, zs, [p[3] for p in PROFILE])
        out.append((z, w, t, b)); z += step
    if out[-1][0] < zs[-1]: out.append(PROFILE[-1])
    return out

PROFILE = [(-9.6, 1.5, 1.1, 0.9), (-9.2, 2.1, 1.5, 1.1), (-7.5, 2.5, 1.9, 1.35), (-4.0, 2.75, 2.15, 1.5),
           (0.0, 2.8, 2.2, 1.5), (2.5, 2.6, 2.05, 1.4), (4.5, 2.25, 1.85, 1.25), (6.5, 1.75, 1.45, 1.05),
           (8.5, 1.15, 1.0, 0.8), (10.2, 0.6, 0.55, 0.5), (11.0, 0.3, 0.3, 0.32)]

def filt(m, keep):
    out = Mesh()
    for i in range(0, len(m.P), 3):
        c = (m.P[i] + m.P[i+1] + m.P[i+2]) / 3
        if keep(c):
            out.P += m.P[i:i+3]; out.N += m.N[i:i+3]
    return out

def jitter(m, amp, freq, pred=None, seed=0):
    P = np.array(m.P)
    d = np.stack([noise3(P * freq + seed), noise3(P * freq + seed + 31.7), noise3(P * freq + seed + 63.1)], 1) * amp
    if pred is not None:
        w = np.array([pred(p) for p in P])[:, None]; d *= w
    m.P = list(P + d)
    return m

def colors_for(m, fn):
    P = np.array(m.P)
    return fn(P)

def build():
    parts = {"hull": [], "dark": [], "trim": [], "glass": [], "glow": [], "red": [], "inner": []}
    # ---------------- fuselage
    secs = [section(w, t, b, z, sub=5) for z, w, t, b in dense_profile(0.28)]
    fus = loft(secs)
    # Breach on the right flank (+X): a ragged hole with torn metal round
    # its edge and ribs behind it.
    BC = np.array([2.6, 0.45, -0.6])
    def breach_r(c):
        d = np.array([(c[2] - BC[2]) / 1.9, (c[1] - BC[1]) / 0.85])
        return np.linalg.norm(d) + noise3(np.array([c * 2.3]))[0] * 0.35
    def in_breach(c):
        return c[0] > 1.5 and breach_r(c) < 1.0
    fus = filt(fus, lambda c: not in_breach(c))
    # Torn edge: find the hole's boundary edges and grow jagged, bent teeth
    # plus a strip showing the hull's thickness.
    from collections import defaultdict
    cnt = defaultdict(int); owner = {}
    key = lambda p: tuple(np.round(p, 4))
    for i in range(0, len(fus.P), 3):
        tri = fus.P[i:i+3]
        for a, b2 in ((0, 1), (1, 2), (2, 0)):
            e = tuple(sorted((key(tri[a]), key(tri[b2]))))
            cnt[e] += 1; owner[e] = fus.N[i]
    teeth = Mesh()
    for e, c in cnt.items():
        if c != 1: continue
        a, b2 = np.array(e[0]), np.array(e[1])
        mid = (a + b2) / 2
        if mid[0] < 1.5 or breach_r(mid) > 1.25: continue
        n = owner[e]
        inward = np.array([0.0, (BC[1] - mid[1]), (BC[2] - mid[2])]); inward /= max(1e-6, np.linalg.norm(inward))
        L = rng.uniform(0.05, 0.38)
        bend = n * rng.uniform(-0.25, 0.35)
        tip = mid + inward * L + bend
        teeth.tri(a, b2, tip); teeth.tri(a, tip, b2)
        th = -n * 0.09   # hull thickness strip
        teeth.quad(a, b2, b2 + th, a + th); teeth.quad(a, a + th, b2 + th, b2)
    parts["dark"].append(teeth)
    # Crumpled nose
    fus = jitter(fus, 0.22, 0.9, lambda p: np.clip((p[2] - 7.5) / 3.0, 0, 1), 5)
    parts["hull"].append(fus)
    # Interior behind the breach: dark ribs and a bulkhead
    inner = Mesh()
    for z in (-2.8, -1.6, -0.4, 0.8, 2.0):
        s = section(2.55, 2.0, 1.35, z)
        for k in range(len(s)):
            a, b2 = s[k], s[(k + 1) % len(s)]
            if a[0] < 0.5 and b2[0] < 0.5: continue
            mid = (a + b2) / 2; L = np.linalg.norm(b2 - a)
            box = bevel_box((0.16, L + 0.1, 0.22), 0.03)
            v = (b2 - a) / L; ang = math.atan2(v[1], v[0]) - math.pi / 2
            box.transform(rotz(ang), mid)
            inner.extend(box)
    wall = bevel_box((0.12, 2.6, 6.2), 0.03, (0.4, 0.3, -0.4)); inner.extend(wall)
    floor = bevel_box((2.4, 0.1, 6.2), 0.02, (1.5, -1.05, -0.4)); inner.extend(floor)
    for k in range(6):   # hanging cables / conduits
        y = 1.5 - k * 0.15
        c = lathe([(0.04, -3.0), (0.04, 2.2)], 6); c.transform(None, (2.1 - k * 0.12, y, 0)); inner.extend(c)
    parts["inner"].append(inner)
    # (old peeled plates removed)
    for k in range(0):
        a = k / 9 * 2 * math.pi
        z = BC[2] + math.cos(a) * 2.7; y = BC[1] + math.sin(a) * 1.1
        if y > 1.9 or y < -1.3: continue
        plate = bevel_box((0.06, 0.55 + rng.random() * 0.4, 0.7 + rng.random() * 0.4), 0.02)
        plate.transform(rotz(rng.uniform(-0.6, 0.6)) @ roty(rng.uniform(0.3, 0.9) * (1 if math.cos(a) > 0 else -1)),
                        (2.75 + rng.random() * 0.3, y, z))
        parts["hull"].append(plate)
    # ---------------- dorsal spine + canopy
    spine = [section(0.55, 0.55, 0.05, z, y0=1.95 if z < 1 else 1.95 - (z - 1) * 0.12) for z in (-8.8, -7.5, -4, -0.5, 2.0, 3.2)]
    parts["hull"].append(loft(spine))
    canopy = [section(w * 0.55, 0.6 * s, 0.05, z, y0=y0) for z, w, s, y0 in
              [(3.4, 1.9, 0.3, 1.9), (4.4, 1.8, 0.9, 1.75), (5.6, 1.5, 1.0, 1.42), (6.8, 1.15, 0.75, 1.1), (7.6, 0.8, 0.3, 0.92)]]
    parts["glass"].append(loft(canopy))
    for z in (4.4, 5.6, 6.8):   # canopy frame
        s = canopy[[4.4, 5.6, 6.8].index(z) + 1]
        for k in range(1, 5):
            a, b2 = s[k], s[k + 1] if k + 1 < len(s) else s[0]
        fr = loft([s * [1.04, 1, 1] + [0, 0.02, -0.06], s * [1.04, 1, 1] + [0, 0.02, 0.06]], cap_start=False, cap_end=False)
        fr = filt(fr, lambda c: c[1] > 1.0)
        parts["dark"].append(fr)
    # ---------------- engines
    for sx in (-1, 1):
        X = 3.35 * sx
        prof = [(0.75, -2.6), (1.05, -2.8), (1.12, -3.2), (1.15, -5.0), (1.08, -5.1), (1.15, -5.2), (1.15, -8.6), (1.02, -9.2), (1.2, -10.6), (1.1, -10.7), (0.85, -9.9)]
        nac = lathe(prof, 20); nac.transform(None, (X, 0.55, 0))
        parts["hull"].append(nac)
        for zr in (-5.1, -8.0):
            band = lathe([(1.17, zr - 0.25), (1.17, zr + 0.25)], 20); band.transform(None, (X, 0.55, 0)); parts["trim"].append(band)
        core = lathe([(0.0, -9.6), (0.8, -9.8)], 20); core.transform(None, (X, 0.55, 0)); parts["glow"].append(core)
        intake = lathe([(0.0, -3.4), (0.78, -2.7)], 20); intake.transform(None, (X, 0.55, 0)); parts["dark"].append(intake)
        # vanes inside the intake
        for k in range(6):
            v = bevel_box((0.05, 1.4, 0.2), 0.01); v.transform(rotz(k * math.pi / 6), (X, 0.55, -2.95)); parts["dark"].append(v)
        # pylon
        py = hull_of([(sx * 2.4, 1.0, -3.0), (sx * 2.4, 1.0, -8.6), (sx * 2.5, 0.1, -3.5), (sx * 2.5, 0.1, -8.4),
                      (sx * 2.9, 0.9, -3.4), (sx * 2.9, 0.9, -8.2), (sx * 2.9, 0.2, -3.6), (sx * 2.9, 0.2, -8.2)])
        parts["dark"].append(py)
        # exhaust petals
        for k in range(10):
            a = k / 10 * 2 * math.pi
            pet = bevel_box((0.42, 0.05, 0.7), 0.02)
            ca, sa = math.cos(a), math.sin(a)
            tilt = np.array([[1, 0, 0], [0, math.cos(-0.12), -math.sin(-0.12)], [0, math.sin(-0.12), math.cos(-0.12)]])
            pet.transform(rotz(a - math.pi / 2) @ tilt, (X + ca * 1.14, 0.55 + sa * 1.14, -10.85))
            parts["dark"].append(pet)
    # ---------------- wings
    def wing(sx, root_x, jag=False, span=7.2):
        secs = []
        steps = 6
        for i in range(steps + 1):
            f = i / steps
            x = sx * (root_x + span * f)
            zf = -1.0 - 3.6 * f          # leading edge sweeps back
            chord = 6.2 - 4.0 * f
            th = 0.42 - 0.27 * f
            y = -0.35 + 0.35 * f         # slight dihedral
            pts = [(zf, 0.0), (zf - chord * 0.1, th * 0.5), (zf - chord * 0.75, th * 0.5), (zf - chord, 0.04),
                   (zf - chord * 0.75, -th * 0.5), (zf - chord * 0.1, -th * 0.5)]
            secs.append(np.array([(x, y + yy, z) for z, yy in pts]))
        if jag:   # torn root: ragged ring
            r = secs[0].copy()
            r[:, 0] += sx * (rng.random(len(r)) * 0.7)
            r[:, 1] += rng.normal(0, 0.08, len(r))
            secs[0] = r
        return loft(secs, cap_start=True, cap_end=True)
    wl = wing(-1, 2.6)
    tipL = hull_of([(-9.6, -0.05, -4.6), (-9.8, -0.05, -6.8), (-9.7, -1.2, -6.4), (-9.9, 0.8, -6.6), (-9.75, 0.1, -5.0),
                    (-9.45, -0.05, -4.6), (-9.45, -1.15, -6.3), (-9.6, 0.75, -6.5)])
    for b2 in (wl,): parts["hull"].append(b2)
    parts["trim"].append(tipL)
    # wing cannon on the left tip
    gun = lathe([(0.14, -3.0), (0.14, 1.2), (0.08, 1.25), (0.08, 2.2), (0.11, 2.3), (0.11, 2.6)], 10); gun.transform(None, (-8.4, -0.45, -1.8))
    parts["dark"].append(gun)
    # torn right wing (separate node), and a ragged stub with spars on the hull
    wr = wing(1, 3.4, jag=True, span=6.4)
    tipR = hull_of([(9.6, -0.05, -4.6), (9.8, -0.05, -6.8), (9.7, -1.2, -6.4), (9.9, 0.8, -6.6), (9.75, 0.1, -5.0),
                    (9.45, -0.05, -4.6), (9.45, -1.15, -6.3), (9.6, 0.75, -6.5)])
    stub = wing(1, 2.6, span=0.9)
    stub = jitter(stub, 0.25, 2.2, lambda p: np.clip((p[0] - 2.9) / 0.6, 0, 1), 9)
    parts["hull"].append(stub)
    for k, z in enumerate((-1.6, -3.0, -4.4)):
        spar = bevel_box((1.6 + k * 0.3, 0.12, 0.14), 0.02); spar.transform(rotz(-0.15 + k * 0.12) @ roty(0.1 * k), (3.9 + k * 0.1, -0.3, z))
        parts["dark"].append(spar)
    # ---------------- tail fins
    for sx in (-1, 1):
        fin = hull_of([(sx * 0.4, 2.3, -6.0), (sx * 0.4, 2.3, -9.2), (sx * 1.9, 4.3, -8.9), (sx * 1.9, 4.3, -10.0),
                       (sx * 0.5, 2.2, -6.0), (sx * 0.55, 2.2, -9.2), (sx * 2.0, 4.25, -8.9), (sx * 2.0, 4.25, -10.0)])
        parts["hull"].append(fin)
        cap = bevel_box((0.3, 0.12, 1.2), 0.03); cap.transform(rotz(sx * -0.9), (sx * 1.95, 4.3, -9.45)); parts["trim"].append(cap)
        nl = bevel_box((0.12, 0.12, 0.12), 0.03, (sx * 2.0, 4.42, -9.3)); parts["red"].append(nl)
    # ---------------- greebles
    for sx in (-1, 1):
        for k in range(5):   # side vents
            v = bevel_box((0.12, 0.42, 0.8), 0.04, (sx * 2.78, 0.9, -7.0 + k * 1.0))
            if not (sx > 0 and -3.3 < -7.0 + k < 2.3): parts["dark"].append(v)
        for k in range(3):   # sensor blisters
            d = lathe([(0.0, 0.25), (0.22, 0.2), (0.3, 0.0)], 12, axis='y'); d.transform(None, (sx * 1.1, -1.5, 4.0 - k * 2.4))
            parts["dark"].append(d)
        gb = bevel_box((1.1, 0.12, 2.2), 0.04, (sx * 1.2, -1.52, -3.0)); parts["dark"].append(gb)   # gear doors
        rail = bevel_box((0.1, 0.1, 9.0), 0.03, (sx * 2.65, 1.55, -3.5)); parts["trim"].append(rail)
    # cheek intakes and landing skids
    for sx in (-1, 1):
        ck = hull_of([(sx * 1.9, 0.2, 5.2), (sx * 1.9, -0.9, 5.2), (sx * 2.35, 0.15, 2.8), (sx * 2.35, -0.95, 2.8),
                      (sx * 1.7, 0.2, 5.2), (sx * 1.7, -0.9, 5.2), (sx * 2.1, 0.15, 2.6), (sx * 2.1, -0.95, 2.6)])
        if sx < 0: parts["hull"].append(ck)
        mouth = bevel_box((0.42, 0.95, 0.06), 0.02, (sx * 2.08, -0.38, 5.2)); parts["dark"].append(mouth)
        sk = bevel_box((0.18, 0.18, 5.5), 0.05, (sx * 1.3, -1.95, -2.5)); parts["dark"].append(sk)
        for z in (-4.5, -0.5):
            leg = bevel_box((0.12, 0.6, 0.12), 0.03, (sx * 1.3, -1.7, z)); parts["dark"].append(leg)
    # nose cannons
    for sx in (-1, 1):
        g2 = lathe([(0.12, 7.0), (0.12, 10.8), (0.07, 10.85), (0.07, 11.6), (0.1, 11.7), (0.1, 11.9)], 10)
        g2.transform(None, (sx * 0.85, -0.85, 0)); parts["dark"].append(g2)
    # rear ramp outline + dorsal antenna array + comms dish
    ramp = bevel_box((2.6, 1.7, 0.08), 0.04, (0, -0.1, -9.62)); parts["dark"].append(ramp)
    for k in range(3):
        an = lathe([(0.03, 0), (0.03, 1.2 + k * 0.4)], 6, axis='y'); an.transform(None, (-0.25 + k * 0.25, 2.55, -2.0 - k * 0.6)); parts["dark"].append(an)
    dish = lathe([(0.0, 0.25), (0.45, 0.0), (0.5, 0.05)], 16, axis='y'); dish.transform(rotx(0.5), (0.0, 2.6, -6.6)); parts["dark"].append(dish)
    # red faction stripe along both flanks
    for sx in (-1, 1):
        st = bevel_box((0.05, 0.22, 7.0), 0.01, (sx * 2.77, 0.3, 4.0 if sx > 0 else 1.0)); parts["trim"].append(st)
    # nav lights
    for p in [(-9.85, 0.0, -5.6)]:
        parts["red"].append(bevel_box((0.14, 0.14, 0.14), 0.04, p))
    return parts, wr, tipR

def vcol(P, burn_bias=0.0):
    """Grime + scorch as vertex colour (multiplied into albedo)."""
    g = fbm3(P * 0.35, 3) * 0.5 + 0.5
    streak = noise3(P * np.array([2.5, 0.25, 2.5])) * 0.5 + 0.5
    low = np.clip((-P[:, 1] + 0.2) / 2.0, 0, 1)
    grime = np.clip(g * 0.35 + streak * 0.15 + low * 0.25 - 0.15, 0, 0.6)
    hot = np.array([2.6, 0.45, -0.6])
    dd = np.linalg.norm((P - hot) * np.array([1.0, 1.3, 0.8]), axis=1)
    near = np.clip(1.25 - dd / 3.2, 0, 1) ** 1.2
    eng = np.clip(1 - np.abs(P[:, 2] + 10.3) / 2.0, 0, 1) * 0.7
    nose = np.clip((P[:, 2] - 8.0) / 3.0, 0, 1) * 0.6
    patch = np.clip((fbm3(P * 0.22 + 40, 3) - 0.15) * 2.2, 0, 1)
    burn = np.clip(near * 0.9 + eng + nose + patch * 0.6 + burn_bias, 0, 1)
    c = (1 - grime)[:, None] * np.ones((len(P), 3))
    c = c * (1 - burn[:, None] * 0.92) + np.array([0.28, 0.12, 0.04]) * (burn * (1 - burn))[:, None] * 0.8
    return np.hstack([np.clip(c, 0, 1), np.ones((len(P), 1))]).astype(np.float32)

def merge(ms):
    m = Mesh()
    for x in ms: m.extend(x)
    return m

if __name__ == "__main__":
    import sys
    parts, wr, tipR = build()
    g = GLB()
    a, n, mr = hull_panels(2048, base=(0.6, 0.61, 0.64))
    ta, tn, tm = g.image(a, "hull_albedo"), g.image(n, "hull_normal"), g.image(mr, "hull_mr")
    g.material("Hull", albedo_tex=ta, normal_tex=tn, mr_tex=tm, metal=1.0, rough=1.0)
    g.material("DarkMetal", color=(0.22, 0.23, 0.25, 1), albedo_tex=ta, normal_tex=tn, mr_tex=tm, metal=1.0, rough=1.1)
    g.material("Trim", color=(0.62, 0.09, 0.07, 1), albedo_tex=ta, normal_tex=tn, mr_tex=tm, metal=0.4, rough=1.0)
    g.material("Glass", color=(0.03, 0.05, 0.07, 0.82), metal=0.2, rough=0.06, blend=True, double=True)
    g.material("EngineGlow", color=(0.1, 0.05, 0.02, 1), emissive=(1.0, 0.42, 0.12), emissive_strength=3.0, rough=0.6)
    g.material("NavLight", color=(0.3, 0.02, 0.02, 1), emissive=(1.0, 0.12, 0.06), emissive_strength=4.0)
    g.material("Interior", color=(0.08, 0.085, 0.09, 1), albedo_tex=ta, normal_tex=tn, mr_tex=tm, metal=0.8, rough=1.2, double=True)
    root = None   # Hull and WingR sit at the scene root (wreck.gd looks for WingR there)
    body = []
    for key, mat in [("hull", "Hull"), ("dark", "DarkMetal"), ("trim", "Trim"), ("glass", "Glass"), ("glow", "EngineGlow"), ("red", "NavLight"), ("inner", "Interior")]:
        m = merge(parts[key])
        P, N = m.arrays()
        col = vcol(P) if key in ("hull", "dark", "trim", "inner") else None
        body.append((m, mat, col, 0.25))
    g.mesh_node("Hull", body, parent=root)
    wm = merge([wr]); tm2 = merge([tipR])
    P, _ = wm.arrays(); ctr = P.mean(axis=0)
    wm.transform(None, -ctr); tm2.transform(None, -ctr)   # centre the torn wing on its origin
    P, _ = wm.arrays(); P2, _ = tm2.arrays()
    g.mesh_node("WingR", [(wm, "Hull", vcol(P + ctr, 0.15), 0.25), (tm2, "Trim", vcol(P2 + ctr, 0.15), 0.25)], parent=root)
    g.save(sys.argv[1] if len(sys.argv) > 1 else "crashed_ship.glb")
    print("tris", sum(len(merge(parts[k]).P) for k in parts) // 3)
