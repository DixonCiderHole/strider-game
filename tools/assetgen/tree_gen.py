"""High-detail trees for Strider (models/trees.glb).
Node names match the old nature-kit models (Pine_1.., CommonTree_1.., DeadTree_1..,
TwistedTree_1..) at roughly the same size, so every scene picks them up, plus
Cherry_1.. blossom trees and a FallenLog. Foliage materials are named Foliage_*
(the game swaps in a wind-sway shader for those)."""
import math, numpy as np
from meshlib import Mesh, GLB, rotx, roty, rotz
from tree_tex import bark, pine_sprig, broadleaf, blossom, petals

TEX_WORLD = 1.1   # model units per bark texture repeat (along the limb)

def _norm(v):
    v = np.asarray(v, float); l = np.linalg.norm(v)
    return v / l if l > 1e-9 else v

class Tree:
    def __init__(self, seed):
        self.rng = np.random.default_rng(seed)
        self.bark = Mesh(); self.leaf = Mesh(); self.leaf_col = []
        self.limbs = []; self.cards = []     # recorded so lower-detail versions keep the same shape
        self.crown = np.array([0.0, 4.0, 0.0]); self.crown_r = np.array([2.0, 2.0, 2.0])

    # ------------------------------------------------------------ limbs
    def limb(self, pts, radii, sides=6, flare=None, v0=0.0):
        self.limbs.append((list(pts), list(radii), sides, flare, v0))
        return self._emit_limb(self.bark, pts, radii, sides, flare, v0)

    def _emit_limb(self, m, pts, radii, sides=6, flare=None, v0=0.0):
        pts = [np.asarray(p, float) for p in pts]
        n = len(pts)
        T = [_norm(pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]) for i in range(n)]
        up = np.array([0, 1.0, 0]) if abs(T[0][1]) < 0.95 else np.array([1.0, 0, 0])
        A = [_norm(np.cross(T[0], up))]
        for i in range(1, n):    # parallel transport
            a = A[-1] - T[i] * np.dot(A[-1], T[i])
            A.append(_norm(a))
        B = [np.cross(T[i], A[i]) for i in range(n)]
        circ = 2 * math.pi * radii[0]
        urep = max(1, int(round(circ / TEX_WORLD)))
        rings = []; v = v0
        for i in range(n):
            if i: v += np.linalg.norm(pts[i] - pts[i - 1]) / TEX_WORLD
            ring = []
            for k in range(sides + 1):
                th = 2 * math.pi * k / sides
                r = radii[i] * (flare(i / (n - 1), th) if flare else 1.0)
                d = A[i] * math.cos(th) + B[i] * math.sin(th)
                ring.append((pts[i] + d * r, d, (k / sides * urep, v)))
            rings.append(ring)
        for i in range(n - 1):
            for k in range(sides):
                a, b, c, d = rings[i][k], rings[i][k + 1], rings[i + 1][k + 1], rings[i + 1][k]
                for tri in ((a, c, b), (a, d, c)):
                    p0, p1, p2 = tri
                    f = np.cross(p1[0] - p0[0], p2[0] - p0[0])
                    if np.dot(f, p0[1] + p1[1] + p2[1]) < 0: tri = (p0, p2, p1)
                    for q in tri:
                        m.P.append(q[0]); m.N.append(q[1]); m.UV.append(q[2])
        return v

    def path(self, start, d, length, steps, bend=0.0, gravity=0.0, wobble=0.08, attract=None):
        p = np.asarray(start, float); d = _norm(d)
        pts = [p.copy()]; seg = length / steps
        for i in range(steps):
            d = d + self.rng.normal(0, wobble, 3) + np.array([0, gravity, 0])
            if attract is not None: d = d + attract * bend
            d = _norm(d)
            p = p + d * seg; pts.append(p.copy())
        return pts

    # ------------------------------------------------------------ foliage cards
    def card(self, base, up, w, h, roll=None, tint=1.0):
        rng = self.rng
        up = _norm(up)
        side = _norm(np.cross(up, rng.normal(0, 1, 3) if roll is None else roll))
        nrm = _norm(np.cross(side, up))
        c = np.asarray(base, float) + up * h * 0.5
        out = _norm((c - self.crown) / self.crown_r)
        out = _norm(out + np.array([0, 0.75, 0]))
        n = _norm(nrm * (1 if np.dot(nrm, out) > 0 else -1) * 0.3 + out * 0.7)
        b = np.asarray(base, float) - up * h * 0.04
        a0, a1 = b - side * w / 2, b + side * w / 2
        a2, a3 = a1 + up * h, a0 + up * h
        m = self.leaf
        m.quad_uv(a0, a1, a2, a3, (0, 1), (1, 1), (1, 0), (0, 0), n=n)
        m.quad_uv(a1, a0, a3, a2, (1, 1), (0, 1), (0, 0), (1, 0), n=n)
        rec = [b, side, up, w, h, n]
        # colour: brighter on the outside / top of the crown, per-card variation
        d = np.linalg.norm((c - self.crown) / self.crown_r)
        ao = 0.5 + 0.5 * min(1.0, d) ** 1.3 + 0.1 * np.clip((c[1] - self.crown[1]) / self.crown_r[1], -1, 1)
        hue = np.array([1.0, 1.0, 1.0]) * rng.uniform(0.88, 1.08) * tint
        hue *= np.array([rng.uniform(0.92, 1.08), 1.0, rng.uniform(0.9, 1.05)])
        col = np.clip(np.append(hue * np.clip(ao, 0.45, 1.1), 1.0), 0, 1.2)
        self.leaf_col += [col] * 12
        rec.append(col); self.cards.append(rec)

    # ------------------------------------------------------------ level of detail
    def lod(self, level):
        """Same tree, less geometry: drops twigs, halves sides and rings, and
        keeps a share of the foliage cards, enlarged to cover the same crown."""
        bark, leaf, cols = Mesh(), Mesh(), []
        min_r, keep, grow = {1: (0.011, 0.45, 1.38), 2: (0.045, 0.22, 1.95)}[level]
        for (pts, radii, sides, flare, v0) in self.limbs:
            if radii[0] < min_r: continue
            if level == 1:
                idx = list(range(0, len(pts), 2))
                sd = max(3, (sides + 1) // 2 + 1)
            else:
                idx = [0, len(pts) // 2] if len(pts) > 3 else [0]
                sd = 6 if radii[0] > 0.15 else 4
            if idx[-1] != len(pts) - 1: idx.append(len(pts) - 1)
            self._emit_limb(bark, [pts[i] for i in idx], [radii[i] for i in idx], sd, flare, v0)
        r = np.random.default_rng(97 + level)
        for (b, side, up, w, h, n, col) in self.cards:
            if r.random() > keep: continue
            g = grow * r.uniform(0.9, 1.1)
            if level == 2:
                b = self.crown + (b - self.crown) * 0.82
            a0, a1 = b - side * w * g / 2, b + side * w * g / 2
            a2, a3 = a1 + up * h * g, a0 + up * h * g
            leaf.quad_uv(a0, a1, a2, a3, (0, 1), (1, 1), (1, 0), (0, 0), n=n)
            leaf.quad_uv(a1, a0, a3, a2, (1, 1), (0, 1), (0, 0), (1, 0), n=n)
            cols += [col] * 12
        return bark, leaf, cols

    def bark_colors(self, moss=0.3, mesh=None):
        P, N = (mesh or self.bark).arrays()
        ao = np.clip(0.55 + 0.45 * np.clip(P[:, 1] / 1.6, 0, 1), 0, 1)
        green = np.clip((1.4 - P[:, 1]) / 1.4, 0, 1) * np.clip(N[:, 1] * 0.5 + 0.6 + N[:, 2] * 0.3, 0, 1) * moss
        c = np.ones((len(P), 3)) * ao[:, None]
        c = c * (1 - green[:, None]) + c * np.array([0.55, 0.75, 0.4]) * green[:, None]
        return np.hstack([c, np.ones((len(P), 1))]).astype(np.float32)

# ---------------------------------------------------------------- species
def pine(seed):
    t = Tree(seed); r = t.rng
    Ht = r.uniform(6.6, 7.6)
    t.crown = np.array([0, Ht * 0.5, 0]); t.crown_r = np.array([2.2, Ht * 0.55, 2.2])
    lean = r.normal(0, 0.03, 3); lean[1] = 1
    trunk = t.path((0, -0.3, 0), lean, Ht + 0.3, 14, wobble=0.015)
    radii = [0.21 * (1 - i / 14) ** 1.1 + 0.012 for i in range(15)]
    t.limb(trunk, radii, 10, flare=lambda f, th: 1 + 0.45 * math.exp(-f * 30) * (1 + 0.25 * math.sin(th * 5)))
    def trunk_at(y):
        i = min(13, max(0, int((y + 0.3) / (Ht + 0.3) * 14)))
        return trunk[i] + (trunk[i + 1] - trunk[i]) * (((y + 0.3) / (Ht + 0.3) * 14) - i)
    y = 0.9; twist = r.uniform(0, 6.3)
    while y < Ht - 0.35:
        f = y / Ht
        nb = r.integers(4, 7)
        twist += r.uniform(0.6, 1.2)
        for k in range(nb):
            az = twist + 2 * math.pi * k / nb + r.normal(0, 0.2)
            base = trunk_at(y)
            if y < 1.9:     # dead lower stubs
                if r.random() < 0.5:
                    pts = t.path(base, (math.cos(az), -0.1, math.sin(az)), r.uniform(0.2, 0.55), 2, wobble=0.1)
                    t.limb(pts, [0.03, 0.012, 0.004], 4)
                continue
            L = (1 - f) * 2.5 * r.uniform(0.8, 1.1) + 0.3
            elev = -0.45 + 0.75 * f
            d = np.array([math.cos(az), elev, math.sin(az)])
            pts = t.path(base, d, L, 4, gravity=-0.07 * (1 - f), wobble=0.05)
            pts[-1] = pts[-1] + np.array([0, 0.08 * L, 0])     # tips curl up
            rb = 0.012 + 0.022 * L / 2.5
            t.limb(pts, [rb, rb * 0.7, rb * 0.45, rb * 0.25, 0.004], 5)
            # needle sprigs along the outer part of the branch
            ns = max(2, int(L / 0.32))
            for j in range(ns):
                s = 0.2 + 0.8 * j / max(1, ns - 1)
                i0 = min(3, int(s * 4)); u = s * 4 - i0
                p = pts[i0] + (pts[i0 + 1] - pts[i0]) * u
                bd = _norm(pts[i0 + 1] - pts[i0])
                sideway = _norm(np.cross(bd, (0, 1, 0)))
                sz = 0.62 + 0.35 * min(1.0, L / 2.0)
                for sgn in (-1, 1):
                    up = _norm(bd * 0.7 + sideway * sgn * 0.6 + np.array([0, 0.12, 0]))
                    t.card(p, up, sz, sz, roll=np.array([0, 1.0, 0]) + r.normal(0, 0.25, 3))
            t.card(pts[-1] - _norm(pts[-1] - pts[-2]) * 0.1, _norm(pts[-1] - pts[-2]) + np.array([0, 0.1, 0]), 0.75, 0.75, roll=np.array([0, 1.0, 0]))
        y += r.uniform(0.3, 0.42)
    top = trunk[-1]
    for k in range(3):   # leader
        a = k * math.pi / 3
        t.card(top - np.array([0, 0.55, 0]), (0, 1, 0), 0.55, 0.9, roll=np.array([math.cos(a), 0, math.sin(a)]))
    return t

def _branchy(t, start, d, L, r0, level, max_level, spread, kids, leaf_fn, gravity=0.0, upward=0.15, steps=5):
    r = t.rng
    attract = np.array([0, 1.0, 0])
    pts = t.path(start, d, L, steps, bend=upward, gravity=gravity, wobble=0.09, attract=attract)
    radii = [r0 * (1 - 0.75 * i / steps) for i in range(steps + 1)]
    radii[-1] = max(radii[-1], 0.004)
    t.limb(pts, radii, max(4, 9 - 2 * level))
    if level >= max_level:
        leaf_fn(t, pts)
        return
    nk = kids[level]
    for k in range(nk):
        s = r.uniform(0.35, 0.95) if level else r.uniform(0.45, 1.0)
        i0 = min(steps - 1, int(s * steps)); u = s * steps - i0
        p = pts[i0] + (pts[i0 + 1] - pts[i0]) * u
        bd = _norm(pts[i0 + 1] - pts[i0])
        az = r.uniform(0, 2 * math.pi)
        perp = _norm(np.cross(bd, (math.cos(az), 0.3, math.sin(az))))
        nd = _norm(bd * math.cos(spread[level]) + perp * math.sin(spread[level]))
        rr = radii[i0] * r.uniform(0.55, 0.75)
        _branchy(t, p, nd, L * r.uniform(0.5, 0.68), rr, level + 1, max_level, spread, kids, leaf_fn, gravity, upward, max(3, steps - 1))
    if level >= max_level - 1:
        leaf_fn(t, pts[len(pts) // 2:])

def _leaves(size, per=4, tint=1.0):
    def fn(t, pts):
        r = t.rng
        tip = pts[-1]; bd = _norm(pts[-1] - pts[-2])
        for k in range(per):
            out = _norm(tip - t.crown)
            up = _norm(bd * 0.6 + out * 0.6 + r.normal(0, 0.45, 3))
            base = pts[r.integers(max(0, len(pts) - 3), len(pts))]
            t.card(base, up, size * r.uniform(0.85, 1.15), size * r.uniform(0.85, 1.15), tint=tint)
    return fn

def broad(seed):
    t = Tree(seed); r = t.rng
    Ht = r.uniform(7.0, 9.0)
    fork = r.uniform(2.0, 2.8)
    t.crown = np.array([0, fork + (Ht - fork) * 0.5, 0]); t.crown_r = np.array([2.4, (Ht - fork) * 0.55, 2.4])
    trunk = t.path((0, -0.3, 0), (r.normal(0, 0.04), 1, r.normal(0, 0.04)), fork + 0.3, 6, wobble=0.03)
    t.limb(trunk, [0.24 * (1 - 0.3 * i / 6) for i in range(7)], 10, flare=lambda f, th: 1 + 0.5 * math.exp(-f * 18) * (1 + 0.3 * math.sin(th * 4)))
    nl = r.integers(3, 5)
    for k in range(nl):
        az = 2 * math.pi * k / nl + r.normal(0, 0.3)
        d = (math.cos(az) * 0.55, 1, math.sin(az) * 0.55)
        _branchy(t, trunk[-1] - np.array([0, 0.1, 0]), d, (Ht - fork) * r.uniform(0.6, 0.75), 0.14, 0, 2,
                 spread=[0.75, 0.85, 0.9], kids=[4, 3], leaf_fn=_leaves(1.3, 7), upward=0.12)
    return t

def cherry(seed):
    t = Tree(seed); r = t.rng
    fork = r.uniform(1.1, 1.5)
    t.crown = np.array([0, 3.6, 0]); t.crown_r = np.array([3.0, 1.8, 3.0])
    trunk = t.path((0, -0.3, 0), (r.normal(0, 0.06), 1, r.normal(0, 0.06)), fork + 0.3, 4, wobble=0.04)
    t.limb(trunk, [0.2, 0.18, 0.17, 0.16, 0.15], 10, flare=lambda f, th: 1 + 0.4 * math.exp(-f * 14) * (1 + 0.2 * math.sin(th * 3)))
    nl = r.integers(4, 6)
    def bloom(t, pts):
        rr = t.rng
        for j, p in enumerate(pts[1:], 1):
            bd = _norm(pts[j] - pts[j - 1])
            for k in range(3):
                out = _norm(p - t.crown)
                up = _norm(bd * 0.5 + out * 0.5 + np.array([0, 0.35, 0]) + rr.normal(0, 0.5, 3))
                t.card(p, up, rr.uniform(0.75, 1.0), rr.uniform(0.75, 1.0))
    for k in range(nl):
        az = 2 * math.pi * k / nl + r.normal(0, 0.25)
        d = (math.cos(az) * 0.9, 1, math.sin(az) * 0.9)     # vase shape
        _branchy(t, trunk[-1] - np.array([0, 0.05, 0]), d, r.uniform(2.4, 3.0), 0.1, 0, 2,
                 spread=[0.7, 0.8, 0.9], kids=[4, 3], leaf_fn=bloom, gravity=-0.03, upward=0.05)
    return t

def dead(seed):
    t = Tree(seed); r = t.rng
    Ht = r.uniform(7.5, 9.0)
    trunk = t.path((0, -0.3, 0), (r.normal(0, 0.08), 1, r.normal(0, 0.08)), Ht * 0.88, 10, wobble=0.06)
    rad = [0.23 * (1 - 0.85 * i / 10) + 0.01 for i in range(11)]
    t.limb(trunk, rad, 9, flare=lambda f, th: 1 + 0.6 * math.exp(-f * 16) * (1 + 0.35 * math.sin(th * 4)))
    for i in range(3, 10):
        if r.random() < 0.7:
            az = r.uniform(0, 2 * math.pi)
            d = (math.cos(az), r.uniform(0.2, 0.9), math.sin(az))
            _branchy(t, trunk[i], d, r.uniform(1.8, 3.2) * (1 - i / 16), rad[i] * 0.6, 0, 2,
                     spread=[0.8, 0.9, 0.9], kids=[3, 2], leaf_fn=lambda t, p: None, upward=0.1, steps=4)
    return t

def oak(seed):
    """Big, gnarled meadow tree with a wide crown and surface roots."""
    t = Tree(seed); r = t.rng
    fork = r.uniform(2.6, 3.4)
    t.crown = np.array([0, 7.2, 0]); t.crown_r = np.array([5.5, 3.2, 5.5])
    trunk = t.path((0, -0.4, 0), (r.normal(0, 0.05), 1, r.normal(0, 0.05)), fork + 0.4, 6, wobble=0.04)
    t.limb(trunk, [0.62 * (1 - 0.3 * i / 6) for i in range(7)], 14,
           flare=lambda f, th: (1 + 0.6 * math.exp(-f * 10) * (1 + 0.35 * math.sin(th * 5))) * (1 + 0.06 * math.sin(th * 3 + f * 9)))
    for k in range(6):   # surface roots
        az = k * math.pi / 3 + r.normal(0, 0.2)
        pts = t.path((math.cos(az) * 0.35, 0.12, math.sin(az) * 0.35), (math.cos(az), -0.18, math.sin(az)), r.uniform(1.6, 2.6), 5, wobble=0.06, gravity=-0.015)
        t.limb(pts, [0.3, 0.22, 0.16, 0.11, 0.07, 0.03], 8)
    nl = r.integers(3, 5)
    for k in range(nl):
        az = 2 * math.pi * k / nl + r.normal(0, 0.3)
        d = (math.cos(az) * 1.4, 1, math.sin(az) * 1.4)
        _branchy(t, trunk[-1] - np.array([0, 0.2, 0]), d, r.uniform(5.0, 6.2), 0.36, 0, 3,
                 spread=[0.7, 0.8, 0.85, 0.9], kids=[4, 3, 2], leaf_fn=_leaves(1.6, 4, 0.92), upward=0.1, steps=6)
    return t

def fallen_log(seed):
    t = Tree(seed); r = t.rng
    L = 5.2
    pts = [np.array([-L / 2 + L * i / 10, 0.3 + 0.05 * math.sin(i * 0.8), r.normal(0, 0.04)]) for i in range(11)]
    rad = [0.36 - 0.06 * i / 10 for i in range(11)]
    t.limb(pts, rad, 12, flare=lambda f, th: 1 + 0.06 * math.sin(th * 5 + f * 20))
    for end, sgn in ((pts[0], -1), (pts[-1], 1)):     # jagged broken ends
        for k in range(10):
            th = 2 * math.pi * k / 10
            o = np.array([0, math.cos(th), math.sin(th)]) * rad[0 if sgn < 0 else -1] * 0.95
            tip = end + o * 0.6 + np.array([sgn * r.uniform(0.08, 0.35), 0, 0])
            a = end + o; b = end + np.array([0, math.cos(th + 0.63), math.sin(th + 0.63)]) * rad[0 if sgn < 0 else -1] * 0.95
            for tri in ((a, b, tip),):
                n = _norm(np.cross(tri[1] - tri[0], tri[2] - tri[0]))
                if np.dot(n, tip - end) < 0: tri = (a, tip, b); n = -n
                for q in tri:
                    t.bark.P.append(q); t.bark.N.append(n); t.bark.UV.append((q[2], q[1]))
            t.bark.P += [end, b, a] if sgn > 0 else [end, a, b]
            nn = np.array([sgn, 0, 0.0]); t.bark.N += [nn] * 3; t.bark.UV += [(0.5, 0.5), (0.6, 0.5), (0.5, 0.6)]
    for k in range(4):   # broken branch stubs
        p = pts[r.integers(2, 9)]
        d = (r.normal(0, 0.3), r.uniform(0.3, 1), r.choice([-1, 1]))
        s = t.path(p, d, r.uniform(0.4, 0.9), 3, wobble=0.1)
        t.limb(s, [0.08, 0.06, 0.04, 0.02], 6)
    return t

# ---------------------------------------------------------------- export
SPECIES = [("Pine", pine, 5, "Pine"), ("CommonTree", broad, 5, "Broad"), ("DeadTree", dead, 3, "Dead"),
           ("TwistedTree", oak, 5, "Oak"), ("Cherry", cherry, 3, "Cherry")]

def export(path):
    g = GLB()
    for name, style, seed in [("Pine", "plates", 61), ("Broad", "furrow", 62), ("Cherry", "cherry", 63), ("Dead", "dead", 64), ("Oak", "furrow", 65)]:
        a, n, mr = bark(1024, seed=seed, style=style)
        if name == "Oak":
            a = a.point(lambda v: int(v * 0.85))
        g.material("Bark_" + name, albedo_tex=g.image(a, name + "_bark_a"), normal_tex=g.image(n, name + "_bark_n"), mr_tex=g.image(mr, name + "_bark_mr"), rough=1.0)
    for name, (img, nrm) in [("Pine", pine_sprig()), ("Broad", broadleaf(seed=71)), ("Oak", broadleaf(seed=72)), ("Cherry", blossom())]:
        g.material("Foliage_" + name, albedo_tex=g.image(img, name + "_leaf_a"), normal_tex=g.image(nrm, name + "_leaf_n"), rough=0.8, mask=True, cutoff=0.5)
    pa, pn = petals()
    g.material("Petals", albedo_tex=g.image(pa, "petals_a"), normal_tex=g.image(pn, "petals_n"), rough=0.8, mask=True, cutoff=0.5)
    x = 0.0
    for name, fn, count, mat in SPECIES:
        for i in range(count):
            t = fn(1000 + hash(name) % 97 * 10 + i if False else 1000 + len(name) * 37 + i * 11)
            parts = [(t.bark, "Bark_" + mat, t.bark_colors(0.45 if mat != "Cherry" else 0.15), 1)]
            if t.leaf.P:
                parts.append((t.leaf, "Foliage_" + mat, np.array(t.leaf_col, np.float32), 1))
            if mat == "Cherry":
                pm = Mesh()
                for k in range(5):   # fallen petals on the ground under the crown
                    a = k * 1.256 + t.rng.normal(0, 0.3); rr = t.rng.uniform(0.6, 2.4); s = t.rng.uniform(1.6, 2.6)
                    c = np.array([math.cos(a) * rr, 0.02 + 0.003 * k, math.sin(a) * rr])
                    sd = np.array([math.cos(a * 3), 0, math.sin(a * 3)]); fw = np.cross(sd, (0, 1, 0))
                    pm.quad_uv(c - sd * s / 2 - fw * s / 2, c + sd * s / 2 - fw * s / 2, c + sd * s / 2 + fw * s / 2, c - sd * s / 2 + fw * s / 2,
                               (0, 1), (1, 1), (1, 0), (0, 0), n=np.array([0, 1.0, 0]))
                    if np.dot(np.cross(pm.P[-5] - pm.P[-6], pm.P[-4] - pm.P[-6]), (0, 1, 0)) < 0:
                        pm.P[-6:] = [pm.P[-6], pm.P[-4], pm.P[-5], pm.P[-3], pm.P[-1], pm.P[-2]]
                        pm.UV[-6:] = [pm.UV[-6], pm.UV[-4], pm.UV[-5], pm.UV[-3], pm.UV[-1], pm.UV[-2]]
                parts.append((pm, "Petals", None, 1))
            g.mesh_node(f"{name}_{i + 1}", parts, translation=(x, 0, 0))
            moss = 0.45 if mat != "Cherry" else 0.15
            for lv in (1, 2):
                lb, ll, lc = t.lod(lv)
                lparts = [(lb, "Bark_" + mat, t.bark_colors(moss, lb), 1)]
                if ll.P:
                    lparts.append((ll, "Foliage_" + mat, np.array(lc, np.float32), 1))
                if lv == 1 and mat == "Cherry":
                    lparts.append(parts[-1])
                g.mesh_node(f"{name}_{i + 1}_LOD{lv}", lparts, translation=(x, 0, 12.0 * lv))
                print(f"   LOD{lv}: {(len(lb.P) + len(ll.P)) // 3} tris")
            P, _ = t.bark.arrays()
            print(f"{name}_{i + 1}: bark {len(t.bark.P) // 3} tris, leaves {len(t.leaf.P) // 3} tris, h {P[:, 1].max():.1f}")
            x += 12.0
    lg = fallen_log(7)
    P, N = lg.bark.arrays()
    from meshlib import fbm3
    mossy = np.clip(N[:, 1] * 1.4 - 0.2, 0, 1) * np.clip(fbm3(P * 1.7, 3) * 1.5 + 0.6, 0, 1)
    lc = np.ones((len(P), 4), np.float32)
    lc[:, :3] = (1 - mossy[:, None]) * 0.85 + mossy[:, None] * np.array([0.38, 0.55, 0.22])
    g.mesh_node("FallenLog", [(lg.bark, "Bark_Broad", lc, 1)], translation=(x, 0, 0))
    g.save(path)

if __name__ == "__main__":
    export("trees.glb")
