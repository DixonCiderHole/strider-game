"""Preview helper: make a copy of a kit .glb whose scene shows only the named
nodes, each moved/turned, so shot.js can render a lineup.

python3 layout.py kit.glb out.glb Name:x,y,z[:yaw_deg[:pitch_deg[:roll_deg]]] ...
"""
import json, math, struct, sys


def quat(yaw, pitch, roll):
    # Y (yaw) then X (pitch) then Z (roll), degrees.
    def q(ax, a):
        s = math.sin(math.radians(a) / 2)
        return [ax[0] * s, ax[1] * s, ax[2] * s, math.cos(math.radians(a) / 2)]
    def mul(a, b):
        x1, y1, z1, w1 = a; x2, y2, z2, w2 = b
        return [w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2, w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2,
                w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2, w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2]
    return mul(mul(q((0, 1, 0), yaw), q((1, 0, 0), pitch)), q((0, 0, 1), roll))


def main(src, dst, specs):
    d = open(src, 'rb').read()
    jl = struct.unpack('<I', d[12:16])[0]
    j = json.loads(d[20:20 + jl])
    binchunk = d[20 + jl:]
    names = {n.get('name'): i for i, n in enumerate(j['nodes'])}
    roots = []
    for s in specs:
        f = s.split(':')
        i = names[f[0]]
        x, y, z = map(float, f[1].split(','))
        ang = [float(v) for v in f[2:]] + [0.0] * (3 - len(f[2:]))
        w = {"name": f[0] + "_v", "children": [i], "translation": [x, y, z], "rotation": quat(*ang)}
        j['nodes'].append(w)
        roots.append(len(j['nodes']) - 1)
    j['scenes'][0]['nodes'] = roots
    js = json.dumps(j, separators=(',', ':')).encode()
    while len(js) % 4:
        js += b' '
    out = struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + len(binchunk))
    out += struct.pack('<II', len(js), 0x4E4F534A) + js + binchunk
    open(dst, 'wb').write(out)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3:])
