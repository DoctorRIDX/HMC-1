import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Binary model formats are produced by tool/convert_models.py.
class _Rd {
  _Rd(this.d);
  final ByteData d;
  int o = 0;

  int u8() => d.getUint8(o++);
  int u32() {
    final v = d.getUint32(o, Endian.little);
    o += 4;
    return v;
  }

  double f32() {
    final v = d.getFloat32(o, Endian.little);
    o += 4;
    return v;
  }

  String str() {
    final n = u8();
    final s = String.fromCharCodes(d.buffer.asUint8List(d.offsetInBytes + o, n));
    o += n;
    return s;
  }

  Float32List f32s(int n) {
    final r = Float32List(n);
    for (var i = 0; i < n; i++) {
      r[i] = d.getFloat32(o, Endian.little);
      o += 4;
    }
    return r;
  }

  Float64List f64s(int n) {
    final r = Float64List(n);
    for (var i = 0; i < n; i++) {
      r[i] = d.getFloat32(o, Endian.little);
      o += 4;
    }
    return r;
  }

  Uint16List u16s(int n) {
    final r = Uint16List(n);
    for (var i = 0; i < n; i++) {
      r[i] = d.getUint16(o, Endian.little);
      o += 2;
    }
    return r;
  }

  Uint8List u8s(int n) {
    final r = Uint8List.fromList(d.buffer.asUint8List(d.offsetInBytes + o, n));
    o += n;
    return r;
  }

  List<int> i16s(int n) {
    final r = <int>[];
    for (var i = 0; i < n; i++) {
      r.add(d.getInt16(o, Endian.little));
      o += 2;
    }
    return r;
  }
}

class MeshPart {
  MeshPart(this.name, this.px, this.py, this.pz, this.vc, this.tc, this.verts, this.tris, this.cols);
  final String name;
  final double px, py, pz; // pivot / offset of the part inside its model
  final int vc, tc;
  final Float32List verts;
  final Uint16List tris;
  final Uint8List cols; // rgb per triangle

  /// Unit cube (1 x 1 x 1, base on y = 0, centered on x/z). Scale it with a matrix.
  factory MeshPart.unitBox() {
    final v = Float32List.fromList([
      -.5, 0, -.5, .5, 0, -.5, .5, 0, .5, -.5, 0, .5, //
      -.5, 1, -.5, .5, 1, -.5, .5, 1, .5, -.5, 1, .5,
    ]);
    // Winding chosen so (b-a)x(c-a) points outward in the game's left-handed space.
    final t = Uint16List.fromList([
      0, 1, 2, 0, 2, 3, // bottom
      4, 6, 5, 4, 7, 6, // top
      0, 4, 5, 0, 5, 1, // -z
      1, 5, 6, 1, 6, 2, // +x
      2, 6, 7, 2, 7, 3, // +z
      3, 7, 4, 3, 4, 0, // -x
    ]);
    return MeshPart('Box', 0, 0, 0, 8, 12, v, t, Uint8List(36));
  }
}

class StaticModel {
  StaticModel(this.parts, this.min, this.max);
  final List<MeshPart> parts;
  final Float32List min, max; // 3 floats each
  int get tris => parts.fold(0, (a, p) => a + p.tc);
  MeshPart? part(String n) {
    for (final p in parts) {
      if (p.name == n) return p;
    }
    return null;
  }
}

class CharMesh {
  CharMesh(this.vc, this.tc, this.jc, this.verts, this.j0, this.j1, this.w0, this.tris, this.triMat,
      this.matNames, this.matRgb, this.ibm);
  final int vc, tc, jc;
  final Float32List verts;
  final Uint8List j0, j1, w0, triMat;
  final Uint16List tris;
  final List<String> matNames;
  final Uint8List matRgb; // default rgb per material
  final Float64List ibm; // jc * 12

  /// Copy of the default material colors with overrides (name -> 0xRRGGBB).
  Uint8List buildRgb(Map<String, int> tint) {
    final o = Uint8List.fromList(matRgb);
    for (var i = 0; i < matNames.length; i++) {
      final c = tint[matNames[i]];
      if (c != null) {
        o[i * 3] = (c >> 16) & 255;
        o[i * 3 + 1] = (c >> 8) & 255;
        o[i * 3 + 2] = c & 255;
      }
    }
    return o;
  }
}

class AnimClip {
  AnimClip(this.name, this.duration, this.frames, this.fps, this.loop, this.jc, this.data);
  final String name;
  final double duration, fps;
  final int frames, jc;
  final bool loop;
  final Float32List data; // frames * jc * 7  (tx ty tz qx qy qz qw)
}

class Skeleton {
  Skeleton(this.names, this.parents, this.root, this.clips);
  final List<String> names;
  final List<int> parents;
  final Float64List root; // 12
  final Map<String, AnimClip> clips;
  int get jc => names.length;
  int indexOf(String n) => names.indexOf(n);
}

class ModelLibrary {
  ModelLibrary(this.vehicles, this.buildings, this.props, this.chars, this.skeleton);
  final Map<String, StaticModel> vehicles;
  final Map<String, List<StaticModel>> buildings; // LOD0, LOD1
  final Map<String, StaticModel> props;
  final Map<String, CharMesh> chars;
  final Skeleton skeleton;
  final MeshPart box = MeshPart.unitBox();

  static StaticModel _static(ByteData bd) {
    final r = _Rd(bd)..o = 4;
    r.u32();
    final n = r.u32();
    final b = r.f32s(6);
    final parts = <MeshPart>[];
    for (var i = 0; i < n; i++) {
      final name = r.str();
      final px = r.f32(), py = r.f32(), pz = r.f32();
      final vc = r.u32(), tc = r.u32();
      final v = r.f32s(vc * 3);
      final t = r.u16s(tc * 3);
      final c = r.u8s(tc * 3);
      parts.add(MeshPart(name, px, py, pz, vc, tc, v, t, c));
    }
    return StaticModel(parts, Float32List.fromList(b.sublist(0, 3)), Float32List.fromList(b.sublist(3, 6)));
  }

  static CharMesh _char(ByteData bd) {
    final r = _Rd(bd)..o = 4;
    r.u32();
    final vc = r.u32(), tc = r.u32(), jc = r.u32(), mc = r.u32();
    final v = r.f32s(vc * 3);
    final j0 = r.u8s(vc), j1 = r.u8s(vc), w0 = r.u8s(vc);
    final t = r.u16s(tc * 3);
    final tm = r.u8s(tc);
    final names = <String>[];
    final rgb = Uint8List(mc * 3);
    for (var i = 0; i < mc; i++) {
      names.add(r.str());
      rgb[i * 3] = r.u8();
      rgb[i * 3 + 1] = r.u8();
      rgb[i * 3 + 2] = r.u8();
    }
    final ibm = r.f64s(jc * 12);
    return CharMesh(vc, tc, jc, v, j0, j1, w0, t, tm, names, rgb, ibm);
  }

  static Skeleton _skeleton(ByteData bd) {
    final r = _Rd(bd)..o = 4;
    r.u32();
    final jc = r.u32(), na = r.u32();
    final names = [for (var i = 0; i < jc; i++) r.str()];
    final parents = r.i16s(jc);
    final root = r.f64s(12);
    r.f32s(jc * 3); // bind T (unused at runtime)
    r.f32s(jc * 4); // bind Q (unused at runtime)
    final clips = <String, AnimClip>{};
    for (var i = 0; i < na; i++) {
      final name = r.str();
      final dur = r.f32();
      final nf = r.u32();
      final fps = r.f32();
      final loop = r.u8() == 1;
      clips[name] = AnimClip(name, dur, nf, fps, loop, jc, r.f32s(nf * jc * 7));
    }
    for (var k = 0; k < jc; k++) {
      if (parents[k] >= k) throw StateError('joints must be ordered parent-first');
    }
    return Skeleton(names, parents, root, clips);
  }

  static Future<ModelLibrary> load() async {
    Future<ByteData> bd(String f) => rootBundle.load('assets/models/$f');
    final man = jsonDecode(await rootBundle.loadString('assets/models/manifest.json')) as Map<String, dynamic>;
    final vehicles = <String, StaticModel>{};
    for (final e in (man['vehicles'] as Map<String, dynamic>).entries) {
      vehicles[e.key] = _static(await bd((e.value as Map)['file'] as String));
    }
    final buildings = <String, List<StaticModel>>{};
    for (final e in (man['buildings'] as Map<String, dynamic>).entries) {
      buildings[e.key] = [
        for (final f in (e.value as Map)['files'] as List) _static(await bd(f as String))
      ];
    }
    final props = <String, StaticModel>{};
    for (final e in (man['props'] as Map<String, dynamic>).entries) {
      props[e.key] = _static(await bd((e.value as Map)['file'] as String));
    }
    final chars = <String, CharMesh>{};
    for (final e in (man['characters'] as Map<String, dynamic>).entries) {
      chars[e.key] = _char(await bd((e.value as Map)['file'] as String));
    }
    final sk = _skeleton(await bd(man['anims'] as String));
    return ModelLibrary(vehicles, buildings, props, chars, sk);
  }
}
