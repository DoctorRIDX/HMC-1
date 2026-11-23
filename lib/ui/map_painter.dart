import 'dart:math';

import 'package:flutter/material.dart';

import '../game/entities.dart';
import '../game/game_controller.dart';
import '../game/world.dart';

Color _mapColor(String model) {
  switch (model) {
    case 'bank':
      return const Color(0xFF47527F);
    case 'hq':
      return const Color(0xFF2F7A3B);
    case 'hospital':
      return const Color(0xFFD9D9D9);
    case 'shop':
      return const Color(0xFF7D5A86);
    default:
      return const Color(0xFF8A7A66);
  }
}

/// Mini-map (upper-left HUD) and the full-screen map.
class MapPainter extends CustomPainter {
  MapPainter(this.g, {this.full = false}) : super(repaint: g);
  final GameController g;
  final bool full;

  @override
  void paint(Canvas c, Size s) {
    final double k, ox, oz;
    if (full) {
      k = min(s.width, s.height) / 250;
      ox = 120;
      oz = 120;
    } else {
      k = s.width / 110;
      ox = g.px;
      oz = g.pz;
    }
    Offset p(double x, double z) => Offset((x - ox) * k + s.width / 2, s.height / 2 - (z - oz) * k);
    Rect rect(Rect2 q) => Rect.fromPoints(p(q.x0, q.z0), p(q.x1, q.z1));
    final paint = Paint();
    c.save();
    c.clipRect(Offset.zero & s);
    c.drawRect(Offset.zero & s, paint..color = const Color(0xFF3C5A3A));
    c.drawRect(rect(const Rect2(206, 46, 240, 114)), paint..color = const Color(0xFF486B44));
    c.drawRect(rect(const Rect2(206, 126, 240, 194)), paint..color = const Color(0xFF55555C));
    for (final rd in World.roads) {
      c.drawRect(rect(rd), paint..color = const Color(0xFF4E4E57));
    }
    for (final pl in World.placements) {
      c.drawRect(rect(World.footprint(pl)), paint..color = _mapColor(pl.model));
    }
    for (final b in World.procBoxes) {
      if (b.y0 > 0 || b.h < 5) continue;
      c.drawRect(rect(Rect2(b.cx - b.w / 2, b.cz - b.d / 2, b.cx + b.w / 2, b.cz + b.d / 2)),
          paint..color = Color(0xFF000000 | b.rgb));
    }
    c.drawRect(rect(World.homeRect), paint..color = const Color(0xFFE9E2CF));

    for (final pl in World.places) {
      if (!g.unlocked.contains(pl.id)) continue;
      final o = p(pl.x, pl.z);
      c.drawCircle(o, full ? 6 : 4, paint..color = Colors.black);
      c.drawCircle(o, full ? 4.5 : 3, paint..color = Color(pl.color));
      if (full) {
        final tp = TextPainter(
            text: TextSpan(
                text: pl.name,
                style: const TextStyle(
                    fontFamily: 'Chorus',
                    color: Color(0xFFE9E2CF),
                    fontSize: 13,
                    shadows: [Shadow(blurRadius: 3, color: Colors.black)])),
            textDirection: TextDirection.ltr)
          ..layout();
        tp.paint(c, o + Offset(-tp.width / 2, 8));
      }
    }
    if (g.wanted > 0) {
      for (final n in g.npcs) {
        if (n.kind == NpcKind.police && n.visible && n.alive) {
          c.drawCircle(p(n.x, n.z), 3, paint..color = const Color(0xFF6C8CE0));
        }
      }
      for (final v in g.vehicles) {
        if (v.ai) c.drawCircle(p(v.x, v.z), 4, paint..color = const Color(0xFF6C8CE0));
      }
    }

    final wp = g.waypoint;
    if (wp != null) {
      var o = p(wp.x, wp.z);
      if (!full) {
        final cen = Offset(s.width / 2, s.height / 2);
        final d = o - cen;
        final lim = s.width / 2 - 10;
        final dist = d.distance;
        if (dist > lim) o = cen + d * (lim / dist); // GPS arrow clamps to the rim
      }
      final path = Path()
        ..moveTo(o.dx, o.dy - 8)
        ..lineTo(o.dx + 6, o.dy)
        ..lineTo(o.dx, o.dy + 8)
        ..lineTo(o.dx - 6, o.dy)
        ..close();
      c.drawPath(path, paint..color = const Color(0xFFB02A2A));
      c.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = const Color(0xFFE9E2CF));
    }

    final me = p(g.px, g.pz);
    final dir = Offset(sin(g.yaw), -cos(g.yaw));
    final perp = Offset(-dir.dy, dir.dx);
    final arrow = Path()
      ..moveTo(me.dx + dir.dx * 9, me.dy + dir.dy * 9)
      ..lineTo(me.dx - dir.dx * 5 + perp.dx * 5, me.dy - dir.dy * 5 + perp.dy * 5)
      ..lineTo(me.dx - dir.dx * 5 - perp.dx * 5, me.dy - dir.dy * 5 - perp.dy * 5)
      ..close();
    c.drawPath(arrow, paint..color = const Color(0xFFE9E2CF));
    c.drawPath(
        arrow,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.black);
    c.restore();
  }

  @override
  bool shouldRepaint(covariant MapPainter old) => true;
}
