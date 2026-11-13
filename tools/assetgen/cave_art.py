"""Cave wall art for the base camp cave (models/cave_art/*.png, RGBA).

Painted onto the rock as decals, so each image is pigment on transparency:
rough brush strokes, eroded by noise so the rock shows through, with uneven
pigment density. Four panels:

  vaari_hunt.png     ochre pictograph: spined beasts, tall long-headed Vaari
                     leading small human figures toward a crystal spire.
  hands_spirals.png  four-fingered alien handprints and spirals.
  sky_fall.png       pale glowing pigment: a spire pulsing rings while ships
                     fall burning from the sky (they've done this before).
  k7_tally.png       scratched by a human: tally marks, "K-7 TEAM 2",
                     "LIGHTS IN THE TREES" (a first-team survivor sheltered here).

Run: python3 tools/assetgen/cave_art.py
"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "models", "cave_art")
S = 1024          # output size
SS = 2            # supersample while drawing


def noise(size, scale, seed, octaves=4):
    """Smooth value noise in 0..1 (sum of upscaled random grids)."""
    rng = np.random.default_rng(seed)
    acc = np.zeros((size, size), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        n = max(2, int(size / scale * (2 ** o)))
        g = rng.random((n, n)).astype(np.float32)
        img = Image.fromarray((g * 255).astype(np.uint8)).resize((size, size), Image.BICUBIC)
        acc += np.asarray(img, np.float32) / 255.0 * amp
        tot += amp
        amp *= 0.5
    return acc / tot


class Painter:
    def __init__(self, seed):
        self.rng = random.Random(seed)
        self.mask = Image.new("L", (S * SS, S * SS), 0)
        self.d = ImageDraw.Draw(self.mask)

    def p(self, x, y):
        return (x * SS, y * SS)

    def stroke(self, pts, w, jitter=3.0, a=255):
        """A wobbly brush stroke through points (in 0..S space)."""
        r = self.rng
        out = []
        for i in range(len(pts) - 1):
            (x0, y0), (x1, y1) = pts[i], pts[i + 1]
            steps = max(2, int(math.hypot(x1 - x0, y1 - y0) / 6))
            for k in range(steps):
                t = k / steps
                out.append((x0 + (x1 - x0) * t + r.uniform(-jitter, jitter) * 0.3,
                            y0 + (y1 - y0) * t + r.uniform(-jitter, jitter) * 0.3))
        out.append(pts[-1])
        for i in range(len(out) - 1):
            ww = w * r.uniform(0.75, 1.15)
            self.d.line([self.p(*out[i]), self.p(*out[i + 1])], fill=a, width=int(ww * SS))
            self.d.ellipse([self.p(out[i][0] - ww / 2, out[i][1] - ww / 2), self.p(out[i][0] + ww / 2, out[i][1] + ww / 2)], fill=a)

    def blob(self, cx, cy, rx, ry, a=255, rot=0.0):
        pts = []
        for i in range(24):
            ang = i / 24 * math.tau
            k = self.rng.uniform(0.85, 1.12)
            x, y = math.cos(ang) * rx * k, math.sin(ang) * ry * k
            pts.append(self.p(cx + x * math.cos(rot) - y * math.sin(rot), cy + x * math.sin(rot) + y * math.cos(rot)))
        self.d.polygon(pts, fill=a)

    def poly(self, pts, a=255):
        self.d.polygon([self.p(*q) for q in pts], fill=a)

    def finish(self, colour, seed, erosion=0.55, density=(0.55, 1.0), blur=1.2, glow=False):
        m = self.mask.resize((S, S), Image.LANCZOS).filter(ImageFilter.GaussianBlur(blur))
        m = np.asarray(m, np.float32) / 255.0
        # Erode: pigment flaked off where the rock is rough.
        n1 = noise(S, 90, seed)
        n2 = noise(S, 14, seed + 1, 3)
        keep = np.clip((n1 * 0.6 + n2 * 0.4 - erosion * 0.55) * 3.2, 0.0, 1.0)
        dens = density[0] + (density[1] - density[0]) * noise(S, 40, seed + 2)
        alpha = np.clip(m * keep * dens, 0.0, 1.0)
        # Soft fade at the panel edges so nothing ends in a hard line.
        yy, xx = np.mgrid[0:S, 0:S] / (S - 1)
        edge = np.clip(np.minimum.reduce([xx, 1 - xx, yy, 1 - yy]) / 0.06, 0, 1)
        alpha *= edge
        c = np.array(colour, np.float32)
        tint = 0.85 + 0.3 * noise(S, 60, seed + 3)[..., None]
        rgb = np.clip(c[None, None, :] * tint, 0, 255)
        img = np.dstack([rgb, alpha[..., None] * 255]).astype(np.uint8)
        return Image.fromarray(img, "RGBA")


# ------------------------------------------------------------------ panels

def beast(pt, x, y, s, facing=1):
    """A spined quadruped (the creatures), side view."""
    f = facing
    pt.blob(x, y, 46 * s, 17 * s, rot=-0.08 * f)                    # body
    pt.blob(x + 50 * s * f, y - 10 * s, 16 * s, 11 * s)               # head
    pt.stroke([(x + 60 * s * f, y - 8 * s), (x + 76 * s * f, y - 2 * s)], 5 * s)   # jaw
    for lx in (-30, -12, 18, 34):                                     # legs
        knee = (x + (lx + 6 * f) * s, y + 26 * s)
        pt.stroke([(x + lx * s, y + 8 * s), knee, (x + (lx - 4 * f) * s, y + 46 * s)], 7 * s)
    for i in range(6):                                               # spines
        bx = x + (-34 + i * 13) * s
        pt.stroke([(bx, y - 12 * s), (bx - 6 * s * f, y - (34 + (i % 2) * 10) * s)], 5 * s, jitter=1)
    pt.stroke([(x - 44 * s * f, y - 4 * s), (x - 70 * s * f, y - 18 * s), (x - 84 * s * f, y - 10 * s)], 6 * s)  # tail


def vaari(pt, x, y, s):
    """Tall, thin, long-headed figure."""
    pt.blob(x, y - 150 * s, 9 * s, 24 * s, rot=0.25)                 # elongated head
    pt.stroke([(x - 2 * s, y - 128 * s), (x, y - 60 * s)], 9 * s)     # body
    pt.stroke([(x, y - 112 * s), (x + 30 * s, y - 92 * s), (x + 46 * s, y - 100 * s)], 5 * s)   # reaching arm
    pt.stroke([(x, y - 112 * s), (x - 22 * s, y - 84 * s), (x - 18 * s, y - 64 * s)], 5 * s)
    pt.stroke([(x, y - 60 * s), (x + 10 * s, y - 28 * s), (x + 8 * s, y)], 6 * s)
    pt.stroke([(x, y - 60 * s), (x - 12 * s, y - 28 * s), (x - 14 * s, y)], 6 * s)


def human(pt, x, y, s):
    """Small stick figure, arms raised or bound."""
    pt.blob(x, y - 62 * s, 8 * s, 8 * s)
    pt.stroke([(x, y - 54 * s), (x, y - 26 * s)], 6 * s)
    pt.stroke([(x, y - 46 * s), (x + 12 * s, y - 34 * s)], 4 * s)
    pt.stroke([(x, y - 46 * s), (x - 12 * s, y - 34 * s)], 4 * s)
    pt.stroke([(x, y - 26 * s), (x + 8 * s, y)], 5 * s)
    pt.stroke([(x, y - 26 * s), (x - 8 * s, y)], 5 * s)


def spire(pt, x, y, s, rays=True):
    pt.poly([(x - 34 * s, y), (x - 12 * s, y - 120 * s), (x - 4 * s, y - 210 * s), (x + 8 * s, y - 140 * s), (x + 30 * s, y)])
    pt.poly([(x + 14 * s, y - 40 * s), (x + 36 * s, y - 130 * s), (x + 30 * s, y - 40 * s)])
    if rays:
        for i in range(7):
            a = -math.pi * 0.5 + (i - 3) * 0.32
            r0, r1 = 230 * s, 300 * s
            pt.stroke([(x + math.cos(a) * r0 * 0.4, y - 210 * s + math.sin(a) * r0 * 0.4 + 80 * s),
                       (x + math.cos(a) * r1 * 0.55, y - 210 * s + math.sin(a) * r1 * 0.55 + 80 * s)], 5 * s)


def panel_vaari_hunt():
    pt = Painter(11)
    # A spire on the right, the procession heading to it, beasts above.
    spire(pt, 840, 930, 2.3)
    beast(pt, 230, 260, 2.1, facing=1)
    beast(pt, 560, 330, 1.8, facing=1)
    vaari(pt, 150, 930, 2.2)
    human(pt, 290, 930, 2.0)
    human(pt, 390, 930, 1.95)
    vaari(pt, 520, 930, 2.2)
    human(pt, 640, 930, 1.9)
    # The rope between them.
    pt.stroke([(240, 735), (290, 820), (390, 820), (470, 735)], 5, jitter=1)
    pt.stroke([(560, 735), (640, 830)], 5, jitter=1)
    # Ground line and dots (counting?).
    pt.stroke([(40, 950), (980, 940)], 9, jitter=4)
    for i in range(16):
        pt.blob(70 + i * 40, 990, 9, 9)
    return pt.finish((175, 60, 34), 11, erosion=0.32, density=(0.75, 1.0))


def panel_hands():
    pt = Painter(22)
    r = pt.rng
    for (x, y, rot, sc) in [(250, 300, -0.3, 1.1), (430, 250, 0.1, 1.0), (620, 330, 0.35, 1.05), (330, 560, -0.1, 0.95), (720, 600, 0.2, 1.15)]:
        # Palm and four long, jointed fingers.
        pt.blob(x, y + 40 * sc, 46 * sc, 52 * sc, rot=rot)
        for k in range(3):   # three long fingers and a thumb: not human
            a = rot - math.pi * 0.5 + (k - 1.0) * 0.36
            base = (x + math.cos(a) * 40 * sc, y + 40 * sc + math.sin(a) * 46 * sc)
            mid = (base[0] + math.cos(a) * 52 * sc, base[1] + math.sin(a) * 52 * sc)
            tip = (mid[0] + math.cos(a + 0.18) * 62 * sc, mid[1] + math.sin(a + 0.18) * 62 * sc)
            pt.stroke([base, mid, tip], 17 * sc, jitter=1)
        pt.stroke([(x - 44 * sc, y + 50 * sc), (x - 84 * sc, y + 20 * sc)], 16 * sc)   # thumb
    # Spirals.
    for (cx, cy, rr) in [(170, 800, 90), (520, 820, 110), (860, 380, 80)]:
        pts = []
        for i in range(120):
            t = i / 119
            a = t * math.tau * 3.2
            pts.append((cx + math.cos(a) * rr * t, cy + math.sin(a) * rr * t))
        pt.stroke(pts, 9, jitter=2)
    return pt.finish((185, 48, 32), 22, erosion=0.3, density=(0.75, 1.0))


def panel_sky_fall():
    pt = Painter(33)
    spire(pt, 512, 900, 1.5, rays=False)
    # Pulse rings from the tip.
    tip = (506, 585)
    for i, rr in enumerate([90, 160, 240, 330]):
        pts = [(tip[0] + math.cos(a) * rr, tip[1] + math.sin(a) * rr * 0.9)
               for a in np.linspace(math.pi * 1.05, math.pi * 1.95, 30)]
        pt.stroke(pts, 9 - i, jitter=2)
    # Ships falling, trailing fire.
    for (x, y, ang) in [(150, 130, 0.9), (330, 70, 1.15), (760, 110, 2.1), (890, 260, 2.35)]:
        dx, dy = math.cos(ang), math.sin(ang)
        pt.poly([(x + dx * 30, y + dy * 30), (x - dy * 12, y + dx * 12), (x + dy * 12, y - dx * 12)])
        trail = [(x - dx * k * 40 + pt.rng.uniform(-6, 6), y - dy * k * 40 + pt.rng.uniform(-6, 6)) for k in range(0, 5)]
        pt.stroke(trail, 6, jitter=3)
    return pt.finish((150, 225, 245), 33, erosion=0.4, density=(0.5, 0.95), blur=1.6)


def panel_tally():
    """Scratched into the rock by a human: thin, sharp, pale."""
    img = Image.new("L", (S * SS, S * SS), 0)
    d = ImageDraw.Draw(img)
    r = random.Random(44)
    # Tally marks in fives.
    x0, y0 = 110, 140
    days = 19
    for i in range(days):
        g, k = divmod(i, 5)
        gx = x0 + g * 170
        if k < 4:
            x = gx + k * 26 + r.uniform(-3, 3)
            d.line([(x * SS, (y0 + r.uniform(-4, 4)) * SS), ((x + r.uniform(-6, 6)) * SS, (y0 + 120 + r.uniform(-6, 6)) * SS)], fill=255, width=5 * SS)
        else:
            d.line([((gx - 14) * SS, (y0 + 100) * SS), ((gx + 96) * SS, (y0 + 18) * SS)], fill=255, width=5 * SS)
    font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf"
    try:
        f_big = ImageFont.truetype(font_path, 74 * SS)
        f_mid = ImageFont.truetype(font_path, 58 * SS)
    except OSError:
        f_big = f_mid = ImageFont.load_default()
    for text, y, f, tilt in [("K-7  TEAM 2", 360, f_big, -1.5), ("LIGHTS IN THE TREES", 520, f_mid, 1.0),
                             ("DON'T FOLLOW THEM", 650, f_mid, -0.8)]:
        layer = Image.new("L", img.size, 0)
        ImageDraw.Draw(layer).text((110 * SS, y * SS), text, font=f, fill=255)
        layer = layer.rotate(tilt, resample=Image.BICUBIC, center=(512 * SS, y * SS))
        img = Image.fromarray(np.maximum(np.asarray(img), np.asarray(layer)))
    # Scratched by hand: wobble each row a little and chip the edges.
    arr = np.asarray(img).copy()
    rr = np.random.default_rng(45)
    wob = np.cumsum(rr.normal(0, 0.6, arr.shape[0])).astype(int)
    wob -= wob.mean().astype(int)
    for y in range(arr.shape[0]):
        arr[y] = np.roll(arr[y], int(np.clip(wob[y], -6, 6)))
    chips = (np.asarray(Image.fromarray((rr.random((arr.shape[0] // 3, arr.shape[1] // 3)) * 255).astype(np.uint8)).resize(img.size)) > 70)
    img = Image.fromarray((arr * chips).astype(np.uint8))
    # Gouged underline under the warning.
    d = ImageDraw.Draw(img)
    d.line([(110 * SS, 745 * SS), (760 * SS, 735 * SS)], fill=255, width=4 * SS)
    pt = Painter(44)
    pt.mask = img
    return pt.finish((215, 205, 190), 44, erosion=0.38, density=(0.55, 1.0), blur=0.9)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in [("vaari_hunt", panel_vaari_hunt), ("hands_spirals", panel_hands),
                     ("sky_fall", panel_sky_fall), ("k7_tally", panel_tally)]:
        img = fn()
        img.save(os.path.join(OUT, name + ".png"))
        if True:
            # Glow map: colour only where there's pigment (emission ignores alpha).
            a = np.asarray(img, np.float32)
            glow = (a[..., :3] * (a[..., 3:4] / 255.0)).astype(np.uint8)
            Image.fromarray(glow, "RGB").save(os.path.join(OUT, name + "_glow.png"))
        print("wrote", name)


if __name__ == "__main__":
    main()
