"""Procedural textures for trees: barks, pine sprigs, broadleaf twigs, cherry
blossom clusters, fallen petals. All RGBA foliage cards: twig base at the
bottom centre, growing up the card."""
import math, numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage
from textures import _tile_noise, _normal_from_height, _img

def _wrap_blur(a, sy, sx):
    return ndimage.gaussian_filter(a, (sy, sx), mode='wrap')

def bark(n=1024, seed=1, style="furrow"):
    """Tileable bark: returns (albedo, normal, metal_rough)."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:n, 0:n].astype(float)
    if style == "furrow":       # deep vertical ridges that split and merge (oak / common)
        r = _wrap_blur(rng.random((n, n)), 60, 5)
        r = (r - r.min()) / np.ptp(r)
        warp = _tile_noise(n, 3, rng, 3)
        ridges = np.abs(np.sin((xx / n * 2 * np.pi * 9) + warp * 6 + r * 4))
        H = ridges ** 0.6 * 0.75 + _tile_noise(n, 40, rng, 3) * 0.25
        cracks = _wrap_blur(rng.random((n, n)), 2, 0.7) > 0.535
        H = H - cracks * 0.12
        base, dark = np.array([0.36, 0.29, 0.22]), np.array([0.11, 0.085, 0.07])
        lichen = 0.35
    elif style == "plates":     # pine: scaly reddish plates divided by dark fissures
        H = np.zeros((n, n))
        pts = rng.random((260, 2)) * n
        pts[:, 1] *= 1.0
        from scipy.spatial import cKDTree
        tile = np.vstack([pts + np.array([dx, dy]) * n for dx in (-1, 0, 1) for dy in (-1, 0, 1)])
        t = cKDTree(tile * np.array([1.0, 0.45]))
        q = np.dstack([xx, yy]).reshape(-1, 2) * np.array([1.0, 0.45])
        d, _ = t.query(q, k=2)
        edge = (d[:, 1] - d[:, 0]).reshape(n, n)
        H = np.clip(edge / 14.0, 0, 1) ** 0.5
        H = H * 0.8 + _tile_noise(n, 48, rng, 3) * 0.2
        base, dark = np.array([0.52, 0.3, 0.2]), np.array([0.12, 0.08, 0.07])
        lichen = 0.15
    elif style == "cherry":     # smooth glossy red-brown bark with horizontal lenticels
        H = 0.6 + _tile_noise(n, 6, rng, 4) * 0.25
        for k in range(420):
            cx, cy = rng.uniform(0, n), rng.uniform(0, n)
            w, h = rng.uniform(14, 46), rng.uniform(2, 4.5)
            m = (np.abs(((xx - cx + n / 2) % n) - n / 2) < w) & (np.abs(((yy - cy + n / 2) % n) - n / 2) < h)
            H[m] -= 0.35
        rings = (np.sin(yy / n * 2 * np.pi * 26 + _tile_noise(n, 4, rng, 2) * 3) > 0.92)
        H = H - rings * 0.06
        H = _wrap_blur(H, 0.8, 1.5)
        base, dark = np.array([0.36, 0.2, 0.17]), np.array([0.14, 0.08, 0.07])
        lichen = 0.08
    else:                       # dead: bleached grey wood with long splits
        r = _wrap_blur(rng.random((n, n)), 90, 2.5)
        r = (r - r.min()) / np.ptp(r)
        H = 0.55 + r * 0.45
        splits = r < 0.22
        H[splits] = 0.1
        base, dark = np.array([0.55, 0.52, 0.47]), np.array([0.16, 0.15, 0.14])
        lichen = 0.2
    H = (H - H.min()) / (np.ptp(H) + 1e-9)
    fine = _tile_noise(n, 96, rng, 2)
    c = dark + (base - dark) * (H[..., None] ** 0.8) * (0.85 + 0.3 * fine[..., None])
    # lichen / moss blotches in the crevices
    ln = _tile_noise(n, 8, rng, 4)
    lm = np.clip((ln - (1 - lichen)) * 6, 0, 1) * (1 - H) ** 0.5
    c = c * (1 - lm[..., None] * 0.7) + np.array([0.33, 0.4, 0.2]) * lm[..., None] * 0.7
    nrm = _normal_from_height(_wrap_blur(H, 1.0, 1.0), 9.0 if style != "cherry" else 5.0)
    rough = np.clip(0.95 - H * 0.15 - (0.3 if style == "cherry" else 0), 0, 1)
    mr = np.dstack([np.ones_like(rough), rough, np.zeros_like(rough)])
    return _img(c), Image.fromarray(nrm), _img(mr)

def _finish(rgba_big, hgt_big, size):
    rgba = rgba_big.resize(size, Image.LANCZOS)
    a = np.asarray(rgba).astype(float) / 255
    # bleed colour into transparent texels so mip-maps don't fringe dark
    alpha = a[..., 3]
    col = a[..., :3].copy()
    known = alpha > 0.5
    if known.any():
        idx = ndimage.distance_transform_edt(~known, return_distances=False, return_indices=True)
        col = col[idx[0], idx[1]]
    out = np.dstack([col, (alpha > 0.5).astype(float)])
    h = np.asarray(hgt_big.resize(size, Image.LANCZOS), float) / 255
    nrm = _normal_from_height(ndimage.gaussian_filter(h, 1.0), 6.0)
    return _img(out), Image.fromarray(nrm)

def pine_sprig(w=1024, h=1024, seed=21, ss=2):
    rng = np.random.default_rng(seed)
    W, H = w * ss, h * ss
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    hg = Image.new("L", (W, H), 0); dh = ImageDraw.Draw(hg)
    def twig(x0, y0, ang, length, width, depth):
        pts = [(x0, y0)]
        x, y = x0, y0
        steps = 36
        for i in range(steps):
            ang += rng.normal(0, 0.025)
            x += math.cos(ang) * length / steps; y -= math.sin(ang) * length / steps
            pts.append((x, y))
        # needles first (behind the twig)
        for i, (px, py) in enumerate(pts[1:], 1):
            t = i / steps
            for side in (-1, 1):
                for k in range(5):
                    na = ang + side * rng.uniform(0.45, 1.05)
                    nl = (rng.uniform(55, 90) * ss) * (1 - 0.35 * t) * (0.85 if depth else 1.0)
                    ex, ey = px + math.cos(na) * nl, py - math.sin(na) * nl
                    g = np.array([0.1, 0.22, 0.12]) * rng.uniform(0.75, 1.3)
                    tip = np.clip(g * 1.6 + np.array([0.04, 0.05, 0.0]), 0, 1)
                    d.line([(px, py), ((px + ex) / 2, (py + ey) / 2)], fill=tuple(int(v * 255) for v in g) + (255,), width=int(3 * ss))
                    d.line([((px + ex) / 2, (py + ey) / 2), (ex, ey)], fill=tuple(int(v * 255) for v in tip) + (255,), width=int(2 * ss))
                    dh.line([(px, py), (ex, ey)], fill=int(rng.uniform(140, 230)), width=int(3 * ss))
        d.line(pts, fill=(78, 52, 34, 255), width=int(width))
        dh.line(pts, fill=120, width=int(width))
        if depth < 1:
            for i in range(2, steps - 4, 3):
                px, py = pts[i]
                for side in (-1, 1):
                    if rng.random() < 0.85:
                        twig(px, py, ang + side * rng.uniform(0.55, 0.85), length * rng.uniform(0.36, 0.46) * (1 - i / steps * 0.6), width * 0.55, depth + 1)
    twig(W / 2, H - 6 * ss, math.pi / 2 + rng.normal(0, 0.05), H * 0.9, 6 * ss, 0)
    return _finish(im, hg, (w, h))

def _leaf_poly(cx, cy, length, width, ang, serr=0.0, rng=None):
    pts = []
    for i in range(40):
        t = i / 39
        x = t * length
        y = width * math.sin(math.pi * t) ** 0.9 * (1 - 0.25 * t)
        if serr and i % 2: y *= (1 - serr)
        pts.append((x, y))
    pts = pts + [(x, -y) for x, y in pts[::-1]]
    ca, sa = math.cos(ang), math.sin(ang)
    return [(cx + x * ca - y * sa, cy - (x * sa + y * ca)) for x, y in pts]

def broadleaf(n=1024, seed=22, ss=2, palette="green"):
    rng = np.random.default_rng(seed)
    N = n * ss
    im = Image.new("RGBA", (N, N), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    hg = Image.new("L", (N, N), 0); dh = ImageDraw.Draw(hg)
    leaves = []
    def twig(x, y, ang, length, width, depth):
        pts = [(x, y)]
        for i in range(16):
            ang += rng.normal(0, 0.05)
            x += math.cos(ang) * length / 16; y -= math.sin(ang) * length / 16
            pts.append((x, y))
        d.line(pts, fill=(70, 50, 34, 255), width=int(width)); dh.line(pts, fill=110, width=int(width))
        for i in range(2, 17):
            px, py = pts[i]
            side = 1 if i % 2 else -1
            la = ang + side * rng.uniform(0.5, 1.1)
            L = rng.uniform(130, 190) * ss * (1 - 0.3 * i / 16) * (0.85 if depth else 1)
            leaves.append((px, py, la, L))
        leaves.append((pts[-1][0], pts[-1][1], ang + rng.normal(0, 0.2), rng.uniform(170, 220) * ss))
        if depth < 1:
            for k, i in enumerate((3, 6, 8, 10, 12)):
                px, py = pts[i]
                twig(px, py, ang + (-1) ** k * rng.uniform(0.5, 0.9), length * rng.uniform(0.42, 0.55), width * 0.6, depth + 1)
    twig(N / 2, N - 4 * ss, math.pi / 2 + rng.normal(0, 0.08), N * 0.62, 10 * ss, 0)
    rng.shuffle(leaves)
    for (px, py, la, L) in leaves:
        W = L * rng.uniform(0.44, 0.54)
        # petiole
        bx, by = px + math.cos(la) * L * 0.08, py - math.sin(la) * L * 0.08
        d.line([(px, py), (bx, by)], fill=(80, 70, 30, 255), width=int(3 * ss))
        if palette == "green":
            g = np.array([0.2, 0.36, 0.1]) * rng.uniform(0.7, 1.25) + np.array([0.06, 0.04, 0]) * rng.random()
        else:   # young bronze cherry leaves
            g = np.array([0.42, 0.3, 0.12]) * rng.uniform(0.75, 1.2)
        poly = _leaf_poly(bx, by, L, W / 2, la, 0.06)
        d.polygon(poly, fill=tuple(int(np.clip(v, 0, 1) * 255) for v in g) + (255,))
        # lighter half + midrib + veins
        half = _leaf_poly(bx, by, L * 0.98, W / 2 * 0.92, la)[:40] + [(bx + math.cos(la) * L * 0.98, by - math.sin(la) * L * 0.98)]
        hi = tuple(int(np.clip(v * 1.25, 0, 1) * 255) for v in g) + (255,)
        d.polygon(half + [(bx, by)], fill=hi)
        vein = tuple(int(np.clip(v * 1.6 + 0.05, 0, 1) * 255) for v in g) + (255,)
        ex, ey = bx + math.cos(la) * L * 0.95, by - math.sin(la) * L * 0.95
        d.line([(bx, by), (ex, ey)], fill=vein, width=int(2 * ss))
        for k in range(1, 7):
            t = k / 7
            sx, sy = bx + math.cos(la) * L * t, by - math.sin(la) * L * t
            for side in (-1, 1):
                va = la + side * 0.9
                vl = W * 0.42 * math.sin(math.pi * t)
                d.line([(sx, sy), (sx + math.cos(va) * vl, sy - math.sin(va) * vl)], fill=vein, width=max(1, int(1 * ss)))
        dh.polygon(poly, fill=int(rng.uniform(150, 210)))
        dh.line([(bx, by), (ex, ey)], fill=240, width=int(3 * ss))
    return _finish(im, hg, (n, n))

def blossom(n=1024, seed=23, ss=2):
    """Double-pink cherry blossom clusters on a dark twig with a few bronze leaves."""
    rng = np.random.default_rng(seed)
    N = n * ss
    im = Image.new("RGBA", (N, N), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    hg = Image.new("L", (N, N), 0); dh = ImageDraw.Draw(hg)
    spots = []
    def twig(x, y, ang, length, width, depth):
        pts = [(x, y)]
        for i in range(14):
            ang += rng.normal(0, 0.07)
            x += math.cos(ang) * length / 14; y -= math.sin(ang) * length / 14
            pts.append((x, y))
        d.line(pts, fill=(58, 34, 30, 255), width=int(width)); dh.line(pts, fill=100, width=int(width))
        for i in range(3, 15, 2):
            spots.append(pts[i])
        spots.append(pts[-1])
        if depth < 1:
            for k, i in enumerate((3, 5, 7, 9, 11)):
                px, py = pts[i]
                twig(px, py, ang + (-1) ** k * rng.uniform(0.8, 1.25), length * rng.uniform(0.55, 0.75), width * 0.6, depth + 1)
    twig(N / 2, N - 4 * ss, math.pi / 2 + rng.normal(0, 0.1), N * 0.5, 11 * ss, 0)
    # a few bronze-green young leaves under the clusters
    for (sx, sy) in spots[::2]:
        la = rng.uniform(0, 2 * math.pi)
        L = rng.uniform(110, 170) * ss
        g = np.array([0.45, 0.32, 0.14]) * rng.uniform(0.8, 1.2)
        d.polygon(_leaf_poly(sx, sy, L, L * 0.15, la, 0.08), fill=tuple(int(np.clip(v, 0, 1) * 255) for v in g) + (255,))
        dh.polygon(_leaf_poly(sx, sy, L, L * 0.15, la), fill=150)
    def flower(cx, cy, r):
        base = np.array([0.98, 0.66, 0.78]) * rng.uniform(0.92, 1.04)
        deep = np.array([0.86, 0.36, 0.52])
        layers = [(r, 12, 0.0), (r * 0.78, 10, 0.3), (r * 0.55, 8, 0.6)]
        for li, (rr, count, off) in enumerate(layers):
            for k in range(count):
                a = 2 * math.pi * k / count + off + rng.normal(0, 0.08)
                pr = rr * rng.uniform(0.85, 1.05)
                pw = pr * 0.42
                px, py = cx + math.cos(a) * pr * 0.5, cy - math.sin(a) * pr * 0.5
                poly = []
                for i in range(24):
                    t = i / 23 * 2 * math.pi
                    ex = math.cos(t) * pr * 0.5; ey = math.sin(t) * pw
                    if math.cos(t) > 0.85: ex *= 0.92     # notched tip
                    poly.append((px + ex * math.cos(a) - ey * math.sin(a), py - (ex * math.sin(a) + ey * math.cos(a))))
                shade = 1.0 - 0.1 * li + rng.normal(0, 0.04)
                col = np.clip(base * shade + (deep - base) * (0.15 * li), 0, 1)
                d.polygon(poly, fill=tuple(int(v * 255) for v in col) + (255,), outline=tuple(int(v * 220) for v in col) + (255,))
                dh.polygon(poly, fill=int(150 + li * 35))
        d.ellipse([cx - r * 0.16, cy - r * 0.16, cx + r * 0.16, cy + r * 0.16], fill=(200, 70, 110, 255))
        for k in range(10):
            a = rng.uniform(0, 2 * math.pi); rr = r * 0.2
            d.ellipse([cx + math.cos(a) * rr - 2 * ss, cy - math.sin(a) * rr - 2 * ss, cx + math.cos(a) * rr + 2 * ss, cy - math.sin(a) * rr + 2 * ss], fill=(250, 220, 120, 255))
    for (sx, sy) in spots:
        if not (40 * ss < sx < N - 40 * ss and 40 * ss < sy < N - 40 * ss): continue
        for k in range(rng.integers(3, 6)):
            a = rng.uniform(0, 2 * math.pi); l = rng.uniform(30, 70) * ss
            fx, fy = sx + math.cos(a) * l, sy - math.sin(a) * l - 20 * ss
            d.line([(sx, sy), (fx, fy)], fill=(110, 140, 60, 255), width=int(2 * ss))
            flower(fx, fy, rng.uniform(40, 56) * ss)
    return _finish(im, hg, (n, n))

def petals(n=512, seed=24, ss=2):
    rng = np.random.default_rng(seed)
    N = n * ss
    im = Image.new("RGBA", (N, N), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    hg = Image.new("L", (N, N), 0); dh = ImageDraw.Draw(hg)
    yy, xx = None, None
    for k in range(420):
        r = N * 0.48 * math.sqrt(rng.random()) * (0.6 + 0.4 * rng.random())
        a = rng.uniform(0, 2 * math.pi)
        cx, cy = N / 2 + math.cos(a) * r, N / 2 + math.sin(a) * r
        pl = rng.uniform(8, 14) * ss; pw = pl * 0.55; pa = rng.uniform(0, 2 * math.pi)
        poly = [(cx + math.cos(t) * pl * math.cos(pa) - math.sin(t) * pw * math.sin(pa), cy + math.cos(t) * pl * math.sin(pa) + math.sin(t) * pw * math.cos(pa)) for t in np.linspace(0, 2 * math.pi, 14)]
        col = np.array([0.97, 0.68, 0.78]) * rng.uniform(0.8, 1.05) * (0.8 if rng.random() < 0.3 else 1.0)
        d.polygon(poly, fill=tuple(int(np.clip(v, 0, 1) * 255) for v in col) + (255,))
        dh.polygon(poly, fill=200)
    return _finish(im, hg, (n, n))

if __name__ == "__main__":
    import os, time
    os.makedirs("/tmp/claude-0/tt", exist_ok=True)
    t = time.time()
    for st in ("furrow", "plates", "cherry", "dead"):
        a, nn, m = bark(512, style=st); a.save(f"/tmp/claude-0/tt/bark_{st}.png")
    pine_sprig()[0].save("/tmp/claude-0/tt/pine.png")
    broadleaf()[0].save("/tmp/claude-0/tt/leaf.png")
    blossom()[0].save("/tmp/claude-0/tt/blossom.png")
    petals()[0].save("/tmp/claude-0/tt/petals.png")
    print(time.time() - t)
