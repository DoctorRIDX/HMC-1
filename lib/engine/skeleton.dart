import 'dart:math';
import 'dart:typed_data';

import 'assets.dart';
import 'math34.dart';

/// Animation state shared by the player and NPCs (cross-fades between clips).
class Actor {
  String anim = 'Idle';
  String prev = 'Idle';
  double t = 0, pt = 0, blend = 1, talkT = 0;
  bool talking = false;

  void play(String name, {bool restart = false}) {
    if (anim == name && !restart) return;
    prev = anim;
    pt = t;
    anim = name;
    t = 0;
    blend = 0;
  }

  void advance(double dt, [double rate = 1]) {
    t += dt * rate;
    pt += dt * rate;
    if (blend < 1) blend = min(1.0, blend + dt / 0.2);
    if (talking) talkT += dt;
  }
}

class Pose {
  Pose(this.jc)
      : world = Float64List(jc * 12),
        skin = Float64List(jc * 12),
        _a = Float64List(jc * 7),
        _b = Float64List(jc * 7);
  final int jc;
  final Float64List world; // joint matrices in model space
  final Float64List skin; // world * inverse bind
  final Float64List _a, _b;
  final Float64List _l = Float64List(12);
  final List<int> extraJoint = [];
  final List<double> extraQ = []; // qx qy qz qw per extra joint

  void clearExtras() {
    extraJoint.clear();
    extraQ.clear();
  }

  void addExtra(int joint, double ax, double ay, double az, double angle) {
    if (joint < 0) return;
    final s = sin(angle / 2);
    extraJoint.add(joint);
    extraQ.addAll([ax * s, ay * s, az * s, cos(angle / 2)]);
  }
}

void _sample(AnimClip c, double time, Float64List out) {
  final n = c.jc * 7;
  final nf = c.frames;
  var fr = time * c.fps;
  final mx = (nf - 1).toDouble();
  if (c.loop) {
    fr = fr % mx;
  } else if (fr > mx) {
    fr = mx;
  }
  if (fr < 0) fr = 0;
  final i = fr.floor();
  final f = fr - i;
  final i2 = i + 1 < nf ? i + 1 : nf - 1;
  final d = c.data;
  final o1 = i * n, o2 = i2 * n;
  for (var k = 0; k < n; k++) {
    out[k] = d[o1 + k] * (1 - f) + d[o2 + k] * f;
  }
}

/// Evaluates joint matrices for clip [a] at time [ta], cross-faded from clip [b]
/// (previous animation) by [blend] (0 = all b, 1 = all a).
void evaluatePose(Skeleton sk, CharMesh mesh, AnimClip a, double ta, AnimClip? b, double tb,
    double blend, Pose p) {
  final jc = sk.jc;
  _sample(a, ta, p._a);
  var cur = p._a;
  if (b != null && blend < 1) {
    _sample(b, tb, p._b);
    for (var k = 0; k < jc; k++) {
      final o = k * 7;
      for (var i = 0; i < 3; i++) {
        p._b[o + i] = p._b[o + i] * (1 - blend) + p._a[o + i] * blend;
      }
      final dot = p._b[o + 3] * p._a[o + 3] + p._b[o + 4] * p._a[o + 4] +
          p._b[o + 5] * p._a[o + 5] + p._b[o + 6] * p._a[o + 6];
      final sgn = dot < 0 ? -1.0 : 1.0;
      for (var i = 3; i < 7; i++) {
        p._b[o + i] = p._b[o + i] * (1 - blend) + p._a[o + i] * blend * sgn;
      }
    }
    cur = p._b;
  }
  final ibm = mesh.ibm;
  for (var k = 0; k < jc; k++) {
    final o = k * 7;
    var qx = cur[o + 3], qy = cur[o + 4], qz = cur[o + 5], qw = cur[o + 6];
    for (var e = 0; e < p.extraJoint.length; e++) {
      if (p.extraJoint[e] == k) {
        final ex = p.extraQ[e * 4], ey = p.extraQ[e * 4 + 1], ez = p.extraQ[e * 4 + 2], ew = p.extraQ[e * 4 + 3];
        final nx = qw * ex + qx * ew + qy * ez - qz * ey;
        final ny = qw * ey - qx * ez + qy * ew + qz * ex;
        final nz = qw * ez + qx * ey - qy * ex + qz * ew;
        final nw = qw * ew - qx * ex - qy * ey - qz * ez;
        qx = nx;
        qy = ny;
        qz = nz;
        qw = nw;
      }
    }
    final inv = 1 / sqrt(qx * qx + qy * qy + qz * qz + qw * qw);
    m34Quat(p._l, 0, qx * inv, qy * inv, qz * inv, qw * inv, cur[o], cur[o + 1], cur[o + 2]);
    final par = sk.parents[k];
    if (par >= 0) {
      m34Mul(p.world, par * 12, p._l, 0, p.world, k * 12);
    } else {
      m34Mul(sk.root, 0, p._l, 0, p.world, k * 12);
    }
    m34Mul(p.world, k * 12, ibm, k * 12, p.skin, k * 12);
  }
}
