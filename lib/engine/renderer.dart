import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../game/entities.dart';
import '../game/game_controller.dart';
import '../game/world.dart';
import 'assets.dart';
import 'math34.dart';
import 'skeleton.dart';

class _Draw {
  _Draw(this.dist, this.tris, this.fn);
  final double dist;
  final int tris;
  final void Function() fn;
}

/// Software 3D renderer. Triangles are transformed, lit (flat shading with a
/// moving sun, sky/ground ambient and distance fog), depth-sorted back to front
/// and submitted as ONE Canvas.drawVertices call per frame. Shadows are
/// projected onto the ground along the sun direction.
class WorldRenderer {
  WorldRenderer(this.lib)
      : _pose = Pose(lib.skeleton.jc),
        _jHead = lib.skeleton.indexOf('Head'),
        _jUpR = lib.skeleton.indexOf('UpperArm.R'),
        _jLoR = lib.skeleton.indexOf('LowerArm.R') {
    final r = Random(3);
    for (var i = 0; i < 70; i++) {
      final a = r.nextDouble() * 2 * pi, e = 0.15 + r.nextDouble() * 1.3;
      _stars.add([cos(a) * cos(e), sin(e), sin(a) * cos(e), 0.4 + r.nextDouble() * 0.6]);
    }
    for (final p in World.placements) {
      _rects.add(World.footprint(p));
    }
    final bones = [
      ['Hips', 'Torso'], ['Torso', 'Head'], ['Torso', 'UpperArm.L'], ['UpperArm.L', 'LowerArm.L'],
      ['LowerArm.L', 'Fist.L'], ['Torso', 'UpperArm.R'], ['UpperArm.R', 'LowerArm.R'],
      ['LowerArm.R', 'Fist.R'], ['Hips', 'UpperLeg.L'], ['UpperLeg.L', 'LowerLeg.L'],
      ['LowerLeg.L', 'Foot.L'], ['Hips', 'UpperLeg.R'], ['UpperLeg.R', 'LowerLeg.R'], ['LowerLeg.R', 'Foot.R'],
    ];
    for (final b in bones) {
      _bones.add([lib.skeleton.indexOf(b[0]), lib.skeleton.indexOf(b[1])]);
    }
  }

  final ModelLibrary lib;
  final Pose _pose;
  final int _jHead, _jUpR, _jLoR;
  final List<List<double>> _stars = [];
  final List<Rect2> _rects = [];
  final List<List<int>> _bones = [];
  final Map<String, Uint8List> _rgbCache = {};

  static const int maxItemTris = 8000, maxItemVerts = 9000, maxOutTris = 40000;
  final Float32List vX = Float32List(maxItemVerts), vY = Float32List(maxItemVerts), vZ = Float32List(maxItemVerts);
  final Float32List tScr = Float32List(maxItemTris * 6), tDep = Float32List(maxItemTris);
  final Int32List tCol = Int32List(maxItemTris);
  final Int64List keys = Int64List(maxItemTris);
  final Float32List outPos = Float32List(maxOutTris * 6);
  final Int32List outCol = Int32List(maxOutTris * 3);
  int outTris = 0;

  // camera
  double camX = 0, camY = 0, camZ = 0, rx = 1, ry = 0, rz = 0, ux = 0, uy = 1, uz = 0, fx = 0, fy = 0, fz = 1;
  double focal = 1, midX = 0, midY = 0, sw = 1, sh = 1;
  final Float64List view = Float64List(12);
  final Float64List _m1 = Float64List(12), _m2 = Float64List(12), _m3 = Float64List(12), _m4 = Float64List(12);
  final Float64List _mv = Float64List(12);
  final Float64List _skinMv = Float64List(24 * 12);

  // lighting snapshot
  double sunX = 0, sunY = 1, sunZ = 0;
  double sR = .5, sG = .5, sB = .5, gR = .3, gG = .3, gB = .3, cR = 1, cG = 1, cB = 1;
  double fogR = 200, fogG = 210, fogB = 230, fogStart = 50, fogEnd = 150;

  // adaptive quality (frame-time governor)
  double scale = 1;
  double _ema = 16;

  // ------------------------------------------------------------------ core

  void _emit(Uint16List tris, int tc, Uint8List? cols, Uint8List? triMat, Uint8List? matRgb, int flat) {
    final foc = focal, mx = midX, my = midY, w = sw, h = sh;
    final fogS = fogStart, fogSpan = max(1.0, fogEnd - fogStart);
    var n = 0;
    for (var t = 0; t < tc; t++) {
      if (n >= maxItemTris) break;
      final i0 = tris[t * 3], i1 = tris[t * 3 + 1], i2 = tris[t * 3 + 2];
      final z0 = vZ[i0], z1 = vZ[i1], z2 = vZ[i2];
      if (z0 < 0.35 || z1 < 0.35 || z2 < 0.35) continue;
      final x0 = vX[i0], y0 = vY[i0], x1 = vX[i1], y1 = vY[i1], x2 = vX[i2], y2 = vY[i2];
      final ax = x1 - x0, ay = y1 - y0, az = z1 - z0, bx = x2 - x0, by = y2 - y0, bz = z2 - z0;
      var nx = ay * bz - az * by, ny = az * bx - ax * bz, nz = ax * by - ay * bx;
      if (nx * x0 + ny * y0 + nz * z0 >= 0) continue; // back face
      final ln = sqrt(nx * nx + ny * ny + nz * nz);
      if (ln < 1e-12) continue;
      nx /= ln;
      ny /= ln;
      nz /= ln;
      final k0 = foc / z0, k1 = foc / z1, k2 = foc / z2;
      final s0x = mx + x0 * k0, s0y = my - y0 * k0;
      final s1x = mx + x1 * k1, s1y = my - y1 * k1;
      final s2x = mx + x2 * k2, s2y = my - y2 * k2;
      if ((s0x < 0 && s1x < 0 && s2x < 0) || (s0x > w && s1x > w && s2x > w)) continue;
      if ((s0y < 0 && s1y < 0 && s2y < 0) || (s0y > h && s1y > h && s2y > h)) continue;
      final wx = nx * rx + ny * ux + nz * fx;
      final wy = nx * ry + ny * uy + nz * fy;
      final wz = nx * rz + ny * uz + nz * fz;
      var nd = wx * sunX + wy * sunY + wz * sunZ;
      if (nd < 0) nd = 0;
      final hemi = 0.5 + 0.5 * wy;
      int br, bg, bb;
      if (flat >= 0) {
        br = (flat >> 16) & 255;
        bg = (flat >> 8) & 255;
        bb = flat & 255;
      } else if (triMat != null) {
        final m = triMat[t] * 3;
        br = matRgb![m];
        bg = matRgb[m + 1];
        bb = matRgb[m + 2];
      } else {
        br = cols![t * 3];
        bg = cols[t * 3 + 1];
        bb = cols[t * 3 + 2];
      }
      var r = br * (gR + (sR - gR) * hemi + cR * nd);
      var g = bg * (gG + (sG - gG) * hemi + cG * nd);
      var b = bb * (gB + (sB - gB) * hemi + cB * nd);
      final depth = (z0 + z1 + z2) / 3;
      if (depth > fogS) {
        var f = (depth - fogS) / fogSpan;
        if (f > 1) f = 1;
        f *= 0.92;
        r += (fogR - r) * f;
        g += (fogG - g) * f;
        b += (fogB - b) * f;
      }
      final ri = r > 255 ? 255 : (r < 0 ? 0 : r.toInt());
      final gi = g > 255 ? 255 : (g < 0 ? 0 : g.toInt());
      final bi = b > 255 ? 255 : (b < 0 ? 0 : b.toInt());
      tCol[n] = 0xFF000000 | (ri << 16) | (gi << 8) | bi;
      final o = n * 6;
      tScr[o] = s0x;
      tScr[o + 1] = s0y;
      tScr[o + 2] = s1x;
      tScr[o + 3] = s1y;
      tScr[o + 4] = s2x;
      tScr[o + 5] = s2y;
      tDep[n] = depth;
      n++;
    }
    if (n == 0) return;
    for (var i = 0; i < n; i++) {
      keys[i] = (((1e5 - tDep[i]) * 32).toInt() << 20) | i;
    }
    Int64List.sublistView(keys, 0, n).sort();
    for (var i = 0; i < n; i++) {
      if (outTris >= maxOutTris) return;
      final slot = keys[i] & 0xFFFFF;
      final so = slot * 6, oo = outTris * 6;
      outPos[oo] = tScr[so];
      outPos[oo + 1] = tScr[so + 1];
      outPos[oo + 2] = tScr[so + 2];
      outPos[oo + 3] = tScr[so + 3];
      outPos[oo + 4] = tScr[so + 4];
      outPos[oo + 5] = tScr[so + 5];
      final c = tCol[slot], co = outTris * 3;
      outCol[co] = c;
      outCol[co + 1] = c;
      outCol[co + 2] = c;
      outTris++;
    }
  }

  void _rigid(MeshPart p, Float64List model, {int flat = -1}) {
    if (p.vc > maxItemVerts) return;
    m34Mul(view, 0, model, 0, _mv, 0);
    final m0 = _mv[0], m1 = _mv[1], m2 = _mv[2], m3 = _mv[3];
    final m4 = _mv[4], m5 = _mv[5], m6 = _mv[6], m7 = _mv[7];
    final m8 = _mv[8], m9 = _mv[9], m10 = _mv[10], m11 = _mv[11];
    final v = p.verts;
    for (var i = 0, j = 0; i < p.vc; i++, j += 3) {
      final x = v[j], y = v[j + 1], z = v[j + 2];
      vX[i] = m0 * x + m1 * y + m2 * z + m3;
      vY[i] = m4 * x + m5 * y + m6 * z + m7;
      vZ[i] = m8 * x + m9 * y + m10 * z + m11;
    }
    _emit(p.tris, p.tc, p.cols, null, null, flat);
  }

  void _skinned(CharMesh c, Float64List model, Uint8List rgb) {
    if (c.vc > maxItemVerts) return;
    m34Mul(view, 0, model, 0, _mv, 0);
    for (var k = 0; k < c.jc; k++) {
      m34Mul(_mv, 0, _pose.skin, k * 12, _skinMv, k * 12);
    }
    final S = _skinMv, v = c.verts;
    for (var i = 0, j = 0; i < c.vc; i++, j += 3) {
      final x = v[j], y = v[j + 1], z = v[j + 2];
      final a = c.j0[i] * 12, b = c.j1[i] * 12;
      final w = c.w0[i] / 255.0, iw = 1 - w;
      vX[i] = (S[a] * x + S[a + 1] * y + S[a + 2] * z + S[a + 3]) * w +
          (S[b] * x + S[b + 1] * y + S[b + 2] * z + S[b + 3]) * iw;
      vY[i] = (S[a + 4] * x + S[a + 5] * y + S[a + 6] * z + S[a + 7]) * w +
          (S[b + 4] * x + S[b + 5] * y + S[b + 6] * z + S[b + 7]) * iw;
      vZ[i] = (S[a + 8] * x + S[a + 9] * y + S[a + 10] * z + S[a + 11]) * w +
          (S[b + 8] * x + S[b + 9] * y + S[b + 10] * z + S[b + 11]) * iw;
    }
    _emit(c.tris, c.tc, null, c.triMat, rgb, -1);
  }

  // -------------------------------------------------------------- helpers

  bool _visible(double x, double y, double z, double radius) {
    final dx = x - camX, dy = y - camY, dz = z - camZ;
    final vz = dx * fx + dy * fy + dz * fz;
    if (vz < -radius) return false;
    final vx = dx * rx + dy * ry + dz * rz;
    return vx.abs() <= (vz + radius) * 1.45 + radius;
  }

  double _rectDist(Rect2 r) {
    final dx = max(0.0, max(r.x0 - camX, camX - r.x1));
    final dz = max(0.0, max(r.z0 - camZ, camZ - r.z1));
    return sqrt(dx * dx + dz * dz);
  }

  Uint8List _rgb(String key, CharMesh m, Map<String, int> tint) =>
      _rgbCache.putIfAbsent(key, () => m.buildRgb(tint));

  // shadows --------------------------------------------------------------

  ui.Path? _shadow;

  /// Projects a world point to the ground along the sun direction.
  List<double> _gp(double x, double y, double z) {
    final k = 1 / max(sunY, 0.25);
    return [x - sunX * k * y, z - sunZ * k * y];
  }

  void _addGroundPoly(List<double> p) {
    // p = x,z pairs on y = 0.03; clipped to the near plane, orientation normalized.
    final pts = <List<double>>[];
    final n = p.length ~/ 2;
    final vs = <List<double>>[];
    for (var i = 0; i < n; i++) {
      final dx = p[i * 2] - camX, dy = 0.03 - camY, dz = p[i * 2 + 1] - camZ;
      vs.add([dx * rx + dy * ry + dz * rz, dx * ux + dy * uy + dz * uz, dx * fx + dy * fy + dz * fz]);
    }
    for (var i = 0; i < n; i++) {
      final a = vs[i], b = vs[(i + 1) % n];
      final ai = a[2] >= 0.3, bi = b[2] >= 0.3;
      if (ai) pts.add(a);
      if (ai != bi) {
        final t = (0.3 - a[2]) / (b[2] - a[2]);
        pts.add([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, 0.3]);
      }
    }
    if (pts.length < 3) return;
    final sp = [for (final q in pts) Offset(midX + q[0] / q[2] * focal, midY - q[1] / q[2] * focal)];
    var area = 0.0;
    for (var i = 0; i < sp.length; i++) {
      final a = sp[i], b = sp[(i + 1) % sp.length];
      area += a.dx * b.dy - b.dx * a.dy;
    }
    final list = area < 0 ? sp.reversed.toList() : sp;
    _shadow!.addPolygon(list, true);
  }

  List<double> _hull(List<double> p) {
    final pts = <List<double>>[for (var i = 0; i < p.length; i += 2) [p[i], p[i + 1]]];
    pts.sort((a, b) => a[0] != b[0] ? a[0].compareTo(b[0]) : a[1].compareTo(b[1]));
    double cross(List<double> o, List<double> a, List<double> b) =>
        (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
    final lo = <List<double>>[], up = <List<double>>[];
    for (final q in pts) {
      while (lo.length >= 2 && cross(lo[lo.length - 2], lo.last, q) <= 0) {
        lo.removeLast();
      }
      lo.add(q);
    }
    for (final q in pts.reversed) {
      while (up.length >= 2 && cross(up[up.length - 2], up.last, q) <= 0) {
        up.removeLast();
      }
      up.add(q);
    }
    lo.removeLast();
    up.removeLast();
    return [for (final q in [...lo, ...up]) ...q];
  }

  void _boxShadow(double cx, double cz, double hw, double hl, double yaw, double h, int mode) {
    if (mode == 0) {
      _blob(cx, cz, max(hw, hl) * 0.9, max(hw, hl) * 0.9);
      return;
    }
    final s = sin(yaw), c = cos(yaw);
    final pts = <double>[];
    for (final sr in const [-1.0, 1.0]) {
      for (final sf in const [-1.0, 1.0]) {
        final x = cx + c * hw * sr + s * hl * sf, z = cz - s * hw * sr + c * hl * sf;
        pts.addAll([x, z]);
        pts.addAll(_gp(x, h, z));
      }
    }
    _addGroundPoly(_hull(pts));
  }

  void _blob(double x, double z, double rx_, double rz_) {
    final pts = <double>[];
    for (var i = 0; i < 10; i++) {
      final a = i / 10 * 2 * pi;
      pts.addAll([x + cos(a) * rx_, z + sin(a) * rz_]);
    }
    _addGroundPoly(pts);
  }

  void _charShadow(double x, double z, double yaw, double scale, double y0) {
    final c = cos(yaw), s = sin(yaw);
    List<double> jp(int k) {
      final mx = _pose.world[k * 12 + 3], my = _pose.world[k * 12 + 7], mz = _pose.world[k * 12 + 11];
      final wx = (mx * c + mz * s) * scale + x, wz = (-mx * s + mz * c) * scale + z;
      return _gp(wx, my * scale + y0, wz);
    }
    for (final b in _bones) {
      if (b[0] < 0 || b[1] < 0) continue;
      final p = jp(b[0]), q = jp(b[1]);
      final dx = q[0] - p[0], dz = q[1] - p[1];
      final l = sqrt(dx * dx + dz * dz);
      final nx = l < 1e-4 ? 0.1 : -dz / l * 0.11, nz = l < 1e-4 ? 0.0 : dx / l * 0.11;
      _addGroundPoly([p[0] + nx, p[1] + nz, q[0] + nx, q[1] + nz, q[0] - nx, q[1] - nz, p[0] - nx, p[1] - nz]);
    }
  }

  // ----------------------------------------------------------------- actors

  void _drawChar(CharMesh cm, Actor a, double x, double y, double z, double yaw, Uint8List rgb,
      {double scale = 0.55, int shadow = 1}) {
    final sk = lib.skeleton;
    final ca = sk.clips[a.anim] ?? sk.clips['Idle']!;
    final cb = a.blend < 1 ? sk.clips[a.prev] : null;
    _pose.clearExtras();
    if (a.talking) {
      final t = a.talkT;
      _pose.addExtra(_jHead, 1, 0, 0, 0.12 * sin(t * 3.4));
      _pose.addExtra(_jHead, 0, 1, 0, 0.14 * sin(t * 1.3));
      _pose.addExtra(_jLoR, 1, 0, 0, 0.55 + 0.35 * sin(t * 4.3));
      _pose.addExtra(_jUpR, 1, 0, 0, 0.25 + 0.15 * sin(t * 2.1));
    }
    evaluatePose(sk, cm, ca, a.t, cb, a.pt, a.blend, _pose);
    m34Yaw(_m2, 0, yaw, scale, x, y, z);
    _skinned(cm, _m2, rgb);
    if (_shadow != null && shadow > 0) {
      if (shadow == 1) {
        _blob(x, z, 0.45, 0.45);
      } else {
        _charShadow(x, z, yaw, scale, y);
      }
    }
  }

  void _drawVehicle(Vehicle v, StaticModel m, int shadowMode) {
    m34Yaw(_m1, 0, v.yaw, 1, v.x, 0, v.z);
    for (final p in m.parts) {
      m34Trans(_m2, 0, p.px, p.py, p.pz);
      m34Mul(_m1, 0, _m2, 0, _m3, 0);
      if (p.name.startsWith('Wheel')) {
        if (p.name.startsWith('Wheel_F')) {
          m34RotY(_m2, 0, v.steer * 0.45);
          m34Mul(_m3, 0, _m2, 0, _m4, 0);
          for (var i = 0; i < 12; i++) {
            _m3[i] = _m4[i];
          }
        }
        m34RotX(_m2, 0, v.roll);
        m34Mul(_m3, 0, _m2, 0, _m4, 0);
        _rigid(p, _m4);
      } else {
        _rigid(p, _m3);
      }
    }
    if (_shadow != null) {
      _boxShadow(v.x, v.z, v.def.wid / 2, v.def.len / 2, v.yaw, v.isBike ? 1.0 : 1.5, shadowMode);
    }
  }

  // ---------------------------------------------------------------- frame

  void paint(Canvas canvas, Size size, GameController g) {
    final sw0 = Stopwatch()..start();
    sw = size.width;
    sh = size.height;
    final q = g.settings.quality;
    _setCamera(g, size);
    _setLighting(g);
    final lit = g.lighting;
    final drawDist = const [75.0, 115.0, 165.0][q] * scale;
    final lodDist = const [30.0, 42.0, 58.0][q];
    final charDist = max(28.0, const [38.0, 55.0, 75.0][q] * scale);
    final maxChars = const [4, 6, 9][q];
    final budget = const [14000, 24000, 34000][q];
    final shadowMode = q == 0 ? 0 : 1; // 0 = blobs, 1 = projected
    final buildingShadows = q >= 2;
    fogStart = drawDist * 0.45;
    fogEnd = drawDist * 1.02;

    // ---- sky
    final horizon = midY - tan(g.camPitch) * focal;
    final skyRect = Offset.zero & size;
    final skyH = horizon.clamp(1.0, size.height).toDouble();
    canvas.drawRect(
        skyRect,
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, Offset(0, skyH), [_col(lit.skyTop), _col(lit.skyHor)]));
    _drawSkyBodies(canvas, g, horizon);

    // ---- ground
    final groundTop = horizon.clamp(0.0, size.height).toDouble();
    final grass = _litColor(0x6FBF5E);
    final ground = Paint()
      ..shader = ui.Gradient.linear(Offset(0, groundTop), Offset(0, groundTop + size.height * 0.42),
          [_col(lit.skyHor), grass]);
    _flat(canvas, [-500, -500, 740, -500, 740, 740, -500, 740], 0, ground);
    _flat(canvas, [206, 46, 240, 46, 240, 114, 206, 114], 0.02, Paint()..color = _litColor(0x4E9F4A));
    _flat(canvas, [206, 126, 240, 126, 240, 194, 206, 194], 0.02, Paint()..color = _litColor(0x585862));
    for (final rd in World.roads) {
      _flat(canvas, [rd.x0 - 2, rd.z0 - 2, rd.x1 + 2, rd.z0 - 2, rd.x1 + 2, rd.z1 + 2, rd.x0 - 2, rd.z1 + 2], 0.03,
          Paint()..color = _litColor(0xB9B9C0));
    }
    final asphalt = Paint()..color = _litColor(0x3C3C46);
    for (final rd in World.roads) {
      _flat(canvas, [rd.x0, rd.z0, rd.x1, rd.z0, rd.x1, rd.z1, rd.x0, rd.z1], 0.05, asphalt);
    }
    final dash = Paint()..color = _litColor(0xEAD04A);
    for (final rd in World.roads) {
      final horiz = (rd.x1 - rd.x0) > (rd.z1 - rd.z0);
      final mid = horiz ? (rd.z0 + rd.z1) / 2 : (rd.x0 + rd.x1) / 2;
      for (var t = 4.0; t < 236; t += 10) {
        final x = horiz ? t : mid, z = horiz ? mid : t;
        if ((x - camX).abs() > 70 || (z - camZ).abs() > 70) continue;
        _flat(canvas, horiz ? [t, mid - 0.15, t + 4, mid - 0.15, t + 4, mid + 0.15, t, mid + 0.15]
            : [mid - 0.15, t, mid + 0.15, t, mid + 0.15, t + 4, mid - 0.15, t + 4], 0.07, dash);
      }
    }
    _flat(canvas, [14, 10, 26, 10, 26, 22, 14, 22], 0.08, Paint()..color = _litColor(0xB48A5C));

    // ---- collect scene draws
    _shadow = lit.shadowAlpha > 0.02 || q == 0 ? ui.Path() : null;
    final draws = <_Draw>[];
    void add(double d, int tris, void Function() fn) => draws.add(_Draw(d, tris, fn));
    final shadowDist = drawDist * 0.6;

    for (var i = 0; i < World.placements.length; i++) {
      final pl = World.placements[i];
      final r = _rects[i];
      final d = _rectDist(r);
      if (d > drawDist || !_visible((r.x0 + r.x1) / 2, 6, (r.z0 + r.z1) / 2, max(r.x1 - r.x0, r.z1 - r.z0) * 0.75)) {
        continue;
      }
      final lods = lib.buildings[pl.model]!;
      final m = lods[d < lodDist ? 0 : 1];
      add(d, m.tris, () {
        m34Yaw(_m1, 0, pl.yaw, 1, pl.x, 0, pl.z);
        _rigid(m.parts.first, _m1);
        if (_shadow != null && buildingShadows && d < shadowDist) {
          final s = kModelSize[pl.model]!;
          _boxShadow(pl.x, pl.z, s[0] / 2 - 0.3, s[2] / 2 - 0.3, pl.yaw, s[1] * 0.9, 1);
        }
      });
    }
    final box = lib.box;
    for (final b in World.procBoxes) {
      final d = max(0.0, sqrt((b.cx - camX) * (b.cx - camX) + (b.cz - camZ) * (b.cz - camZ)) - max(b.w, b.d) * 0.5);
      if (d > drawDist || !_visible(b.cx, b.y0 + b.h / 2, b.cz, max(b.w, b.d))) continue;
      add(d, 12, () {
        m34Scale(_m1, 0, b.w, b.h, b.d, b.cx, b.y0, b.cz);
        _rigid(box, _m1, flat: b.rgb);
      });
    }
    // Hoross's house
    final hd = max(0.0, sqrt((20 - camX) * (20 - camX) + (16 - camZ) * (16 - camZ)) - 8);
    if (hd < drawDist) {
      final inside = g.inHome;
      add(hd, 90, () {
        final wallH = inside ? 0.6 : 3.2;
        for (final w in World.homeWalls) {
          m34Scale(_m1, 0, w.x1 - w.x0, wallH, w.z1 - w.z0, (w.x0 + w.x1) / 2, 0, (w.z0 + w.z1) / 2);
          _rigid(box, _m1, flat: 0xEFE3C8);
        }
        if (!inside) {
          m34Scale(_m1, 0, 13.4, 0.35, 13.4, 20, 3.2, 16);
          _rigid(box, _m1, flat: 0x8A3B2E);
        }
        final bed = World.furniture[0], table = World.furniture[1];
        m34Scale(_m1, 0, bed.x1 - bed.x0, 0.7, bed.z1 - bed.z0, (bed.x0 + bed.x1) / 2, 0, (bed.z0 + bed.z1) / 2);
        _rigid(box, _m1, flat: 0x8E5BA8);
        m34Scale(_m1, 0, table.x1 - table.x0, 0.9, table.z1 - table.z0, (table.x0 + table.x1) / 2, 0, (table.z0 + table.z1) / 2);
        _rigid(box, _m1, flat: 0x8D6E63);
      });
    }
    for (var i = 0; i < world(g).trees.length; i++) {
      final t = world(g).trees[i];
      final d = sqrt((t.x - camX) * (t.x - camX) + (t.z - camZ) * (t.z - camZ));
      if (d > drawDist * 0.7 || !_visible(t.x, 3, t.z, 4)) continue;
      final m = lib.props[t.type == 0 ? 'pine' : 'round']!;
      add(d, m.tris, () {
        m34Yaw(_m1, 0, i * 1.7, t.scale, t.x, 0, t.z);
        _rigid(m.parts.first, _m1);
        if (_shadow != null && d < shadowDist * 0.7) _blob(t.x, t.z, 1.6 * t.scale, 1.6 * t.scale);
      });
    }
    for (final v in g.vehicles) {
      final d = sqrt((v.x - camX) * (v.x - camX) + (v.z - camZ) * (v.z - camZ));
      if (d > drawDist * 0.8 || !_visible(v.x, 1, v.z, 5)) continue;
      final m = lib.vehicles[v.def.model]!;
      add(d, m.tris, () => _drawVehicle(v, m, d < shadowDist ? shadowMode : 0));
      if (v.isBike) {
        if (g.driving == v) {
          add(d - 0.1, 3400, () => _bikeRider(v, g.hero, 'casual2m', 'hero', _heroTint, -0.12, 0.0));
        }
        var k = 0;
        for (final p in v.passengers) {
          final seat = -0.66 - k * 0.0;
          add(d - 0.2, 3400, () => _bikeRider(v, p, p.model, p.id, p.tint, seat, 0));
          k++;
        }
      }
    }
    // characters (nearest first, limited)
    final cand = <Npc>[];
    for (final n in g.npcs) {
      if (!n.visible || n.riding || n.driving) continue;
      final d = sqrt((n.x - camX) * (n.x - camX) + (n.z - camZ) * (n.z - camZ));
      if (d > charDist || !_visible(n.x, 1, n.z, 2)) continue;
      cand.add(n);
    }
    cand.sort((a, b) {
      final da = (a.x - camX) * (a.x - camX) + (a.z - camZ) * (a.z - camZ);
      final db = (b.x - camX) * (b.x - camX) + (b.z - camZ) * (b.z - camZ);
      return da.compareTo(db);
    });
    for (var i = 0; i < cand.length && i < maxChars; i++) {
      final n = cand[i];
      final d = sqrt((n.x - camX) * (n.x - camX) + (n.z - camZ) * (n.z - camZ));
      final cm = lib.chars[n.model]!;
      add(d, cm.tc, () {
        final y = n.state == NpcState.down ? 0.0 : 0.0;
        _drawChar(cm, n, n.x, y, n.z, n.yaw, _rgb(n.id, cm, n.tint),
            shadow: _shadow == null ? 0 : (shadowMode == 0 || d > 22 ? 1 : 2));
      });
    }
    // Johnson's car and other driven NPCs
    for (final n in g.npcs) {
      if (!n.visible || !n.driving) continue;
      final d = sqrt((n.x - camX) * (n.x - camX) + (n.z - camZ) * (n.z - camZ));
      if (d > drawDist * 0.8 || !_visible(n.x, 1, n.z, 5)) continue;
      final m = lib.vehicles['yellwo']!;
      final fake = Vehicle('johnson', kVehicleDefs['racer']!, n.x, n.z, n.yaw)
        ..speed = n.speed
        ..roll = g.clock * n.speed * 2.5;
      add(d, m.tris, () => _drawVehicle(fake, m, d < shadowDist ? shadowMode : 0));
    }
    // the hero
    final dv = g.driving;
    if (dv == null || !dv.isBike) {
      if (dv == null) {
        final cm = lib.chars['casual2m']!;
        add(0.5, cm.tc, () => _drawChar(cm, g.hero, g.px, g.py, g.pz, g.yaw, _rgb('hero', cm, _heroTint),
            shadow: _shadow == null ? 0 : (shadowMode == 0 ? 1 : 2)));
      }
    }

    // ---- budget (keep the nearest), draw far -> near
    draws.sort((a, b) => a.dist.compareTo(b.dist));
    var used = 0, keep = 0;
    for (final d in draws) {
      if (used + d.tris > budget) break;
      used += d.tris;
      keep++;
    }
    outTris = 0;
    for (var i = keep - 1; i >= 0; i--) {
      draws[i].fn();
    }

    // ---- shadows then triangles
    final sh0 = _shadow;
    if (sh0 != null) {
      final a = q == 0 ? 0.28 : lit.shadowAlpha;
      canvas.drawPath(sh0, Paint()..color = Color.fromRGBO(0, 0, 0, a.clamp(0.0, 0.6).toDouble()));
    }
    if (outTris > 0) {
      final vs = ui.Vertices.raw(ui.VertexMode.triangles, Float32List.sublistView(outPos, 0, outTris * 6),
          colors: Int32List.sublistView(outCol, 0, outTris * 3));
      canvas.drawVertices(vs, BlendMode.srcOver, Paint());
      vs.dispose();
    }

    _overlays(canvas, g, size);

    // frame-time governor: shrink the draw distance when painting is slow
    final ms = sw0.elapsedMicroseconds / 1000.0;
    _ema = _ema * 0.92 + ms * 0.08;
    if (_ema > 24) {
      scale = max(0.45, scale - 0.012);
    } else if (_ema < 13) {
      scale = min(1.0, scale + 0.004);
    }
  }

  World world(GameController g) => g.world;

  static final Map<String, int> _heroTint = {
    'Shirt': 0x3C7A46,
    'Pants': 0x2A3140,
    'Skin': 0xC68A62,
  };

  void _bikeRider(Vehicle v, Actor a, String model, String id, Map<String, int> tint, double seat, double side) {
    final cm = lib.chars[model]!;
    final x = v.x + sin(v.yaw) * seat, z = v.z + cos(v.yaw) * seat;
    _drawChar(cm, a, x, 0.56, z, v.yaw, _rgb(id, cm, tint), shadow: 0);
  }

  // ------------------------------------------------------------ camera/light

  void _setCamera(GameController g, Size size) {
    camX = g.camX;
    camY = g.camY;
    camZ = g.camZ;
    final cp = cos(g.camPitch), sp = sin(g.camPitch), sy = sin(g.camYaw), cy = cos(g.camYaw);
    rx = cy;
    ry = 0;
    rz = -sy;
    ux = sy * sp;
    uy = cp;
    uz = cy * sp;
    fx = sy * cp;
    fy = -sp;
    fz = cy * cp;
    view[0] = rx;
    view[1] = ry;
    view[2] = rz;
    view[3] = -(rx * camX + ry * camY + rz * camZ);
    view[4] = ux;
    view[5] = uy;
    view[6] = uz;
    view[7] = -(ux * camX + uy * camY + uz * camZ);
    view[8] = fx;
    view[9] = fy;
    view[10] = fz;
    view[11] = -(fx * camX + fy * camY + fz * camZ);
    focal = size.height * 0.95;
    midX = size.width / 2;
    midY = size.height * 0.46;
  }

  void _setLighting(GameController g) {
    final l = g.lighting;
    sunX = l.sunX;
    sunY = l.sunY;
    sunZ = l.sunZ;
    sR = l.ambSky[0];
    sG = l.ambSky[1];
    sB = l.ambSky[2];
    gR = l.ambGnd[0];
    gG = l.ambGnd[1];
    gB = l.ambGnd[2];
    cR = l.sunCol[0] * l.sunInt;
    cG = l.sunCol[1] * l.sunInt;
    cB = l.sunCol[2] * l.sunInt;
    fogR = l.skyHor[0] * 255;
    fogG = l.skyHor[1] * 255;
    fogB = l.skyHor[2] * 255;
  }

  Color _col(List<double> c) => Color.fromRGBO((c[0] * 255).round(), (c[1] * 255).round(), (c[2] * 255).round(), 1);

  /// Ground-facing (up normal) lit color for flat decals.
  Color _litColor(int rgb) {
    final r = ((rgb >> 16) & 255) * (sR + cR * sunY);
    final g = ((rgb >> 8) & 255) * (sG + cG * sunY);
    final b = (rgb & 255) * (sB + cB * sunY);
    return Color.fromARGB(255, min(255, r.round()), min(255, g.round()), min(255, b.round()));
  }

  /// Flat polygon on the ground (x,z pairs), clipped at the near plane.
  void _flat(Canvas c, List<double> xz, double y, Paint paint) {
    final n = xz.length ~/ 2;
    final vs = <List<double>>[];
    for (var i = 0; i < n; i++) {
      final dx = xz[i * 2] - camX, dy = y - camY, dz = xz[i * 2 + 1] - camZ;
      vs.add([dx * rx + dy * ry + dz * rz, dx * ux + dy * uy + dz * uz, dx * fx + dy * fy + dz * fz]);
    }
    final pts = <List<double>>[];
    for (var i = 0; i < n; i++) {
      final a = vs[i], b = vs[(i + 1) % n];
      final ai = a[2] >= 0.3, bi = b[2] >= 0.3;
      if (ai) pts.add(a);
      if (ai != bi) {
        final t = (0.3 - a[2]) / (b[2] - a[2]);
        pts.add([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, 0.3]);
      }
    }
    if (pts.length < 3) return;
    final path = ui.Path();
    for (var i = 0; i < pts.length; i++) {
      final sx = midX + pts[i][0] / pts[i][2] * focal, sy = midY - pts[i][1] / pts[i][2] * focal;
      if (i == 0) {
        path.moveTo(sx, sy);
      } else {
        path.lineTo(sx, sy);
      }
    }
    path.close();
    c.drawPath(path, paint);
  }

  Offset? _proj(double x, double y, double z) {
    final dx = x - camX, dy = y - camY, dz = z - camZ;
    final vz = dx * fx + dy * fy + dz * fz;
    if (vz < 0.3) return null;
    return Offset(midX + (dx * rx + dy * ry + dz * rz) / vz * focal, midY - (dx * ux + dy * uy + dz * uz) / vz * focal);
  }

  void _drawSkyBodies(Canvas canvas, GameController g, double horizon) {
    final l = g.lighting;
    final night = 1 - l.day;
    if (night > 0.45) {
      final p = Paint()..color = Colors.white;
      for (final s in _stars) {
        final vx = s[0] * rx + s[1] * ry + s[2] * rz, vy = s[0] * ux + s[1] * uy + s[2] * uz;
        final vz = s[0] * fx + s[1] * fy + s[2] * fz;
        if (vz < 0.1) continue;
        final sx = midX + vx / vz * focal, sy = midY - vy / vz * focal;
        if (sy > horizon) continue;
        p.color = Color.fromRGBO(255, 255, 255, ((night - 0.4) * s[3] * 1.2).clamp(0.0, 1.0).toDouble());
        canvas.drawCircle(Offset(sx, sy), 1.2, p);
      }
    }
    final vx = l.sunX * rx + l.sunY * ry + l.sunZ * rz, vy = l.sunX * ux + l.sunY * uy + l.sunZ * uz;
    final vz = l.sunX * fx + l.sunY * fy + l.sunZ * fz;
    if (vz < 0.1) return;
    final c = Offset(midX + vx / vz * focal, midY - vy / vz * focal);
    if (c.dy > horizon + 20) return;
    if (l.day > 0.08) {
      final a = (l.day * l.cloud).clamp(0.0, 1.0).toDouble();
      canvas.drawCircle(
          c,
          70,
          Paint()
            ..shader = ui.Gradient.radial(c, 70,
                [Color.fromRGBO(255, 235, 190, 0.55 * a), Color.fromRGBO(255, 200, 140, 0.0)]));
      canvas.drawCircle(c, 15, Paint()..color = Color.fromRGBO(255, 244, 214, 0.95 * a));
    } else {
      canvas.drawCircle(c, 15, Paint()..color = Color.fromRGBO(225, 232, 245, 0.9));
    }
  }

  void _glow(Canvas c, double x, double y, double z, double rad, Color color) {
    final p = _proj(x, y, z);
    if (p == null) return;
    final dx = x - camX, dy = y - camY, dz = z - camZ;
    final vz = dx * fx + dy * fy + dz * fz;
    final r = (rad * focal / vz).clamp(3.0, 60.0).toDouble();
    c.drawCircle(p, r, Paint()..shader = ui.Gradient.radial(p, r, [color, color.withAlpha(0)]));
  }

  void _overlays(Canvas canvas, GameController g, Size size) {
    // head/tail lights at night, police light bars
    for (final v in g.vehicles) {
      final d = sqrt((v.x - camX) * (v.x - camX) + (v.z - camZ) * (v.z - camZ));
      if (d > 90 || !_visible(v.x, 1, v.z, 4)) continue;
      if (v.ai) {
        final flash = ((g.clock * 5).floor() % 2 == 0);
        if (g.wanted > 0 || d < 60) {
          _glow(canvas, v.x - cos(v.yaw) * 0.45, 2.0, v.z + sin(v.yaw) * 0.45, 1.6,
              flash ? const Color(0xCCD02020) : const Color(0x44D02020));
          _glow(canvas, v.x + cos(v.yaw) * 0.45, 2.0, v.z - sin(v.yaw) * 0.45, 1.6,
              flash ? const Color(0x442040D0) : const Color(0xCC2040D0));
        }
      }
      if (g.lighting.day < 0.5 && (v.speed.abs() > 0.5 || g.driving == v)) {
        for (final side in const [-0.7, 0.7]) {
          final hx = v.x + sin(v.yaw) * 2.4 + cos(v.yaw) * side, hz = v.z + cos(v.yaw) * 2.4 - sin(v.yaw) * side;
          _glow(canvas, hx, 0.7, hz, 1.1, const Color(0x99FFE9B0));
        }
      }
    }
    // mission beam
    final wp = g.waypoint;
    if (wp != null) {
      final px = wp.x, pz = wp.z;
      final bx = cos(g.camYaw) * 0.9, bz = -sin(g.camYaw) * 0.9;
      final pts = <Offset>[];
      for (final e in const [
        [-1.0, 0.0], [1.0, 0.0], [1.0, 70.0], [-1.0, 70.0]
      ]) {
        final p = _proj(px + bx * e[0], e[1], pz + bz * e[0]);
        if (p != null) pts.add(p);
      }
      if (pts.length == 4) {
        final a = 0.36 + 0.12 * sin(g.clock * 3);
        canvas.drawPath(ui.Path()..addPolygon(pts, true), Paint()..color = Color.fromRGBO(190, 35, 35, a));
      }
    }
    // name tags
    for (final n in g.npcs) {
      if (!n.visible || n.riding || !(n.kind == NpcKind.key || n.id == 'officer' || n.driving)) continue;
      final p = _proj(n.x, n.driving ? 3.0 : 2.2, n.z);
      if (p == null) continue;
      final d = sqrt((n.x - camX) * (n.x - camX) + (n.z - camZ) * (n.z - camZ));
      if (d > 28) continue;
      final tp = TextPainter(
          text: TextSpan(
              text: n.name,
              style: const TextStyle(
                  fontFamily: 'Chorus',
                  color: Color(0xFFF1EBD8),
                  fontSize: 15,
                  shadows: [Shadow(blurRadius: 2, color: Colors.black), Shadow(offset: Offset(1, 1), color: Colors.black)])),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height));
    }
  }
}

class WorldPainter extends CustomPainter {
  WorldPainter(this.renderer, this.g) : super(repaint: g);
  final WorldRenderer renderer;
  final GameController g;

  @override
  void paint(Canvas canvas, Size size) => renderer.paint(canvas, size, g);

  @override
  bool shouldRepaint(covariant WorldPainter old) => true;
}
