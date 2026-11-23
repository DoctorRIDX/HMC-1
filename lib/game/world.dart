import 'dart:math';

class P2 {
  const P2(this.x, this.z);
  final double x, z;
}

class Rect2 {
  const Rect2(this.x0, this.z0, this.x1, this.z1);
  final double x0, z0, x1, z1;
  bool contains(double x, double z) => x >= x0 && x <= x1 && z >= z0 && z <= z1;
}

/// Collision footprint. [h] is only used to stop the camera (0 = ignored).
class Solid {
  const Solid(this.x0, this.z0, this.x1, this.z1, this.h, {this.home = false});
  final double x0, z0, x1, z1, h;
  final bool home;
}

/// A model placed in the city. yaw 0 faces +z (north); pi/2 faces +x (east).
class Placement {
  const Placement(this.model, this.x, this.z, this.yaw);
  final String model;
  final double x, z, yaw;
}

/// Simple colored box built from the shared unit cube (warehouses, canopy ...).
class ProcBox {
  const ProcBox(this.cx, this.cz, this.w, this.d, this.y0, this.h, this.rgb);
  final double cx, cz, w, d, y0, h;
  final int rgb;
}

class Tree {
  const Tree(this.x, this.z, this.type, this.scale);
  final double x, z, scale;
  final int type;
}

class Place {
  const Place(this.id, this.name, this.x, this.z, this.color);
  final String id, name;
  final double x, z;
  final int color;
}

class Resolved {
  const Resolved(this.x, this.z, this.hit);
  final double x, z;
  final bool hit;
}

double _cl(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

/// Footprint (width x, height y, depth z) of the converted building models, in meters.
const Map<String, List<double>> kModelSize = {
  'bank': [28.1, 20.5, 29.7],
  'hospital': [22.5, 26.1, 19.0],
  'hq': [15.2, 22.2, 15.0],
  'flat1': [15.2, 22.2, 15.0],
  'flat2': [15.2, 22.2, 13.2],
  'shop': [16.0, 9.0, 11.7],
  'house1': [11.0, 12.5, 15.4],
  'house2': [11.3, 11.8, 13.0],
  'house3': [11.3, 17.4, 12.9],
  'house4': [17.3, 10.5, 11.5],
  'house5': [16.2, 9.9, 16.1],
};

/// New Merrci: a 240 x 240 m city on a 3x3 road grid (roads are 12 m wide).
class World {
  World() {
    for (final p in placements) {
      final s = kModelSize[p.model]!;
      final turned = (sin(p.yaw).abs() > 0.7);
      final hx = (turned ? s[2] : s[0]) / 2 - 0.2, hz = (turned ? s[0] : s[2]) / 2 - 0.2;
      solids.add(Solid(p.x - hx, p.z - hz, p.x + hx, p.z + hz, s[1]));
    }
    for (final b in procBoxes) {
      if (b.h >= 1.5 && b.y0 < 0.5) {
        solids.add(Solid(b.cx - b.w / 2, b.cz - b.d / 2, b.cx + b.w / 2, b.cz + b.d / 2, b.h));
      }
    }
    for (final r in homeWalls) {
      solids.add(Solid(r.x0, r.z0, r.x1, r.z1, 3.2, home: true));
    }
    for (final r in furniture) {
      solids.add(Solid(r.x0, r.z0, r.x1, r.z1, 0));
    }
    final rnd = Random(5);
    void tree(double x, double z) {
      trees.add(Tree(x, z, rnd.nextInt(2), 0.8 + rnd.nextDouble() * 0.5));
    }

    for (var x = 213.0; x < 238; x += 9) {
      for (var z = 52.0; z < 110; z += 10) {
        tree(x + ((z ~/ 10) % 2) * 2, z);
      }
    }
    for (var x = 50.0; x < 112; x += 16) {
      tree(x, 31);
      tree(x, 49);
    }
    for (var z = 130.0; z < 195; z += 16) {
      tree(40.0 + (z % 2), z);
    }
    for (final t in trees) {
      solids.add(Solid(t.x - 0.35, t.z - 0.35, t.x + 0.35, t.z + 0.35, 0));
    }
  }

  static const double size = 240;
  static const Rect2 homeRect = Rect2(14, 10, 26, 22);

  static const List<Rect2> roads = [
    Rect2(0, 34, 240, 46),
    Rect2(0, 114, 240, 126),
    Rect2(0, 194, 240, 206),
    Rect2(34, 0, 46, 240),
    Rect2(114, 0, 126, 240),
    Rect2(194, 0, 206, 240),
  ];

  static const List<Placement> placements = [
    // south row
    Placement('house1', 58, 17, 0),
    Placement('house3', 80, 16, 0),
    Placement('house5', 102, 17, 0),
    Placement('house4', 222, 17, 0),
    // west shops
    Placement('shop', 17, 62, pi / 2),
    Placement('shop', 17, 82, pi / 2),
    Placement('shop', 17, 102, pi / 2),
    // Mr. Will's block
    Placement('house2', 58, 66, 0),
    Placement('house1', 80, 92, 0),
    Placement('house5', 102, 64, pi),
    // police station
    Placement('bank', 160, 80, 0),
    // gas station store, Gromson HQ
    Placement('shop', 17, 165, pi / 2),
    Placement('hq', 80, 168, pi),
    Placement('flat2', 56, 172, pi),
    // south of the far road
    Placement('house1', 17, 222, pi),
    Placement('hospital', 80, 224, pi),
    Placement('flat1', 140, 224, pi),
    Placement('flat2', 170, 224, pi),
    Placement('house2', 222, 222, pi),
  ];

  static const List<ProcBox> procBoxes = [
    // grey warehouses (north-west industrial block)
    ProcBox(145, 17, 30, 22, 0, 6.5, 0x78909C),
    ProcBox(145, 17, 30.8, 22.8, 6.5, 0.5, 0x4E5B63),
    ProcBox(178, 17, 24, 22, 0, 6.5, 0x607D8B),
    ProcBox(178, 17, 24.8, 22.8, 6.5, 0.5, 0x424E55),
    // Yellwo warehouses
    ProcBox(149, 166, 22, 32, 0, 7, 0xE0B400),
    ProcBox(149, 166, 22.8, 32.8, 7, 0.5, 0x6B5500),
    ProcBox(176, 161, 24, 22, 0, 7, 0xD9A700),
    ProcBox(176, 161, 24.8, 22.8, 7, 0.5, 0x6B5500),
    ProcBox(149, 149.8, 5, 0.4, 0, 4, 0x33302A),
    ProcBox(176, 149.8, 5, 0.4, 0, 4, 0x33302A),
    // gas station canopy and pumps
    ProcBox(28.5, 165, 9, 20, 4.2, 0.5, 0xB23A1A),
    ProcBox(24.4, 156, 0.5, 0.5, 0, 4.2, 0xDDDDDD),
    ProcBox(32.6, 156, 0.5, 0.5, 0, 4.2, 0xDDDDDD),
    ProcBox(24.4, 174, 0.5, 0.5, 0, 4.2, 0xDDDDDD),
    ProcBox(32.6, 174, 0.5, 0.5, 0, 4.2, 0xDDDDDD),
    ProcBox(28.5, 160, 0.9, 0.9, 0, 1.5, 0xC9C9C9),
    ProcBox(28.5, 170, 0.9, 0.9, 0, 1.5, 0xC9C9C9),
  ];

  /// Hoross's house: an open-top room (roof is drawn when the player is outside).
  static const List<Rect2> homeWalls = [
    Rect2(13.5, 9.5, 26.5, 10),
    Rect2(13.5, 10, 14, 22),
    Rect2(26, 10, 26.5, 22),
    Rect2(13.5, 22, 19, 22.5),
    Rect2(21, 22, 26.5, 22.5),
  ];
  static const List<Rect2> furniture = [Rect2(15, 10.5, 17.6, 14.5), Rect2(23, 16, 25.5, 19.5)];

  static const List<Place> places = [
    Place('home', 'Hoross House', 20, 26, 0xFFFFFFFF),
    Place('will', "Mr. Will's House", 80, 108, 0xFFB5651D),
    Place('police', 'Police Station', 160, 104, 0xFF3F51B5),
    Place('hq', 'Gromson HQ', 80, 150, 0xFF2EAD4B),
    Place('yellwo', 'Yellwo Warehouse', 158, 140, 0xFFF2C811),
    Place('ariss_home', "Ariss's House", 222, 30, 0xFFE57373),
    Place('gas', 'Gas Station', 28, 148, 0xFFFF7043),
    Place('park', 'New Merrci Park', 224, 80, 0xFF4E9F4A),
    Place('hospital', 'Merrci Hospital', 80, 208, 0xFFEEEEEE),
  ];

  final List<Solid> solids = [];
  final List<Tree> trees = [];

  bool inHome(double x, double z) => homeRect.contains(x, z);

  Place place(String id) => places.firstWhere((p) => p.id == id);

  /// Rectangle covered by a placement (for the map and collisions).
  static Rect2 footprint(Placement p) {
    final s = kModelSize[p.model]!;
    final turned = sin(p.yaw).abs() > 0.7;
    final hx = (turned ? s[2] : s[0]) / 2, hz = (turned ? s[0] : s[2]) / 2;
    return Rect2(p.x - hx, p.z - hz, p.x + hx, p.z + hz);
  }

  /// Pushes a circle out of all solids; also clamps to the city bounds.
  Resolved resolve(double x, double z, double r) {
    var hit = false;
    for (var it = 0; it < 2; it++) {
      for (final s in solids) {
        final cx = _cl(x, s.x0, s.x1), cz = _cl(z, s.z0, s.z1);
        final dx = x - cx, dz = z - cz;
        final d2 = dx * dx + dz * dz;
        if (d2 >= r * r) continue;
        hit = true;
        if (d2 > 1e-9) {
          final d = sqrt(d2);
          x = cx + dx / d * r;
          z = cz + dz / d * r;
        } else {
          final l = x - s.x0, rr = s.x1 - x, b = z - s.z0, t = s.z1 - z;
          final m = min(min(l, rr), min(b, t));
          if (m == l) {
            x = s.x0 - r;
          } else if (m == rr) {
            x = s.x1 + r;
          } else if (m == b) {
            z = s.z0 - r;
          } else {
            z = s.z1 + r;
          }
        }
      }
    }
    final nx = _cl(x, 1, size - 1), nz = _cl(z, 1, size - 1);
    if (nx != x || nz != z) hit = true;
    return Resolved(nx, nz, hit);
  }

  /// How far the camera may travel from (x,y,z) along (dx,dy,dz) before hitting a building.
  double camClip(double x, double y, double z, double dx, double dy, double dz, double maxDist,
      {required bool skipHome}) {
    for (var s = 1.0; s <= maxDist; s += 0.8) {
      final py = y + dy * s, px = x + dx * s, pz = z + dz * s;
      if (py < 0.5) return max(1.5, s - 0.8);
      for (final b in solids) {
        if (b.h <= 0 || (skipHome && b.home)) continue;
        if (px > b.x0 - 0.4 && px < b.x1 + 0.4 && pz > b.z0 - 0.4 && pz < b.z1 + 0.4 && py < b.h + 0.4) {
          return max(1.5, s - 1.2);
        }
      }
    }
    return maxDist;
  }
}
