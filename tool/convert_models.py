#!/usr/bin/env python3
"""Converts the ModelHMC pack (glTF/GLB/OBJ) into the compact binary assets used by HMC: 1.

Usage: python3 tool/convert_models.py /path/to/ModelHMC assets/models

All geometry is mirrored on X so it matches the game's left-handed world
(x right, y up, z forward). Triangle winding is flipped to compensate.
Colors are baked per triangle (flat-shaded low-poly look).
"""
import base64, json, math, os, struct, sys
import numpy as np
from PIL import Image
import io

SRC = sys.argv[1] if len(sys.argv) > 1 else '/home/claude/model/ModelHMC'
OUT = sys.argv[2] if len(sys.argv) > 2 else '/home/claude/hmc-1/assets/models'
os.makedirs(OUT, exist_ok=True)
manifest = {'vehicles': {}, 'buildings': {}, 'characters': {}, 'anims': 'char.anim'}

# ------------------------------------------------------------------ helpers
def srgb(c):
    c = np.clip(np.asarray(c, dtype=np.float64), 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)

def rgb8(lin):
    return [int(round(float(v) * 255)) for v in srgb(lin[:3])]

def load_gltf(path):
    if path.endswith('.glb'):
        d = open(path, 'rb').read()
        off = 12; j = None; binc = b''
        while off < len(d):
            ln, ty = struct.unpack('<II', d[off:off + 8]); ch = d[off + 8:off + 8 + ln]; off += 8 + ln
            if ty == 0x4E4F534A: j = json.loads(ch)
            elif ty == 0x004E4942: binc = ch
        return j, [binc]
    j = json.load(open(path))
    bufs = [base64.b64decode(b['uri'].split(',', 1)[1]) for b in j['buffers']]
    return j, bufs

def accessor(j, bufs, i):
    a = j['accessors'][i]; bv = j['bufferViews'][a['bufferView']]
    ct = {5126: '<f4', 5123: '<u2', 5125: '<u4', 5121: 'u1', 5120: 'i1', 5122: '<i2'}[a['componentType']]
    n = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[a['type']]
    isz = np.dtype(ct).itemsize
    stride = bv.get('byteStride') or isz * n
    off = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    raw = bufs[bv['buffer']]
    if stride == isz * n:
        arr = np.frombuffer(raw, dtype=ct, count=a['count'] * n, offset=off).astype(np.float64 if ct == '<f4' else np.int64)
    else:
        arr = np.stack([np.frombuffer(raw, dtype=ct, count=n, offset=off + k * stride) for k in range(a['count'])]).astype(np.float64)
    return arr.reshape(a['count'], n) if n > 1 else arr.reshape(-1)

def qmat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])

def trs(t, q, s):
    m = np.eye(4); m[:3, :3] = qmat(q) * np.asarray(s)[None, :]; m[:3, 3] = t; return m

def node_trs(n):
    return (np.array(n.get('translation', [0, 0, 0]), dtype=np.float64),
            np.array(n.get('rotation', [0, 0, 0, 1]), dtype=np.float64),
            np.array(n.get('scale', [1, 1, 1]), dtype=np.float64))

RX = np.diag([-1.0, 1, 1, 1])

def w_str(s):
    b = s.encode(); return struct.pack('<B', len(b)) + b

def cluster(verts, tris, cols, cell):
    """Vertex-clustering decimation. verts Nx3, tris Mx3, cols Mx3 (uint8)."""
    if cell <= 0: return verts, tris, cols
    q = np.floor(verts / cell).astype(np.int64)
    _, inv, cnt = np.unique(q, axis=0, return_inverse=True, return_counts=True)
    inv = inv.reshape(-1)
    nv = np.zeros((cnt.size, 3)); np.add.at(nv, inv, verts); nv /= cnt[:, None]
    t = inv[tris]
    ok = (t[:, 0] != t[:, 1]) & (t[:, 1] != t[:, 2]) & (t[:, 0] != t[:, 2])
    t, c = t[ok], cols[ok]
    key = np.sort(t, axis=1)
    _, first = np.unique(key, axis=0, return_index=True)
    first.sort()
    t, c = t[first], c[first]
    return nv, t, c

def compact(verts, tris):
    used = np.unique(tris.reshape(-1))
    remap = -np.ones(len(verts), dtype=np.int64); remap[used] = np.arange(len(used))
    return verts[used], remap[tris]

def write_smesh(path, parts):
    """parts: list of (name, pivot(3), verts Nx3 float, tris Mx3 int, cols Mx3 uint8)"""
    allmin = np.array([1e9] * 3); allmax = np.array([-1e9] * 3)
    body = b''
    for name, piv, v, t, c in parts:
        body += w_str(name) + struct.pack('<3f', *piv) + struct.pack('<II', len(v), len(t))
        body += np.asarray(v, dtype='<f4').tobytes() + np.asarray(t, dtype='<u2').tobytes() + np.asarray(c, dtype='u1').tobytes()
        if len(v):
            allmin = np.minimum(allmin, v.min(0) + piv); allmax = np.maximum(allmax, v.max(0) + piv)
    hdr = b'SMSH' + struct.pack('<II', 1, len(parts)) + struct.pack('<6f', *allmin, *allmax)
    open(path, 'wb').write(hdr + body)
    return allmin, allmax, sum(len(p[3]) for p in parts)

def flip_x_tris(verts, tris):
    v = verts.copy(); v[:, 0] *= -1
    return v, tris[:, [0, 2, 1]]

# ------------------------------------------------------------- vehicles
def sample_palette(img, uv, flip=True):
    # OBJ uv origin is bottom-left (flip=True); glTF uv origin is top-left (flip=False)
    w, h = img.size
    vv = (1 - uv[:, 1]) if flip else uv[:, 1]
    px = np.clip((uv[:, 0] * w).astype(int), 0, w - 1); py = np.clip((vv * h).astype(int), 0, h - 1)
    arr = np.asarray(img.convert('RGB'))
    return arr[py, px]

def convert_vehicle(name, out_id, recolor=None):
    j, bufs = load_gltf(f'{SRC}/LowPoly_Vehicles_Pack/GLB/{name}.glb')
    img = Image.open(io.BytesIO(bufs[0][j['bufferViews'][j['images'][0]['bufferView']].get('byteOffset', 0):][:j['bufferViews'][j['images'][0]['bufferView']]['byteLength']]))
    parts = []
    parent_of = {}
    for ni, nn in enumerate(j['nodes']):
        for c in nn.get('children', []): parent_of[c] = ni
    def wtrans(ni):
        t = np.array(j['nodes'][ni].get('translation', [0, 0, 0]), dtype=np.float64)
        return t + wtrans(parent_of[ni]) if ni in parent_of else t
    for ni, n in enumerate(j['nodes']):
        if 'mesh' not in n: continue
        pr = j['meshes'][n['mesh']]['primitives'][0]
        v = accessor(j, bufs, pr['attributes']['POSITION']); uv = accessor(j, bufs, pr['attributes']['TEXCOORD_0'])
        idx = accessor(j, bufs, pr['indices']).reshape(-1, 3)
        col = sample_palette(img, uv, flip=False)
        tc = ((col[idx[:, 0]].astype(int) + col[idx[:, 1]] + col[idx[:, 2]]) // 3).astype(np.uint8)
        piv = wtrans(ni); piv[0] *= -1
        v, idx = flip_x_tris(v, idx)
        parts.append([n['name'], piv, v, idx, tc])
    if recolor:
        for p in parts:
            for src_c, dst_c in recolor.items():
                m = np.all(p[4] == np.array(src_c), axis=1); p[4][m] = dst_c
        print('  recolor', out_id, recolor)
    mn, mx, nt = write_smesh(f'{OUT}/v_{out_id}.smesh', [tuple(p) for p in parts])
    manifest['vehicles'][out_id] = {'file': f'v_{out_id}.smesh', 'min': mn.tolist(), 'max': mx.tolist(), 'tris': nt}
    print('vehicle', out_id, 'tris', nt, 'size', np.round(mx - mn, 2).tolist(), 'parts', [p[0] for p in parts])

# ------------------------------------------------------------- buildings
def convert_building(name, out_id, scale, lods=((0.0, 0.0), (0.0, 0.0)), recolor_red=None):
    path = f'{SRC}/Buildings pack - Aug 2017/OBJ/{name}.obj'
    V, VT, F = [], [], []
    for l in open(path):
        p = l.split()
        if not p: continue
        if p[0] == 'v': V.append([float(x) for x in p[1:4]])
        elif p[0] == 'vt': VT.append([float(p[1]), float(p[2])])
        elif p[0] == 'f':
            idx = [tuple(int(x) if x else 0 for x in (t.split('/') + ['', ''])[:2]) for t in p[1:]]
            for k in range(1, len(idx) - 1): F.append((idx[0], idx[k], idx[k + 1]))
    V = np.array(V); VT = np.array(VT)
    tex = [f for f in os.listdir(f'{SRC}/Buildings pack - Aug 2017/Textures')]
    mtl = open(path.replace('.obj', '.mtl')).read()
    img = None
    for t in tex:
        if t.startswith(name.rstrip('0123456789')) or t.lower().startswith('hotel') and name.startswith('Flat'): pass
    # texture mapping by name (obj files reference textures inside the blend, not the mtl)
    tmap = {'Bank': 'Hotel', 'Flat': 'Hotel', 'Flat2': 'HouseTexture4', 'Hospital': 'Hotel', 'Shop': 'Shop',
            'House': 'HouseTexture1', 'House2': 'HouseTexture2', 'House3': 'HouseTexture3', 'House4': 'HouseTexture4', 'House5': 'HouseTexture1'}
    img = Image.open(f'{SRC}/Buildings pack - Aug 2017/Textures/{tmap[name]}.png')
    vi = np.array([[f[0][0] - 1, f[1][0] - 1, f[2][0] - 1] for f in F])
    ti = np.array([[f[0][1] - 1, f[1][1] - 1, f[2][1] - 1] for f in F])
    if len(VT):
        uv = VT[ti].mean(axis=1)
        cols = sample_palette(img, uv)
    else:
        cols = np.tile(np.array([208, 206, 198], dtype=np.uint8), (len(vi), 1))
    if recolor_red is not None:
        red = (cols[:, 0] > 140) & (cols[:, 1] < 120) & (cols[:, 2] < 100)
        cols = cols.copy(); cols[red] = recolor_red
    verts = V.copy()
    verts[:, 0] -= (verts[:, 0].min() + verts[:, 0].max()) / 2; verts[:, 2] -= (verts[:, 2].min() + verts[:, 2].max()) / 2
    verts[:, 1] -= verts[:, 1].min(); verts *= scale
    verts, tris = flip_x_tris(verts, vi)
    # drop faces pointing straight down (never visible from a camera above ground)
    a = verts[tris[:, 1]] - verts[tris[:, 0]]; b = verts[tris[:, 2]] - verts[tris[:, 0]]
    nrm = np.cross(a, b); ln = np.linalg.norm(nrm, axis=1) + 1e-12; ny = nrm[:, 1] / ln
    keep = ~((ny < -0.9) & (verts[tris].mean(axis=1)[:, 1] < 0.3))
    tris, cols = tris[keep], cols[keep]
    files = []; stats = []
    for li, (cell, _) in enumerate(lods):
        v2, t2, c2 = cluster(verts, tris, cols, cell * scale)
        v2, t2 = compact(v2, t2)
        # after clustering keep outward winding consistent (cluster keeps order), fine.
        fn = f'b_{out_id}_{li}.smesh'
        mn, mx, nt = write_smesh(f'{OUT}/{fn}', [('Main', np.zeros(3), v2, t2, c2)])
        files.append(fn); stats.append(nt)
    manifest['buildings'][out_id] = {'files': files, 'min': mn.tolist(), 'max': mx.tolist(), 'tris': stats}
    print('building', out_id, 'tris per lod', stats, 'size', np.round(mx - mn, 1).tolist())

# ------------------------------------------------------------ props (trees)
def make_tree(out_id, trunk=(110, 78, 55), leaf=(52, 128, 62), h=7.0, r=2.4, sides=6, tiers=2):
    verts = []; tris = []; cols = []
    def add_prism(y0, y1, r0, r1, col):
        base = len(verts)
        for k in range(sides):
            a = 2 * math.pi * k / sides
            verts.append([r0 * math.cos(a), y0, r0 * math.sin(a)]); verts.append([r1 * math.cos(a), y1, r1 * math.sin(a)])
        for k in range(sides):
            a0, a1 = base + 2 * k, base + 2 * ((k + 1) % sides)
            tris.append([a0, a1, a0 + 1]); cols.append(col); tris.append([a1, a1 + 1, a0 + 1]); cols.append(col)
    def add_cone(y0, y1, rr, col):
        base = len(verts); verts.append([0, y1, 0])
        for k in range(sides):
            a = 2 * math.pi * k / sides; verts.append([rr * math.cos(a), y0, rr * math.sin(a)])
        for k in range(sides):
            tris.append([base, base + 1 + k, base + 1 + (k + 1) % sides]); cols.append(col)
    add_prism(0, h * 0.35, 0.28, 0.2, list(trunk))
    for t in range(tiers):
        y0 = h * (0.25 + 0.22 * t); add_cone(y0, y0 + h * 0.55, r * (1 - 0.25 * t), [int(c * (1 - 0.08 * t)) for c in leaf])
    v = np.array(verts); t = np.array(tris); c = np.array(cols, dtype=np.uint8)
    # winding: flip so normals point outward in the left-handed game space
    t = t[:, [0, 2, 1]]
    mn, mx, nt = write_smesh(f'{OUT}/p_{out_id}.smesh', [('Main', np.zeros(3), v, t, c)])
    manifest.setdefault('props', {})[out_id] = {'file': f'p_{out_id}.smesh', 'min': mn.tolist(), 'max': mx.tolist(), 'tris': nt}

# ------------------------------------------------------------ characters
ANIMS = ['Idle', 'Walk', 'Run', 'Jump', 'Punch', 'RecieveHit', 'SitDown', 'Death', 'Victory']
ANIM_LOOP = {'Idle': 1, 'Walk': 1, 'Run': 1}
FPS = 15.0
skel_written = False

def slerp(a, b, t):
    d = float(np.dot(a, b))
    if d < 0: b = -b; d = -d
    if d > 0.9995:
        r = a + (b - a) * t
    else:
        th = math.acos(d); r = (math.sin((1 - t) * th) * a + math.sin(t * th) * b) / math.sin(th)
    return r / np.linalg.norm(r)

def sample_channel(times, vals, t, is_rot):
    if t <= times[0]: return vals[0]
    if t >= times[-1]: return vals[-1]
    i = int(np.searchsorted(times, t, side='right') - 1)
    f = (t - times[i]) / (times[i + 1] - times[i])
    return slerp(vals[i], vals[i + 1], f) if is_rot else vals[i] * (1 - f) + vals[i + 1] * f

def convert_character(name, out_id, cell=0.0):
    global skel_written
    j, bufs = load_gltf(f'{SRC}/Ultimate Animated Character Pack - Nov 2019/glTF/{name}.gltf')
    skin = j['skins'][0]; joints = skin['joints']; jc = len(joints)
    jidx = {n: i for i, n in enumerate(joints)}
    nodes = j['nodes']
    parent_of = {}
    for ni, n in enumerate(nodes):
        for c in n.get('children', []): parent_of[c] = ni
    def world(ni):
        t, q, s = node_trs(nodes[ni]); m = trs(t, q, s)
        return world(parent_of[ni]) @ m if ni in parent_of else m
    mesh_node = [i for i, n in enumerate(nodes) if 'skin' in n][0]
    root_parent = None
    parents = []
    for ji in joints:
        p = parent_of.get(ji)
        parents.append(jidx[p] if p in jidx else -1)
        if p not in jidx: root_parent = p
    root_m = np.linalg.inv(world(mesh_node)) @ world(root_parent)
    ibm = accessor(j, bufs, skin['inverseBindMatrices']).reshape(jc, 4, 4).transpose(0, 2, 1)  # glTF is column-major
    # bind-pose check: root * chain * ibm ~ identity
    def bind_world(k):
        t, q, s = node_trs(nodes[joints[k]]); m = trs(t, q, s)
        return (bind_world(parents[k]) if parents[k] >= 0 else root_m) @ m
    print(f'character {out_id}: joints {jc}')
    # mirror
    root_m_r = RX @ root_m @ RX; ibm_r = np.stack([RX @ ibm[k] @ RX for k in range(jc)])
    # mesh
    P, J, W, T, TM = [], [], [], [], []
    base = 0
    for pr in j['meshes'][nodes[mesh_node]['mesh']]['primitives']:
        pos = accessor(j, bufs, pr['attributes']['POSITION']); jj = accessor(j, bufs, pr['attributes']['JOINTS_0']).astype(int)
        ww = accessor(j, bufs, pr['attributes']['WEIGHTS_0']); idx = accessor(j, bufs, pr['indices']).reshape(-1, 3)
        order = np.argsort(-ww, axis=1)[:, :2]
        j0 = np.take_along_axis(jj, order[:, :1], 1)[:, 0]; j1 = np.take_along_axis(jj, order[:, 1:2], 1)[:, 0]
        w0 = np.take_along_axis(ww, order[:, :1], 1)[:, 0]; w1 = np.take_along_axis(ww, order[:, 1:2], 1)[:, 0]
        tot = np.maximum(w0 + w1, 1e-6); w0n = w0 / tot
        P.append(pos); J.append(np.stack([j0, j1], 1)); W.append(w0n)
        T.append(idx + base); TM.append(np.full(len(idx), pr['material'])); base += len(pos)
    P = np.concatenate(P); J = np.concatenate(J); W = np.concatenate(W); T = np.concatenate(T); TM = np.concatenate(TM)
    P[:, 0] *= -1; T = T[:, [0, 2, 1]]
    # weld duplicates (same position + skin)
    key = np.concatenate([np.round(P * 1e4).astype(np.int64), J, np.round(W * 64).astype(np.int64)[:, None]], axis=1)
    _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    inv = inv.reshape(-1)
    P2, J2, W2 = P[first], J[first], W[first]; T2 = inv[T]
    if cell > 0:   # optional clustering (weights/joints taken from the first vertex of a cluster)
        q = np.floor(P2 / cell).astype(np.int64); _, fi, iv, cnt = np.unique(q, axis=0, return_index=True, return_inverse=True, return_counts=True)
        iv = iv.reshape(-1)
        nv = np.zeros((cnt.size, 3)); np.add.at(nv, iv, P2); nv /= cnt[:, None]
        T3 = iv[T2]; ok = (T3[:, 0] != T3[:, 1]) & (T3[:, 1] != T3[:, 2]) & (T3[:, 0] != T3[:, 2])
        P2, J2, W2, T2, TM = nv, J2[fi], W2[fi], T3[ok], TM[ok]
        P2, T2 = compact(P2, T2) if False else (P2, T2)
    mats = j['materials']
    mat_cols = [rgb8(m['pbrMetallicRoughness'].get('baseColorFactor', [0.8, 0.8, 0.8, 1])) for m in mats]
    mat_names = [m['name'] for m in mats]
    mat_cols = [[214, 160, 122] if n == 'Skin' else c for n, c in zip(mat_names, mat_cols)]  # pack ships Skin as near-black; default tone, overridable at runtime
    # skin color fix: pack uses very dark linear values; keep as authored
    b = b'CMSH' + struct.pack('<5I', 1, len(P2), len(T2), jc, len(mats))
    b += np.asarray(P2, '<f4').tobytes() + J2[:, 0].astype('u1').tobytes() + J2[:, 1].astype('u1').tobytes() + np.round(W2 * 255).astype('u1').tobytes()
    b += np.asarray(T2, '<u2').tobytes() + TM.astype('u1').tobytes()
    for nm, c in zip(mat_names, mat_cols): b += w_str(nm) + bytes(c)
    b += np.asarray(ibm_r[:, :3, :], '<f4').reshape(-1).tobytes()
    open(f'{OUT}/c_{out_id}.cmesh', 'wb').write(b)
    manifest['characters'][out_id] = {'file': f'c_{out_id}.cmesh', 'tris': int(len(T2)), 'verts': int(len(P2)), 'materials': mat_names,
                                      'height': float(P2[:, 1].max() - P2[:, 1].min())}
    print(f'  verts {len(P2)} tris {len(T2)} height {P2[:,1].max()-P2[:,1].min():.2f} mats {mat_names}')
    if skel_written: return
    skel_written = True
    # animations
    names = [nodes[k]['name'] for k in joints]
    out = b'ANIM' + struct.pack('<3I', 1, jc, 0)
    anims = {a['name']: a for a in j['animations']}
    body = b''
    cnt = 0
    for an in ANIMS:
        a = anims[an]; ch = {}
        dur = 0
        for c in a['channels']:
            s = a['samplers'][c['sampler']]
            times = accessor(j, bufs, s['input']); vals = accessor(j, bufs, s['output'])
            ch[(c['target']['node'], c['target']['path'])] = (times, vals); dur = max(dur, float(times.max()))
        nf = max(2, int(round(dur * FPS)) + 1)
        data = np.zeros((nf, jc, 7), dtype=np.float32)
        prev = [None] * jc
        for f in range(nf):
            t = min(dur, f / FPS)
            for k, ni in enumerate(joints):
                bt, bq, bs = node_trs(nodes[ni])
                tr = sample_channel(*ch[(ni, 'translation')], t, False) if (ni, 'translation') in ch else bt
                q = sample_channel(*ch[(ni, 'rotation')], t, True) if (ni, 'rotation') in ch else bq
                if prev[k] is not None and np.dot(prev[k], q) < 0: q = -q
                prev[k] = q
                # mirror on X
                data[f, k] = [-tr[0], tr[1], tr[2], q[0], -q[1], -q[2], q[3]]
        body += w_str(an) + struct.pack('<fIfB', dur, nf, FPS, ANIM_LOOP.get(an, 0)) + data.tobytes()
        cnt += 1
    out = b'ANIM' + struct.pack('<3I', 1, jc, cnt)
    for n in names: out += w_str(n)
    out += struct.pack(f'<{jc}h', *parents) + np.asarray(root_m_r[:3, :], '<f4').tobytes()
    bt = np.array([[-node_trs(nodes[k])[0][0], node_trs(nodes[k])[0][1], node_trs(nodes[k])[0][2]] for k in joints], dtype='<f4')
    bq = np.array([[node_trs(nodes[k])[1][0], -node_trs(nodes[k])[1][1], -node_trs(nodes[k])[1][2], node_trs(nodes[k])[1][3]] for k in joints], dtype='<f4')
    out += bt.tobytes() + bq.tobytes() + body
    open(f'{OUT}/char.anim', 'wb').write(out)
    print('  anims', ANIMS, 'bytes', len(out))

CELL = {'suitm': 0.1, 'casual2f': 0.1, 'oldm': 0.1, 'workerf': 0.1}

if __name__ == '__main__':
    for nm, oid, rc in [('Family_Car', 'compact', None), ('Taxi', 'sedan', None), ('Pickup_Truck', 'gromson', {(219, 43, 38): (46, 125, 50)}),
                        ('Sports_Car', 'yellwo', None), ('Police_Car', 'police', None), ('Ambulance', 'ambulance', None),
                        ('Delivery_Truck', 'truck', None), ('Motorcycle', 'bike', None)]:
        convert_vehicle(nm, oid, rc)
    for nm, oid, sc, lods in [('Bank', 'bank', 7.0, [(0.07, 0), (0.14, 0)]),
                              ('Flat', 'hq', 7.0, [(0.03, 0), (0.1, 0)]),
                              ('Hospital', 'hospital', 5.5, [(0.03, 0), (0.1, 0)]),
                              ('Flat', 'flat1', 7.0, [(0.03, 0), (0.1, 0)]), ('Flat2', 'flat2', 7.0, [(0.03, 0), (0.1, 0)]),
                              ('Shop', 'shop', 6.5, [(0.03, 0), (0.1, 0)]),
                              ('House', 'house1', 9.0, [(0.03, 0), (0.1, 0)]), ('House2', 'house2', 9.0, [(0.03, 0), (0.1, 0)]),
                              ('House3', 'house3', 9.0, [(0.03, 0), (0.1, 0)]), ('House4', 'house4', 8.0, [(0.03, 0), (0.1, 0)]),
                              ('House5', 'house5', 7.5, [(0.03, 0), (0.1, 0)])]:
        convert_building(nm, oid, sc, lods, recolor_red=(46, 125, 50) if oid == 'hq' else None)
    make_tree('pine'); make_tree('round', leaf=(70, 150, 60), h=6.0, r=2.6, sides=7, tiers=1)
    for nm, oid in [('Casual2_Male', 'casual2m'), ('Worker_Male', 'workerm'), ('BlueSoldier_Male', 'copm'),
                    ('Suit_Male', 'suitm'), ('Casual2_Female', 'casual2f'), ('OldClassy_Male', 'oldm'),
                    ('Worker_Female', 'workerf')]:
        convert_character(nm, oid, cell=CELL.get(oid, 0.0))
    json.dump(manifest, open(f'{OUT}/manifest.json', 'w'), indent=1)
    tot = sum(os.path.getsize(f'{OUT}/{f}') for f in os.listdir(OUT)); print('total bytes', tot)
