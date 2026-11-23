import 'dart:math';
import 'dart:typed_data';

// 3x4 affine matrices, row-major, stored at an offset inside a Float64List.
// World axes: x right/east, y up, z forward/north (left-handed). Yaw 0 faces +z.

/// o = a * b (o must not alias a or b).
void m34Mul(Float64List a, int ao, Float64List b, int bo, Float64List o, int oo) {
  final a0 = a[ao], a1 = a[ao + 1], a2 = a[ao + 2], a3 = a[ao + 3];
  final a4 = a[ao + 4], a5 = a[ao + 5], a6 = a[ao + 6], a7 = a[ao + 7];
  final a8 = a[ao + 8], a9 = a[ao + 9], a10 = a[ao + 10], a11 = a[ao + 11];
  final b0 = b[bo], b1 = b[bo + 1], b2 = b[bo + 2], b3 = b[bo + 3];
  final b4 = b[bo + 4], b5 = b[bo + 5], b6 = b[bo + 6], b7 = b[bo + 7];
  final b8 = b[bo + 8], b9 = b[bo + 9], b10 = b[bo + 10], b11 = b[bo + 11];
  o[oo] = a0 * b0 + a1 * b4 + a2 * b8;
  o[oo + 1] = a0 * b1 + a1 * b5 + a2 * b9;
  o[oo + 2] = a0 * b2 + a1 * b6 + a2 * b10;
  o[oo + 3] = a0 * b3 + a1 * b7 + a2 * b11 + a3;
  o[oo + 4] = a4 * b0 + a5 * b4 + a6 * b8;
  o[oo + 5] = a4 * b1 + a5 * b5 + a6 * b9;
  o[oo + 6] = a4 * b2 + a5 * b6 + a6 * b10;
  o[oo + 7] = a4 * b3 + a5 * b7 + a6 * b11 + a7;
  o[oo + 8] = a8 * b0 + a9 * b4 + a10 * b8;
  o[oo + 9] = a8 * b1 + a9 * b5 + a10 * b9;
  o[oo + 10] = a8 * b2 + a9 * b6 + a10 * b10;
  o[oo + 11] = a8 * b3 + a9 * b7 + a10 * b11 + a11;
}

/// Rotation about Y by [yaw], uniform scale [s], then translation.
void m34Yaw(Float64List o, int oo, double yaw, double s, double x, double y, double z) {
  final c = cos(yaw) * s, sn = sin(yaw) * s;
  o[oo] = c;
  o[oo + 1] = 0;
  o[oo + 2] = sn;
  o[oo + 3] = x;
  o[oo + 4] = 0;
  o[oo + 5] = s;
  o[oo + 6] = 0;
  o[oo + 7] = y;
  o[oo + 8] = -sn;
  o[oo + 9] = 0;
  o[oo + 10] = c;
  o[oo + 11] = z;
}

void m34Scale(Float64List o, int oo, double sx, double sy, double sz, double x, double y, double z) {
  o[oo] = sx;
  o[oo + 1] = 0;
  o[oo + 2] = 0;
  o[oo + 3] = x;
  o[oo + 4] = 0;
  o[oo + 5] = sy;
  o[oo + 6] = 0;
  o[oo + 7] = y;
  o[oo + 8] = 0;
  o[oo + 9] = 0;
  o[oo + 10] = sz;
  o[oo + 11] = z;
}

void m34Trans(Float64List o, int oo, double x, double y, double z) =>
    m34Scale(o, oo, 1, 1, 1, x, y, z);

void m34RotX(Float64List o, int oo, double a) {
  final c = cos(a), s = sin(a);
  o[oo] = 1;
  o[oo + 1] = 0;
  o[oo + 2] = 0;
  o[oo + 3] = 0;
  o[oo + 4] = 0;
  o[oo + 5] = c;
  o[oo + 6] = -s;
  o[oo + 7] = 0;
  o[oo + 8] = 0;
  o[oo + 9] = s;
  o[oo + 10] = c;
  o[oo + 11] = 0;
}

void m34RotY(Float64List o, int oo, double a) => m34Yaw(o, oo, a, 1, 0, 0, 0);

/// Rotation matrix from quaternion (x, y, z, w) plus translation.
void m34Quat(Float64List o, int oo, double x, double y, double z, double w, double tx, double ty, double tz) {
  o[oo] = 1 - 2 * (y * y + z * z);
  o[oo + 1] = 2 * (x * y - z * w);
  o[oo + 2] = 2 * (x * z + y * w);
  o[oo + 3] = tx;
  o[oo + 4] = 2 * (x * y + z * w);
  o[oo + 5] = 1 - 2 * (x * x + z * z);
  o[oo + 6] = 2 * (y * z - x * w);
  o[oo + 7] = ty;
  o[oo + 8] = 2 * (x * z - y * w);
  o[oo + 9] = 2 * (y * z + x * w);
  o[oo + 10] = 1 - 2 * (x * x + y * y);
  o[oo + 11] = tz;
}
