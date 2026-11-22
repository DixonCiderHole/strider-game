"""Camp job board (models/job_board.glb): a salvaged Coalition field terminal
on a tripod stand, its screen showing the posted jobs.

Node: JobBoard (origin at the feet, screen faces +Z, ~1.9 m tall)

python3 board_gen.py ../../models/job_board.glb
"""
import sys, math, numpy as np
from PIL import Image, ImageDraw
from meshlib import *
from textures import hull_panels
from reach_gen import add, smooth_normals, flat_normals, outward_from


def screen_tex(n=512):
    """Amber job listings on a dark glass screen."""
    img = Image.new("RGB", (n, int(n * 0.66)), (6, 9, 12))
    d = ImageDraw.Draw(img)
    W, H = img.size
    amber = (255, 170, 60)
    dim = (120, 80, 30)
    d.rectangle([0, 0, W, 46], fill=(60, 30, 8))
    d.rectangle([14, 14, 200, 32], fill=amber)
    d.rectangle([W - 90, 14, W - 14, 32], fill=dim)
    for k in range(3):
        y = 70 + k * 90
        d.rectangle([14, y, W - 14, y + 74], outline=dim, width=3)
        d.rectangle([28, y + 14, 74, y + 60], outline=amber, width=4)
        d.line([34, y + 37, 68, y + 37], fill=amber, width=4)
        d.rectangle([92, y + 16, 92 + 180 + k * 40, y + 30], fill=amber)
        d.rectangle([92, y + 44, 92 + 120, y + 54], fill=dim)
        d.rectangle([W - 120, y + 26, W - 30, y + 48], fill=(40, 120, 60) if k == 0 else dim)
    for y in range(0, H, 4):
        d.line([0, y, W, y], fill=(0, 0, 0), width=1)
    return img


def board():
    p = {"frame": [], "dark": [], "screen": [], "glow": []}
    # Tripod legs splayed out from a hub.
    hub_y = 0.75
    for k in range(3):
        a = k * 2 * math.pi / 3 + math.pi / 2
        foot = np.array([math.cos(a) * 0.42, 0.0, math.sin(a) * 0.42])
        knee = np.array([math.cos(a) * 0.2, 0.42, math.sin(a) * 0.2])
        p["frame"].append(tube([foot + np.array([0, 0.03, 0]), knee, np.array([0, hub_y, 0])], 0.028, 8))
        pad = cyl(0.06, 0.03, 12, tuple(foot + np.array([0, 0.015, 0])))
        smooth_normals(pad)
        p["dark"].append(pad)
    # Centre mast with a collar.
    mast = cyl(0.04, 0.85, 14, (0, hub_y + 0.42, 0))
    smooth_normals(mast)
    p["frame"].append(mast)
    col = cyl(0.07, 0.08, 14, (0, hub_y, 0))
    smooth_normals(col)
    p["dark"].append(col)
    # Screen housing, tilted back a little, with a bezel and side grips.
    tilt = rotx(-0.22)
    c = np.array([0, 1.5, 0.04])
    house = bevel_box((1.0, 0.68, 0.09), 0.025)
    house.transform(tilt, c)
    flat_normals(house)
    p["frame"].append(house)
    bez = bevel_box((0.92, 0.6, 0.02), 0.008)
    bez.transform(tilt, c + tilt @ np.array([0, 0, 0.045]))
    flat_normals(bez)
    p["dark"].append(bez)
    # Screen face (own UVs so the listings texture maps on straight).
    sw, sh = 0.86, 0.56
    scr = Mesh()
    z = 0.057
    corners = [tilt @ np.array(v) + c for v in ([-sw / 2, -sh / 2, z], [sw / 2, -sh / 2, z], [sw / 2, sh / 2, z], [-sw / 2, sh / 2, z])]
    scr.quad_uv(*corners, (0, 1), (1, 1), (1, 0), (0, 0))
    p["screen"].append(scr)
    for sx in (-1, 1):
        g = tube([c + tilt @ np.array([sx * 0.52, -0.25, 0.0]), c + tilt @ np.array([sx * 0.58, -0.2, 0.02]),
                  c + tilt @ np.array([sx * 0.58, 0.2, 0.02]), c + tilt @ np.array([sx * 0.52, 0.25, 0.0])], 0.016, 8)
        p["dark"].append(g)
    # Mounting bracket: mast to the back of the housing.
    br = bevel_box((0.22, 0.26, 0.12), 0.02)
    br.transform(tilt, c + tilt @ np.array([0, -0.05, -0.09]))
    flat_normals(br)
    p["dark"].append(br)
    # Light bar along the top and a little antenna.
    bar = bevel_box((0.7, 0.03, 0.04), 0.01)
    bar.transform(tilt, c + tilt @ np.array([0, 0.36, 0.03]))
    flat_normals(bar)
    p["glow"].append(bar)
    p["frame"].append(tube([c + tilt @ np.array([0.42, 0.34, -0.03]), c + tilt @ np.array([0.45, 0.62, -0.05])], 0.008, 6))
    # Cable from the housing down the mast.
    p["dark"].append(tube([c + tilt @ np.array([-0.3, -0.3, -0.05]), np.array([-0.15, 1.0, -0.05]), np.array([-0.05, 0.8, -0.04])], 0.012, 6))
    return p


def main(path):
    g = GLB()
    ha, hn, hm = hull_panels(512, seed=31, base=(0.62, 0.63, 0.66), plate=(96, 48))
    th = (g.image(ha, "frame_a"), g.image(hn, "frame_n"), g.image(hm, "frame_mr"))
    st = g.image(screen_tex(), "screen_e")
    g.material("Frame", color=(0.85, 0.86, 0.88, 1), albedo_tex=th[0], normal_tex=th[1], mr_tex=th[2], metal=0.5, rough=0.7)
    g.material("Dark", color=(0.18, 0.19, 0.21, 1), normal_tex=th[1], metal=0.8, rough=0.6)
    g.material("Screen", color=(0.05, 0.05, 0.05, 1), albedo_tex=st, emissive_tex=st, emissive=(1, 1, 1), emissive_strength=1.6, rough=0.15)
    g.material("Glow", color=(0.3, 0.15, 0.03, 1), emissive=(1.0, 0.62, 0.2), emissive_strength=3.0)
    add(g, "JobBoard", board(), {"frame": "Frame", "dark": "Dark", "screen": "Screen", "glow": "Glow"}, uvs=2.0)
    g.save(path)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "../../models/job_board.glb")
