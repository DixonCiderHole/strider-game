"""Damaged sci-fi outpost buildings you can walk into (sliding door is a
separate node, 'Door', so the game can open it)."""
import math, sys, numpy as np
from meshlib import *
from textures import hull_panels, grating

def slab(w, h, t, origin, axis_u, axis_v, normal, removed, cell=0.14, teeth=None, rng=None):
    """A wall/roof slab made of cells; cells where removed(u, v) is True are
    missing, and their edges get side faces so the slab shows its thickness.
    origin = corner, axis_u/v = unit directions along width/height, normal = outward."""
    o = np.asarray(origin, float); U = np.asarray(axis_u, float); V = np.asarray(axis_v, float); Nn = np.asarray(normal, float)
    nu, nv = max(1, int(round(w / cell))), max(1, int(round(h / cell)))
    du, dv = w / nu, h / nv
    keep = np.ones((nu, nv), bool)
    for i in range(nu):
        for j in range(nv):
            if removed((i + 0.5) * du, (j + 0.5) * dv): keep[i, j] = False
    m = Mesh()
    def P(u, v, s): return o + U * u + V * v + Nn * s
    for i in range(nu):
        for j in range(nv):
            if not keep[i, j]: continue
            u0, u1, v0, v1 = i * du, (i + 1) * du, j * dv, (j + 1) * dv
            # outer face (towards +normal)
            a, b, c, d = P(u0, v0, 0), P(u1, v0, 0), P(u1, v1, 0), P(u0, v1, 0)
            if np.dot(np.cross(b - a, c - a), Nn) > 0: m.quad(a, b, c, d)
            else: m.quad(a, d, c, b)
            a, b, c, d = P(u0, v0, -t), P(u1, v0, -t), P(u1, v1, -t), P(u0, v1, -t)
            if np.dot(np.cross(b - a, c - a), -Nn) > 0: m.quad(a, b, c, d)
            else: m.quad(a, d, c, b)
            # side faces where the neighbour is missing or at the slab edge
            for di, dj, uu, vv in ((-1, 0, (u0, u0), (v0, v1)), (1, 0, (u1, u1), (v0, v1)), (0, -1, (u0, u1), (v0, v0)), (0, 1, (u0, u1), (v1, v1))):
                ii, jj = i + di, j + dj
                if 0 <= ii < nu and 0 <= jj < nv and keep[ii, jj]: continue
                a = P(uu[0], vv[0], 0); b = P(uu[1], vv[1], 0); c = P(uu[1], vv[1], -t); d = P(uu[0], vv[0], -t)
                out = U * di + V * dj
                if np.dot(np.cross(b - a, c - a), out) > 0: m.quad(a, b, c, d)
                else: m.quad(a, d, c, b)
                # Torn edge: bent, jagged sheet teeth sticking into damage holes.
                inside = (0 <= ii < nu and 0 <= jj < nv)
                if teeth is not None and inside and rng is not None and rng.random() < 0.55:
                    L = rng.uniform(0.06, 0.3)
                    mid = (a + b) / 2 + out * L + Nn * rng.uniform(-0.15, 0.12) - Nn * t * 0.5
                    teeth.tri(a, b, mid); teeth.tri(a, mid, b)
    return m, keep

def ragged(cx, cy, rx, ry, seed, amp=0.35):
    def f(u, v):
        d = math.hypot((u - cx) / rx, (v - cy) / ry)
        n = noise3(np.array([[u * 1.7 + seed, v * 1.7, seed * 0.37]]))[0]
        return d + n * amp < 1.0
    return f

def rect(x0, y0, x1, y1):
    return lambda u, v: x0 <= u <= x1 and y0 <= v <= y1

def any_of(*fs):
    return lambda u, v: any(f(u, v) for f in fs)

def vcol(P, hot=None, seed=0, N=None):
    g = fbm3(P * 0.45 + seed, 3) * 0.5 + 0.5
    low = np.clip((0.8 - P[:, 1]) / 0.8, 0, 1)
    streak = noise3(P * np.array([3.0, 0.3, 3.0]) + seed) * 0.5 + 0.5
    grime = np.clip(g * 0.32 + low * 0.3 + streak * 0.12 - 0.12, 0, 0.6)
    burn = np.zeros(len(P))
    if hot is not None:
        d = np.linalg.norm(P - np.asarray(hot), axis=1)
        burn = np.clip(1.15 - d / 2.6, 0, 1) * np.clip(fbm3(P * 0.8 + 9, 3) * 0.8 + 0.8, 0, 1)
    c = (1 - grime)[:, None] * np.ones((len(P), 3)) * (1 - burn[:, None] * 0.9)
    c += np.array([0.25, 0.1, 0.03]) * (burn * (1 - burn))[:, None]
    # moss and lichen creeping up from the ground and settling on ledges
    up = np.clip(N[:, 1], 0, 1) if N is not None else 0
    mn = fbm3(P * 1.3 + seed * 3, 3) * 0.5 + 0.5
    moss = np.clip((np.clip((1.1 - P[:, 1]) / 1.1, 0, 1) * 0.8 + up * 0.7) * (mn * 1.6 - 0.35), 0, 0.85)
    c = c * (1 - moss[:, None]) + c * np.array([0.42, 0.56, 0.26]) * moss[:, None]
    return np.hstack([np.clip(c, 0, 1), np.ones((len(P), 1))]).astype(np.float32)

def building(kind="hab", seed=1):
    rng = np.random.default_rng(seed)
    L, D, H, T = (8.0, 5.2, 3.3, 0.22) if kind == "hab" else (6.0, 6.0, 3.6, 0.22)
    X0, Z0 = -L / 2, -D / 2
    LX, LZ = -X0 + 0.34, -Z0 * 0.2     # ladder on the +X side wall
    ext = Mesh(); inn = Mesh(); trim = Mesh(); dark = Mesh(); glass = Mesh(); glow = Mesh(); floor = Mesh(); red = Mesh()
    door_w, door_h = 1.5, 2.3
    door_u = L / 2 - door_w / 2      # door centred on the front (+Z) wall
    # damage: a collapsed back corner in the roof, a blast hole in one wall
    roof_hole = ragged(L * 0.78, D * 0.3, 1.6, 1.3, seed * 3.1)
    wall_hole = ragged(1.3, 1.2, 0.9, 0.8, seed * 5.3)
    win = [(0.5, 1.2, 1.9, 2.05), (L - 1.9, 1.2, L - 0.5, 2.05)] if kind == "hab" else [(0.3, 1.2, 1.3, 2.1), (L - 1.3, 1.2, L - 0.3, 2.1)]
    hot = np.array([X0 + L * 0.78, H, Z0 + D * 0.3])
    teeth = Mesh()
    # Front wall (+Z): door + windows
    f, _ = slab(L, H, T, (X0, 0, -Z0), (1, 0, 0), (0, 1, 0), (0, 0, 1),
                any_of(rect(door_u, 0, door_u + door_w, door_h), *[rect(*w) for w in win]))
    ext.extend(f)
    # Back wall (-Z): blast hole low on one side
    b, _ = slab(L, H, T, (-X0, 0, Z0), (-1, 0, 0), (0, 1, 0), (0, 0, -1), wall_hole, teeth=teeth, rng=rng)
    ext.extend(b)
    # Side walls
    s1, _ = slab(D, H, T, (X0, 0, Z0), (0, 0, 1), (0, 1, 0), (-1, 0, 0), rect(D * 0.35, 1.2, D * 0.65, 2.0))
    s2, _ = slab(D, H, T, (-X0, 0, -Z0), (0, 0, -1), (0, 1, 0), (1, 0, 0), lambda u, v: False)
    ext.extend(s1); ext.extend(s2)
    # Roof with a collapsed corner
    r, _ = slab(L, D, T, (X0, H + T, Z0), (1, 0, 0), (0, 0, 1), (0, 1, 0), roof_hole, teeth=teeth, rng=rng)
    ext.extend(r)
    dark.extend(teeth)
    # Angled armour parapet round the roof (broken where the roof caved in)
    for side in range(4):
        n_seg = 8
        for k in range(n_seg):
            f0, f1 = k / n_seg, (k + 1) / n_seg
            if side == 0:   p0, p1, o = (X0 + L * f0, -Z0), (X0 + L * f1, -Z0), (0, 1)
            elif side == 1: p0, p1, o = (-X0, -Z0 - D * f0), (-X0, -Z0 - D * f1), (1, 0)
            elif side == 2: p0, p1, o = (-X0 - L * f0, Z0), (-X0 - L * f1, Z0), (0, -1)
            else:           p0, p1, o = (X0, Z0 + D * f0), (X0, Z0 + D * f1), (-1, 0)
            mx, mz = (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2
            if roof_hole(mx - X0, mz - Z0) or roof_hole(mx - X0 - o[0] * 0.4, mz - Z0 - o[1] * 0.4): continue
            if side == 1 and abs(mz - LZ) < 0.75: continue    # gap at the top of the ladder
            y0 = H + T; ox, oz = o[0] * 0.18, o[1] * 0.18
            pts = [(p0[0] + ox, y0 - 0.25, p0[1] + oz), (p1[0] + ox, y0 - 0.25, p1[1] + oz),
                   (p0[0] + ox, y0 + 0.35, p0[1] + oz), (p1[0] + ox, y0 + 0.35, p1[1] + oz),
                   (p0[0] - ox * 1.5, y0 + 0.45, p0[1] - oz * 1.5), (p1[0] - ox * 1.5, y0 + 0.45, p1[1] - oz * 1.5),
                   (p0[0] - ox * 1.5, y0, p0[1] - oz * 1.5), (p1[0] - ox * 1.5, y0, p1[1] - oz * 1.5)]
            pad = 0.02
            seg = hull_of(pts)
            ext.extend(seg)
    # Roof edge cap / cornice and corner pillars
    for x in (X0 - 0.1, -X0 + 0.1):
        for z in (Z0 - 0.1, -Z0 + 0.1):
            trim.extend(bevel_box((0.42, H + 0.5, 0.42), 0.06, (x, (H + 0.5) / 2 - 0.1, z)))
    # Airlock vestibule round the door: angled cheeks and a canopy
    vz0, vz1 = -Z0, -Z0 + 0.9
    dx0, dx1 = X0 + door_u - 0.35, X0 + door_u + door_w + 0.35
    for xx, sgn in ((dx0, -1), (dx1, 1)):
        ext.extend(hull_of([(xx, 0, vz0), (xx + sgn * 0.35, 0, vz0), (xx, 0, vz1), (xx + sgn * 0.12, 0, vz1),
                            (xx, door_h + 0.55, vz0), (xx + sgn * 0.35, door_h + 0.55, vz0), (xx, door_h + 0.35, vz1), (xx + sgn * 0.12, door_h + 0.35, vz1)]))
    ext.extend(hull_of([(dx0 - 0.4, door_h + 0.35, vz0), (dx1 + 0.4, door_h + 0.35, vz0), (dx0 - 0.3, door_h + 0.35, vz1 + 0.15), (dx1 + 0.3, door_h + 0.35, vz1 + 0.15),
                        (dx0 - 0.4, door_h + 0.7, vz0), (dx1 + 0.4, door_h + 0.7, vz0), (dx0 - 0.3, door_h + 0.5, vz1 + 0.15), (dx1 + 0.3, door_h + 0.5, vz1 + 0.15)]))
    glow.extend(bevel_box((dx1 - dx0, 0.04, 0.06), 0.01, ((dx0 + dx1) / 2, door_h + 0.33, vz1 + 0.05)))
    # Base skirt
    dark.extend(bevel_box((L + 0.2, 0.35, 0.16), 0.04, (0, 0.12, Z0 - 0.08)))
    # front run stops at the airlock cheeks so nothing sits across the doorway
    dl, dr_ = X0 + door_u - 0.75, X0 + door_u + door_w + 0.75
    dark.extend(bevel_box((dl - (X0 - 0.1), 0.35, 0.16), 0.04, ((X0 - 0.1 + dl) / 2, 0.12, -Z0 + 0.08)))
    dark.extend(bevel_box((-X0 + 0.1 - dr_, 0.35, 0.16), 0.04, ((dr_ - X0 + 0.1) / 2, 0.12, -Z0 + 0.08)))
    for x in (X0 - 0.08, -X0 + 0.08):
        dark.extend(bevel_box((0.16, 0.35, D + 0.2), 0.04, (x, 0.12, 0)))
    # Door frame: chunky beveled frame with hazard trim and a glowing panel
    fz = -Z0 + 0.06
    trim.extend(bevel_box((0.3, door_h + 0.3, 0.42), 0.06, (X0 + door_u - 0.12, (door_h + 0.3) / 2, fz)))
    trim.extend(bevel_box((0.3, door_h + 0.3, 0.42), 0.06, (X0 + door_u + door_w + 0.12, (door_h + 0.3) / 2, fz)))
    trim.extend(bevel_box((door_w + 0.6, 0.32, 0.42), 0.06, (X0 + door_u + door_w / 2, door_h + 0.14, fz)))
    red.extend(bevel_box((door_w + 0.5, 0.06, 0.05), 0.01, (X0 + door_u + door_w / 2, door_h + 0.06, fz + 0.22)))
    dark.extend(bevel_box((0.22, 0.32, 0.06), 0.02, (X0 + door_u + door_w + 0.5, 1.25, fz + 0.12)))
    glow.extend(bevel_box((0.14, 0.12, 0.03), 0.01, (X0 + door_u + door_w + 0.5, 1.3, fz + 0.16)))
    # Window frames and (partly broken) glass
    for k, w in enumerate(win):
        x0, y0, x1, y1 = w
        cx = X0 + (x0 + x1) / 2; cy = (y0 + y1) / 2
        trim.extend(bevel_box((x1 - x0 + 0.16, 0.12, 0.3), 0.03, (cx, y0 - 0.04, -Z0)))
        trim.extend(bevel_box((x1 - x0 + 0.16, 0.12, 0.3), 0.03, (cx, y1 + 0.04, -Z0)))
        if k == 0:
            glass.quad((X0 + x0, y0, -Z0 - 0.1), (X0 + x1, y0, -Z0 - 0.1), (X0 + x1, y1, -Z0 - 0.1), (X0 + x0, y1, -Z0 - 0.1))
        else:   # shattered: a few shards left in the frame
            for s in range(4):
                u = rng.uniform(x0, x1); v = rng.uniform(y0, y1)
                glass.tri((X0 + u, v, -Z0 - 0.1), (X0 + u + rng.uniform(0.2, 0.5), v + rng.uniform(-0.2, 0.2), -Z0 - 0.1),
                          (X0 + u + rng.uniform(-0.1, 0.2), v + rng.uniform(0.2, 0.4), -Z0 - 0.1))
    # Side window glass
    glass.quad((X0 - 0.1, 1.2, Z0 + D * 0.35), (X0 - 0.1, 1.2, Z0 + D * 0.65), (X0 - 0.1, 2.0, Z0 + D * 0.65), (X0 - 0.1, 2.0, Z0 + D * 0.35))
    # Exterior greebles: conduits, vent boxes, roof units, ladder, antenna
    for k in range(3):
        y = 0.6 + k * 0.18
        c = lathe([(0.05, 0), (0.05, D)], 8); c.transform(None, (-X0 + 0.16, y, Z0)); dark.extend(c)
    for k in range(2):
        dark.extend(bevel_box((0.6, 0.5, 0.25), 0.05, (X0 + 1.3 + k * 4.4 * (L / 8), 2.75, Z0 - 0.2)))
    for k in range(2):
        u = bevel_box((1.3, 0.55, 0.9), 0.08, (X0 + 1.4 + k * 1.7, H + T + 0.3, Z0 + 1.2)); ext.extend(u)
        fan = lathe([(0.0, 0.0), (0.36, 0.0)], 16, axis='y'); fan.transform(None, (X0 + 1.4 + k * 1.7, H + T + 0.58, Z0 + 1.2)); dark.extend(fan)
    an = lathe([(0.05, 0), (0.04, 2.4)], 8, axis='y'); an.transform(None, (X0 + 0.6, H + T, -Z0 - 0.6)); dark.extend(an)
    red.extend(bevel_box((0.12, 0.12, 0.12), 0.04, (X0 + 0.6, H + T + 2.45, -Z0 - 0.6)))
    # Ladder (own node, local to its foot): round rails with grab hoops over the roof edge
    ladder = Mesh(); ladder_y = Mesh()
    top = H + T + 1.05
    for z in (-0.3, 0.3):
        ladder.extend(tube([(0, 0.0, z), (0, top - 0.25, z), (-0.06, top - 0.05, z), (-0.3, top, z), (-0.55, top - 0.15, z), (-0.62, H + T + 0.02, z)], 0.03, 10))
        for y in (0.9, 2.2):   # wall brackets
            ladder.extend(bevel_box((0.3, 0.05, 0.05), 0.01, (-0.17, y, z)))
    for k in range(int((H + T) / 0.3)):
        ladder.extend(cyl(0.022, 0.6, 10, (0, 0.3 + k * 0.3, 0), axis='z'))
    for k in range(int((H + T) / 0.3)):
        ladder_y.extend(bevel_box((0.012, 0.05, 0.5), 0.004, (0.026, 0.3 + k * 0.3 + 0.018, 0)))  # worn hazard grip strips
    # Stencilled red band along the front
    red.extend(bevel_box((L * 0.3, 0.12, 0.03), 0.01, (X0 + L * 0.78, 2.6, -Z0 + 0.02)))
    # ---------------- interior
    fl = bevel_box((L - 2 * T, 0.06, D - 2 * T), 0.0, (0, 0.03, 0)); floor.extend(fl)
    ceil = Mesh()
    for i in range(int(L / 1.0)):
        for j in range(int(D / 1.0)):
            u, v = i + 0.5, j + 0.5
            if roof_hole(u, v) or roof_hole(u + 0.3, v) or roof_hole(u, v + 0.3): continue
            ceil.extend(bevel_box((0.96, 0.06, 0.96), 0.02, (X0 + u, H - 0.05, Z0 + v)))
    inn.extend(ceil)
    for k in range(2):   # ceiling light strips (one dead)
        strip = bevel_box((L * 0.5, 0.05, 0.14), 0.02, (-L * 0.15, H - 0.12, Z0 + D * (0.3 + 0.4 * k)))
        (glow if k == 0 else dark).extend(strip)
    # Inner wall lining panels (rows of inset plates)
    for z in (Z0 + T + 0.03,):
        for i in range(int(L / 1.2)):
            x = X0 + 0.7 + i * 1.2
            if not (wall_hole(-X0 - x + L / 2 - L / 2 + (L / 2 - (x - X0) + L / 2) % L * 0, 1.2)) and abs(x - (X0 + 1.3 + 0.0)) > 1.2:
                inn.extend(bevel_box((1.1, 2.2, 0.05), 0.02, (x, 1.3, z)))
    # Props
    if kind == "hab":
        for k in range(2):   # bunks
            bx = X0 + 0.9 + k * 1.9
            inn.extend(bevel_box((1.0, 0.08, 2.1), 0.02, (bx, 0.55, Z0 + 1.3)))
            inn.extend(bevel_box((1.0, 0.08, 2.1), 0.02, (bx, 1.55, Z0 + 1.3)))
            for dx in (-0.47, 0.47):
                for dz in (-1.0, 1.0):
                    dark.extend(bevel_box((0.06, 1.9, 0.06), 0.01, (bx + dx, 0.95, Z0 + 1.3 + dz)))
            trim.extend(bevel_box((0.9, 0.14, 1.95), 0.05, (bx, 0.66, Z0 + 1.3)))
        for k in range(4):   # lockers along the side wall
            dark.extend(bevel_box((0.5, 2.0, 0.55), 0.03, (-X0 - T - 0.3, 1.0, Z0 + 0.6 + k * 0.56)))
            inn.extend(bevel_box((0.02, 1.7, 0.4), 0.005, (-X0 - T - 0.56, 1.05, Z0 + 0.6 + k * 0.56)))
        # console with screens
        dark.extend(bevel_box((1.8, 0.9, 0.7), 0.05, (0.6, 0.45, Z0 + T + 0.4)))
        dark.extend(bevel_box((1.8, 0.6, 0.12), 0.03, (0.6, 1.2, Z0 + T + 0.12)))
        glow.extend(bevel_box((0.7, 0.4, 0.02), 0.01, (0.25, 1.2, Z0 + T + 0.19)))
        glow.extend(bevel_box((0.7, 0.4, 0.02), 0.01, (1.0, 1.2, Z0 + T + 0.19)))
        # table + overturned chair
        inn.extend(bevel_box((1.2, 0.06, 0.8), 0.02, (-0.3, 0.78, 0.2)))
        dark.extend(bevel_box((0.08, 0.76, 0.08), 0.01, (-0.3, 0.38, 0.2)))
        ch = bevel_box((0.45, 0.06, 0.45), 0.02); ch.transform(rotz(1.4) @ roty(0.4), (0.6, 0.25, 0.6)); dark.extend(ch)
    else:
        for k in range(3):   # lab benches with screens
            x = X0 + 1.2 + k * 1.8
            dark.extend(bevel_box((1.4, 0.9, 0.7), 0.04, (x, 0.45, Z0 + T + 0.45)))
            glow.extend(bevel_box((0.6, 0.35, 0.02), 0.01, (x, 1.25, Z0 + T + 0.2)))
            dark.extend(bevel_box((0.7, 0.45, 0.06), 0.02, (x, 1.25, Z0 + T + 0.16)))
        for k in range(3):   # server racks
            dark.extend(bevel_box((0.6, 2.1, 0.8), 0.03, (-X0 - T - 0.4, 1.05, -1.2 + k * 0.85)))
            for j in range(6):
                glow.extend(bevel_box((0.02, 0.03, 0.5), 0.005, (-X0 - T - 0.71, 0.4 + j * 0.28, -1.2 + k * 0.85)))
        dark.extend(lathe([(0.0, 0), (0.55, 0), (0.55, 1.1), (0.4, 1.3), (0.0, 1.3)], 20, axis='y').transform(None, (0.0, 0.0, 0.2)))   # specimen tank base
        glass.extend(lathe([(0.45, 1.3), (0.45, 2.7)], 20, axis='y').transform(None, (0.0, 0.0, 0.2)))
    # Rubble under the roof hole and a fallen ceiling panel
    hx, hz = X0 + L * 0.78, Z0 + D * 0.3
    for k in range(14):
        rb = bevel_box((rng.uniform(0.2, 0.7), rng.uniform(0.1, 0.35), rng.uniform(0.2, 0.6)), 0.04)
        rb.transform(rotx(rng.uniform(-0.6, 0.6)) @ roty(rng.uniform(0, 6.3)) @ rotz(rng.uniform(-0.6, 0.6)),
                     (hx + rng.normal(0, 0.7), 0.12, hz + rng.normal(0, 0.5)))
        (ext if k % 2 else dark).extend(rb)
    fp = bevel_box((1.9, 0.08, 1.4), 0.03); fp.transform(rotz(0.45) @ roty(0.3), (hx - 0.4, 0.7, hz + 0.2)); ext.extend(fp)
    # cables hanging through the hole
    for k in range(4):
        c = lathe([(0.025, 0), (0.025, 1.4 + k * 0.3)], 6, axis='y'); c.transform(rotz(rng.uniform(-0.2, 0.2)), (hx - 0.6 + k * 0.35, H - 1.4 - k * 0.3, hz + 0.6)); dark.extend(c)
    # ---------------- sliding door (separate node, slides along +X into the wall)
    door = Mesh()
    door.extend(bevel_box((door_w, door_h, 0.1), 0.03, (0, door_h / 2, 0)))
    door_dark = Mesh()
    for k in range(3):
        door_dark.extend(bevel_box((door_w - 0.25, 0.05, 0.12), 0.01, (0, 0.6 + k * 0.6, 0)))
    door_red = bevel_box((0.1, door_h * 0.6, 0.12), 0.01, (door_w / 2 - 0.15, door_h / 2, 0))
    door_pos = (X0 + door_u + door_w / 2, 0.0, -Z0 - T / 2)
    return dict(ext=ext, inn=inn, trim=trim, dark=dark, glass=glass, glow=glow, floor=floor, red=red,
                door=(door, door_dark, door_red, door_pos), hot=hot, size=(L, D, H),
                ladder=(ladder, ladder_y, (LX, 0.0, LZ)), wall_hole=wall_hole, roof_hole=roof_hole,
                door_u=door_u, door_w=door_w, door_h=door_h, win=win, T=T)

# ---------------------------------------------------------------- nature reclaiming it
def _frame(L, D):
    """Exterior walls as (origin at bottom-left seen from outside, u axis, outward normal, width)."""
    X0, Z0 = -L / 2, -D / 2
    return {
        "front": (np.array([X0, 0, -Z0]), np.array([1.0, 0, 0]), np.array([0, 0, 1.0]), L),
        "back": (np.array([-X0, 0, Z0]), np.array([-1.0, 0, 0]), np.array([0, 0, -1.0]), L),
        "left": (np.array([X0, 0, Z0]), np.array([0, 0, 1.0]), np.array([-1.0, 0, 0]), D),
        "right": (np.array([-X0, 0, -Z0]), np.array([0, 0, -1.0]), np.array([1.0, 0, 0]), D),
    }

def _strip(m, path, width, out, taper_end, v_scale):
    """Ribbon of ivy along `path` (list of 3D points), lying flat on a wall with normal `out`."""
    v = 0.0
    for i in range(len(path) - 1):
        a, b = np.asarray(path[i]), np.asarray(path[i + 1])
        t = b - a; seg = np.linalg.norm(t)
        if seg < 1e-6: continue
        side = np.cross(out, t / seg)
        f0 = 1 - (i / (len(path) - 1)) ** 2 if taper_end else 1.0
        f1 = 1 - ((i + 1) / (len(path) - 1)) ** 2 if taper_end else 1.0
        f0, f1 = max(f0, 0.15), max(f1, 0.15)
        w0, w1 = width * f0 / 2, width * f1 / 2
        v1 = v + seg / v_scale
        m.quad_uv(a - side * w0, a + side * w0, b + side * w1, b - side * w1,
                  (0.5 - f0 / 2, v), (0.5 + f0 / 2, v), (0.5 + f1 / 2, v1), (0.5 - f1 / 2, v1), n=out)
        v = v1

def _card(m, centre, size, normal, up, u0=0.0, u1=1.0, v0=0.0, v1=1.0):
    c = np.asarray(centre, float); n = np.asarray(normal, float); up = np.asarray(up, float)
    r = np.cross(up, n); r /= np.linalg.norm(r)
    up = np.cross(n, r)
    w, h = size
    m.quad_uv(c - r * w / 2 - up * h / 2, c + r * w / 2 - up * h / 2, c + r * w / 2 + up * h / 2, c - r * w / 2 + up * h / 2,
              (u0, v1), (u1, v1), (u1, v0), (u0, v0), n=n)

def overgrowth(p, kind, seed):
    rng = np.random.default_rng(seed + 100)
    L, D, H = p["size"]; T = p["T"]
    X0, Z0 = -L / 2, -D / 2
    ivy_m, grass_m, moss_m, crack_m = Mesh(), Mesh(), Mesh(), Mesh()
    du, dw, dh = p["door_u"], p["door_w"], p["door_h"]
    def opening(wall, u, v, pad=0.15):
        if wall == "front":
            if du - pad < u < du + dw + pad and v < dh + pad: return True
            for (x0, y0, x1, y1) in p["win"]:
                if x0 - pad < u < x1 + pad and y0 - pad < v < y1 + pad: return True
        if wall == "back" and p["wall_hole"](u, v): return True
        if wall == "left" and D * 0.35 - pad < u < D * 0.65 + pad and 1.2 - pad < v < 2.0 + pad: return True
        if wall == "right" and abs(u - (D / 2 - D * 0.1)) < 0.6: return True     # ladder
        return False
    walls = _frame(L, D)
    # Climbing ivy: from the ground up the walls, wandering sideways.
    for name, (o, U, N, W) in walls.items():
        n_vines = {"front": 4, "back": 5, "left": 4, "right": 3}[name]
        for k in range(n_vines):
            u = rng.uniform(0.3, W - 0.3)
            top = rng.uniform(1.4, H + 0.3)
            pts = []; v = -0.05
            while v < top:
                if not opening(name, u, v):
                    pts.append(o + U * u + np.array([0, v, 0]) + N * (0.035 + 0.01 * rng.random()))
                elif len(pts) > 1:
                    _strip(ivy_m, pts, rng.uniform(0.55, 0.95), N, False, 1.3); pts = []
                v += 0.25; u = np.clip(u + rng.normal(0, 0.12), 0.2, W - 0.2)
            if len(pts) > 1: _strip(ivy_m, pts, rng.uniform(0.55, 0.95), N, True, 1.3)
        # Vines spilling down from the roof edge.
        for k in range(rng.integers(2, 5)):
            u = rng.uniform(0.4, W - 0.4)
            if opening(name, u, H - 0.5): continue
            length = rng.uniform(0.6, 2.0)
            pts = []
            for j in range(9):
                v = H + 0.4 - length * j / 8
                if opening(name, u, v): break
                pts.append(o + U * (u + rng.normal(0, 0.03)) + np.array([0, v, 0]) + N * 0.2 * (1 - j / 8) + N * 0.05)
            if len(pts) > 1: _strip(ivy_m, pts, rng.uniform(0.35, 0.6), N, True, 1.0)
        # Low moss stains and cracks on the outside.
        for k in range(5):
            u, v = rng.uniform(0.3, W - 0.3), rng.uniform(0.05, 0.6)
            if opening(name, u, v + 0.2): continue
            s = rng.uniform(0.4, 0.9)
            _card(moss_m, o + U * u + np.array([0, v, 0]) + N * 0.025, (s * 1.4, s), N, (0, 1, 0))
        for k in range(3):
            u, v = rng.uniform(0.6, W - 0.6), rng.uniform(0.6, H - 0.4)
            if opening(name, u, v, 0.6): continue
            s = rng.uniform(0.8, 1.6)
            _card(crack_m, o + U * u + np.array([0, v, 0]) + N * 0.02, (s, s), N, (np.sin(rng.uniform(0, 6.3)), 1, 0) if abs(N[1]) < 0.5 else (0, 0, 1))
    # Interior cracks (inside face of the walls).
    for name, (o, U, N, W) in walls.items():
        for k in range(2):
            u, v = rng.uniform(0.7, W - 0.7), rng.uniform(0.8, H - 0.5)
            if opening(name, u, v, 0.6): continue
            s = rng.uniform(0.7, 1.3)
            _card(crack_m, o + U * u + np.array([0, v, 0]) - N * (T + 0.07), (s, s), -N, (rng.uniform(-0.5, 0.5), 1, 0))
    # Grass round the base (thinner in front of the door) and in the rubble under the holes.
    def tuft(c, h):
        a0 = rng.uniform(0, np.pi)
        for k in range(3):
            a = a0 + k * np.pi / 3
            n = np.array([np.cos(a), 0, np.sin(a)])
            _card(grass_m, np.asarray(c) + np.array([0, h / 2 - 0.03, 0]), (h * 1.1, h), n, (0, 1, 0))
    for k in range(70):
        side = rng.integers(4)
        d = rng.uniform(0.15, 1.1) ** 1.5
        if side == 0: c = (rng.uniform(X0 - 0.5, -X0 + 0.5), 0, -Z0 + 0.2 + d)
        elif side == 1: c = (rng.uniform(X0 - 0.5, -X0 + 0.5), 0, Z0 - 0.2 - d)
        elif side == 2: c = (X0 - 0.2 - d, 0, rng.uniform(Z0 - 0.5, -Z0 + 0.5))
        else: c = (-X0 + 0.2 + d, 0, rng.uniform(Z0 - 0.5, -Z0 + 0.5))
        if side == 0 and abs(c[0] - (X0 + du + dw / 2)) < 1.3: continue
        if side == 3 and abs(c[2] - (-Z0 * 0.2)) < 0.6: continue
        tuft(c, rng.uniform(0.25, 0.65))
    hx, hz = X0 + L * 0.78, Z0 + D * 0.3
    for k in range(16):
        tuft((hx + rng.normal(0, 0.7), 0.05, hz + rng.normal(0, 0.5)), rng.uniform(0.2, 0.5))
        _card(moss_m, (hx + rng.normal(0, 0.8), 0.075 + 0.002 * k, hz + rng.normal(0, 0.6)), (rng.uniform(0.4, 0.9),) * 2, (0, 1, 0), (np.cos(k), 0, np.sin(k)))
    # Vines dangling through the roof hole.
    for k in range(6):
        x, z = hx + rng.normal(0, 0.6), hz + rng.normal(0, 0.45)
        if not p["roof_hole"](x - X0, z - Z0): continue
        pts = [(x + rng.normal(0, 0.03), H + T + 0.1 - j * 0.3, z) for j in range(int(rng.uniform(3, 8)))]
        _strip(ivy_m, pts, rng.uniform(0.3, 0.5), np.array([np.cos(k), 0, np.sin(k)]), True, 1.0)
        _strip(ivy_m, pts, rng.uniform(0.3, 0.5), np.array([np.sin(k), 0, -np.cos(k)]), True, 1.0)
    # Moss and grass taking over the roof.
    for k in range(40):
        x, z = rng.uniform(X0 + 0.3, -X0 - 0.3), rng.uniform(Z0 + 0.3, -Z0 - 0.3)
        if p["roof_hole"](x - X0, z - Z0) or p["roof_hole"](x - X0 + 0.4, z - Z0): continue
        edge = min(x - X0, -X0 - x, z - Z0, -Z0 - z)
        if rng.random() < 0.6 or edge < 0.6:
            s = rng.uniform(0.5, 1.4)
            _card(moss_m, (x, H + T + 0.012 + 0.001 * k, z), (s, s), (0, 1, 0), (np.cos(k * 2.1), 0, np.sin(k * 2.1)))
        if edge < 0.7 and rng.random() < 0.7:
            tuft((x, H + T, z), rng.uniform(0.2, 0.45))
    return ivy_m, grass_m, moss_m, crack_m

def export(kind, seed, path):
    p = building(kind, seed)
    g = GLB()
    a, n, mr = hull_panels(1024, seed=seed + 20, base=(0.66, 0.66, 0.64), plate=(256, 192))
    ta, tn, tm = g.image(a, "wall_a"), g.image(n, "wall_n"), g.image(mr, "wall_mr")
    a2, n2, mr2 = hull_panels(1024, seed=seed + 40, base=(0.36, 0.38, 0.4), plate=(128, 256))
    ia, inn_, imr = g.image(a2, "int_a"), g.image(n2, "int_n"), g.image(mr2, "int_mr")
    ga, gn, gm = grating(1024)
    fa, fn, fm = g.image(ga, "floor_a"), g.image(gn, "floor_n"), g.image(gm, "floor_mr")
    g.material("Wall", albedo_tex=ta, normal_tex=tn, mr_tex=tm, metal=0.6, rough=1.0)
    g.material("Interior", albedo_tex=ia, normal_tex=inn_, mr_tex=imr, metal=0.7, rough=1.0)
    g.material("Trim", color=(0.85, 0.62, 0.18, 1), albedo_tex=ta, normal_tex=tn, mr_tex=tm, metal=0.4, rough=0.9)
    g.material("DarkMetal", color=(0.2, 0.21, 0.23, 1), albedo_tex=ta, normal_tex=tn, mr_tex=tm, metal=1.0, rough=0.9)
    g.material("Floor", albedo_tex=fa, normal_tex=fn, mr_tex=fm, metal=1.0, rough=1.0)
    g.material("Glass", color=(0.15, 0.3, 0.38, 0.45), metal=0.1, rough=0.05, blend=True, double=True)
    g.material("Glow", color=(0.1, 0.3, 0.35, 1), emissive=(0.35, 0.85, 1.0), emissive_strength=3.0)
    g.material("Red", color=(0.55, 0.06, 0.04, 1), emissive=(1.0, 0.12, 0.05), emissive_strength=1.5)
    hot = p["hot"]
    parts = []
    for key, mat, cv, uvs in [("ext", "Wall", True, 0.5), ("inn", "Interior", True, 0.6), ("trim", "Trim", True, 0.6), ("dark", "DarkMetal", True, 0.6),
                              ("floor", "Floor", True, 0.5), ("glass", "Glass", False, 1), ("glow", "Glow", False, 1), ("red", "Red", False, 1)]:
        m = p[key]; P, N = m.arrays()
        parts.append((m, mat, vcol(P, hot, seed, N) if cv else None, uvs))
    g.mesh_node("Shell", parts)
    # Ladder: separate, non-solid node the game turns into a climbable zone.
    lad, lad_y, lpos = p["ladder"]
    P, N = lad.arrays()
    g.mesh_node("Ladder", [(lad, "DarkMetal", vcol(P + np.asarray(lpos), None, seed, N), 0.6), (lad_y, "Trim", None, 0.6)], translation=lpos)
    # Overgrowth + cracks: cut-out cards, no collision.
    from textures import ivy, grass_card, moss_patch, crack_decal
    ia_, in_ = ivy(seed=seed + 3); gr_ = grass_card(seed=seed + 4); ma_, mn_ = moss_patch(seed=seed + 5); ca_, cn_ = crack_decal(seed=seed + 6)
    g.material("Ivy", albedo_tex=g.image(ia_, "ivy_a"), normal_tex=g.image(in_, "ivy_n"), rough=0.75, mask=True, cutoff=0.45, double=True)
    g.material("Grass", albedo_tex=g.image(gr_, "grass_a"), rough=0.85, mask=True, cutoff=0.4, double=True)
    g.material("Moss", albedo_tex=g.image(ma_, "moss_a"), normal_tex=g.image(mn_, "moss_n"), rough=0.95, mask=True, cutoff=0.5)
    g.material("Crack", albedo_tex=g.image(ca_, "crack_a"), normal_tex=g.image(cn_, "crack_n"), rough=0.9, mask=True, cutoff=0.5)
    iv, gr, mo, cr = overgrowth(p, kind, seed)
    g.mesh_node("Overgrowth", [(iv, "Ivy", None, 1), (gr, "Grass", None, 1), (mo, "Moss", None, 1), (cr, "Crack", None, 1)])
    door, dd, dr, pos = p["door"]
    door.transform(None, -np.array([0, 0, 0])); 
    P, _ = door.arrays()
    g.mesh_node("Door", [(door, "Wall", vcol(P + pos, None, seed), 0.6), (dd, "DarkMetal", None, 0.6), (dr, "Red", None, 1)], translation=pos)
    g.save(path)
    print(kind, "ok", p["size"])

if __name__ == "__main__":
    export("hab", 1, "outpost_hab.glb")
    export("lab", 2, "outpost_lab.glb")
