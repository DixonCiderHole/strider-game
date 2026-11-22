"""Spire Canyon kit (models/canyon_kit.glb): the new assets for the canyon
hub and the five places off it.

Nodes (each at its own origin, +Z forward, Y up, metres):
  Bulkhead        a whole armoured bulkhead torn out of a warship, jammed
                  upright across a gorge (16 x 12 m)
  BulkheadCut     the same, with a doorway cut through it (glowing edges)
  BulkheadSlab    the slab the saw cut out, lying flat
  SupplyDrop      an Ascendancy supply drop pod, split open, with the
                  droid repair cradle beside it (the droid sits on CradleAt)
  GiantShroomA/B  towering glowcap fungi for the Glowmire Caverns
  IceSpire        a tall cluster of blue ice crystal (Rimefall Plateau)
  HangarShell     a 60 m section of the capital ship VIGILANT's hull, torn
                  open at both ends: walk-in hangar deck inside
  HangarGantry    a catwalk with stairs up to the hangar's upper deck
  TempleGate      a Vaari stone gateway with a crystal keystone
  TempleStep      a stepped Vaari pyramid with a crystal heart on top
  RootArch        a huge swamp root arching out of the mud (Sunken Mire)
  TempleHall      the temple's inside: entry passage, columned great hall
                  with an upper gallery, two side chambers and the sanctum

python3 canyon_gen.py ../../models/canyon_kit.glb
"""
import sys, math, numpy as np
from meshlib import *
from textures import hull_panels
import reach_gen as R
from reach_gen import (add, smooth_normals, flat_normals, outward_from, jitter, merge, filt, filt_pairs,
                       rounded_rect, ragged_ring, torn_edge, vcol_grime, vcol_stone, carved_stone,
                       stone_column, crystal_cluster, crystal_prism, align_y, hazard, axis_between)

rng = np.random.default_rng(77)


def box(size, c, rot=None, bev=0.05):
    b = bevel_box(size, bev)
    if rot is not None:
        b.transform(rot)
    b.transform(None, c)
    flat_normals(b)
    return b


# ---------------------------------------------------------------- bulkhead

def bulkhead(cut=False):
    p = {"hull": [], "dark": [], "hazard": [], "glow": []}
    W, H, T = 16.0, 12.0, 1.2
    door_w, door_h = 3.6, 4.6
    # Main plate: built from panels round the doorway so a cut can open it.
    if cut:
        sides = [(-(W + door_w) / 4, H / 2, (W - door_w) / 2, H),
                 ((W + door_w) / 4, H / 2, (W - door_w) / 2, H),
                 (0.0, door_h + (H - door_h) / 2, door_w, H - door_h)]
    else:
        sides = [(0.0, H / 2, W, H)]
    for (x, y, w, h) in sides:
        pl = box((w, h, T), (x, y, 0.0), bev=0.08)
        pl = jitter(pl, 0.06, 0.4, None, x + y)
        flat_normals(pl)
        p["hull"].append(pl)
    # Heavy frame ribs both faces, broken off at ragged lengths.
    for face in (-1, 1):
        for x in np.linspace(-W / 2 + 0.6, W / 2 - 0.6, 6):
            if cut and abs(x) < door_w / 2 + 0.3:
                top = H
                p["dark"].append(box((0.5, H - door_h - 0.3, 0.45), (x, door_h + 0.3 + (H - door_h - 0.3) / 2, face * (T / 2 + 0.22))))
                continue
            hh = H * rng.uniform(0.85, 1.05)
            p["dark"].append(box((0.5, hh, 0.45), (x, hh / 2, face * (T / 2 + 0.22))))
        for y in (2.2, 6.0, 9.8):
            if cut and y < door_h:
                for sx in (-1, 1):
                    seg_w = (W - door_w) / 2 - 0.4
                    p["dark"].append(box((seg_w, 0.4, 0.35), (sx * (door_w / 2 + 0.2 + seg_w / 2), y, face * (T / 2 + 0.2))))
                continue
            p["dark"].append(box((W - 0.8, 0.4, 0.35), (0.0, y, face * (T / 2 + 0.2))))
        # Conduits and pipe runs on the faces.
        for k in range(3):
            y = 3.6 + k * 2.6
            pts = [(-W / 2 + 0.4, y, face * (T / 2 + 0.55)), (-1.0, y + 0.3, face * (T / 2 + 0.6)), (W / 2 - 0.4, y - 0.2, face * (T / 2 + 0.55))]
            if cut and y < door_h + 0.2:
                continue
            p["dark"].append(tube(pts, 0.14, 8))
    # Torn top edge: jagged plates sticking up.
    for k in range(9):
        x = -W / 2 + 1.0 + k * (W - 2.0) / 8
        h = rng.uniform(0.6, 2.2)
        shard = hull_of([(x - 0.7, H - 0.1, -T / 2), (x + 0.7, H - 0.1, -T / 2), (x - 0.7, H - 0.1, T / 2), (x + 0.7, H - 0.1, T / 2),
                         (x + rng.uniform(-0.3, 0.3), H + h, rng.uniform(-0.2, 0.2))])
        flat_normals(shard)
        p["hull"].append(shard)
    # The sealed hatch outline (or the cut doorway) with hazard framing.
    for face in (-1, 1):
        zf = face * (T / 2 + 0.06)
        for (sx, sy, x, y) in ((0.35, door_h + 0.7, -door_w / 2 - 0.35, (door_h + 0.7) / 2),
                               (0.35, door_h + 0.7, door_w / 2 + 0.35, (door_h + 0.7) / 2),
                               (door_w + 1.05, 0.35, 0.0, door_h + 0.52)):
            p["hazard"].append(box((sx, sy, 0.12), (x, y, zf), bev=0.03))
        if not cut:
            p["dark"].append(box((door_w, door_h, 0.1), (0.0, door_h / 2, zf), bev=0.02))
    if cut:
        # Cut edges still glowing from the saw.
        for (a, b) in [((-door_w / 2, 0.0), (-door_w / 2, door_h)), ((door_w / 2, 0.0), (door_w / 2, door_h)),
                       ((-door_w / 2, door_h), (door_w / 2, door_h))]:
            for z in (-T / 2 + 0.05, T / 2 - 0.05):
                pts = [(a[0], a[1], z), (b[0], b[1], z)]
                p["glow"].append(tube(pts, 0.05, 6))
    return p


def bulkhead_slab():
    p = {"hull": [], "dark": [], "glow": []}
    s = box((3.6, 1.2, 4.6), (0.0, 0.6, 0.0), bev=0.06)
    p["hull"].append(s)
    for z in (-1.4, 0.0, 1.4):
        p["dark"].append(box((3.2, 0.35, 0.4), (0.0, 1.35, z)))
    for x in (-1.8, 1.8):
        p["glow"].append(tube([(x, 0.05, -2.3), (x, 0.05, 2.3)], 0.05, 6))
    return p


# ---------------------------------------------------------------- supply drop

def supply_drop():
    p = {"black": [], "red": [], "dark": [], "glow": [], "hazard": []}
    # Pod lying on its side, nose buried, split open along its length.
    prof = [(0.0, -2.0), (0.9, -1.9), (1.4, -1.3), (1.45, 1.2), (1.1, 1.8), (0.5, 2.1), (0.0, 2.15)]
    pod = lathe(prof, 28, axis='z', flat=False)
    outward_from(pod, lambda f: np.array([0.0, 0.0, float(np.clip(f[2], -1.5, 1.7))]))
    # Open along the top: drop the upper wedge.
    pod = filt(pod, lambda c: not (c[1] > 0.55 and abs(c[0]) < 0.9))
    smooth_normals(pod)
    pod.transform(rotz(0.25) @ roty(0.15), (0.0, 1.25, 0.0))
    p["black"].append(pod)
    inner = lathe([(1.3, -1.6), (1.32, 1.4)], 28, axis='z')
    outward_from(inner, lambda f: np.array([0.0, 0.0, f[2]]), inward=True)
    inner = filt(inner, lambda c: not (c[1] > 0.5 and abs(c[0]) < 0.85))
    inner.transform(rotz(0.25) @ roty(0.15), (0.0, 1.25, 0.0))
    p["dark"].append(inner)
    # Red faction bands and the open petal doors.
    for z in (-1.2, 0.0, 1.0):
        band = lathe([(1.48, z - 0.12), (1.48, z + 0.12)], 28, axis='z')
        outward_from(band, lambda f: np.array([0.0, 0.0, f[2]]))
        band = filt(band, lambda c: not (c[1] > 0.55 and abs(c[0]) < 0.95))
        band.transform(rotz(0.25) @ roty(0.15), (0.0, 1.25, 0.0))
        p["red"].append(band)
    for sx in (-1, 1):
        # Petal doors hinged on the split edges, flopped open against the hull.
        door = box((0.12, 1.2, 3.2), (sx * 1.55, 2.05, 0.0), rotz(sx * 1.2), 0.03)
        p["black"].append(door)
        p["red"].append(box((0.14, 0.25, 3.0), (sx * 1.62, 2.12, 0.0), rotz(sx * 1.2), 0.02))
    # Retro thrusters on the tail.
    for k in range(4):
        a = k * math.pi / 2 + 0.4
        n = lathe([(0.25, 0.0), (0.32, 0.5), (0.2, 0.55)], 14, axis='z')
        outward_from(n, lambda f: np.array([0.0, 0.0, 0.25]))
        n.transform(roty(0.15), (math.cos(a) * 0.7, 1.25 + math.sin(a) * 0.7, -2.2))
        p["dark"].append(n)
    # The repair cradle beside it: a frame with clamps and a power spine.
    cx = 3.6
    p["dark"].append(box((2.4, 0.3, 2.6), (cx, 0.15, 0.0), bev=0.06))
    p["hazard"].append(box((2.5, 0.1, 0.3), (cx, 0.33, 1.2), bev=0.02))
    p["hazard"].append(box((2.5, 0.1, 0.3), (cx, 0.33, -1.2), bev=0.02))
    for sx in (-1, 1):
        for sz in (-1, 1):
            post = box((0.18, 1.6, 0.18), (cx + sx * 1.05, 1.0, sz * 1.1), bev=0.03)
            p["black"].append(post)
            p["red"].append(box((0.4, 0.14, 0.24), (cx + sx * 0.92, 1.7, sz * 1.1), bev=0.02))
    spine = box((0.3, 2.6, 0.4), (cx, 1.4, -1.45), bev=0.05)
    p["black"].append(spine)
    p["glow"].append(box((0.08, 2.0, 0.06), (cx, 1.4, -1.24), bev=0.01))
    for k in range(3):
        p["dark"].append(tube([(cx, 2.5, -1.4), (cx + 0.5 - k * 0.5, 2.9, -0.6), (cx + 0.6 - k * 0.6, 2.4, 0.0)], 0.04, 6))
    return p


# ---------------------------------------------------------------- caverns

def giant_shroom(h, r, bend, seed):
    p = {"stalk": [], "cap": [], "glow": []}
    rr = np.random.default_rng(seed)
    pts = []
    for i in range(10):
        t = i / 9
        pts.append(np.array([math.sin(t * 1.4) * bend, t * h, math.sin(t * 2.0 + seed) * bend * 0.4]))
    st = tube(pts, 1.0, 14)
    P = np.array(st.P)
    for i in range(len(P)):
        t = np.clip(P[i, 1] / h, 0, 1)
        c = pts[min(9, int(round(t * 9)))]
        d = P[i] - c
        P[i] = c + d * (0.55 + 0.45 * (1 - t) + 0.4 * (1 - t) ** 4) * r * 0.18
    st.P = list(P)
    st = jitter(st, 0.05, 1.5, None, seed)
    smooth_normals(st)
    p["stalk"].append(st)
    top = pts[-1]
    cap = lathe([(0.0, 0.25 * r), (0.5 * r, 0.22 * r), (0.85 * r, 0.1 * r), (1.0 * r, -0.08 * r), (0.95 * r, -0.14 * r), (0.2 * r, -0.05 * r)], 32, axis='y')
    outward_from(cap, lambda f: np.array([0.0, 0.05 * r, 0.0]))
    cap = jitter(cap, 0.06 * r, 0.8 / r, None, seed + 3)
    smooth_normals(cap)
    cap.transform(rotx(rr.uniform(-0.12, 0.12)), tuple(top))
    p["cap"].append(cap)
    # Gills underneath glow, plus bright spots on the cap.
    gills = lathe([(0.25 * r, -0.07 * r), (0.93 * r, -0.13 * r)], 32, axis='y')
    outward_from(gills, lambda f: np.array([0.0, 1.0 * r, 0.0]), inward=True)
    gills.transform(None, tuple(top))
    p["glow"].append(gills)
    for k in range(9):
        a = rr.uniform(0, 2 * math.pi)
        d = rr.uniform(0.2, 0.8) * r
        y = 0.25 * r * (1 - (d / r) ** 2) + 0.02 * r
        sp = blob((0.25 * r * 0.4, 0.06 * r, 0.25 * r * 0.4), e=0.6, nu=10, nv=6, center=(top[0] + math.cos(a) * d, top[1] + y, top[2] + math.sin(a) * d))
        p["glow"].append(sp)
    return p


# ---------------------------------------------------------------- plateau

def ice_spire():
    p = {"ice": [], "rock": []}
    m = Mesh()
    r = np.random.default_rng(5)
    for k in range(11):
        a = r.uniform(0, 2 * math.pi)
        d = r.uniform(0, 1.2) * (0.2 if k == 0 else 1.0)
        L = 9.0 if k == 0 else r.uniform(2.5, 6.5)
        tilt = np.array([math.cos(a) * d * 0.5, 1.0, math.sin(a) * d * 0.5])
        c = crystal_prism(0.9 if k == 0 else r.uniform(0.35, 0.7), L, 6)
        c.transform(align_y(tilt), (math.cos(a) * d, -0.3, math.sin(a) * d))
        m.extend(c)
    p["ice"].append(m)
    base = blob((4.0, 1.4, 4.0), e=0.7, nu=16, nv=8, center=(0, 0.0, 0))
    base = jitter(base, 0.3, 0.6, None, 3.0)
    smooth_normals(base)
    p["rock"].append(base)
    return p


# ---------------------------------------------------------------- the VIGILANT

HW, HH = 15.0, 9.0      # hull half-width, height above the deck


def hull_section(z, s=1.0):
    return rounded_rect(HW * s, HH * s, z, e=0.28, n=40, y0=HH * 0.35 * s, flat_bottom=HH * 0.55 * s)


def hangar_shell():
    p = {"hull": [], "inner": [], "dark": [], "glow": [], "hazard": [], "deck": []}
    L = 60.0
    rings = [hull_section(z) for z in np.arange(-L / 2, L / 2 + 0.01, 2.0)]
    rings[0] = ragged_ring(rings[0], -1, 2.2, 3.3)
    rings[-1] = ragged_ring(rings[-1], 1, 2.2, 4.4)
    outer = loft(rings, cap_start=False, cap_end=False)
    outward_from(outer, axis_between(-L / 2 + 2, L / 2 - 2, HH * 0.35))
    outer = jitter(outer, 0.35, 0.15, None, 2.0)
    p["hull"].append(outer)
    inner_r = [hull_section(z, 0.94) for z in np.arange(-L / 2 + 1.0, L / 2 - 0.99, 2.0)]
    inner = loft(inner_r, cap_start=False, cap_end=False)
    outward_from(inner, axis_between(-L / 2 + 2, L / 2 - 2, HH * 0.35), inward=True)
    p["inner"].append(inner)
    p["dark"].append(torn_edge(rings[0], -1, 0.3, 4))
    p["dark"].append(torn_edge(rings[-1], 1, 0.3, 5))
    # Hangar deck, with bays marked out and a central lift track.
    deck = box((HW * 1.86, 0.4, L - 2.0), (0.0, 0.0, 0.0), bev=0.05)
    p["deck"].append(deck)
    for z in np.arange(-L / 2 + 6.0, L / 2 - 5.0, 12.0):
        for sx in (-1, 1):
            p["hazard"].append(box((7.0, 0.04, 0.3), (sx * 7.5, 0.22, z - 5.0), bev=0.01))
            p["hazard"].append(box((7.0, 0.04, 0.3), (sx * 7.5, 0.22, z + 5.0), bev=0.01))
            p["hazard"].append(box((0.3, 0.04, 10.0), (sx * 11.0, 0.22, z), bev=0.01))
    p["glow"].append(box((0.25, 0.05, L - 4.0), (-1.2, 0.23, 0.0), bev=0.01))
    p["glow"].append(box((0.25, 0.05, L - 4.0), (1.2, 0.23, 0.0), bev=0.01))
    # Ribs overhead every 4 m.
    for zr in np.arange(-L / 2 + 2.0, L / 2 - 1.0, 4.0):
        ring = hull_section(zr, 0.9)
        for k in range(len(ring)):
            a, b = ring[k], ring[(k + 1) % len(ring)]
            if a[1] < 0.3 and b[1] < 0.3:
                continue
            Lg = np.linalg.norm(b - a)
            v = (b - a) / max(Lg, 1e-6)
            rib = bevel_box((0.5, Lg + 0.1, 0.7), 0.06)
            rib.transform(rotz(math.atan2(v[1], v[0]) - math.pi / 2), (a + b) / 2)
            flat_normals(rib)
            p["dark"].append(rib)
        # A strip light on every other rib.
        if int(zr) % 8 == 2:
            p["glow"].append(box((6.0, 0.15, 0.2), (0.0, HH * 1.27, zr + 0.45), bev=0.02))
    # Wall consoles and cargo racks along both sides.
    for sx in (-1, 1):
        for z in np.arange(-L / 2 + 5.0, L / 2 - 4.0, 9.0):
            p["dark"].append(box((1.4, 3.0, 4.5), (sx * (HW * 0.86), 1.7, z), bev=0.08))
            p["glow"].append(box((0.06, 0.8, 3.0), (sx * (HW * 0.86 - 0.73), 2.4, z), bev=0.01))
    # Torn plating hanging from the ceiling near the breach.
    for k in range(6):
        x = rng.uniform(-8, 8)
        z = rng.choice([-L / 2 + rng.uniform(2, 6), L / 2 - rng.uniform(2, 6)])
        sh = hull_of([(x - 1.2, HH * 1.2, z - 0.8), (x + 1.2, HH * 1.2, z + 0.8), (x - 0.8, HH * 1.2, z + 0.6),
                      (x + rng.normal(0, 0.6), HH * 1.2 - rng.uniform(2, 5), z + rng.normal(0, 0.4))])
        flat_normals(sh)
        p["inner"].append(sh)
    return p


def hangar_gantry():
    """Catwalk round an upper deck at 5 m, reached by a stair."""
    p = {"dark": [], "deck": [], "hazard": []}
    H = 5.0
    p["deck"].append(box((4.0, 0.25, 16.0), (0.0, H, 0.0), bev=0.04))
    for z in (-7.5, -2.5, 2.5, 7.5):
        for sx in (-1.8, 1.8):
            p["dark"].append(box((0.25, H, 0.25), (sx, H / 2, z), bev=0.03))
    for sx in (-2.0, 2.0):
        p["hazard"].append(box((0.08, 0.08, 16.0), (sx, H + 1.0, 0.0), bev=0.01))
        for z in np.arange(-7.5, 7.6, 2.5):
            p["dark"].append(box((0.06, 1.0, 0.06), (sx, H + 0.5, z), bev=0.01))
    # Stair down from one end: 20 steps over 7 m.
    for k in range(20):
        y = H - (k + 1) * H / 20
        z = 8.0 + (k + 0.5) * 0.35
        p["deck"].append(box((2.2, 0.12, 0.38), (0.0, y, z), bev=0.02))
    for sx in (-1.15, 1.15):
        p["dark"].append(tube([(sx, H + 1.0, 8.0), (sx, 1.0, 15.0)], 0.05, 6))
        p["dark"].append(box((0.12, 0.3, 7.6), (sx, H / 2 - 0.1, 11.5), rotx(math.atan2(H, 7.0)), 0.02))
    return p


# ---------------------------------------------------------------- temple

def temple_gate():
    parts = {"stone": [], "crystal": [], "glow": []}
    span = 4.2
    for sx in (-1, 1):
        c = stone_column(10.0, 1.0, 10, 30 + sx, crystal=True)
        for k in c:
            for m in c[k]:
                m.transform(None, (sx * span, 0, 0))
                parts[k].append(m)
    lin = bevel_box((span * 2 + 3.0, 1.6, 2.4), 0.25)
    lin.transform(None, (0, 10.6, 0))
    lin = jitter(lin, 0.12, 0.6, None, 3.0)
    flat_normals(lin)
    parts["stone"].append(lin)
    cap = bevel_box((span * 2 + 1.6, 0.8, 2.0), 0.2)
    cap.transform(None, (0, 11.8, 0))
    parts["stone"].append(jitter(cap, 0.1, 0.8, None, 4.0))
    for k in range(5):
        g = bevel_box((0.35, 0.35, 0.06), 0.05)
        g.transform(None, (-2.0 + k, 10.6, 1.22))
        parts["glow"].append(g)
    cc = crystal_cluster(9, 0.3, 1.2, 11)
    cc.transform(None, (0, 12.1, 0))
    parts["crystal"].append(cc)
    for m in parts["stone"]:
        flat_normals(m)
    return parts


def temple_step():
    """A stepped pyramid: five square tiers, stairs up the front (+Z)."""
    parts = {"stone": [], "crystal": [], "glow": []}
    y = 0.0
    sizes = [26.0, 21.0, 16.5, 12.0, 8.0]
    for i, s in enumerate(sizes):
        h = 2.6
        t = bevel_box((s, h, s), 0.3)
        t.transform(None, (0, y + h / 2, 0))
        t = jitter(t, 0.12, 0.5, None, i * 2.0)
        flat_normals(t)
        parts["stone"].append(t)
        # Carved glowing band round each tier.
        for sx, sz, w, d in ((0, s / 2 + 0.02, s * 0.7, 0.06), (0, -s / 2 - 0.02, s * 0.7, 0.06),
                             (s / 2 + 0.02, 0, 0.06, s * 0.7), (-s / 2 - 0.02, 0, 0.06, s * 0.7)):
            g = bevel_box((w, 0.18, d), 0.02)
            g.transform(None, (sx, y + h * 0.55, sz))
            parts["glow"].append(g)
        y += h
    # Stairs: a wide flight up the front from the ground to the top.
    steps = 40
    for k in range(steps):
        sy = (k + 0.5) * y / steps
        z = sizes[0] / 2 + 3.0 - k * (sizes[0] / 2 + 3.0 - sizes[-1] / 2) / steps
        st = bevel_box((5.0, y / steps + 0.02, 0.9), 0.04)
        st.transform(None, (0, sy, z))
        flat_normals(st)
        parts["stone"].append(st)
    # Shrine on top with the crystal heart.
    sh = lathe([(0.0, 0.0), (2.6, 0.0), (2.6, 0.5), (2.0, 0.7), (0.0, 0.7)], 8, axis='y')
    outward_from(sh, lambda f: np.array([0.0, 0.35, 0.0]))
    sh.transform(None, (0, y, 0))
    flat_normals(sh)
    parts["stone"].append(sh)
    cc = crystal_cluster(12, 0.6, 2.2, 21)
    cc.transform(None, (0, y + 0.6, 0))
    parts["crystal"].append(cc)
    return parts


# ---------------------------------------------------------------- temple interior

def _wall(parts, a, b, h, thick, openings=(), seed=0.0, inner=None):
    """A stone wall from a to b (x, z) on the floor (y = 0), `h` tall.
    openings: (t, width, height) with t the opening centre in metres from a.
    inner: a point on the side the rooms are on (gets rune bands, pilasters)."""
    a = np.array([a[0], 0.0, a[1]]); b = np.array([b[0], 0.0, b[1]])
    L = float(np.linalg.norm(b - a))
    d = (b - a) / L
    yaw = math.atan2(d[0], d[2])
    R = roty(yaw)          # local +Z runs along the wall, X across it
    nrm = np.array([d[2], 0.0, -d[0]])
    if inner is not None and np.dot(np.array([inner[0], 0, inner[1]]) - a, nrm) < 0:
        nrm = -nrm
    cuts = sorted(openings)
    t0 = 0.0
    spans = []
    for (t, w, oh) in cuts:
        spans.append((t0, t - w / 2))
        t0 = t + w / 2
    spans.append((t0, L))

    def blk(t_a, t_b, y_a, y_b, out=0.0, dep=thick, key="stone", jit=0.05):
        if t_b - t_a < 0.05 or y_b - y_a < 0.05:
            return
        m = bevel_box((dep, y_b - y_a, t_b - t_a), 0.06)
        c = a + d * ((t_a + t_b) / 2) + nrm * out
        m.transform(R, (c[0], (y_a + y_b) / 2, c[2]))
        if jit > 0:
            m = jitter(m, jit, 0.7, None, seed + t_a)
        flat_normals(m)
        parts[key].append(m)

    for (s0, s1) in spans:
        blk(s0, s1, 0.0, h)
    for (t, w, oh) in cuts:
        blk(t - w / 2, t + w / 2, oh, h)
        # Door frame: heavy jambs and a carved lintel with a crystal key.
        for sgn in (-1, 1):
            blk(t + sgn * (w / 2 + 0.35) - 0.35, t + sgn * (w / 2 + 0.35) + 0.35, 0.0, oh + 0.5, 0.0, thick + 0.7)
        blk(t - w / 2 - 0.7, t + w / 2 + 0.7, oh, oh + 1.0, 0.0, thick + 0.8)
        key_c = a + d * t + nrm * (thick / 2 + 0.42)
        cc = crystal_cluster(5, 0.12, 0.45, int(seed * 10 + t))
        cc.transform(align_y(nrm * 0.6 + np.array([0, 0.8, 0])), (key_c[0], oh + 0.55, key_c[2]))
        parts["crystal"].append(cc)
    if inner is None:
        return
    # Inside face: plinth, cornice, pilasters and a glowing rune band.
    for (s0, s1) in spans:
        blk(s0, s1, 0.0, 0.6, thick / 2 + 0.15, 0.3, jit=0.03)
        blk(s0, s1, h - 0.9, h - 0.4, thick / 2 + 0.25, 0.5, jit=0.03)
        if s1 - s0 > 1.2:
            blk(s0 + 0.4, s1 - 0.4, 3.2, 3.36, thick / 2 + 0.02, 0.06, key="glow", jit=0.0)
        t = s0 + 2.5
        while t < s1 - 1.5:
            blk(t - 0.45, t + 0.45, 0.0, h - 0.4, thick / 2 + 0.3, 0.6, jit=0.04)
            t += 5.0


def _slab(parts, x0, z0, x1, z1, y, th, key="stone", seed=0.0, tiles=False):
    m = bevel_box((x1 - x0, th, z1 - z0), 0.05)
    m.transform(None, ((x0 + x1) / 2, y - th / 2, (z0 + z1) / 2))
    flat_normals(m)
    parts[key].append(m)
    if tiles:
        # Raised flagstones on top so the floor isn't one flat plane.
        r = np.random.default_rng(int(seed * 7 + 3))
        x = x0 + 0.1
        while x < x1 - 0.5:
            w = min(r.uniform(1.4, 2.6), x1 - 0.1 - x)
            z = z0 + 0.1
            while z < z1 - 0.5:
                dz = min(r.uniform(1.4, 2.6), z1 - 0.1 - z)
                t = bevel_box((w - 0.08, 0.06, dz - 0.08), 0.025)
                t.transform(None, (x + w / 2, y + 0.03 + r.uniform(-0.012, 0.012), z + dz / 2))
                flat_normals(t)
                parts["floor"].append(t)
                z += dz
            x += w


def _stairs(parts, x, z0, z1, y0, y1, width, n=None):
    """Straight stone flight along Z from (x, y0, z0) up to (x, y1, z1)."""
    n = n or max(4, int(abs(y1 - y0) / 0.3))
    for k in range(n):
        f = (k + 0.5) / n
        zz = z0 + (z1 - z0) * f
        top = y0 + (y1 - y0) * (k + 1) / n
        st = bevel_box((width, top - y0 + 0.02, abs(z1 - z0) / n + 0.02), 0.03)
        st.transform(None, (x, (top + y0) / 2, zz))
        flat_normals(st)
        parts["stone"].append(st)


def _brazier(parts, c, s=1.0):
    bowl = lathe([(0.0, 0.0), (0.35 * s, 0.0), (0.22 * s, 0.6 * s), (0.25 * s, 0.75 * s), (0.6 * s, 1.05 * s),
                  (0.7 * s, 1.2 * s), (0.55 * s, 1.2 * s), (0.0, 1.1 * s)], 10, axis='y', flat=True)
    outward_from(bowl, lambda f: np.array([0.0, f[1], 0.0]))
    bowl = jitter(bowl, 0.02, 3.0, None, c[0])
    flat_normals(bowl)
    bowl.transform(None, c)
    parts["stone"].append(bowl)
    cc = crystal_cluster(6, 0.25 * s, 0.6 * s, int(abs(c[0] * 13 + c[2] * 7)))
    cc.transform(None, (c[0], c[1] + 1.1 * s, c[2]))
    parts["crystal"].append(cc)


def _restraint(parts, c, yaw, seed):
    """An empty stone cradle with open crystal-grown cuffs: it held someone."""
    R = roty(yaw)
    def put(m, off):
        o = R @ np.array(off)
        m.transform(R, (c[0] + o[0], c[1] + o[1], c[2] + o[2]))
        flat_normals(m)
        parts["stone"].append(m)
    slab = jitter(bevel_box((1.1, 2.3, 0.35), 0.1), 0.04, 1.2, None, seed)
    slab.transform(rotx(-0.25))
    put(slab, (0.0, 1.35, 0.0))
    base = jitter(bevel_box((1.4, 0.4, 1.1), 0.08), 0.03, 1.2, None, seed + 1)
    put(base, (0.0, 0.2, 0.2))
    for (x, y) in ((-0.45, 2.2), (0.45, 2.2), (-0.25, 0.6), (0.25, 0.6)):
        cuff = lathe([(0.11, -0.06), (0.15, -0.06), (0.15, 0.06), (0.11, 0.06)], 10, axis='z', flat=True)
        outward_from(cuff, lambda f: np.array([0.0, 0.0, f[2]]))
        # Open: cut the cuff's front arc away.
        cuff = filt(cuff, lambda q: not (q[1] > 0.05))
        o = R @ rotx(-0.25) @ np.array([x, y - 1.15, 0.22])
        cuff.transform(R @ rotx(-0.25), (c[0] + o[0], c[1] + 1.35 + o[1], c[2] + o[2]))
        flat_normals(cuff)
        parts["crystal"].append(cuff)


def temple_hall():
    """The temple's inside: an entry passage, a great columned hall with an
    upper gallery, two side chambers and the sanctum. Entrance at the origin
    facing +Z; it runs back along -Z. Floor y = 0."""
    p = {"stone": [], "floor": [], "crystal": [], "glow": []}
    T = 1.2
    # Entry passage x[-4, 4], z[0, -22], 8 m high.
    _slab(p, -5.0, -22.0, 5.0, 0.6, 0.0, 1.0, seed=1, tiles=True)
    _slab(p, -5.2, -22.0, 5.2, 0.6, 9.0, 1.0)
    _wall(p, (-4.6, 0.6), (-4.6, -22.0), 8.0, T, (), 1.0, inner=(0, -10))
    _wall(p, (4.6, -22.0), (4.6, 0.6), 8.0, T, (), 2.0, inner=(0, -10))
    _wall(p, (-5.2, 0.6), (5.2, 0.6), 9.0, T, [(5.2, 5.0, 6.0)], 3.0)
    for z in (-5.0, -11.0, -17.0):
        for sx in (-1, 1):
            _brazier(p, (sx * 3.2, 0.0, z), 0.8)
    # Ceiling ribs over the passage.
    for z in np.arange(-2.0, -22.0, -3.0):
        rb = bevel_box((8.4, 0.6, 0.7), 0.1)
        rb.transform(None, (0.0, 8.0, z))
        p["stone"].append(jitter(rb, 0.04, 1.0, None, z))
    # Great hall x[-16, 16], z[-22, -54], 16 m high.
    _slab(p, -17.0, -54.6, 17.0, -22.0, 0.0, 1.0, seed=2, tiles=True)
    _slab(p, -17.2, -55.2, 17.2, -21.4, 17.0, 1.0)
    _wall(p, (-16.6, -22.0), (-16.6, -54.6), 16.0, T, [(5.5, 4.0, 5.0)], 4.0, inner=(0, -38))
    _wall(p, (16.6, -54.6), (16.6, -22.0), 16.0, T, [(32.6 - 5.5, 4.0, 5.0)], 5.0, inner=(0, -38))
    _wall(p, (-17.2, -21.4), (17.2, -21.4), 16.0, T, [(17.2, 8.0, 8.0)], 6.0, inner=(0, -38))
    _wall(p, (17.2, -55.2), (-17.2, -55.2), 16.0, T, [(17.2, 5.0, 7.0)], 7.0, inner=(0, -38))
    # Two rows of crystal-veined columns.
    for z in (-28.0, -36.0, -44.0):
        for sx in (-1, 1):
            c = stone_column(16.0, 0.95, 12, 40 + z + sx, crystal=True)
            for k in c:
                for m in c[k]:
                    m.transform(None, (sx * 8.0, 0.0, z))
                    p[k].append(m)
    # Coffered ceiling beams.
    for z in np.arange(-24.0, -54.0, -5.0):
        rb = bevel_box((33.0, 1.0, 1.0), 0.12)
        rb.transform(None, (0.0, 15.5, z))
        p["stone"].append(jitter(rb, 0.05, 0.8, None, z))
    for x in (-8.0, 0.0, 8.0):
        rb = bevel_box((1.0, 1.0, 33.0), 0.12)
        rb.transform(None, (x, 15.5, -38.0))
        p["stone"].append(jitter(rb, 0.05, 0.8, None, x))
    # Centre: a sunken ring with a crystal obelisk and glowing inlay.
    ring = lathe([(4.2, 0.0), (4.6, 0.12), (4.6, 0.3), (3.6, 0.3), (3.6, 0.0)], 24, axis='y', flat=True)
    outward_from(ring, lambda f: np.array([0.0, 0.15, 0.0]))
    flat_normals(ring)
    ring.transform(None, (0.0, 0.0, -38.0))
    p["stone"].append(ring)
    inl = lathe([(3.35, 0.0), (3.5, 0.0), (3.5, 0.04), (3.35, 0.04)], 32, axis='y', flat=True)
    outward_from(inl, lambda f: np.array([0.0, 0.02, 0.0]))
    inl.transform(None, (0.0, 0.0, -38.0))
    p["glow"].append(inl)
    ob = lathe([(1.0, 0.0), (1.0, 0.5), (0.7, 0.7), (0.6, 5.5), (0.0, 6.6)], 4, axis='y', flat=True)
    outward_from(ob, lambda f: np.array([0.0, f[1], 0.0]))
    ob = jitter(ob, 0.03, 1.0, None, 9.0)
    flat_normals(ob)
    ob.transform(roty(math.pi / 4), (0.0, 0.0, -38.0))
    p["stone"].append(ob)
    for k in range(4):
        a = k * math.pi / 2
        g = bevel_box((0.1, 3.8, 0.08), 0.02)
        g.transform(roty(a), (math.sin(a) * 0.68, 2.9, -38.0 + math.cos(a) * 0.68))
        p["glow"].append(g)
    cc = crystal_cluster(10, 0.35, 1.3, 61)
    cc.transform(None, (0.0, 6.4, -38.0))
    p["crystal"].append(cc)
    # Upper gallery along the back wall (6 m up), stairs up both side walls.
    _slab(p, -16.0, -54.6, 16.0, -49.0, 6.0, 0.8)
    for x in np.arange(-15.0, 16.0, 2.5):
        if abs(x) < 3.2:
            continue
        bal = bevel_box((0.5, 1.0, 0.5), 0.06)
        bal.transform(None, (x, 6.5, -49.2))
        p["stone"].append(jitter(bal, 0.02, 2.0, None, x))
    for sx in (-1, 1):
        rail = bevel_box((12.8, 0.25, 0.7), 0.05)
        rail.transform(None, (sx * 9.6, 7.1, -49.2))
        p["stone"].append(rail)
        _stairs(p, sx * 14.3, -30.0, -49.0, 0.0, 6.0, 3.6)
        # Stair stringer wall (solid under the flight).
        sw = bevel_box((0.6, 6.0, 19.0), 0.06)
        sw.transform(None, (sx * 12.25, 3.0, -39.5))
        sw = filt(sw, lambda q: True)
        P = np.array(sw.P)
        f = np.clip((-30.0 - P[:, 2]) / 19.0, 0, 1)
        P[:, 1] = np.where(P[:, 1] > 3.0, f * 6.0 + 0.9, P[:, 1] * 0 )
        sw.P = list(P)
        flat_normals(sw)
        p["stone"].append(sw)
    for x in (-10.0, 10.0):
        _brazier(p, (x, 6.0, -53.0), 0.9)
    for z in (-26.0, -50.0):
        for sx in (-1, 1):
            _brazier(p, (sx * 4.5, 0.0, z), 1.1)
    # Side chambers: west (the holding room), east (the star room). 12 x 12, 7 high.
    for sx, sd in ((-1, 8.0), (1, 9.0)):
        xa, xb = sorted((sx * 17.2, sx * 29.8))
        _slab(p, xa, -34.0, xb, -21.0, 0.0, 1.0, seed=sd, tiles=True)
        _slab(p, xa - 0.4, -34.4, xb + 0.4, -20.6, 8.0, 1.0)
        cx = sx * 23.5
        _wall(p, (sx * 29.8, -21.0), (sx * 29.8, -34.0), 7.0, T, (), sd, inner=(cx, -27.5))
        _wall(p, (xa - 0.6, -20.6), (xb + 0.6, -20.6), 7.0, T, (), sd + 1, inner=(cx, -27.5))
        _wall(p, (xa - 0.6, -34.4), (xb + 0.6, -34.4), 7.0, T, (), sd + 2, inner=(cx, -27.5))
    # Holding room: a row of empty restraint cradles along the back wall.
    for k, z in enumerate((-23.5, -27.5, -31.5)):
        _restraint(p, (-28.4, 0.0, z), math.pi / 2, 70 + k)
    # Star room: a hanging crystal orb under a ring of carved stars.
    orb = crystal_cluster(14, 0.5, 1.0, 81)
    orb.transform(rotx(math.pi), (23.5, 6.9, -27.5))
    p["crystal"].append(orb)
    for k in range(8):
        a = k * math.pi / 4
        st = bevel_box((0.25, 0.25, 0.06), 0.03)
        st.transform(roty(a), (23.5 + math.cos(a) * 3.2, 6.9, -27.5 + math.sin(a) * 3.2))
        p["glow"].append(st)
    _brazier(p, (23.5, 0.0, -27.5), 1.4)
    # Sanctum x[-9, 9], z[-55, -73], 12 high: a dais and the great crystal heart.
    _slab(p, -10.0, -74.0, 10.0, -55.2, 0.0, 1.0, seed=3, tiles=True)
    _slab(p, -10.4, -74.4, 10.4, -54.6, 13.0, 1.0)
    _wall(p, (-9.6, -55.8), (-9.6, -73.6), 12.0, T, (), 11.0, inner=(0, -64))
    _wall(p, (9.6, -73.6), (9.6, -55.8), 12.0, T, (), 12.0, inner=(0, -64))
    _wall(p, (-10.4, -73.6), (10.4, -73.6), 12.0, T, (), 13.0, inner=(0, -64))
    for i, (r0, h0) in enumerate(((6.0, 0.5), (4.6, 1.0), (3.2, 1.5))):
        d = lathe([(0.0, 0.0), (r0, 0.0), (r0, h0), (0.0, h0)], 8, axis='y', flat=True)
        outward_from(d, lambda f: np.array([0.0, f[1] * 0.5, 0.0]))
        d = jitter(d, 0.03, 1.0, None, 30 + i)
        flat_normals(d)
        d.transform(roty(math.pi / 8), (0.0, 0.0, -66.0))
        p["stone"].append(d)
    heart = crystal_cluster(18, 0.8, 3.0, 91)
    heart.transform(None, (0.0, 1.5, -66.0))
    p["crystal"].append(heart)
    for k in range(6):
        a = k * math.pi / 3 + 0.3
        c = stone_column(9.0, 0.6, 10, 100 + k, crystal=False, broken_at=(None if k % 2 else 6.0 + k * 0.3))
        for kk in c:
            for m in c[kk]:
                m.transform(None, (math.cos(a) * 7.4, 0.0, -66.0 + math.sin(a) * 6.2))
                p[kk].append(m)
    for m in p["stone"]:
        pass
    return p


# ---------------------------------------------------------------- swamp

def root_arch():
    p = {"bark": []}
    for k in range(3):
        a = k * 0.5 - 0.5
        pts = []
        for i in range(14):
            t = i / 13
            x = (t - 0.5) * 18.0
            y = math.sin(t * math.pi) * (6.5 - k * 1.2) - 0.8
            z = math.sin(t * 3.0 + k) * 1.2 + a * 2.0
            pts.append((x, y, z))
        r0 = 1.1 - k * 0.25
        tb = tube(pts, r0, 12)
        P = np.array(tb.P)
        tb.P = list(P)
        tb = jitter(tb, 0.18, 0.5, None, k * 3.0)
        smooth_normals(tb)
        p["bark"].append(tb)
    return p


# ---------------------------------------------------------------- build

def main(path):
    g = GLB()
    ha, hn, hm = hull_panels(2048, seed=12, base=(0.58, 0.59, 0.62))
    th = (g.image(ha, "hull_a"), g.image(hn, "hull_n"), g.image(hm, "hull_mr"))
    sa, sn, sm = carved_stone(2048, seed=9)
    ts = (g.image(sa, "stone_a"), g.image(sn, "stone_n"), g.image(sm, "stone_mr"))
    hz = g.image(hazard(), "hazard_a")

    def hullmat(name, col, metal=1.0, rough=1.0, **k):
        g.material(name, color=col, albedo_tex=th[0], normal_tex=th[1], mr_tex=th[2], metal=metal, rough=rough, **k)
    hullmat("Armour", (0.62, 0.63, 0.66, 1), 0.8)
    hullmat("DarkMetal", (0.16, 0.17, 0.19, 1), 1.0, 1.1)
    hullmat("Interior", (0.22, 0.23, 0.25, 1), 0.8, 1.1, double=True)
    hullmat("AscBlack", (0.07, 0.07, 0.08, 1), 0.6, 0.8)
    hullmat("AscRed", (0.6, 0.06, 0.05, 1), 0.4, 0.8)
    hullmat("Deck", (0.3, 0.31, 0.33, 1), 0.9, 1.0)
    g.material("Hazard", albedo_tex=hz, normal_tex=th[1], metal=0.5, rough=0.7)
    g.material("CutGlow", color=(0.3, 0.08, 0.02, 1), emissive=(1.0, 0.45, 0.1), emissive_strength=4.0)
    g.material("RedGlow", color=(0.3, 0.02, 0.02, 1), emissive=(1.0, 0.1, 0.06), emissive_strength=3.0)
    g.material("ShipGlow", color=(0.2, 0.25, 0.3, 1), emissive=(0.6, 0.85, 1.0), emissive_strength=2.4)
    g.material("Stone", albedo_tex=ts[0], normal_tex=ts[1], mr_tex=ts[2], metal=0.0, rough=1.0)
    g.material("Crystal", color=(0.35, 0.85, 1.0, 0.88), emissive=(0.2, 0.75, 1.0), emissive_strength=2.6, rough=0.08, blend=True)
    g.material("CrystalLine", color=(0.05, 0.2, 0.25, 1), emissive=(0.2, 0.75, 1.0), emissive_strength=1.8, rough=0.3)
    g.material("Ice", color=(0.7, 0.88, 1.0, 0.8), emissive=(0.35, 0.6, 0.9), emissive_strength=0.6, rough=0.05, blend=True)
    g.material("FrostRock", color=(0.55, 0.6, 0.66, 1), albedo_tex=ts[0], normal_tex=ts[1], rough=0.9)
    g.material("Stalk", color=(0.62, 0.6, 0.55, 1), albedo_tex=ts[0], normal_tex=ts[1], rough=0.85)
    g.material("Cap", color=(0.2, 0.26, 0.32, 1), albedo_tex=ts[0], normal_tex=ts[1], rough=0.6)
    g.material("ShroomGlow", color=(0.1, 0.4, 0.35, 1), emissive=(0.25, 1.0, 0.8), emissive_strength=2.8, rough=0.4)
    g.material("TempleFloor", color=(0.62, 0.6, 0.58, 1), albedo_tex=ts[0], normal_tex=ts[1], mr_tex=ts[2], metal=0.0, rough=0.8)
    g.material("Bark", color=(0.3, 0.26, 0.2, 1), albedo_tex=ts[0], normal_tex=ts[1], rough=1.0)

    def grime(scorch=0.5, dark=0.0, seed=0.0):
        def f(key, P, N):
            if key in ("glow", "hazard"):
                return None
            return vcol_grime(P, (), 3.0, dark, scorch, seed)
        return f

    def stonecol(moss=0.6, seed=0.0):
        def f(key, P, N):
            return vcol_stone(P, N, moss, seed) if key in ("stone", "floor") else None
        return f

    bm = {"hull": "Armour", "dark": "DarkMetal", "hazard": "Hazard", "glow": "CutGlow"}
    add(g, "Bulkhead", bulkhead(False), bm, grime(0.6, 0.0, 1.0), uvs=0.12)
    add(g, "BulkheadCut", bulkhead(True), bm, grime(0.6, 0.0, 1.0), uvs=0.12)
    add(g, "BulkheadSlab", bulkhead_slab(), bm, grime(0.4, 0.0, 2.0), uvs=0.12)
    add(g, "SupplyDrop", supply_drop(), {"black": "AscBlack", "red": "AscRed", "dark": "DarkMetal", "glow": "RedGlow", "hazard": "Hazard"},
        grime(0.7, 0.0, 3.0), uvs=0.3)
    g.empty("CradleAt", parent=len(g.j["nodes"]) - 1, translation=(3.6, 0.3, 0.0))
    sm_ = {"stalk": "Stalk", "cap": "Cap", "glow": "ShroomGlow"}
    add(g, "GiantShroomA", giant_shroom(9.0, 4.2, 1.2, 1), sm_, uvs=0.25)
    add(g, "GiantShroomB", giant_shroom(5.5, 2.8, 0.7, 2), sm_, uvs=0.25)
    add(g, "IceSpire", ice_spire(), {"ice": "Ice", "rock": "FrostRock"}, uvs=0.25)
    add(g, "HangarShell", hangar_shell(), {"hull": "Armour", "inner": "Interior", "dark": "DarkMetal", "glow": "ShipGlow", "hazard": "Hazard", "deck": "Deck"},
        grime(0.5, 0.05, 6.0), uvs=0.06)
    add(g, "HangarGantry", hangar_gantry(), {"dark": "DarkMetal", "deck": "Deck", "hazard": "Hazard"}, grime(0.3, 0.0, 7.0), uvs=0.2)
    rm = {"stone": "Stone", "crystal": "Crystal", "glow": "CrystalLine"}
    add(g, "TempleGate", temple_gate(), rm, stonecol(0.5, 8.0), uvs=0.25)
    add(g, "TempleStep", temple_step(), rm, stonecol(0.6, 9.0), uvs=0.25)
    add(g, "RootArch", root_arch(), {"bark": "Bark"}, uvs=0.3)
    add(g, "TempleHall", temple_hall(), {"stone": "Stone", "floor": "TempleFloor", "crystal": "Crystal", "glow": "CrystalLine"},
        stonecol(0.15, 12.0), uvs=0.25)
    g.save(path)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "../../models/canyon_kit.glb")
