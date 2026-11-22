"""Shipfall Reach kit (models/reach_kit.glb): the new assets for the area east
of Base Camp where Ilsa runs her medical missions.

Nodes (each at its own origin, +Z forward, Y up, metres):
  FreighterFore   nose half of a downed bulk hauler, torn open at the back
  FreighterAft    engine half of the same ship, torn open at the front
  CargoPod        spilled cargo container (corrugated, end doors)
  SurveyLander    K-7 survey lander, crumpled nose, one leg snapped
  HullPlate       a big torn hull plate (debris)
  RuinPillar      Vaari carved stone column with a crystal vein
  RuinPillarBroken  the same column snapped off, with a jagged top
  RuinDrum        a fallen column drum
  RuinArch        two columns and a carved lintel, crystal keystone
  RuinWall        a broken wall of hand-cut blocks
  RuinDais        a stepped round platform with a crystal heart
  CrystalCluster  a cluster of glowing spire crystal
  MedCase         Coalition medical cache case (lid is MedCaseLid)
  MedCaseLid
  MedPack         pathfinder med pack (the pickup)
  PathfinderBeacon  Coalition waypoint marker tripod (LightAt marks the lamp)
  Glowcap         bioluminescent herb (remedy ingredient)
  TissueVial      sealed sample vial holding a sliver of creature spine
  FieldShelter    collapsed Coalition lean-to (frame + sagging tarp)

python3 reach_gen.py ../../models/reach_kit.glb
"""
import sys, math, numpy as np
from scipy import ndimage
from PIL import Image
from meshlib import *
from textures import hull_panels, _tile_noise, _normal_from_height, _img

rng = np.random.default_rng(42)


# ---------------------------------------------------------------- helpers

def merge(ms):
    m = Mesh()
    for x in ms:
        m.extend(x)
    return m


def filt(m, keep):
    out = Mesh()
    for i in range(0, len(m.P), 3):
        c = (m.P[i] + m.P[i + 1] + m.P[i + 2]) / 3
        if keep(c):
            out.P += m.P[i:i + 3]; out.N += m.N[i:i + 3]
    return out


def filt_pairs(m, keep):
    """Like filt, but keeps or drops loft quads (triangle pairs) together so a
    split along a ring row is a clean line, not a zig-zag."""
    out = Mesh()
    for i in range(0, len(m.P) - 5, 6):
        c = sum(m.P[i:i + 6]) / 6
        if keep(c):
            out.P += m.P[i:i + 6]; out.N += m.N[i:i + 6]
    return out


def jitter(m, amp, freq, pred=None, seed=0.0):
    P = np.array(m.P, float)
    d = np.stack([noise3(P * freq + seed), noise3(P * freq + seed + 31.7), noise3(P * freq + seed + 63.1)], 1) * amp
    if pred is not None:
        d *= np.array([pred(p) for p in P])[:, None]
    m.P = list(P + d)
    return m


def winding_from_normals(m):
    """Make each triangle's winding agree with its stored normals (CCW front)."""
    for t in range(0, len(m.P), 3):
        a, b, c = m.P[t], m.P[t + 1], m.P[t + 2]
        n = np.cross(np.asarray(b) - a, np.asarray(c) - a)
        if np.dot(n, m.N[t] + m.N[t + 1] + m.N[t + 2]) < 0:
            m.P[t + 1], m.P[t + 2] = m.P[t + 2], m.P[t + 1]
            m.N[t + 1], m.N[t + 2] = m.N[t + 2], m.N[t + 1]
    return m


def outward_from(m, centre_fn, inward=False):
    """Point every face (normals + winding) away from centre_fn(face centre)."""
    for t in range(0, len(m.P), 3):
        a, b, c = (np.asarray(m.P[t + k], float) for k in range(3))
        f = (a + b + c) / 3
        n = np.cross(b - a, c - a)
        out = f - centre_fn(f)
        if inward:
            out = -out
        if np.dot(n, out) < 0:
            m.P[t + 1], m.P[t + 2] = m.P[t + 2], m.P[t + 1]
            n = -n
        nn = n / max(1e-9, np.linalg.norm(n))
        for k in range(3):
            if np.dot(m.N[t + k], nn) < 0:
                m.N[t + k] = -np.asarray(m.N[t + k])
    return m


def flat_normals(m):
    for t in range(0, len(m.P), 3):
        a, b, c = (np.asarray(m.P[t + k], float) for k in range(3))
        n = np.cross(b - a, c - a); n /= max(1e-9, np.linalg.norm(n))
        m.N[t] = m.N[t + 1] = m.N[t + 2] = n
    return m


def smooth_normals(m, tol=4):
    """Average normals of corners that share a position (soft shading)."""
    P = np.round(np.array(m.P, float), tol)
    N = np.array(m.N, float)
    _, inv = np.unique(P, axis=0, return_inverse=True)
    inv = inv.reshape(-1)
    acc = np.zeros((inv.max() + 1, 3))
    np.add.at(acc, inv, N)
    acc /= np.maximum(1e-9, np.linalg.norm(acc, axis=1))[:, None]
    m.N = list(acc[inv])
    return m


def rounded_rect(w, h, z, e=0.3, n=28, y0=0.0, flat_bottom=None):
    """Superellipse ring (boxy with rounded corners), clockwise from the top."""
    pts = []
    for k in range(n):
        a = math.pi / 2 - 2 * math.pi * k / n
        c, s = math.cos(a), math.sin(a)
        x = w * math.copysign(abs(c) ** e, c)
        y = h * math.copysign(abs(s) ** e, s)
        if flat_bottom is not None:
            y = max(y, -flat_bottom)
        pts.append((x, y + y0, z))
    return np.array(pts)


def ragged_ring(ring, axis_dir, amount, seed):
    r = ring.copy()
    for k in range(len(r)):
        r[k, 2] += axis_dir * (abs(noise3(np.array([r[k] * 0.9 + seed]))[0]) * amount * 2.2 + rng.random() * amount * 0.4)
    return r


def torn_edge(ring, axis_dir, thick, seed):
    """Teeth + hull thickness strip along an open, ragged ring."""
    m = Mesh()
    K = len(ring)
    ctr = ring.mean(axis=0)
    for k in range(K):
        a, b = ring[k], ring[(k + 1) % K]
        mid = (a + b) / 2
        out = mid - np.array([ctr[0], ctr[1], mid[2]]); out /= max(1e-6, np.linalg.norm(out))
        if rng.random() < 0.6:
            L = rng.uniform(0.15, 0.7)
            tip = mid + np.array([0, 0, axis_dir * L]) + out * rng.uniform(-0.35, 0.45) + rng.normal(0, 0.08, 3)
            m.tri(a, b, tip); m.tri(a, tip, b)
        th = -out * thick
        m.quad(a, b, b + th, a + th); m.quad(a, a + th, b + th, b)
    return m


def vcol_grime(P, burn_at=(), burn_r=3.0, base_dark=0.0, scorch=0.6, seed=0.0):
    """Grime, streaks and scorch baked into vertex colour."""
    g = fbm3(P * 0.35 + seed, 3) * 0.5 + 0.5
    streak = noise3(P * np.array([2.2, 0.22, 2.2]) + seed) * 0.5 + 0.5
    low = np.clip((-P[:, 1] + 1.0) / 2.5, 0, 1)
    grime = np.clip(g * 0.3 + streak * 0.18 + low * 0.25 - 0.12 + base_dark, 0, 0.65)
    burn = np.zeros(len(P))
    for h in burn_at:
        dd = np.linalg.norm(P - np.asarray(h), axis=1)
        burn = np.maximum(burn, np.clip(1.2 - dd / burn_r, 0, 1) ** 1.3)
    patch = np.clip((fbm3(P * 0.2 + 40 + seed, 3) - 0.2) * 2.0, 0, 1) * 0.5
    burn = np.clip(burn + patch, 0, 1) * scorch
    c = (1 - grime)[:, None] * np.ones((len(P), 3))
    c = c * (1 - burn[:, None] * 0.9) + np.array([0.25, 0.11, 0.04]) * (burn * (1 - burn))[:, None] * 0.7
    return np.hstack([np.clip(c, 0, 1), np.ones((len(P), 1))]).astype(np.float32)


def vcol_stone(P, N=None, moss=0.6, seed=0.0):
    """Weathered stone: darker in cracks/low, moss on upward faces."""
    g = fbm3(P * 0.6 + seed, 4) * 0.5 + 0.5
    low = np.clip((-P[:, 1] + 0.8) / 1.5, 0, 1)
    base = 0.82 + 0.25 * g - low * 0.25
    c = np.stack([base * 1.0, base * 0.97, base * 0.9], 1)
    if N is not None and moss > 0:
        up = np.clip((N[:, 1] - 0.35) / 0.5, 0, 1)
        mz = np.clip((fbm3(P * 0.45 + 9 + seed, 3) + 0.2) * 1.6, 0, 1)
        side = np.clip((fbm3(P * 0.8 + 3 + seed, 3) - 0.15) * 2.0, 0, 1) * low   # moss creeping up from the ground
        w = np.clip(up * mz + side, 0, 1) * moss
        c = c * (1 - w[:, None]) + np.array([0.3, 0.42, 0.16]) * w[:, None]
    return np.hstack([np.clip(c, 0, 1.2), np.ones((len(P), 1))]).astype(np.float32)


# ---------------------------------------------------------------- textures

def carved_stone(n=2048, seed=7):
    """Hand-cut ashlar: chisel marks, chipped edges, weathering pits, faint
    carved glyph bands. Returns albedo, normal, metal/rough."""
    r = np.random.default_rng(seed)
    H = np.ones((n, n))
    big = _tile_noise(n, 3, r, 5)
    mid = _tile_noise(n, 12, r, 4)
    fine = _tile_noise(n, 96, r, 3)
    chisel = np.zeros((n, n))
    yy, xx = np.mgrid[0:n, 0:n]
    for k in range(6):   # directional tool marks, each over a patch
        ang = r.uniform(0, np.pi)
        f = r.uniform(0.15, 0.3)
        band = np.sin((xx * np.cos(ang) + yy * np.sin(ang)) * f + r.uniform(0, 6)) * 0.5 + 0.5
        w = np.clip((_tile_noise(n, 2, r, 3) - 0.5) * 3, 0, 1)
        chisel += band * w
    # Glyph band: rows of carved angular marks, part-eroded.
    glyph = np.zeros((n, n))
    gy = n // 2
    cell = 72
    for gx in range(0, n, cell):
        x0 = gx + 10
        for s in range(r.integers(3, 6)):
            kind = r.integers(0, 4)
            a = (x0 + r.integers(0, 40), gy - 28 + r.integers(0, 40))
            if kind == 0:   # vertical stroke
                glyph[a[1]:a[1] + 34, a[0]:a[0] + 5] = 1
            elif kind == 1:  # horizontal
                glyph[a[1]:a[1] + 5, a[0]:a[0] + 26] = 1
            elif kind == 2:  # ring
                rr = np.hypot(xx[a[1] - 14:a[1] + 14, a[0] - 14:a[0] + 14] - a[0], yy[a[1] - 14:a[1] + 14, a[0] - 14:a[0] + 14] - a[1])
                glyph[a[1] - 14:a[1] + 14, a[0] - 14:a[0] + 14] = np.maximum(glyph[a[1] - 14:a[1] + 14, a[0] - 14:a[0] + 14], ((rr > 9) & (rr < 13)).astype(float))
            else:            # chevron
                for t in range(20):
                    glyph[a[1] + t:a[1] + t + 4, a[0] + t:a[0] + t + 4] = 1
                    glyph[a[1] + t:a[1] + t + 4, a[0] + 40 - t:a[0] + 44 - t] = 1
    glyph[gy - 44:gy - 40, :] = 1; glyph[gy + 36:gy + 40, :] = 1     # border lines
    glyph = ndimage.gaussian_filter(glyph, 1.4, mode='wrap') * np.clip(mid * 1.6 - 0.2, 0, 1)
    pits = (fine > 0.82).astype(float) * 0.5 + (mid < 0.18).astype(float) * 0.3
    H = 0.6 + big * 0.25 + mid * 0.1 + chisel * 0.03 - glyph * 0.35 - ndimage.gaussian_filter(pits, 1.5, mode='wrap') * 0.15
    base = np.array([0.56, 0.54, 0.5])
    tint = (big - 0.5) * 0.18
    alb = np.dstack([base[c] * (1 + tint) * (0.86 + 0.18 * mid + 0.06 * fine) for c in range(3)])
    alb *= (1 - glyph * 0.35)[..., None]
    lichen = np.clip((_tile_noise(n, 20, r, 4) - 0.68) * 5, 0, 1)
    alb = alb * (1 - lichen[..., None] * 0.55) + np.array([0.58, 0.6, 0.42]) * lichen[..., None] * 0.55
    nrm = _normal_from_height(ndimage.gaussian_filter(H, 0.8, mode='wrap'), 7.0)
    rough = np.clip(0.82 + fine * 0.15 - lichen * 0.1, 0, 1)
    mr = np.dstack([np.ones_like(rough), rough, np.zeros_like(rough)])
    return _img(alb), Image.fromarray(nrm), _img(mr)


def hazard(n=512):
    yy, xx = np.mgrid[0:n, 0:n]
    s = ((xx + yy) // (n // 8)) % 2
    r = np.random.default_rng(3)
    wear = _tile_noise(n, 16, r, 4)
    alb = np.where(s[..., None] == 0, np.array([0.85, 0.62, 0.08]), np.array([0.06, 0.06, 0.06]))
    alb = alb * (0.8 + 0.25 * wear[..., None])
    worn = (wear < 0.25)
    alb[worn] = alb[worn] * 0.4 + 0.3
    return _img(alb)


def medglyph(n=256):
    """Coalition medic glyph: a white chevron-cross in a teal ring (emissive)."""
    yy, xx = (np.mgrid[0:n, 0:n] - n / 2) / (n / 2)
    r = np.hypot(xx, yy)
    ring = ((r > 0.78) & (r < 0.92)).astype(float)
    bar = ((np.abs(xx) < 0.16) & (np.abs(yy) < 0.6)) | ((np.abs(yy) < 0.16) & (np.abs(xx) < 0.6))
    chev = (np.abs(np.abs(xx) - (0.25 - yy * 0.6)) < 0.08) & (yy > 0.25) & (yy < 0.62)
    glyph = np.clip(ring + bar + chev, 0, 1)
    glyph = ndimage.gaussian_filter(glyph, 0.8)
    bg = np.array([0.05, 0.25, 0.27])
    alb = bg * (1 - glyph[..., None]) + np.array([0.9, 1.0, 1.0]) * glyph[..., None]
    return _img(alb)


# ---------------------------------------------------------------- freighter

FW, FH = 3.3, 2.7     # half width / half height of the hull section


def freighter_section(z, s=1.0, y0=0.0):
    return rounded_rect(FW * s, FH * s, z, e=0.32, n=32, y0=y0, flat_bottom=FH * s * 0.82)


def axis_centre(f):
    return np.array([0.0, 0.0, f[2]])


def axis_between(z0, z1, y=0.0):
    """Centre on the body axis, kept a little inside both ends so end caps
    point out along the axis."""
    return lambda f: np.array([0.0, y, float(np.clip(f[2], z0, z1))])


def freighter_fore():
    parts = {"hull": [], "livery": [], "dark": [], "inner": [], "glass": [], "glow": [], "hazard": []}
    # Body from a torn rear (z=0) to the blunt nose (z=15).
    prof = [(0.0, 1.0, 0.0), (6.0, 1.0, 0.0), (9.5, 0.98, 0.0), (11.5, 0.93, -0.05), (13.0, 0.8, -0.2),
            (14.2, 0.6, -0.45), (15.0, 0.34, -0.7)]
    rings = []
    z = 0.0
    while z <= 15.0001:
        s = np.interp(z, [p[0] for p in prof], [p[1] for p in prof])
        y0 = np.interp(z, [p[0] for p in prof], [p[2] for p in prof])
        rings.append(freighter_section(z, s, y0))
        z += 0.5
    rings[0] = ragged_ring(rings[0], -1, 0.7, 3.1)
    body = loft(rings, cap_start=False, cap_end=True)
    outward_from(body, axis_between(1.0, 13.8, -0.3))
    body = jitter(body, 0.18, 0.8, lambda p: np.clip(1.2 - p[2] / 2.5, 0, 1), 2)      # crumpled at the tear
    body = jitter(body, 0.12, 1.1, lambda p: np.clip((p[2] - 12.0) / 3.0, 0, 1), 5)   # dented nose
    # Livery: a dark band round the lower third, cut from the body by height.
    band = lambda c: c[1] < -FH * 0.3 and c[2] < 13.5
    parts["hull"].append(filt_pairs(body, lambda c: not band(c)))
    parts["livery"].append(filt_pairs(body, band))
    # Side sponsons along the lower flanks.
    for sx in (-1, 1):
        sp = [rounded_rect(0.55 * k, 0.75 * k, z, e=0.45, n=20) for z, k in
              [(0.6, 0.2), (1.0, 1.0), (8.5, 1.0), (9.6, 0.75), (10.2, 0.2)]]
        spm = loft(sp)
        spm.transform(None, (sx * (FW + 0.15), -0.9, 0))
        outward_from(spm, lambda f, sx=sx: np.array([sx * (FW + 0.15), -0.9, float(np.clip(f[2], 1.4, 9.4))]))
        parts["livery"].append(spm)
        for zz in (2.0, 4.5, 7.0):
            hp = bevel_box((0.12, 0.5, 1.2), 0.03, (sx * (FW + 0.72), -0.9, zz)); parts["dark"].append(hp)
    parts["dark"].append(torn_edge(rings[0], -1, 0.12, 4))
    # Inner skin + ribs + deck, visible through the tear.
    inner = loft([freighter_section(z, 0.95) for z in np.arange(0.2, 12.01, 0.6)], cap_start=False, cap_end=True)
    outward_from(inner, axis_between(0.5, 11.0), inward=True)
    parts["inner"].append(inner)
    for zr in np.arange(0.6, 11.0, 1.4):
        ring = freighter_section(zr, 0.93)
        for k in range(len(ring)):
            a, b = ring[k], ring[(k + 1) % len(ring)]
            if a[1] < -FH * 0.7 and b[1] < -FH * 0.7:
                continue
            L = np.linalg.norm(b - a); v = (b - a) / max(L, 1e-6)
            rib = bevel_box((0.16, L + 0.06, 0.22), 0.03)
            rib.transform(rotz(math.atan2(v[1], v[0]) - math.pi / 2), (a + b) / 2 + np.array([0, 0, 0]))
            parts["dark"].append(rib)
    deck = bevel_box((FW * 1.7, 0.14, 11.6), 0.03, (0, -FH * 0.62, 6.0)); parts["dark"].append(deck)
    for x in (-1.6, 1.6):   # cargo racks inside
        for zz in (2.0, 5.0, 8.0):
            rack = bevel_box((0.9, 1.6, 2.4), 0.05, (x, -FH * 0.62 + 0.88, zz)); parts["inner"].append(rack)
            for yy in (0.4, 1.2):
                sh = bevel_box((1.0, 0.06, 2.5), 0.01, (x, -FH * 0.62 + yy, zz)); parts["dark"].append(sh)
    for k in range(9):   # hanging cables out of the tear
        x0 = rng.uniform(-2.4, 2.4); y0 = rng.uniform(0.2, 2.2)
        pts = [(x0, y0, 0.9), (x0 + rng.normal(0, 0.2), y0 - 0.6, 0.35), (x0 + rng.normal(0, 0.3), y0 - 1.2 - rng.random(), -0.15 - rng.random() * 0.4)]
        parts["dark"].append(tube(pts, 0.035 + rng.random() * 0.03, 6))
    # Cockpit: a raised bridge with a strip of windows near the nose.
    br = [rounded_rect(1.9 * s, 0.75 * s, z, e=0.4, n=24, y0=FH * 0.94 + 0.35 * s) for z, s in
          [(9.0, 0.3), (9.4, 0.9), (10.5, 1.0), (12.2, 0.92), (13.1, 0.6), (13.5, 0.25)]]
    bridge = loft(br); outward_from(bridge, lambda f: np.array([0, FH * 0.94 + 0.35, float(np.clip(f[2], 9.6, 12.9))])); parts["hull"].append(bridge)
    for k in range(6):
        a = -0.75 + k * 0.3
        w = bevel_box((0.26, 0.32, 0.06), 0.02)
        w.transform(rotx(-0.55) @ roty(a * 0.5), (math.sin(a) * 1.7, FH * 0.94 + 0.62, 12.62 + -abs(a) * 0.5))
        parts["glass"].append(w)
    side_win = bevel_box((3.9, 0.3, 2.6), 0.04, (0, FH * 0.94 + 0.55, 11.0)); parts["glass"].append(filt(side_win, lambda c: abs(c[0]) > 1.85))
    # Dorsal cargo-clamp frames and spine rails.
    for zz in (1.6, 4.4, 7.2):
        for sx in (-1, 1):
            arm = bevel_box((0.3, 1.0, 0.36), 0.04); arm.transform(rotz(sx * 0.35), (sx * 1.9, FH * 0.94 + 0.35, zz)); parts["dark"].append(arm)
        bar = bevel_box((3.4, 0.24, 0.36), 0.04, (0, FH * 0.94 + 0.82, zz)); parts["livery"].append(bar)
    for sx in (-0.7, 0.7):
        rail = bevel_box((0.18, 0.18, 8.6), 0.03, (sx, FH * 0.94 + 0.06, 4.5)); parts["dark"].append(rail)
    # Side hardpoints, hazard-striped docking collars, vents, nav lights.
    for sx in (-1, 1):
        col = lathe([(0.95, -0.15), (1.0, 0.0), (1.0, 0.35), (0.7, 0.4), (0.0, 0.4)], 24, axis='x')
        col.transform(None if sx > 0 else roty(math.pi), (sx * (FW - 0.05), 0.2, 5.4)); parts["hazard"].append(col)
        door = lathe([(0.0, 0.42), (0.68, 0.42)], 24, axis='x')
        door.transform(None if sx > 0 else roty(math.pi), (sx * (FW - 0.05), 0.2, 5.4)); parts["dark"].append(door)
        for k in range(4):
            v = bevel_box((0.14, 0.5, 0.9), 0.04, (sx * (FW * 0.99), 1.3, 1.6 + k * 1.05)); parts["dark"].append(v)
        nl = cyl(0.09, 0.14, 10, (sx * FW * 0.96, 0.2, 13.0), axis='x'); parts["glow"].append(nl)
        for k in range(3):   # landing gear doors underneath
            gd = bevel_box((1.1, 0.06, 1.8), 0.02, (sx * 1.6, -FH * 0.84, 2.0 + k * 3.6)); parts["dark"].append(gd)
    # Nose: sensor dome and a pair of floodlights.
    dome = lathe([(0.0, 0.42), (0.35, 0.3), (0.5, 0.0)], 18); dome.transform(None, (0, -0.75, 14.95)); parts["dark"].append(dome)
    for sx in (-1, 1):
        fl = lathe([(0.0, 0.0), (0.22, 0.02), (0.24, 0.3), (0.16, 0.32)], 14); fl.transform(None, (sx * 1.1, 0.2, 14.0)); parts["dark"].append(fl)
    # Antenna mast (bent).
    for k in range(3):
        an = tube([(0.8 + k * 0.2, FH * 0.94 + 0.95, 10.4), (0.85 + k * 0.2, FH * 0.94 + 1.9, 10.2), (1.2 + k * 0.3, FH * 0.94 + 2.4 + k * 0.2, 9.6)], 0.035, 6)
        parts["dark"].append(an)
    return parts


def freighter_aft():
    parts = {"hull": [], "livery": [], "dark": [], "inner": [], "glass": [], "glow": [], "hazard": []}
    # From the drive block (z=-11) to a torn front (z=0).
    rings = [freighter_section(z, 1.0 if z > -9.5 else 0.94) for z in np.arange(-11.0, 0.001, 0.5)]
    rings[-1] = ragged_ring(rings[-1], 1, 0.7, 7.7)
    body = loft(rings, cap_start=True, cap_end=False)
    outward_from(body, axis_between(-10.0, -1.0))
    body = jitter(body, 0.2, 0.8, lambda p: np.clip(1.2 + p[2] / 2.5, 0, 1), 9)
    parts["hull"].append(filt_pairs(body, lambda c: c[1] > -FH * 0.3))
    parts["livery"].append(filt_pairs(body, lambda c: c[1] <= -FH * 0.3))
    parts["dark"].append(torn_edge(rings[-1], 1, 0.12, 8))
    inner = loft([freighter_section(z, 0.95) for z in np.arange(-10.0, -0.19, 0.6)], cap_start=True, cap_end=False)
    outward_from(inner, axis_between(-9.5, -1.0), inward=True)
    parts["inner"].append(inner)
    for zr in np.arange(-9.4, -0.5, 1.4):
        ring = freighter_section(zr, 0.93)
        for k in range(len(ring)):
            a, b = ring[k], ring[(k + 1) % len(ring)]
            if a[1] < -FH * 0.7 and b[1] < -FH * 0.7:
                continue
            L = np.linalg.norm(b - a); v = (b - a) / max(L, 1e-6)
            rib = bevel_box((0.16, L + 0.06, 0.22), 0.03)
            rib.transform(rotz(math.atan2(v[1], v[0]) - math.pi / 2), (a + b) / 2)
            parts["dark"].append(rib)
    deck = bevel_box((FW * 1.7, 0.14, 9.8), 0.03, (0, -FH * 0.62, -5.1)); parts["dark"].append(deck)
    # Reactor housing inside: a ribbed cylinder with a dying glow.
    core = lathe([(0.0, -9.6), (0.9, -9.5), (1.0, -9.0), (1.0, -5.5), (0.9, -5.2), (0.0, -5.1)], 20)
    core.transform(None, (0, 0.2, 0)); parts["dark"].append(core)
    for zz in np.arange(-9.0, -5.5, 0.5):
        band = lathe([(1.06, zz - 0.06), (1.06, zz + 0.06)], 20); band.transform(None, (0, 0.2, 0)); parts["glow"].append(band)
    for k in range(6):   # conduits to the hull
        a = k / 6 * 2 * math.pi
        p0 = np.array([math.cos(a) * 1.0, 0.2 + math.sin(a) * 1.0, -7.3])
        p1 = np.array([math.cos(a) * 2.6, 0.2 + math.sin(a) * 2.0, -6.5])
        parts["dark"].append(tube([p0, (p0 + p1) / 2 + np.array([0, 0.2, 0.3]), p1], 0.07, 8))
    # Three drive nozzles on the back.
    for (x, y) in ((-1.8, 0.4), (1.8, 0.4), (0.0, -1.2)):
        noz = lathe([(1.0, -11.0), (1.15, -11.6), (1.25, -12.8), (1.05, -13.2), (0.9, -12.6), (0.6, -11.4)], 22)
        noz.transform(None, (x, y, 0)); parts["dark"].append(noz)
        g = lathe([(0.0, -11.5), (0.6, -11.4)], 22); g.transform(None, (x, y, 0)); parts["glow"].append(g)
        for zz in (-11.9, -12.4):
            band = lathe([(1.22, zz - 0.07), (1.24, zz + 0.07)], 22); band.transform(None, (x, y, 0)); parts["hazard"].append(band)
    # Radiator fins along both flanks, a few bent.
    for sx in (-1, 1):
        for k in range(7):
            fin = bevel_box((1.2, 0.06, 0.7), 0.02)
            bend = rng.uniform(-0.5, 0.4) if rng.random() < 0.4 else 0.0
            fin.transform(rotz(sx * (0.15 + bend)), (sx * (FW + 0.5), 0.9 - k * 0.0, -9.6 + k * 1.0))
            parts["dark"].append(fin)
        for k in range(2):
            v = bevel_box((0.14, 0.5, 1.4), 0.04, (sx * FW * 0.99, 1.6, -4.0 + k * 1.8)); parts["dark"].append(v)
        nl = cyl(0.09, 0.14, 10, (sx * FW * 0.96, 1.9, -10.6), axis='x'); parts["glow"].append(nl)
    # Dorsal heat stack.
    stack = lathe([(0.0, 0.0), (0.55, 0.0), (0.5, 1.6), (0.62, 1.7), (0.62, 1.9), (0.0, 1.9)], 16, axis='y')
    stack.transform(None, (0, FH * 0.94, -8.0)); parts["dark"].append(stack)
    for zz in (-3.0, -6.0):
        bar = bevel_box((3.4, 0.24, 0.36), 0.04, (0, FH * 0.94 + 0.1, zz)); parts["livery"].append(bar)
    return parts


def cargo_pod():
    parts = {"livery": [], "dark": [], "hazard": []}
    L, W, H = 6.0, 2.4, 2.5
    shell = Mesh()
    # Corrugated sides: a zig-zag ring swept along x.
    ring = []
    n = 36
    for k in range(n):
        a = math.pi / 2 - 2 * math.pi * k / n
        c, s = math.cos(a), math.sin(a)
        y = H / 2 * math.copysign(abs(s) ** 0.2, s); z = W / 2 * math.copysign(abs(c) ** 0.2, c)
        ring.append((0.0, y, z))
    ring = np.array(ring)
    secs = []
    for i, x in enumerate(np.arange(-L / 2 + 0.25, L / 2 - 0.24, 0.125)):
        k = 1.0 + (0.025 if i % 2 else -0.025)
        r = ring.copy(); r[:, 0] = x; r[:, 1:] *= k
        secs.append(r)
    body = loft(secs, cap_start=False, cap_end=False, smooth_along=False)
    outward_from(body, lambda f: np.array([f[0], 0, 0]))
    parts["livery"].append(body)
    for sx in (-1, 1):   # end frames and doors
        fr = bevel_box((0.5, H + 0.12, W + 0.12), 0.06, (sx * (L / 2 - 0.25), 0, 0)); parts["dark"].append(filt(fr, lambda c: True))
        for zz in (-0.55, 0.55):
            d = bevel_box((0.06, H - 0.3, 1.0), 0.02, (sx * (L / 2 + 0.01), 0, zz)); parts["livery"].append(d)
            for yy in (-0.6, 0.6):
                bar = cyl(0.035, H - 0.4, 8, (sx * (L / 2 + 0.08), 0, zz + (0.3 if zz > 0 else -0.3)))
                parts["dark"].append(bar)
        st = bevel_box((0.05, 0.3, W - 0.3), 0.01, (sx * (L / 2 + 0.04), H / 2 - 0.35, 0)); parts["hazard"].append(st)
    for x in (-L / 2 + 0.25, L / 2 - 0.25):   # corner castings
        for y in (-H / 2, H / 2):
            for z in (-W / 2, W / 2):
                parts["dark"].append(bevel_box((0.34, 0.24, 0.24), 0.04, (x, y, z)))
    return parts


# ---------------------------------------------------------------- survey lander

def survey_lander():
    parts = {"white": [], "teal": [], "dark": [], "glass": [], "glow": []}
    prof = [(0.0, -3.6), (1.2, -3.55), (1.75, -3.0), (1.95, -1.5), (1.95, 1.2), (1.7, 2.6), (1.25, 3.4), (0.6, 3.9), (0.0, 4.0)]
    # Body: lathe round the z axis, squashed a little in y.
    body = lathe(prof, 30)
    body.P = [p * np.array([1.0, 0.82, 1.0]) for p in body.P]
    outward_from(body, axis_between(-3.0, 3.4))
    body = jitter(body, 0.32, 0.9, lambda p: np.clip((p[2] - 2.0) / 1.8, 0, 1), 11)   # crumpled nose
    parts["white"].append(filt_pairs(body, lambda c: not (abs(c[2] - 0.2) < 0.35)))
    parts["teal"].append(filt_pairs(body, lambda c: abs(c[2] - 0.2) < 0.35))
    # Canopy band.
    cp = lathe([(1.82, 1.4), (1.6, 2.5)], 30)
    cp.P = [p * np.array([1.01, 0.83, 1.0]) for p in cp.P]
    outward_from(cp, axis_centre)
    parts["glass"].append(filt_pairs(cp, lambda c: c[1] > 0.55))
    # Window frames and a row of side ports.
    for k in range(5):
        a = math.pi * (0.25 + 0.125 * k)
        fr = bevel_box((0.06, 0.06, 1.2), 0.015); fr.transform(rotx(-0.25), (math.cos(a) * 1.72, math.sin(a) * 1.45, 1.95)); parts["dark"].append(fr)
    for sx in (-1, 1):
        for k in range(3):
            pw = cyl(0.13, 0.08, 14, (sx * 1.93, 0.55, -2.6 + k * 0.7), axis='x'); parts["glass"].append(pw)
            ring = lathe([(0.17, -0.05), (0.17, 0.05)], 14, axis='x'); ring.transform(None, (sx * 1.93, 0.55, -2.6 + k * 0.7)); parts["dark"].append(ring)
    # Thrusters on the back, RCS pods, dorsal fin, side hatch.
    for (x, y) in ((-0.8, 0.3), (0.8, 0.3), (0.0, -0.7)):
        noz = lathe([(0.45, -3.5), (0.55, -4.1), (0.62, -4.5), (0.5, -4.6), (0.3, -4.0)], 16); noz.transform(None, (x, y, 0)); parts["dark"].append(noz)
    for sx in (-1, 1):
        for zz in (-2.4, 2.0):
            pod = bevel_box((0.3, 0.3, 0.5), 0.06, (sx * 1.95, 0.25, zz)); parts["dark"].append(pod)
        hatch = bevel_box((0.06, 1.0, 1.3), 0.03, (sx * 1.93, 0.0, -0.8)); parts["dark"].append(hatch)
        st = bevel_box((0.04, 0.12, 2.2), 0.01, (sx * 1.95, -0.55, -1.0)); parts["teal"].append(st)
    fin = hull_of([(0, 1.5, -3.3), (0, 1.5, -1.2), (0, 2.7, -3.5), (0, 2.6, -2.9), (0.08, 1.5, -2.2), (-0.08, 1.5, -2.2)])
    parts["teal"].append(fin)
    beacon = cyl(0.1, 0.12, 10, (0, 2.68, -3.3)); parts["glow"].append(beacon)
    # Landing legs: three good, one snapped.
    for i, a in enumerate((0.8, 2.35, 3.95, 5.5)):
        ca, sa = math.cos(a), math.sin(a)
        top = np.array([ca * 1.6, -0.9, sa * 1.6 * 1.2])
        knee = np.array([ca * 2.5, -1.4, sa * 2.5 * 1.2])
        foot = np.array([ca * 2.9, -2.4, sa * 2.9 * 1.2])
        if i == 2:   # snapped
            foot = knee + np.array([0.2, -0.3, -0.5])
        parts["dark"].append(tube([top, knee], 0.11, 8)); parts["dark"].append(tube([knee, foot], 0.08, 8))
        if i != 2:
            pad = lathe([(0.0, 0.0), (0.42, 0.0), (0.38, 0.1), (0.0, 0.12)], 14, axis='y'); pad.transform(None, foot); parts["dark"].append(pad)
        piston = tube([top + np.array([0, -0.2, 0]), (knee + foot) / 2], 0.05, 6); parts["dark"].append(piston)
    # Survey dish and sensor boom.
    dish = lathe([(0.0, 0.18), (0.5, 0.0), (0.55, 0.04)], 18, axis='y'); dish.transform(rotx(0.6), (0.9, 1.65, -1.5)); parts["white"].append(dish)
    boom = tube([(-0.7, 1.4, 0.5), (-1.0, 2.6, 0.2)], 0.04, 6); parts["dark"].append(boom)
    return parts


def hull_plate():
    """A torn sheet of ochre hull with its ribs still riveted on."""
    m = Mesh()
    nx, nz = 14, 10
    G = np.zeros((nz + 1, nx + 1, 3))
    for j in range(nz + 1):
        for i in range(nx + 1):
            u, v = i / nx - 0.5, j / nz - 0.5
            G[j, i] = (u * 4.2, -0.6 * (u * 2) ** 2 + 0.2 * noise3(np.array([[u * 3, 0, v * 3]]))[0], v * 3.0)
    keep = lambda u, v: (abs(u) + abs(v) * 0.9 + 0.35 * noise3(np.array([[u * 4, 1, v * 4]]))[0]) < 0.62
    sheet = Mesh()
    for j in range(nz):
        for i in range(nx):
            u, v = (i + 0.5) / nx - 0.5, (j + 0.5) / nz - 0.5
            if not keep(u, v):
                continue
            a, b, c, d = G[j, i], G[j, i + 1], G[j + 1, i + 1], G[j + 1, i]
            sheet.quad(a, b, c, d)
    outward_from(sheet, lambda f: f - np.array([0, 1.0, 0]))
    under = Mesh()
    for t in range(0, len(sheet.P), 3):
        a, b, c = (np.asarray(sheet.P[t + k]) + np.array([0, -0.07, 0]) for k in range(3))
        under.tri(a, c, b)
    sheet = smooth_normals(sheet); under = smooth_normals(under)
    parts = {"livery": [sheet], "dark": [under]}
    for u in (-0.25, 0.0, 0.25):
        pts = [G[j, int((u + 0.5) * nx)] + np.array([0, -0.12, 0]) for j in range(2, nz - 1) if keep(u, j / nz - 0.5)]
        if len(pts) > 1:
            parts["dark"].append(tube(pts, 0.07, 6))
    return parts


# ---------------------------------------------------------------- Vaari ruins

def stone_column(h, r=0.62, seg=10, seed=0.0, crystal=True, broken_at=None):
    parts = {"stone": [], "crystal": []}
    top = h if broken_at is None else broken_at
    prof = [(r * 1.35, 0.0), (r * 1.35, 0.35), (r * 1.15, 0.45), (r * 1.15, 0.62), (r, 0.72)]
    z = 0.72
    while z < top - 0.6:
        rr = r * (1.0 - 0.12 * z / h)
        prof.append((rr, z))
        if abs((z % 1.6) - 0.8) < 0.13:        # carved ring
            prof.append((rr * 0.9, z + 0.05)); prof.append((rr * 0.9, z + 0.2)); prof.append((rr, z + 0.25))
            z += 0.25
        z += 0.4
    if broken_at is None:
        rt = r * 0.88
        prof += [(rt, h - 0.6), (rt * 1.25, h - 0.5), (rt * 1.25, h - 0.2), (rt * 1.4, h - 0.15), (rt * 1.4, h), (0.0, h)]
    else:
        prof += [(r * (1.0 - 0.12 * top / h), top), (0.0, top)]
    col = lathe(prof, seg, axis='y', flat=True)
    outward_from(col, lambda f: np.array([0.0, f[1], 0.0]))
    if broken_at is not None:
        # Jagged break: push the top cap's points up and down.
        P = np.array(col.P)
        up = P[:, 1] > top - 0.05
        P[up, 1] += (noise3(P[up] * 2.1 + seed) * 0.5 + 0.25) * 0.9 * (np.hypot(P[up, 0], P[up, 2]) / r + 0.2)
        col.P = list(P)
    col = jitter(col, 0.07, 1.6, None, seed)
    col = jitter(col, 0.03, 5.0, None, seed + 3)
    flat_normals(col)
    parts["stone"].append(col)
    if crystal:
        # A vein of crystal growing up one face.
        y = 0.9
        a0 = seed * 1.7
        while y < top - 0.8:
            a = a0 + math.sin(y * 1.3) * 0.25
            rr = r * (1.0 - 0.12 * y / h) + 0.03
            L = rng.uniform(0.25, 0.55)
            p = np.array([math.cos(a) * rr, y, math.sin(a) * rr])
            sh = crystal_prism(rng.uniform(0.08, 0.15), L * 1.3)
            out = np.array([math.cos(a), 0.4, math.sin(a)]); out /= np.linalg.norm(out)
            sh.transform(align_y(out), p)
            parts["crystal"].append(sh)
            y += rng.uniform(0.25, 0.5)
    return parts


def align_y(d):
    """Rotation taking +Y onto direction d."""
    d = np.asarray(d, float); d /= np.linalg.norm(d)
    y = np.array([0, 1.0, 0])
    v = np.cross(y, d); c = np.dot(y, d)
    if np.linalg.norm(v) < 1e-6:
        return np.eye(3) if c > 0 else rotx(math.pi)
    vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx * (1 / (1 + c))


def crystal_prism(r, L, sides=6):
    """Hexagonal crystal with a pointed tip, base at the origin, along +Y."""
    prof = [(0.0, -0.05), (r * 0.85, -0.05), (r, L * 0.15), (r, L * 0.72), (0.0, L)]
    m = lathe(prof, sides, axis='y', flat=True)
    outward_from(m, lambda f: np.array([0.0, f[1], 0.0]))
    flat_normals(m)
    return m


def crystal_cluster(n=9, spread=0.45, size=1.0, seed=0):
    r = np.random.default_rng(seed)
    m = Mesh()
    for k in range(n):
        a = r.uniform(0, 2 * math.pi)
        d = r.uniform(0, spread) * (0.3 if k == 0 else 1.0)
        L = size * (1.6 if k == 0 else r.uniform(0.5, 1.2))
        tilt = np.array([math.cos(a) * d * 1.4, 1.0, math.sin(a) * d * 1.4])
        c = crystal_prism(size * r.uniform(0.07, 0.13) * (1.4 if k == 0 else 1.0), L)
        c.transform(align_y(tilt), (math.cos(a) * d, 0, math.sin(a) * d))
        m.extend(c)
    return m


def ruin_arch():
    parts = {"stone": [], "crystal": []}
    span = 2.6
    for sx, sd in ((-1, 1.0), (1, 2.0)):
        c = stone_column(5.4, 0.55, 10, sd, crystal=(sx < 0))
        for k in c:
            for m in c[k]:
                m.transform(None, (sx * span, 0, 0))
                parts[k].append(m)
    # Lintel: a chunky curved beam with a squared section.
    secs = []
    for i in range(21):
        t = i / 20
        a = math.pi * t
        x = -math.cos(a) * (span + 0.15)
        y = 5.25 + math.sin(a) * 0.75
        tang = np.array([math.sin(a), math.cos(a) * 0.75 / (span + 0.15), 0.0]); tang /= np.linalg.norm(tang)
        nrm = np.array([-tang[1], tang[0], 0.0])
        hh = 0.42 + 0.18 * (1 - math.sin(a))
        ring = []
        for (u, w) in [(hh, 0.55), (hh, -0.55), (-hh, -0.55), (-hh, 0.55)]:
            ring.append(np.array([x, y, 0.0]) + nrm * u + np.array([0, 0, w]))
        secs.append(np.array(ring))
    lin = loft(secs)
    outward_from(lin, lambda f: np.array([-math.cos(math.acos(np.clip(-f[0] / (span + 0.15), -1, 1))) * (span + 0.15), 5.25 + math.sin(math.acos(np.clip(-f[0] / (span + 0.15), -1, 1))) * 0.75, 0.0]))
    lin = jitter(lin, 0.06, 1.8, None, 4.0)
    flat_normals(lin)
    parts["stone"].append(lin)
    key = hull_of([(-0.35, 5.6, -0.62), (0.35, 5.6, -0.62), (-0.45, 6.6, -0.62), (0.45, 6.6, -0.62),
                   (-0.35, 5.6, 0.62), (0.35, 5.6, 0.62), (-0.45, 6.6, 0.62), (0.45, 6.6, 0.62)])
    parts["stone"].append(jitter(key, 0.04, 2.0, None, 8.0))
    for sz in (-1, 1):
        cc = crystal_cluster(5, 0.12, 0.45, 3 + sz)
        cc.transform(rotx(sz * math.pi / 2), (0, 6.1, sz * 0.6))
        parts["crystal"].append(cc)
    return parts


def ruin_wall():
    """Rows of rough hand-cut blocks; the top steps down where blocks fell."""
    parts = {"stone": []}
    L = 9.0
    y = 0.0
    row = 0
    height_at = lambda x: 3.6 - 2.4 * np.clip((x + 1.0) / 4.5, 0, 1) + 0.8 * math.sin(x * 0.9) * (x > 0)
    while y < 3.6:
        h = rng.uniform(0.5, 0.75)
        x = -L / 2 - (row % 2) * 0.5
        while x < L / 2:
            w = rng.uniform(0.9, 1.6)
            cx = x + w / 2
            if -L / 2 < cx < L / 2 and y + h * 0.5 < height_at(cx):
                b = blob((w - 0.05, h - 0.04, 0.9 + rng.uniform(-0.05, 0.08)), e=0.14, nu=20, nv=10,
                         center=(cx, y + h / 2, rng.normal(0, 0.03)))
                # Subdivide a little by jitter so blocks read as hand cut, not boxes.
                b = jitter(b, 0.09, 1.8, None, row * 7.0 + x)
                b.transform(rotz(rng.normal(0, 0.03)) @ roty(rng.normal(0, 0.04)), (0, 0, rng.normal(0, 0.04)))
                parts["stone"].append(b)
            x += w
        y += h; row += 1
    # Fallen blocks at the foot of the broken end.
    for k in range(6):
        w = rng.uniform(0.7, 1.3)
        b = blob((w, rng.uniform(0.45, 0.65), 0.85), e=0.14, nu=20, nv=10)
        b = jitter(b, 0.08, 2.0, None, 50 + k)
        b.transform(rotx(rng.uniform(-0.4, 0.4)) @ roty(rng.uniform(0, 3)) @ rotz(rng.uniform(-0.5, 0.5)),
                    (rng.uniform(1.0, 4.5), 0.25 + (0.3 if k > 3 else 0.0), rng.uniform(0.9, 2.2) * (1 if k % 2 else -1)))
        parts["stone"].append(b)
    for m in parts["stone"]:
        smooth_normals(m)
    return parts


def ruin_dais():
    parts = {"stone": [], "crystal": [], "glow": []}
    prof = [(0.0, 0.0), (5.2, 0.0), (5.2, 0.35), (4.4, 0.35), (4.4, 0.7), (3.5, 0.7), (3.5, 1.05), (2.2, 1.05),
            (2.2, 1.12), (0.0, 1.12)]
    d = lathe(prof, 36, axis='y', flat=True)
    outward_from(d, lambda f: np.array([0.0, f[1], 0.0]))
    d = jitter(d, 0.09, 1.2, lambda p: 1.0 if p[1] > 0.05 else 0.3, 2.0)
    flat_normals(d)
    # Cut a few chunks out of the outer step (crumbled).
    d = filt(d, lambda c: not (np.hypot(c[0], c[2]) > 4.5 and noise3(np.array([c * 0.7]))[0] > 0.32))
    parts["stone"].append(d)
    # Carved ring channel on the top tier that the crystal light runs along.
    ring = lathe([(1.7, 1.125), (1.95, 1.125)], 36, axis='z', flat=True)
    ring.transform(rotx(-math.pi / 2)); ring.transform(None, (0, 0, 0))
    ring.P = [np.array([p[0], 1.125, p[2]]) for p in ring.P]
    outward_from(ring, lambda f: np.array([f[0], 0.0, f[2]]))
    parts["glow"].append(ring)
    # Four low standing stones round the edge.
    for k in range(4):
        a = k * math.pi / 2 + 0.4
        st = stone_column(1.6 + rng.random() * 0.6, 0.32, 8, 10 + k, crystal=False)
        for m in st["stone"]:
            m.transform(None, (math.cos(a) * 4.0, 0.62, math.sin(a) * 4.0))
            parts["stone"].append(m)
    cc = crystal_cluster(11, 0.55, 1.15, 7); cc.transform(None, (0, 1.05, 0)); parts["crystal"].append(cc)
    return parts


def ruin_drum():
    c = stone_column(1.3, 0.55, 10, 21.0, crystal=False, broken_at=1.1)
    for m in c["stone"]:
        m.transform(rotz(math.pi / 2), (0.55, 0.5, 0))
    return {"stone": c["stone"]}


# ---------------------------------------------------------------- Coalition kit

def med_case():
    """Hard-shell cache case: white shell, orange bumpers, latches, handle,
    med glyph panel. Lid is a separate node hinged at the back top edge."""
    W, H, D = 1.0, 0.36, 0.62
    base = blob((W, H, D), e=0.18, nu=28, nv=12, center=(0, H / 2, 0))
    lid = blob((W, 0.16, D), e=0.18, nu=28, nv=10, center=(0, 0.08, D / 2))   # hinge at origin
    body = {"white": [base], "orange": [], "dark": [], "glyph": []}
    lidp = {"white": [lid], "orange": [], "dark": [], "glyph": []}
    for sx in (-1, 1):
        bump = blob((0.12, H + 0.04, D + 0.06), e=0.3, nu=16, nv=10, center=(sx * (W / 2 - 0.03), H / 2, 0))
        body["orange"].append(bump)
        lb = blob((0.12, 0.17, D + 0.06), e=0.3, nu=16, nv=8, center=(sx * (W / 2 - 0.03), 0.08, D / 2))
        lidp["orange"].append(lb)
        latch = bevel_box((0.12, 0.14, 0.04), 0.015, (sx * 0.28, H - 0.04, D / 2 + 0.005)); body["dark"].append(latch)
    handle = tube([(-0.2, H / 2, D / 2 + 0.02), (-0.18, H / 2, D / 2 + 0.09), (0.18, H / 2, D / 2 + 0.09), (0.2, H / 2, D / 2 + 0.02)], 0.018, 8)
    handle.transform(None, (0, 0, 0)); body["dark"].append(handle)
    panel = Mesh()
    panel.quad_uv((-0.17, 0.165, D / 2 - 0.17), (0.17, 0.165, D / 2 - 0.17), (0.17, 0.165, D / 2 + 0.17), (-0.17, 0.165, D / 2 + 0.17),
                  (0, 0), (1, 0), (1, 1), (0, 1), n=np.array([0, 1.0, 0]))
    winding_from_normals(panel)
    lidp["glyph"].append(panel)
    for sz in (-1, 1):
        rib = bevel_box((W - 0.1, 0.03, 0.04), 0.01, (0, H * 0.55, sz * (D / 2 - 0.0))); body["dark"].append(rib)
    return body, lidp


def med_pack():
    """Pathfinder med pouch: padded body, flap, straps and glyph patch."""
    p = {"olive": [], "orange": [], "dark": [], "glyph": []}
    p["olive"].append(blob((0.42, 0.26, 0.2), e=0.45, center=(0, 0.13, 0)))
    p["olive"].append(blob((0.4, 0.06, 0.22), e=0.4, center=(0, 0.25, 0.01)))
    for sx in (-1, 1):
        st = bevel_box((0.04, 0.27, 0.215), 0.01, (sx * 0.12, 0.135, 0)); p["dark"].append(st)
        pk = blob((0.08, 0.16, 0.14), e=0.45, center=(sx * 0.23, 0.1, 0)); p["olive"].append(pk)
    pt = Mesh()
    pt.quad_uv((-0.07, 0.07, 0.102), (0.07, 0.07, 0.102), (0.07, 0.21, 0.102), (-0.07, 0.21, 0.102), (0, 1), (1, 1), (1, 0), (0, 0), n=np.array([0, 0, 1.0]))
    winding_from_normals(pt)
    p["glyph"].append(pt)
    tag = bevel_box((0.12, 0.03, 0.02), 0.005, (0, 0.27, 0.12)); p["orange"].append(tag)
    return p


def pathfinder_beacon():
    p = {"dark": [], "orange": [], "glow": []}
    top = np.array([0, 1.25, 0])
    for k in range(3):
        a = k * 2 * math.pi / 3
        foot = np.array([math.cos(a) * 0.55, 0.0, math.sin(a) * 0.55])
        p["dark"].append(tube([foot, top + np.array([0, -0.1, 0])], 0.025, 6))
        p["dark"].append(lathe([(0.0, 0.0), (0.06, 0.0), (0.04, 0.05), (0.0, 0.05)], 8, axis='y').transform(t=foot))
    mast = cyl(0.04, 0.6, 10, (0, 1.45, 0)); p["dark"].append(mast)
    head = lathe([(0.0, 0.0), (0.12, 0.0), (0.14, 0.05), (0.14, 0.18), (0.1, 0.2), (0.0, 0.2)], 14, axis='y'); head.transform(None, (0, 1.75, 0)); p["orange"].append(head)
    lens = lathe([(0.0, 0.0), (0.09, 0.0), (0.09, 0.12), (0.0, 0.14)], 14, axis='y'); lens.transform(None, (0, 1.95, 0)); p["glow"].append(lens)
    box = bevel_box((0.22, 0.16, 0.12), 0.02, (0, 1.05, 0.06)); p["orange"].append(box)
    panel = bevel_box((0.36, 0.02, 0.24), 0.005); panel.transform(rotx(-0.6), (0, 1.32, -0.14)); p["dark"].append(panel)
    ant = tube([(0.05, 1.75, 0), (0.07, 2.25, 0.02)], 0.008, 4); p["dark"].append(ant)
    return p


def glowcap():
    """Broad dark leaves round a few stalks that end in glowing bulbs."""
    p = {"leaf": [], "stalk": [], "bulb": []}
    r = np.random.default_rng(5)
    for k in range(7):
        a = k / 7 * 2 * math.pi + r.normal(0, 0.2)
        L = r.uniform(0.38, 0.55); W = L * 0.32
        secs = []
        for i in range(9):
            t = i / 8
            w = W * math.sin(math.pi * min(1.0, t * 1.05)) ** 0.8 + 0.004
            d = np.array([math.cos(a), 0, math.sin(a)])
            side = np.array([-math.sin(a), 0, math.cos(a)])
            centre = d * (t * L) + np.array([0, 0.02 + math.sin(t * math.pi * 0.9) * L * 0.45 - t * t * L * 0.2, 0])
            fold = 0.25 * w
            secs.append(np.array([centre + side * w + np.array([0, -fold, 0]), centre + np.array([0, 0.002, 0]),
                                  centre - side * w + np.array([0, -fold, 0])]))
        leaf = loft(secs, closed=False, cap_start=False, cap_end=False)
        outward_from(leaf, lambda f: f - np.array([0, 1.0, 0]))   # face up (material is double-sided)
        p["leaf"].append(smooth_normals(leaf))
    for k in range(5):
        a = r.uniform(0, 2 * math.pi); d = r.uniform(0.0, 0.1)
        h = r.uniform(0.35, 0.62)
        base = np.array([math.cos(a) * d, 0.0, math.sin(a) * d])
        tip = base + np.array([math.cos(a) * 0.08, h, math.sin(a) * 0.08])
        p["stalk"].append(tube([base, base + np.array([0, h * 0.5, 0]), tip], 0.012, 6))
        rb = r.uniform(0.045, 0.07)
        p["bulb"].append(blob((rb * 2, rb * 2.4, rb * 2), e=0.9, nu=14, nv=10, center=tip + np.array([0, rb, 0])))
    return p


def tissue_vial():
    p = {"dark": [], "glass": [], "crystal": []}
    p["glass"].append(lathe([(0.0, 0.03), (0.045, 0.03), (0.045, 0.2), (0.0, 0.2)], 16, axis='y'))
    for y in (0.0, 0.2):
        p["dark"].append(lathe([(0.0, y), (0.055, y), (0.055, y + 0.035), (0.0, y + 0.035)], 16, axis='y'))
    sh = crystal_prism(0.018, 0.13, 5); sh.transform(rotz(0.15), (0, 0.05, 0)); p["crystal"].append(sh)
    return p


def field_shelter():
    """Collapsed Coalition lean-to: a frame with one pole down and a sagging tarp."""
    p = {"dark": [], "tarp": []}
    poles = [((-1.6, 0, -1.0), (-1.5, 1.8, -1.0)), ((1.6, 0, -1.0), (1.4, 1.75, -0.95)), ((-1.6, 0, 1.0), (-1.5, 1.1, 0.95)),
             ((1.6, 0, 1.0), (2.3, 0.15, 1.6))]   # the last one has fallen
    for a, b in poles:
        p["dark"].append(tube([a, b], 0.03, 6))
    p["dark"].append(tube([(-1.5, 1.8, -1.0), (1.4, 1.75, -0.95)], 0.025, 6))
    nx, nz = 16, 12
    G = np.zeros((nz + 1, nx + 1, 3))
    for j in range(nz + 1):
        for i in range(nx + 1):
            u, v = i / nx, j / nz
            x = -1.65 + 3.3 * u
            z = -1.05 + 2.3 * v
            yb = 1.8 - 0.7 * v           # sloping roof
            y = yb - 0.35 * math.sin(math.pi * u) * math.sin(math.pi * v * 0.9)
            if u > 0.6:                   # corner sags where the pole fell
                y -= (u - 0.6) * 2.3 * v ** 1.2
            y += 0.05 * noise3(np.array([[x * 2, 0, z * 2]]))[0]
            G[j, i] = (x, max(0.05, y), z)
    tarp = Mesh()
    for j in range(nz):
        for i in range(nx):
            a, b, c, d = G[j, i], G[j, i + 1], G[j + 1, i + 1], G[j + 1, i]
            tarp.quad(a, b, c, d)
    outward_from(tarp, lambda f: f - np.array([0, 1.0, 0]))
    p["tarp"].append(smooth_normals(tarp))
    return p


# ---------------------------------------------------------------- export

def fabric_tex(n=512, seed=4, col=(0.32, 0.36, 0.24)):
    r = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:n, 0:n]
    weave = (np.sin(xx * 0.9) * np.sin(yy * 0.9)) * 0.5 + 0.5
    stain = _tile_noise(n, 6, r, 4)
    alb = np.dstack([col[c] * (0.85 + 0.15 * weave) * (0.75 + 0.35 * stain) for c in range(3)])
    nrm = _normal_from_height(ndimage.gaussian_filter(weave, 0.8, mode='wrap'), 2.0)
    return _img(alb), Image.fromarray(nrm)


def add(g, name, parts, mats, colfn=None, uvs=0.25, parent=None, translation=None):
    prims = []
    for key, mat in mats.items():
        if key not in parts or not parts[key]:
            continue
        m = merge(parts[key])
        if not m.P:
            continue
        P, N = m.arrays()
        col = colfn(key, P, N) if colfn is not None else None
        prims.append((m, mat, col, uvs))
    return g.mesh_node(name, prims, parent=parent, translation=translation)


def main(path):
    g = GLB()
    ha, hn, hm = hull_panels(2048, seed=8, base=(0.62, 0.62, 0.62))
    th = (g.image(ha, "hull_a"), g.image(hn, "hull_n"), g.image(hm, "hull_mr"))
    sa, sn, sm = carved_stone(2048)
    ts = (g.image(sa, "stone_a"), g.image(sn, "stone_n"), g.image(sm, "stone_mr"))
    hz = g.image(hazard(), "hazard_a")
    mg = g.image(medglyph(), "medglyph_a")
    fa, fn = fabric_tex(512, 4, (0.3, 0.34, 0.22))
    tf = (g.image(fa, "fabric_a"), g.image(fn, "fabric_n"))
    ta, tn = fabric_tex(512, 6, (0.75, 0.42, 0.14))
    tt = (g.image(ta, "tarp_a"), g.image(tn, "tarp_n"))

    def hullmat(name, col, metal=1.0, rough=1.0, **k):
        g.material(name, color=col, albedo_tex=th[0], normal_tex=th[1], mr_tex=th[2], metal=metal, rough=rough, **k)
    hullmat("FreightHull", (0.95, 0.62, 0.26, 1), 0.6)
    hullmat("FreightBand", (0.24, 0.25, 0.27, 1), 0.9)
    hullmat("DarkMetal", (0.2, 0.21, 0.23, 1), 1.0, 1.1)
    hullmat("WreckInterior", (0.1, 0.105, 0.11, 1), 0.8, 1.2, double=True)
    hullmat("SurveyWhite", (0.9, 0.91, 0.93, 1), 0.3)
    hullmat("SurveyTeal", (0.12, 0.55, 0.58, 1), 0.4)
    hullmat("CoalitionWhite", (0.88, 0.89, 0.9, 1), 0.1, 0.8)
    hullmat("CoalitionOrange", (0.95, 0.45, 0.1, 1), 0.2, 0.9)
    g.material("Hazard", albedo_tex=hz, normal_tex=th[1], metal=0.5, rough=0.7)
    g.material("Glass", color=(0.04, 0.06, 0.08, 0.85), metal=0.2, rough=0.06, blend=True, double=True)
    g.material("DyingGlow", color=(0.1, 0.03, 0.02, 1), emissive=(1.0, 0.3, 0.08), emissive_strength=1.6, rough=0.6)
    g.material("NavGlow", color=(0.3, 0.1, 0.02, 1), emissive=(1.0, 0.5, 0.12), emissive_strength=3.0)
    g.material("Stone", albedo_tex=ts[0], normal_tex=ts[1], mr_tex=ts[2], metal=0.0, rough=1.0)
    g.material("Crystal", color=(0.35, 0.85, 1.0, 0.88), emissive=(0.2, 0.75, 1.0), emissive_strength=2.6, rough=0.08, blend=True)
    g.material("CrystalLine", color=(0.05, 0.2, 0.25, 1), emissive=(0.2, 0.75, 1.0), emissive_strength=1.8, rough=0.3)
    g.material("MedGlyph", albedo_tex=mg, emissive_tex=mg, emissive=(0.5, 0.9, 0.95), emissive_strength=1.2, rough=0.4)
    g.material("Olive", albedo_tex=tf[0], normal_tex=tf[1], rough=0.95)
    g.material("Tarp", albedo_tex=tt[0], normal_tex=tt[1], rough=0.9, double=True)
    g.material("BeaconGlow", color=(0.4, 0.15, 0.02, 1), emissive=(1.0, 0.55, 0.12), emissive_strength=4.0)
    g.material("Leaf", color=(0.12, 0.26, 0.2, 1), rough=0.7, double=True)
    g.material("Stalk", color=(0.3, 0.38, 0.22, 1), rough=0.8)
    g.material("Bulb", color=(0.55, 0.9, 0.4, 1), emissive=(0.55, 1.0, 0.35), emissive_strength=2.2, rough=0.35)
    g.material("VialGlass", color=(0.6, 0.8, 0.85, 0.35), rough=0.05, blend=True)

    def grime(burn=(), scorch=0.6, dark=0.0, seed=0.0):
        def f(key, P, N):
            if key in ("glass", "glow", "hazard"):
                return None
            return vcol_grime(P, burn, 3.5, dark + (0.15 if key == "inner" else 0.0), scorch, seed)
        return f

    def stonecol(moss=0.6, seed=0.0):
        def f(key, P, N):
            return vcol_stone(P, N, moss, seed) if key == "stone" else None
        return f

    ship = {"hull": "FreightHull", "livery": "FreightBand", "dark": "DarkMetal", "inner": "WreckInterior",
            "glass": "Glass", "glow": "DyingGlow", "hazard": "Hazard"}
    add(g, "FreighterFore", freighter_fore(), ship, grime([(0, 0.5, 0.3), (2.0, 2.4, 13.5)], 0.7, seed=1.0))
    add(g, "FreighterAft", freighter_aft(), ship, grime([(0, 0.2, -0.3), (-1.8, 0.4, -12.5)], 0.75, seed=2.0))
    add(g, "CargoPod", cargo_pod(), {"livery": "FreightHull", "dark": "DarkMetal", "hazard": "Hazard"}, grime((), 0.3, 0.05, 3.0))
    add(g, "HullPlate", hull_plate(), {"livery": "FreightHull", "dark": "DarkMetal"}, grime([(0, 0, 0)], 0.6, seed=4.0))
    add(g, "SurveyLander", survey_lander(), {"white": "SurveyWhite", "teal": "SurveyTeal", "dark": "DarkMetal", "glass": "Glass", "glow": "NavGlow"},
        grime([(0, 0.5, 3.6)], 0.8, seed=5.0))
    rmats = {"stone": "Stone", "crystal": "Crystal", "glow": "CrystalLine"}
    add(g, "RuinPillar", stone_column(6.2, 0.62, 10, 1.0), rmats, stonecol(0.6, 1.0))
    add(g, "RuinPillarBroken", stone_column(6.2, 0.62, 10, 2.0, crystal=True, broken_at=2.6), rmats, stonecol(0.7, 2.0))
    add(g, "RuinDrum", ruin_drum(), rmats, stonecol(0.5, 3.0))
    add(g, "RuinArch", ruin_arch(), rmats, stonecol(0.55, 4.0))
    add(g, "RuinWall", ruin_wall(), rmats, stonecol(0.65, 5.0))
    add(g, "RuinDais", ruin_dais(), rmats, stonecol(0.5, 6.0))
    add(g, "CrystalCluster", {"crystal": [crystal_cluster(10, 0.5, 1.0, 12)]}, rmats)
    body, lid = med_case()
    cmats = {"white": "CoalitionWhite", "orange": "CoalitionOrange", "dark": "DarkMetal", "glyph": "MedGlyph", "olive": "Olive"}
    add(g, "MedCase", body, cmats, grime((), 0.2, 0.0, 6.0), uvs=0.12)
    add(g, "MedCaseLid", lid, cmats, grime((), 0.2, 0.0, 6.0), uvs=0.12)
    add(g, "MedPack", med_pack(), cmats, None, uvs=2.0)
    add(g, "PathfinderBeacon", pathfinder_beacon(), {"dark": "DarkMetal", "orange": "CoalitionOrange", "glow": "BeaconGlow"}, grime((), 0.1, 0.0, 7.0), uvs=1.0)
    g.empty("LightAt", parent=len(g.j["nodes"]) - 1, translation=(0, 2.02, 0))
    add(g, "Glowcap", glowcap(), {"leaf": "Leaf", "stalk": "Stalk", "bulb": "Bulb"})
    add(g, "TissueVial", tissue_vial(), {"dark": "DarkMetal", "glass": "VialGlass", "crystal": "Crystal"}, uvs=4.0)
    add(g, "FieldShelter", field_shelter(), {"dark": "DarkMetal", "tarp": "Tarp"}, uvs=0.6)
    g.save(path)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "reach_kit.glb")
