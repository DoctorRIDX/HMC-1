import 'dart:math';

double _lerp(double a, double b, double t) => a + (b - a) * t;
double _cl(double v, [double lo = 0, double hi = 1]) => v < lo ? lo : (v > hi ? hi : v);

/// Sun/moon direction, colors and sky for the current time of day and cloud cover.
/// All colors are 0..1 RGB triples.
class Lighting {
  double sunX = 0, sunY = 1, sunZ = 0; // direction TOWARD the light
  double sunInt = 1;
  List<double> sunCol = [1, 1, 1];
  List<double> ambSky = [.5, .5, .5];
  List<double> ambGnd = [.3, .3, .3];
  List<double> skyTop = [.3, .5, .8];
  List<double> skyHor = [.7, .8, .9];
  double day = 1; // 0 night .. 1 day
  double shadowAlpha = .4;
  double cloud = 1;

  void update(double hour, double clock) {
    final a = (hour - 6) / 12 * pi; // 0 at 06:00, pi at 18:00
    final s = sin(a);
    day = _cl(s * 2.6);
    final dusk = 1 - _cl(s.abs() * 3.2);
    cloud = _cl(0.8 + 0.2 * sin(clock * 0.13) * sin(clock * 0.051 + 1.3), 0.55, 1.0);
    double dx, dy, dz;
    if (s > -0.05) {
      dx = cos(a) * 0.9;
      dy = max(s, 0.12);
      dz = -0.4;
    } else {
      dx = -0.35;
      dy = 0.75;
      dz = 0.45; // moon
    }
    final l = sqrt(dx * dx + dy * dy + dz * dz);
    sunX = dx / l;
    sunY = dy / l;
    sunZ = dz / l;
    sunInt = day * cloud * 1.05 + (1 - day) * 0.28;
    final warm = [1.0, 0.62, 0.36];
    final white = [1.0, 0.96, 0.88];
    final moon = [0.55, 0.65, 1.0];
    sunCol = [
      for (var i = 0; i < 3; i++) _lerp(_lerp(moon[i], white[i], day), warm[i], dusk * day)
    ];
    final ambDay = [0.50, 0.55, 0.66], ambNight = [0.10, 0.12, 0.22], ambDusk = [0.62, 0.50, 0.52];
    ambSky = [
      for (var i = 0; i < 3; i++)
        _lerp(_lerp(ambNight[i], ambDay[i], day), ambDusk[i], dusk * 0.6 * day) * _lerp(0.78, 1, cloud)
    ];
    ambGnd = [for (var i = 0; i < 3; i++) ambSky[i] * 0.62];
    final topDay = [0.27, 0.50, 0.80], topNight = [0.03, 0.04, 0.10], topDusk = [0.40, 0.38, 0.55];
    final horDay = [0.74, 0.85, 0.93], horNight = [0.08, 0.10, 0.18], horDusk = [0.95, 0.62, 0.42];
    skyTop = [
      for (var i = 0; i < 3; i++) _lerp(_lerp(topNight[i], topDay[i], day), topDusk[i], dusk * 0.7 * day)
    ];
    skyHor = [
      for (var i = 0; i < 3; i++) _lerp(_lerp(horNight[i], horDay[i], day), horDusk[i], dusk * 0.8 * day)
    ];
    shadowAlpha = 0.46 * day * _cl((cloud - 0.45) * 1.8);
  }
}
