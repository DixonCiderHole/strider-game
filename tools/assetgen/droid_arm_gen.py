"""Strider droid arm attachments (models/droid_arms.glb).

The Strider's right arm socket takes tool arms. Each attachment is built
from the shoulder pivot (origin), pointing forward along +Z with the tool
end a little below the shoulder, in metres for a 1.5 m tall droid.

Nodes:
  SawArm        socket collar, twin hydraulic struts, motor housing and
                blade guard (the plasma saw attachment)
    SawBlade    the diamond-tooth blade on its own node (child of SawArm,
                at the blade centre) so it can spin about its local X axis

python3 droid_arm_gen.py ../../models/droid_arms.glb
"""
import sys, math, numpy as np
from meshlib import *
from textures import hull_panels
from reach_gen import add, smooth_normals, flat_normals, outward_from

BLADE_AT = np.array([0.0, -0.26, 0.86])   # blade centre, from the shoulder
BLADE_R = 0.3


def solid_x(profile, seg=28, smooth=True):
    """Lathe around the X axis (for the socket and hubs, which face sideways)."""
    m = lathe(profile, seg, axis='x', flat=not smooth)
    outward_from(m, lambda f: np.zeros(3))
    if smooth:
        smooth_normals(m)
    else:
        flat_normals(m)
    return m


def strut(a, b, r):
    m = tube([a, b], r, 10)
    smooth_normals(m)
    return m


def saw_arm():
    p = {"plate": [], "dark": [], "glow": [], "chrome": []}
    # Socket collar at the shoulder: a ribbed ring that locks into the droid.
    # (lathe profiles are (radius, position along X))
    p["dark"].append(solid_x([(0.0, -0.09), (0.13, -0.09), (0.15, -0.06), (0.15, 0.06), (0.13, 0.09), (0.0, 0.09)], 32, smooth=False))
    for x in (-0.05, 0.05):
        p["chrome"].append(solid_x([(0.0, x - 0.008), (0.158, x - 0.008), (0.158, x + 0.008), (0.0, x + 0.008)], 32, smooth=False))
    p["glow"].append(solid_x([(0.0, -0.012), (0.153, -0.012), (0.153, 0.012), (0.0, 0.012)], 32, smooth=False))
    # Upper arm: an armoured beam from the collar down to the motor.
    secs = []
    for i in range(7):
        t = i / 6
        c = np.array([0.0, -0.02 - 0.16 * t, 0.12 + 0.48 * t])
        w = 0.085 - 0.015 * t
        h = 0.11 - 0.02 * t
        secs.append(np.array([c + [-w, -h, 0], c + [w, -h, 0], c + [w * 1.1, h * 0.6, 0], c + [0, h, 0], c + [-w * 1.1, h * 0.6, 0]]))
    beam = loft(secs, closed=True)
    def beam_c(f):
        t = min(1.0, max(0.0, (f[2] - 0.12) / 0.48))
        return np.array([0.0, -0.02 - 0.16 * t, 0.12 + 0.48 * t])
    outward_from(beam, beam_c)
    flat_normals(beam)
    p["plate"].append(beam)
    # Twin hydraulic struts under it, chrome rods into dark sleeves.
    for sx in (-0.06, 0.06):
        p["dark"].append(strut(np.array([sx, -0.1, 0.12]), np.array([sx, -0.2, 0.42]), 0.022))
        p["chrome"].append(strut(np.array([sx, -0.2, 0.42]), np.array([sx, -0.24, 0.66]), 0.013))
    # Motor housing at the blade hub, with cooling fins.
    hub = BLADE_AT
    house = bevel_box((0.16, 0.2, 0.26), 0.03)
    house.transform(None, hub + np.array([0.0, 0.06, -0.12]))
    flat_normals(house)
    p["plate"].append(house)
    for k in range(5):
        fin = bevel_box((0.18, 0.012, 0.18), 0.004)
        fin.transform(None, hub + np.array([0.0, 0.0 + k * 0.03, -0.14]))
        flat_normals(fin)
        p["dark"].append(fin)
    # Blade guard: a curved shell over the back and top of the blade.
    gs = []
    for i in range(13):
        a = math.radians(-40 + i * 15)
        r0, r1 = BLADE_R + 0.03, BLADE_R + 0.06
        y, z = math.cos(a), -math.sin(a)
        gs.append(np.array([hub + [-0.045, y * r0, z * r0], hub + [0.045, y * r0, z * r0],
                            hub + [0.045, y * r1, z * r1], hub + [-0.045, y * r1, z * r1]]))
    guard = loft(gs, closed=True)
    outward_from(guard, lambda f: hub + (f - hub) * np.array([0.0, 1.0, 1.0]) / max(1e-6, np.linalg.norm((f - hub)[1:])) * (BLADE_R + 0.045))
    flat_normals(guard)
    p["plate"].append(guard)
    # Heat strip along the guard's lip.
    p["glow"].append(tube([hub + [0.05, math.cos(math.radians(a2)) * (BLADE_R + 0.045), -math.sin(math.radians(a2)) * (BLADE_R + 0.045)]
                           for a2 in range(-40, 141, 10)], 0.006, 6))
    return p


def saw_blade():
    """The blade, centred on the origin, in the YZ plane (spins about X)."""
    p = {"chrome": [], "dark": [], "glow": []}
    teeth = 28
    pts = []
    for k in range(teeth * 2):
        a = 2 * math.pi * k / (teeth * 2)
        r = BLADE_R if k % 2 == 0 else BLADE_R - 0.035
        a2 = a + (0.04 if k % 2 == 0 else 0.0)
        pts.append((r * math.cos(a2), r * math.sin(a2)))
    th = 0.012
    disc = Mesh()
    for side in (-1, 1):
        x = side * th / 2
        for k in range(len(pts)):
            a, b = pts[k], pts[(k + 1) % len(pts)]
            if side > 0:
                disc.tri((x, 0, 0), (x, a[0], a[1]), (x, b[0], b[1]))
            else:
                disc.tri((x, 0, 0), (x, b[0], b[1]), (x, a[0], a[1]))
    for k in range(len(pts)):
        a, b = pts[k], pts[(k + 1) % len(pts)]
        disc.quad((-th / 2, a[0], a[1]), (-th / 2, b[0], b[1]), (th / 2, b[0], b[1]), (th / 2, a[0], a[1]))
    outward_from(disc, lambda f: np.array([0.0, 0.0, 0.0]) if abs(f[0]) < th * 0.4 else np.array([0.0, f[1], f[2]]))
    flat_normals(disc)
    p["chrome"].append(disc)
    # Diamond-grit tips glow when it's cutting.
    for k in range(teeth):
        a = 2 * math.pi * (2 * k) / (teeth * 2) + 0.04
        tip = bevel_box((0.018, 0.02, 0.02), 0.004)
        tip.transform(rotx(-a), (0.0, BLADE_R * math.cos(a) * 0.97, BLADE_R * math.sin(a) * 0.97))
        flat_normals(tip)
        p["glow"].append(tip)
    # Hub, bolts and lightening holes ring.
    p["dark"].append(solid_x([(0.0, -0.03), (0.07, -0.03), (0.07, 0.03), (0.0, 0.03)], 20, smooth=False))
    for k in range(6):
        a = k * math.pi / 3
        b = solid_x([(0.0, -0.035), (0.012, -0.035), (0.012, 0.035), (0.0, 0.035)], 10, smooth=False)
        b.transform(None, (0.0, 0.045 * math.cos(a), 0.045 * math.sin(a)))
        p["chrome"].append(b)
    for k in range(8):
        a = k * math.pi / 4 + 0.2
        h = solid_x([(0.0, -0.008), (0.028, -0.008), (0.028, 0.008), (0.0, 0.008)], 12, smooth=False)
        h.transform(None, (0.0, 0.17 * math.cos(a), 0.17 * math.sin(a)))
        p["dark"].append(h)
    return p


def main(path):
    g = GLB()
    ha, hn, hm = hull_panels(512, seed=44, base=(0.6, 0.61, 0.64), plate=(64, 32))
    th = (g.image(ha, "plate_a"), g.image(hn, "plate_n"), g.image(hm, "plate_mr"))
    # Matches the Strider's gunmetal plating with its blue-white trim.
    g.material("Plate", color=(0.55, 0.57, 0.6, 1), albedo_tex=th[0], normal_tex=th[1], mr_tex=th[2], metal=0.85, rough=0.55)
    g.material("DarkSteel", color=(0.12, 0.13, 0.15, 1), normal_tex=th[1], metal=0.9, rough=0.5)
    g.material("Chrome", color=(0.82, 0.84, 0.86, 1), metal=1.0, rough=0.18)
    g.material("Heat", color=(0.3, 0.08, 0.02, 1), emissive=(1.0, 0.42, 0.1), emissive_strength=3.5)
    mats = {"plate": "Plate", "dark": "DarkSteel", "chrome": "Chrome", "glow": "Heat"}
    arm = add(g, "SawArm", saw_arm(), mats, uvs=6.0)
    add(g, "SawBlade", saw_blade(), mats, uvs=6.0, parent=arm, translation=tuple(BLADE_AT))
    g.save(path)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "../../models/droid_arms.glb")
