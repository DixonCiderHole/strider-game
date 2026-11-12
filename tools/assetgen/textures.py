"""Procedural PBR textures (tileable) for sci-fi hulls and buildings."""
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

def _tile_noise(n, scale, rng, octaves=4):
    out = np.zeros((n, n))
    amp = 1.0; tot = 0
    for o in range(octaves):
        g = max(2, int(scale * 2 ** o))
        base = rng.random((g, g))
        up = np.kron(base, np.ones((n // g + 1, n // g + 1)))[:n, :n]
        up = ndimage.gaussian_filter(up, sigma=n / g / 2.5, mode='wrap')
        out += up * amp; tot += amp; amp *= 0.5
    out /= tot
    return (out - out.min()) / (np.ptp(out) + 1e-9)

def _normal_from_height(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    n = np.dstack([-dx, dy, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return ((n * 0.5 + 0.5) * 255).astype(np.uint8)

def hull_panels(n=2048, seed=3, base=(0.62, 0.63, 0.66), plate=(256, 128)):
    """Panelled hull plating: seams, inset hatches, rivets, per-plate tint,
    fine scuffs. Returns (albedo, normal, metal_rough) PIL images."""
    rng = np.random.default_rng(seed)
    H = np.ones((n, n)); tint = np.zeros((n, n)); rough = np.full((n, n), 0.42)
    pw, ph = plate
    # Rows of plates with offsets, some split further.
    def seam_rect(x0, y0, x1, y1, w=3, depth=0.6):
        H[y0:y0 + w, x0:x1] = np.minimum(H[y0:y0 + w, x0:x1], 1 - depth)
        H[y1 - w:y1, x0:x1] = np.minimum(H[y1 - w:y1, x0:x1], 1 - depth)
        H[y0:y1, x0:x0 + w] = np.minimum(H[y0:y1, x0:x0 + w], 1 - depth)
        H[y0:y1, x1 - w:x1] = np.minimum(H[y0:y1, x1 - w:x1], 1 - depth)
    y = 0; row = 0
    while y < n:
        h = ph * rng.choice([1, 1, 2])
        h = min(h, n - y)
        x = -(row % 2) * pw // 2
        while x < n:
            w = pw * rng.choice([1, 1, 2, 3])
            x0, x1 = max(0, x), min(n, x + w)
            if x1 - x0 > 8:
                t = rng.normal(0, 0.035)
                tint[y:y + h, x0:x1] = t
                rough[y:y + h, x0:x1] = 0.36 + rng.random() * 0.14
                seam_rect(x0, y, x1, y + h)
                r = rng.random()
                if r < 0.3 and x1 - x0 > 80 and h > 60:   # inset hatch
                    m = 18
                    hx0, hy0, hx1, hy1 = x0 + m, y + m, x1 - m, y + h - m
                    H[hy0:hy1, hx0:hx1] -= 0.08
                    seam_rect(hx0, hy0, hx1, hy1, 2, 0.45)
                    # hatch handles
                    cx = (hx0 + hx1) // 2
                    H[hy1 - 14:hy1 - 8, cx - 20:cx + 20] += 0.25
                elif r < 0.5:                              # rivet rows
                    for xx in range(x0 + 12, x1 - 8, 22):
                        for yy in (y + 9, y + h - 10):
                            yy0, xx0 = np.ogrid[-4:5, -4:5]
                            d = (yy0 ** 2 + xx0 ** 2) <= 14
                            sl = H[yy - 4:yy + 5, xx - 4:xx + 5]
                            if sl.shape == d.shape:
                                sl[d] += 0.18
                elif r < 0.62 and h > 60:                  # vent slats
                    vx0, vx1 = x0 + 20, min(x1 - 20, x0 + 140)
                    for k in range(5):
                        yy = y + 20 + k * 10
                        if yy + 5 < y + h - 10:
                            H[yy:yy + 5, vx0:vx1] -= 0.3
            x += w
        y += h; row += 1
    # Scuffs / wear
    scuff = _tile_noise(n, 8, rng, 5)
    fine = _tile_noise(n, 64, rng, 3)
    Hs = ndimage.gaussian_filter(H, 1.0, mode='wrap')
    alb = np.zeros((n, n, 3))
    for c in range(3):
        alb[..., c] = base[c] * (1 + tint) * (0.88 + 0.12 * Hs) * (0.94 + 0.08 * fine)
    alb *= (1 - 0.18 * np.clip(scuff - 0.55, 0, 1) * 3)[..., None]
    # Bright worn edges along seams
    edge = np.clip((Hs - ndimage.gaussian_filter(H, 3.0, mode='wrap')) * 4, 0, 1)
    alb += edge[..., None] * 0.06
    alb = np.clip(alb, 0, 1)
    nrm = _normal_from_height(ndimage.gaussian_filter(H + fine * 0.02, 0.7, mode='wrap'), 6.0)
    r = np.clip(rough + (1 - Hs) * 0.3 + scuff * 0.1, 0, 1)
    mr = np.dstack([np.ones_like(r), r, np.full_like(r, 0.62)])  # glTF: G=rough, B=metal
    return (Image.fromarray((alb * 255).astype(np.uint8)), Image.fromarray(nrm),
            Image.fromarray((mr * 255).astype(np.uint8)))

def grating(n=1024, seed=5):
    """Floor grating / deck plate for interiors."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:n, 0:n]
    cell = 64
    gx = (xx % cell); gy = (yy % cell)
    H = np.ones((n, n))
    bars = ((gx < 10) | (gy < 10))
    H[~bars] = 0.45
    holes = ((gx > 18) & (gx < 58) & (gy > 18) & (gy < 58))
    H[holes] = 0.1
    big = ((xx % 512) < 6) | ((yy % 512) < 6)
    H[big] = 0.3
    fine = _tile_noise(n, 32, rng, 3)
    Hs = ndimage.gaussian_filter(H, 1.0, mode='wrap')
    alb = np.dstack([0.24 * Hs + 0.03, 0.25 * Hs + 0.03, 0.27 * Hs + 0.035]) * (0.9 + 0.2 * fine[..., None])
    nrm = _normal_from_height(Hs, 5.0)
    r = 0.5 + 0.3 * (1 - Hs)
    mr = np.dstack([np.ones_like(r), r, np.full_like(r, 0.75)])
    return (Image.fromarray((np.clip(alb, 0, 1) * 255).astype(np.uint8)), Image.fromarray(nrm),
            Image.fromarray((np.clip(mr, 0, 1) * 255).astype(np.uint8)))

if __name__ == "__main__":
    a, nm, mr = hull_panels(1024)
    a.save("t_hull_a.png"); nm.save("t_hull_n.png"); mr.save("t_hull_mr.png")
    g = grating(); g[0].save("t_grate_a.png")


# ================================================================ nature + props
from PIL import ImageDraw

def _img(a):
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))

def _mr(rough, metal):
    return _img(np.dstack([np.ones_like(rough), rough, np.full_like(rough, metal) if np.isscalar(metal) else metal]))

def ivy(w=512, h=1024, seed=11, ss=2):
    """Climbing-ivy strip, tileable top to bottom, ragged transparent sides.
    Returns (rgba albedo, normal)."""
    rng = np.random.default_rng(seed)
    W, H = w * ss, h * ss
    col = Image.new("RGBA", (W, H * 3), (0, 0, 0, 0))
    hgt = Image.new("L", (W, H * 3), 0)
    dc, dh = ImageDraw.Draw(col), ImageDraw.Draw(hgt)
    # stems: wandering vertical lines (drawn 3x tall, middle third kept -> tiles)
    stems = []
    for s in range(3):
        x = W * (0.25 + 0.25 * s) + rng.normal(0, W * 0.04)
        pts = []
        for k in range(0, 61):
            y = H * k / 60
            x += rng.normal(0, W * 0.012); x = np.clip(x, W * 0.15, W * 0.85)
            pts.append((x, y))
        # make it periodic: blend the last x back to the first
        x0 = pts[0][0]; xe = pts[-1][0]
        pts = [(px + (x0 - xe) * (py / H), py) for px, py in pts]
        stems.append(pts)
        for rep in range(3):
            dc.line([(px, py + rep * H) for px, py in pts], fill=(70, 52, 30, 255), width=int(5 * ss))
            dh.line([(px, py + rep * H) for px, py in pts], fill=120, width=int(5 * ss))
    # leaves: 3-lobed ivy leaves on short petioles along the stems
    def leaf(cx, cy, size, ang, shade):
        th = np.linspace(0, 2 * np.pi, 48, endpoint=False)
        r = size * (0.62 + 0.38 * np.abs(np.cos(1.5 * th)) ** 0.7) * (1 - 0.25 * np.cos(th))
        pts = [(cx + r[i] * np.cos(th[i] + ang), cy + r[i] * np.sin(th[i] + ang) * 0.92) for i in range(48)]
        g = np.array([0.27, 0.5, 0.15]) * shade + rng.normal(0, 0.025, 3)
        g = np.clip(g + np.array([0.06, 0.02, 0.0]) * rng.random(), 0, 1)
        for rep in range(3):
            pp = [(x, y + rep * H) for x, y in pts]
            dc.polygon(pp, fill=tuple(int(v * 255) for v in g) + (255,))
            dh.polygon(pp, fill=int(150 + 80 * rng.random()))
            # veins
            for k in (-1, 0, 1):
                a = ang - np.pi / 2 + k * 0.9
                dc.line([(cx, cy + rep * H), (cx + np.cos(a) * size * 0.8, cy + rep * H + np.sin(a) * size * 0.8)],
                        fill=tuple(int(min(1, v * 1.5) * 255) for v in g) + (255,), width=max(1, int(1.2 * ss)))
    for pts in stems:
        for k in range(1, len(pts) - 1):
            for _ in range(rng.integers(2, 4)):
                px, py = pts[k]
                side = rng.choice([-1, 1])
                size = rng.uniform(22, 40) * ss
                lx = px + side * rng.uniform(0.3, 1.1) * size
                ly = py + rng.uniform(-10, 10) * ss
                lx = np.clip(lx, size, W - size)
                leaf(lx, ly, size, rng.uniform(-0.6, 0.6) + np.pi / 2, rng.uniform(0.6, 1.25))
    col = col.crop((0, H, W, 2 * H)).resize((w, h), Image.LANCZOS)
    hgt = hgt.crop((0, H, W, 2 * H)).resize((w, h), Image.LANCZOS)
    hh = ndimage.gaussian_filter(np.asarray(hgt, float) / 255.0, 1.2)
    nrm = _normal_from_height(hh, 4.0)
    return col, Image.fromarray(nrm)

def grass_card(n=512, seed=12, ss=2):
    rng = np.random.default_rng(seed)
    N = n * ss
    im = Image.new("RGBA", (N, N), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    for b in range(90):
        x = rng.uniform(0.08, 0.92) * N
        hgt = rng.uniform(0.35, 0.98) * N
        lean = rng.normal(0, 0.18) * hgt
        wb = rng.uniform(6, 13) * ss
        pts_l, pts_r = [], []
        for k in range(13):
            t = k / 12
            cx = x + lean * t * t
            cy = N - hgt * t
            ww = wb * (1 - t) ** 0.8 / 2
            pts_l.append((cx - ww, cy)); pts_r.append((cx + ww, cy))
        dry = rng.random() < 0.25
        base = np.array([0.42, 0.40, 0.2]) if dry else np.array([0.2, 0.38, 0.1])
        base = base * rng.uniform(0.7, 1.2)
        d.polygon(pts_l + pts_r[::-1], fill=tuple(int(np.clip(v, 0, 1) * 255) for v in base) + (255,))
    a = np.asarray(im, float) / 255.0
    yy = np.linspace(1, 0, N)[None, :, None].transpose(1, 0, 2)   # 1 at top
    a[..., :3] *= (0.55 + 0.6 * yy)    # darker at the roots
    return _img(a).resize((n, n), Image.LANCZOS)

def moss_patch(n=512, seed=13):
    """A ragged clump of moss (alpha-edged decal) + normal."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:n, 0:n] / n - 0.5
    r = np.hypot(xx, yy) * 2
    nz = _tile_noise(n, 6, rng, 5)
    fine = _tile_noise(n, 48, rng, 3)
    mask = np.clip((1.0 - r) * 1.6 + (nz - 0.5) * 1.6, 0, 1)
    alpha = (mask > 0.35).astype(float)
    hgt = mask * 0.6 + fine * 0.4
    base = np.dstack([0.16 + 0.1 * fine, 0.3 + 0.14 * fine + 0.06 * nz, 0.07 + 0.04 * fine])
    base *= (0.75 + 0.35 * hgt)[..., None]
    rgba = np.dstack([base, alpha])
    nrm = _normal_from_height(ndimage.gaussian_filter(hgt, 1.0), 8.0)
    return _img(rgba), Image.fromarray(nrm)

def crack_decal(n=512, seed=14, ss=2):
    rng = np.random.default_rng(seed)
    N = n * ss
    im = Image.new("L", (N, N), 0); d = ImageDraw.Draw(im)
    halo = Image.new("L", (N, N), 0); dh = ImageDraw.Draw(halo)
    def branch(x, y, ang, length, width, depth):
        pts = [(x, y)]
        for k in range(int(length / (8 * ss))):
            ang += rng.normal(0, 0.22)
            if not (0 < x < N and 0 < y < N): break
            x += np.cos(ang) * 8 * ss; y += np.sin(ang) * 8 * ss
            pts.append((x, y))
            if depth < 3 and rng.random() < 0.07:
                branch(x, y, ang + rng.choice([-1, 1]) * rng.uniform(0.5, 1.1), length * 0.5, max(1, width * 0.6), depth + 1)
        for k in range(len(pts) - 1):
            wk = max(1, int(width * (1 - k / len(pts)) + 1))
            d.line([pts[k], pts[k + 1]], fill=255, width=wk)
            dh.line([pts[k], pts[k + 1]], fill=255, width=wk * 5)
    c = N / 2
    for k in range(rng.integers(3, 6)):
        branch(c + rng.normal(0, N * 0.03), c, rng.uniform(0, 2 * np.pi), N * rng.uniform(0.6, 0.9), 9 * ss, 0)
    core = np.asarray(im.resize((n, n), Image.LANCZOS), float) / 255
    hal = ndimage.gaussian_filter(np.asarray(halo.resize((n, n), Image.LANCZOS), float) / 255, 2)
    rgb = np.dstack([0.04 + 0.3 * (1 - core)] * 3) * (1 - core[..., None] * 0.8)
    rgb = rgb + hal[..., None] * 0.18 * (1 - core[..., None])     # chipped paint round the crack
    alpha = np.clip(core * 1.6 + hal * 0.5, 0, 1)
    alpha = (alpha > 0.3).astype(float)
    hgt = 1 - core
    rgba = np.dstack([np.clip(rgb, 0, 1), alpha])
    return _img(rgba), Image.fromarray(_normal_from_height(ndimage.gaussian_filter(hgt, 1), 6))

def fabric(n=1024, seed=15, color=(0.25, 0.3, 0.34), quilt=96, stripe=None):
    """Woven fabric with quilted stitching, wear and stains."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:n, 0:n].astype(float)
    weave = 0.5 + 0.25 * np.sin(xx * np.pi / 2.0) * np.sign(np.sin(yy * np.pi / 6)) + 0.25 * np.sin(yy * np.pi / 2.0) * np.sign(np.sin(xx * np.pi / 6))
    H = weave * 0.15
    if quilt:
        q = (np.minimum(xx % quilt, quilt - xx % quilt) + 0) / quilt
        qy = (np.minimum(yy % quilt, quilt - yy % quilt)) / quilt
        puff = np.sin(np.clip(q, 0, 0.5) * np.pi) * np.sin(np.clip(qy, 0, 0.5) * np.pi)
        H += puff * 0.85
        weave = weave * (0.75 + 0.35 * puff)
        stitch = ((xx % quilt < 3) | (yy % quilt < 3)) & ((xx + yy) % 10 < 6)
        H[stitch] -= 0.2
    stain = _tile_noise(n, 5, rng, 4); fine = _tile_noise(n, 80, rng, 2)
    c = np.ones((n, n, 3)) * np.asarray(color)
    if stripe is not None:
        band = (((yy // (n / 8)) % 4) == 1)
        c[band] = np.asarray(stripe)
    c *= (0.82 + 0.25 * weave + 0.08 * fine)[..., None]
    c *= (1 - 0.22 * np.clip(stain - 0.55, 0, 1) * 3)[..., None]
    nrm = _normal_from_height(ndimage.gaussian_filter(H, 0.8, mode='wrap'), 7.0)
    rough = 0.85 + 0.1 * fine
    return _img(c), Image.fromarray(nrm), _mr(rough, 0.0)

def wood_planks(n=1024, seed=16, base=(0.42, 0.33, 0.24), weather=0.6):
    """Weathered timber, grain along U; tileable."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:n, 0:n].astype(float)
    warp = _tile_noise(n, 6, rng, 4)
    grain = np.sin((yy / n * 2 * np.pi * 56) + warp * 5 + _tile_noise(n, 24, rng, 2) * 1.5) * 0.5 + 0.5
    streak = _tile_noise(n, 3, rng, 3)
    fine = ndimage.gaussian_filter(rng.random((n, n)), (0.7, 40), mode='wrap')
    fine = (fine - fine.min()) / np.ptp(fine)
    # knots
    H = grain * 0.35 + fine * 0.45
    knots = np.zeros((n, n))
    for k in range(6):
        cx, cy = rng.uniform(0, n), rng.uniform(0, n)
        dx = (xx - cx + n / 2) % n - n / 2; dy = (yy - cy + n / 2) % n - n / 2
        rr = np.hypot(dx / 2.6, dy)
        knots += np.exp(-rr / 9) * (0.6 + 0.4 * np.sin(rr * 0.9))
    knots = np.clip(knots, 0, 1)
    b = np.asarray(base)
    grey = np.array([0.5, 0.49, 0.46])
    c = b * (0.75 + 0.35 * grain[..., None]) * (0.8 + 0.3 * fine[..., None])
    w = np.clip(weather * (0.6 + 0.6 * streak), 0, 1)[..., None]
    c = c * (1 - w) + grey * (0.7 + 0.35 * fine[..., None]) * w
    c *= (1 - 0.5 * knots[..., None])
    H -= knots * 0.4
    nrm = _normal_from_height(ndimage.gaussian_filter(H, 0.8, mode='wrap'), 5.0)
    rough = 0.75 + 0.2 * fine
    return _img(c), Image.fromarray(nrm), _mr(rough, 0.0)

def screen(n=512, seed=17, tint=(0.35, 0.85, 1.0), kind="data"):
    """Emissive UI screen: returns (albedo, emission)."""
    rng = np.random.default_rng(seed)
    im = Image.new("RGB", (n, n), (6, 12, 16)); d = ImageDraw.Draw(im)
    t = tuple(int(v * 255) for v in tint)
    dim = tuple(int(v * 110) for v in tint)
    d.rectangle([8, 8, n - 9, n - 9], outline=dim, width=3)
    if kind == "data":
        d.line([(16, 44), (n - 16, 44)], fill=dim, width=2)
        d.rectangle([16, 14, 200, 34], fill=t)
        pts = [(24 + i * (n - 48) / 40, 220 - 70 * np.sin(i * 0.4) * rng.uniform(0.6, 1)) for i in range(41)]
        d.line(pts, fill=t, width=3)
        for k in range(10):
            y = 270 + k * 22
            d.rectangle([24, y, 24 + rng.integers(60, 300), y + 10], fill=dim if k % 3 else t)
        d.ellipse([n - 170, 260, n - 30, 400], outline=t, width=5)
        d.pieslice([n - 170, 260, n - 30, 400], -90, int(rng.uniform(40, 250)), fill=dim)
    elif kind == "med":
        d.rectangle([n / 2 - 30, 70, n / 2 + 30, 250], fill=t); d.rectangle([n / 2 - 90, 130, n / 2 + 90, 190], fill=t)
        pts = []
        for i in range(60):
            x = 24 + i * (n - 48) / 59
            y = 360 + (-70 if i % 15 == 7 else (30 if i % 15 == 8 else 0)) + rng.normal(0, 2)
            pts.append((x, y))
        d.line(pts, fill=(80, 255, 120), width=4)
        for k in range(3):
            d.rectangle([24, 420 + k * 22, 24 + rng.integers(100, 300), 430 + k * 22], fill=dim)
    elif kind == "droid":
        d.ellipse([n / 2 - 110, 60, n / 2 + 110, 280], outline=t, width=4)
        d.ellipse([n / 2 - 40, 130, n / 2 + 40, 210], fill=t)
        for a in range(0, 360, 30):
            r0, r1 = 120, 150
            ca, sa = np.cos(np.radians(a)), np.sin(np.radians(a))
            d.line([(n / 2 + ca * r0, 170 + sa * r0), (n / 2 + ca * r1, 170 + sa * r1)], fill=dim, width=4)
        for k in range(6):
            y = 320 + k * 26
            w = rng.integers(100, 380)
            d.rectangle([40, y, 40 + w, y + 12], fill=dim); d.rectangle([40, y, 40 + int(w * rng.uniform(0.2, 1)), y + 12], fill=t)
    elif kind == "map":
        yy, xx = np.mgrid[0:n, 0:n]
        hmap = _tile_noise(n, 4, rng, 4)
        a = np.asarray(im, float)
        lines = (np.abs((hmap * 12) % 1 - 0.5) < 0.05)
        a[lines] = np.array(dim)
        im = Image.fromarray(a.astype(np.uint8)); d = ImageDraw.Draw(im)
        d.ellipse([n * 0.6, n * 0.4, n * 0.75, n * 0.55], outline=t, width=4)
        d.line([(n * 0.3, n * 0.7), (n * 0.68, n * 0.47)], fill=t, width=3)
        d.polygon([(n * 0.3, n * 0.66), (n * 0.27, n * 0.72), (n * 0.33, n * 0.72)], fill=(255, 190, 60))
    a = np.asarray(im, float) / 255
    # scanlines
    a *= (0.85 + 0.15 * (np.arange(n) % 3 != 0))[:, None, None]
    glow = ndimage.gaussian_filter(a, (3, 3, 0))
    em = np.clip(a + glow * 0.6, 0, 1)
    return _img(a * 0.6), _img(em)

def pcb(n=512, seed=18):
    rng = np.random.default_rng(seed)
    im = Image.new("RGB", (n, n), (18, 70, 40)); d = ImageDraw.Draw(im)
    H = Image.new("L", (n, n), 80); dh = ImageDraw.Draw(H)
    for k in range(70):
        x, y = rng.integers(0, n), rng.integers(0, n)
        pts = [(x, y)]
        for s in range(rng.integers(2, 5)):
            if rng.random() < 0.5: x += rng.integers(-120, 120)
            else: y += rng.integers(-120, 120)
            pts.append((x, y))
        d.line(pts, fill=(170, 140, 60), width=3); dh.line(pts, fill=140, width=3)
        d.ellipse([x - 5, y - 5, x + 5, y + 5], fill=(200, 180, 90))
    for k in range(9):
        x, y = rng.integers(20, n - 90), rng.integers(20, n - 70)
        w, h = rng.integers(30, 80), rng.integers(30, 60)
        d.rectangle([x, y, x + w, y + h], fill=(20, 20, 22)); dh.rectangle([x, y, x + w, y + h], fill=230)
        for p in range(x + 4, x + w - 2, 7):
            d.line([(p, y - 5), (p, y)], fill=(200, 200, 200), width=2); d.line([(p, y + h), (p, y + h + 5)], fill=(200, 200, 200), width=2)
    nrm = _normal_from_height(ndimage.gaussian_filter(np.asarray(H, float) / 255, 1), 5)
    rough = np.full((n, n), 0.45)
    return im, Image.fromarray(nrm), _mr(rough, 0.3)
