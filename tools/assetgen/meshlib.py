"""Tiny procedural modelling kit + glTF (.glb) writer for Strider assets."""
import json, struct, math, io
import numpy as np
from PIL import Image

# ---------------------------------------------------------------- noise
_rng = np.random.default_rng(7)
_PERM = _rng.permutation(256)
_PERM = np.concatenate([_PERM, _PERM])
_GRAD = _rng.normal(size=(256, 3)); _GRAD /= np.linalg.norm(_GRAD, axis=1, keepdims=True)

def _fade(t): return t * t * t * (t * (t * 6 - 15) + 10)

def noise3(p):
    """Gradient noise for an (N,3) array -> (N,) in about [-1,1]."""
    p = np.asarray(p, float)
    i = np.floor(p).astype(int); f = p - i
    i &= 255
    u = _fade(f)
    def g(dx, dy, dz):
        h = _PERM[_PERM[_PERM[i[:, 0] + dx] + i[:, 1] + dy] + i[:, 2] + dz]
        d = f - np.array([dx, dy, dz])
        return np.sum(_GRAD[h] * d, axis=1)
    n000, n100, n010, n110 = g(0,0,0), g(1,0,0), g(0,1,0), g(1,1,0)
    n001, n101, n011, n111 = g(0,0,1), g(1,0,1), g(0,1,1), g(1,1,1)
    x1 = n000 + u[:, 0] * (n100 - n000); x2 = n010 + u[:, 0] * (n110 - n010)
    x3 = n001 + u[:, 0] * (n101 - n001); x4 = n011 + u[:, 0] * (n111 - n011)
    y1 = x1 + u[:, 1] * (x2 - x1); y2 = x3 + u[:, 1] * (x4 - x3)
    return (y1 + u[:, 2] * (y2 - y1)) * 1.8

def fbm3(p, oct=4):
    p = np.asarray(p, float); s = 0; a = 0.5; tot = 0
    for o in range(oct):
        s = s + noise3(p * (2 ** o) + o * 17.3) * a; tot += a; a *= 0.5
    return s / tot

# ---------------------------------------------------------------- mesh
class Mesh:
    """Triangle soup with per-corner data (flat or smooth as built)."""
    def __init__(self):
        self.P = []; self.N = []; self.C = []; self.UV = []

    def quad_uv(self, a, b, c, d, ua, ub, uc, ud, n=None):
        """Quad with explicit UVs (a-b-c-d counter-clockwise seen from the front)."""
        a, b, c, d = map(lambda x: np.asarray(x, float), (a, b, c, d))
        if n is None:
            n = np.cross(b - a, c - a); l = np.linalg.norm(n)
            if l < 1e-12: return
            n = n / l
        self.P += [a, b, c, a, c, d]; self.N += [n] * 6
        self.UV += [ua, ub, uc, ua, uc, ud]

    def tri(self, a, b, c, n=None):
        a, b, c = map(np.asarray, (a, b, c))
        if n is None:
            n = np.cross(b - a, c - a); l = np.linalg.norm(n)
            if l < 1e-9: return
            n = n / l
        self.P += [a, b, c]; self.N += [n, n, n]

    def tri_n(self, a, b, c, na, nb, nc):
        self.P += [np.asarray(a), np.asarray(b), np.asarray(c)]
        self.N += [np.asarray(na), np.asarray(nb), np.asarray(nc)]

    def quad(self, a, b, c, d):
        self.tri(a, b, c); self.tri(a, c, d)

    def extend(self, other):
        if (self.UV or not self.P) and len(other.UV) == len(other.P) and len(self.UV) == len(self.P):
            self.UV += other.UV
        else:
            self.UV = []
        self.P += other.P; self.N += other.N

    def arrays(self):
        P = np.array(self.P, np.float32).reshape(-1, 3)
        N = np.array(self.N, np.float32).reshape(-1, 3)
        return P, N

    def transform(self, M=None, t=(0, 0, 0)):
        M = np.eye(3) if M is None else np.asarray(M)
        self.P = [M @ p + np.asarray(t) for p in self.P]
        self.N = [(M @ n) / max(1e-9, np.linalg.norm(M @ n)) for n in self.N]
        return self

def rotx(a): c, s = math.cos(a), math.sin(a); return np.array([[1,0,0],[0,c,-s],[0,s,c]])
def roty(a): c, s = math.cos(a), math.sin(a); return np.array([[c,0,s],[0,1,0],[-s,0,c]])
def rotz(a): c, s = math.cos(a), math.sin(a); return np.array([[c,-s,0],[s,c,0],[0,0,1]])

def orient(m):
    """Flip triangle winding so the stored normals face the way the triangles do (CCW front)."""
    return m

def loft(sections, closed=True, cap_start=True, cap_end=True, smooth_along=True):
    """sections: list of (K,3) arrays, same K, each a ring. Facets are flat across
    the ring (hard edges between ring points) and smooth along the length."""
    m = Mesh()
    S = [np.asarray(s, float) for s in sections]
    K = len(S[0]); n_s = len(S)
    rng_k = range(K if closed else K - 1)
    # face normals per segment/side
    for i in range(n_s - 1):
        A, B = S[i], S[i + 1]
        for k in rng_k:
            k2 = (k + 1) % K
            a, b, c, d = A[k], A[k2], B[k2], B[k]
            n = np.cross(c - a, b - d)
            l = np.linalg.norm(n)
            if l < 1e-9: continue
            n /= l
            if smooth_along:
                def side_n(j):
                    if j < 0 or j >= n_s - 1: return None
                    a2, b2, c2, d2 = S[j][k], S[j][k2], S[j + 1][k2], S[j + 1][k]
                    nn = np.cross(c2 - a2, b2 - d2); ll = np.linalg.norm(nn)
                    return nn / ll if ll > 1e-9 else None
                prev = side_n(i - 1); nxt = side_n(i + 1)
                n0 = n if prev is None or np.dot(prev, n) < 0.8 else (prev + n) / np.linalg.norm(prev + n)
                n1 = n if nxt is None or np.dot(nxt, n) < 0.8 else (nxt + n) / np.linalg.norm(nxt + n)
                m.tri_n(a, d, c, n0, n1, n1); m.tri_n(a, c, b, n0, n1, n0)
            else:
                m.tri(a, d, c, n); m.tri(a, c, b, n)
    def cap(R, flip):
        c = R.mean(axis=0)
        for k in range(K):
            a, b = R[k], R[(k + 1) % K]
            if flip: m.tri(c, a, b)
            else: m.tri(c, b, a)
    if cap_start and closed: cap(S[0], False)
    if cap_end and closed: cap(S[-1], True)
    return m

def fix_outward(m, center):
    """Make every face point away from `center` (for convex-ish closed parts)."""
    P, N = m.P, m.N
    for t in range(0, len(P), 3):
        a, b, c = P[t], P[t+1], P[t+2]
        n = np.cross(b - a, c - a)
        if np.dot(n, (a + b + c) / 3 - center) < 0:
            P[t+1], P[t+2] = P[t+2], P[t+1]; N[t+1], N[t+2] = N[t+2], N[t+1]
            fn = -n / max(1e-9, np.linalg.norm(n))
            for j in range(3):
                if np.dot(N[t+j], fn) < 0: N[t+j] = -N[t+j]
    return m

def lathe(profile, seg=24, axis='z', flat=False):
    """profile: list of (r, z). Revolves around the axis."""
    sections = []
    for (r, z) in profile:
        ring = []
        for k in range(seg):
            a = 2 * math.pi * k / seg
            ring.append((r * math.cos(a), r * math.sin(a), z))
        sections.append(np.array(ring))
    m = Mesh()
    for i in range(len(sections) - 1):
        A, B = sections[i], sections[i + 1]
        for k in range(seg):
            k2 = (k + 1) % seg
            a, b, c, d = A[k], A[k2], B[k2], B[k]
            if flat:
                m.quad(a, b, c, d)
            else:
                def rn(p, r, dz_dr):
                    v = np.array([p[0], p[1], 0.0]); l = np.linalg.norm(v)
                    v = v / l if l > 1e-9 else np.array([0, 0, 1.0])
                    return v
                dr = profile[i+1][0] - profile[i][0]; dz = profile[i+1][1] - profile[i][1]
                L = math.hypot(dr, dz) or 1
                def nrm(p):
                    v = np.array([p[0], p[1], 0.0]); l = np.linalg.norm(v)
                    v = v / l if l > 1e-9 else np.zeros(3)
                    return v * (dz / L) + np.array([0, 0, -dr / L])
                m.tri_n(a, b, c, nrm(a), nrm(b), nrm(c)); m.tri_n(a, c, d, nrm(a), nrm(c), nrm(d))
    # orient: lathe from z asc produces quads a,b,c,d; ensure outward
    out = Mesh()
    for t in range(0, len(m.P), 3):
        a, b, c = m.P[t:t+3]; na, nb, nc = m.N[t:t+3]
        n = np.cross(b - a, c - a)
        if np.dot(n, na + nb + nc) < 0:
            out.tri_n(a, c, b, na, nc, nb)
        else:
            out.tri_n(a, b, c, na, nb, nc)
    if axis == 'x':
        out.transform(roty(math.pi / 2))
    elif axis == 'y':
        out.transform(rotx(-math.pi / 2))
    return out

def blob(size, e=0.35, nu=24, nv=14, center=(0, 0, 0), squash=None):
    """Smooth superellipsoid (pillows, cushions, mattresses, bags). e<1 = boxier."""
    sx, sy, sz = np.asarray(size, float) / 2
    def sgnpow(x, p): return np.sign(x) * np.abs(x) ** p
    m = Mesh()
    G = np.zeros((nv + 1, nu + 1, 3))
    for j in range(nv + 1):
        v = -math.pi / 2 + math.pi * j / nv
        for i in range(nu + 1):
            u = -math.pi + 2 * math.pi * i / nu
            x = sx * sgnpow(math.cos(v), e) * sgnpow(math.cos(u), e)
            z = sz * sgnpow(math.cos(v), e) * sgnpow(math.sin(u), e)
            y = sy * sgnpow(math.sin(v), e)
            if squash is not None: y += squash(x / sx, z / sz) * sy * (1 - abs(math.sin(v)))
            G[j, i] = (x, y, z)
    # smooth normals from the grid
    Nn = np.zeros_like(G)
    for j in range(nv + 1):
        for i in range(nu + 1):
            du = G[j, (i + 1) % (nu + 1)] - G[j, (i - 1) % (nu + 1)]
            dv = G[min(nv, j + 1), i] - G[max(0, j - 1), i]
            n = np.cross(dv, du); l = np.linalg.norm(n)
            if l < 1e-9: n = np.array([0, 1.0 if j > nv / 2 else -1.0, 0])
            else: n /= l
            Nn[j, i] = n
    for j in range(nv):
        for i in range(nu):
            a, b, c, d = G[j, i], G[j, i + 1], G[j + 1, i + 1], G[j + 1, i]
            na, nb, nc, nd = Nn[j, i], Nn[j, i + 1], Nn[j + 1, i + 1], Nn[j + 1, i]
            f = np.cross(b - a, c - a)
            if np.dot(f, a + b + c) > 0:
                m.tri_n(a, b, c, na, nb, nc); m.tri_n(a, c, d, na, nc, nd)
            else:
                m.tri_n(a, c, b, na, nc, nb); m.tri_n(a, d, c, na, nd, nc)
    # make normals face outward
    for t in range(len(m.N)):
        if np.dot(m.N[t], m.P[t]) < 0: m.N[t] = -m.N[t]
    return m.transform(t=center)

def cyl(r, h, seg=16, center=(0, 0, 0), axis='y', r2=None):
    """Capped cylinder (or cone frustum) along an axis, centred."""
    r2 = r if r2 is None else r2
    m = lathe([(0.0, -h / 2), (r, -h / 2), (r2, h / 2), (0.0, h / 2)], seg, axis='z', flat=False)
    if axis == 'x': m.transform(roty(math.pi / 2))
    elif axis == 'y': m.transform(rotx(-math.pi / 2))
    return m.transform(t=center)

def tube(points, r, seg=8):
    """A cable / pipe following a polyline."""
    pts = []
    for p in points:
        p = np.asarray(p, float)
        if not pts or np.linalg.norm(p - pts[-1]) > 1e-6: pts.append(p)
    rings = []
    for i, p in enumerate(pts):
        t = pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]; t /= np.linalg.norm(t) + 1e-9
        up = np.array([0, 1.0, 0]) if abs(t[1]) < 0.9 else np.array([1.0, 0, 0])
        a = np.cross(t, up); a /= np.linalg.norm(a); b = np.cross(t, a)
        rings.append([p + (a * math.cos(2 * math.pi * k / seg) + b * math.sin(2 * math.pi * k / seg)) * r for k in range(seg)])
    m = loft(rings, closed=True, cap_start=False, cap_end=False)
    # loft winds these inward: flip faces and normals
    for t in range(0, len(m.P), 3):
        m.P[t + 1], m.P[t + 2] = m.P[t + 2], m.P[t + 1]
        m.N[t], m.N[t + 1], m.N[t + 2] = -m.N[t], -m.N[t + 2], -m.N[t + 1]
    return m

def bevel_box(size, bevel=0.05, center=(0, 0, 0)):
    """Box with chamfered edges (26 faces)."""
    sx, sy, sz = np.asarray(size) / 2.0
    b = min(bevel, sx * 0.45, sy * 0.45, sz * 0.45)
    # vertices of a chamfered box = all (±(s-b) on two axes, ±s on one axis)
    m = Mesh()
    S = np.array([sx, sy, sz]); I = S - b
    def v(sg, axis):
        p = sg * I.copy(); p[axis] = sg[axis] * S[axis]; return p
    signs = [np.array([x, y, z]) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
    # main faces
    for axis in range(3):
        for s in (-1, 1):
            o = [i for i in range(3) if i != axis]
            pts = []
            for (u, w) in [(-1, -1), (1, -1), (1, 1), (-1, 1)]:
                sg = np.zeros(3); sg[axis] = s; sg[o[0]] = u; sg[o[1]] = w
                pts.append(v(sg, axis))
            m.quad(*pts)
    # edge chamfers and corner triangles via convex hull approach: build from point set
    pts = []
    for sg in signs:
        for axis in range(3):
            pts.append(v(sg.astype(float), axis))
    pts = np.unique(np.round(np.array(pts), 6), axis=0)
    from scipy.spatial import ConvexHull
    h = ConvexHull(pts)
    m = Mesh()
    c0 = pts.mean(axis=0)
    for simp, eq in zip(h.simplices, h.equations):
        a, b, c = pts[simp]
        n = eq[:3]
        if np.dot(np.cross(b - a, c - a), n) < 0: b, c = c, b
        m.tri(a, b, c, n)
    return m.transform(t=center)

def hull_of(points):
    """Convex hull mesh of a point set (good for wedges, fins, plates)."""
    from scipy.spatial import ConvexHull
    pts = np.asarray(points, float)
    h = ConvexHull(pts)
    m = Mesh()
    for simp, eq in zip(h.simplices, h.equations):
        a, b, c = pts[simp]; n = eq[:3]
        if np.dot(np.cross(b - a, c - a), n) < 0: b, c = c, b
        m.tri(a, b, c, n)
    return m

# ---------------------------------------------------------------- UVs + colours
def box_uv(P, N, scale=0.25):
    """Planar projection by the dominant normal axis, in metres * scale."""
    a = np.abs(N); ax = np.argmax(a, axis=1)
    uv = np.zeros((len(P), 2), np.float32)
    for k, (i, j) in enumerate([(2, 1), (0, 2), (0, 1)]):
        sel = ax == k
        uv[sel, 0] = P[sel, i] * scale; uv[sel, 1] = -P[sel, j] * scale
    return uv

# ---------------------------------------------------------------- glTF
class GLB:
    def __init__(self):
        self.bin = bytearray(); self.j = {"asset": {"version": "2.0", "generator": "strider-meshlib"},
            "scenes": [{"nodes": []}], "scene": 0, "nodes": [], "meshes": [], "accessors": [],
            "bufferViews": [], "buffers": [], "materials": [], "textures": [], "images": [], "samplers": [
                {"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]}
        self.mat_index = {}

    def _view(self, data, target=None):
        while len(self.bin) % 4: self.bin += b'\0'
        off = len(self.bin); self.bin += data
        bv = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target: bv["target"] = target
        self.j["bufferViews"].append(bv); return len(self.j["bufferViews"]) - 1

    def _acc(self, arr, ctype, typ, target=34962, minmax=False):
        arr = np.ascontiguousarray(arr)
        v = self._view(arr.tobytes(), target)
        a = {"bufferView": v, "componentType": ctype, "count": len(arr), "type": typ}
        if minmax:
            a["min"] = arr.min(axis=0).tolist(); a["max"] = arr.max(axis=0).tolist()
        self.j["accessors"].append(a); return len(self.j["accessors"]) - 1

    def image(self, img, name):
        b = io.BytesIO(); img.save(b, "PNG")
        v = self._view(b.getvalue())
        self.j["images"].append({"bufferView": v, "mimeType": "image/png", "name": name})
        self.j["textures"].append({"sampler": 0, "source": len(self.j["images"]) - 1})
        return len(self.j["textures"]) - 1

    def material(self, name, **k):
        m = {"name": name, "pbrMetallicRoughness": {
            "baseColorFactor": list(k.get("color", (1, 1, 1, 1))),
            "metallicFactor": k.get("metal", 0.0), "roughnessFactor": k.get("rough", 0.5)}}
        if "albedo_tex" in k: m["pbrMetallicRoughness"]["baseColorTexture"] = {"index": k["albedo_tex"]}
        if "mr_tex" in k: m["pbrMetallicRoughness"]["metallicRoughnessTexture"] = {"index": k["mr_tex"]}
        if "normal_tex" in k: m["normalTexture"] = {"index": k["normal_tex"], "scale": k.get("normal_scale", 1.0)}
        if "emissive" in k: m["emissiveFactor"] = list(k["emissive"])
        if "emissive_strength" in k:
            m.setdefault("extensions", {})["KHR_materials_emissive_strength"] = {"emissiveStrength": k["emissive_strength"]}
            self.j.setdefault("extensionsUsed", []).append("KHR_materials_emissive_strength") if "KHR_materials_emissive_strength" not in self.j.get("extensionsUsed", []) else None
        if "emissive_tex" in k: m["emissiveTexture"] = {"index": k["emissive_tex"]}
        if k.get("mask"): m["alphaMode"] = "MASK"; m["alphaCutoff"] = k.get("cutoff", 0.5)
        if k.get("blend"): m["alphaMode"] = "BLEND"
        if k.get("double"): m["doubleSided"] = True
        self.j["materials"].append(m); self.mat_index[name] = len(self.j["materials"]) - 1
        return self.mat_index[name]

    def mesh_node(self, name, parts, parent=None, translation=None, rotation=None):
        """parts: list of (Mesh, material_name, colours (N,4) or None, uv_scale)."""
        prims = []
        for (m, mat, col, uvs) in parts:
            P, N = m.arrays()
            if len(P) == 0: continue
            if len(m.UV) == len(P) and len(P):
                uv = np.array(m.UV, np.float32).reshape(-1, 2)
            else:
                uv = box_uv(P, N, uvs)
            # Weld identical corners into shared, indexed vertices (smaller files,
            # and engine LOD simplification keeps connected surfaces intact).
            cols = [P, N, uv] + ([np.asarray(col, np.float32)] if col is not None else [])
            key = np.round(np.hstack(cols).astype(np.float64), 5)
            _, first, idx = np.unique(key, axis=0, return_index=True, return_inverse=True)
            idx = idx.reshape(-1).astype(np.uint32)
            P, N, uv = P[first], N[first], uv[first]
            if col is not None:
                col = np.asarray(col, np.float32)[first]
            attrs = {"POSITION": self._acc(np.ascontiguousarray(P, np.float32), 5126, "VEC3", minmax=True),
                     "NORMAL": self._acc(np.ascontiguousarray(N, np.float32), 5126, "VEC3"),
                     "TEXCOORD_0": self._acc(np.ascontiguousarray(uv, np.float32), 5126, "VEC2")}
            if col is not None:
                attrs["COLOR_0"] = self._acc(np.ascontiguousarray(col, np.float32), 5126, "VEC4")
            prims.append({"attributes": attrs, "indices": self._acc(idx, 5125, "SCALAR", 34963),
                          "material": self.mat_index[mat]})
        self.j["meshes"].append({"name": name, "primitives": prims})
        node = {"name": name, "mesh": len(self.j["meshes"]) - 1}
        if translation is not None: node["translation"] = list(map(float, translation))
        if rotation is not None: node["rotation"] = list(map(float, rotation))
        self.j["nodes"].append(node); ni = len(self.j["nodes"]) - 1
        if parent is None: self.j["scenes"][0]["nodes"].append(ni)
        else: self.j["nodes"][parent].setdefault("children", []).append(ni)
        return ni

    def empty(self, name, parent=None, translation=None):
        node = {"name": name}
        if translation is not None: node["translation"] = list(map(float, translation))
        self.j["nodes"].append(node); ni = len(self.j["nodes"]) - 1
        if parent is None: self.j["scenes"][0]["nodes"].append(ni)
        else: self.j["nodes"][parent].setdefault("children", []).append(ni)
        return ni

    def save(self, path):
        while len(self.bin) % 4: self.bin += b'\0'
        self.j["buffers"] = [{"byteLength": len(self.bin)}]
        js = json.dumps(self.j, separators=(',', ':')).encode()
        while len(js) % 4: js += b' '
        out = struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(self.bin))
        out += struct.pack('<II', len(js), 0x4E4F534A) + js
        out += struct.pack('<II', len(self.bin), 0x004E4942) + bytes(self.bin)
        open(path, 'wb').write(out)
