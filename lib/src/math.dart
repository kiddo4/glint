import 'dart:math' as math;

/// A small, immutable 3D vector used by Glint's public scene API.
class Vector3 {
  const Vector3(this.x, this.y, this.z);

  static const zero = Vector3(0, 0, 0);
  static const one = Vector3(1, 1, 1);

  final double x;
  final double y;
  final double z;

  Vector3 operator +(Vector3 other) =>
      Vector3(x + other.x, y + other.y, z + other.z);
  Vector3 operator -(Vector3 other) =>
      Vector3(x - other.x, y - other.y, z - other.z);
  Vector3 operator *(double value) => Vector3(x * value, y * value, z * value);

  double dot(Vector3 other) => x * other.x + y * other.y + z * other.z;
  Vector3 cross(Vector3 other) => Vector3(
    y * other.z - z * other.y,
    z * other.x - x * other.z,
    x * other.y - y * other.x,
  );
  double get length => math.sqrt(dot(this));
  Vector3 get normalized => length == 0 ? zero : this * (1 / length);

  @override
  bool operator ==(Object other) =>
      other is Vector3 && x == other.x && y == other.y && z == other.z;

  @override
  int get hashCode => Object.hash(x, y, z);
}

/// A picking ray with an [origin] and a normalized [direction].
class GlintRay {
  const GlintRay(this.origin, this.direction);

  /// Unprojects a normalized-device-coordinate point (x and y in -1..1, with
  /// +y up) through a 16-element column-major *inverse* projection·view·model
  /// matrix, producing a ray in the space that matrix maps back into. Assumes
  /// OpenGL-style clip depth (near plane at z = -1), matching `vector_math`'s
  /// `makePerspectiveMatrix`.
  factory GlintRay.fromNdc(double x, double y, List<double> inverseMatrix) {
    if (inverseMatrix.length != 16) {
      throw ArgumentError.value(
        inverseMatrix.length,
        'inverseMatrix',
        'must have 16 elements',
      );
    }
    Vector3 unproject(double z) {
      final output = List<double>.filled(4, 0);
      for (var i = 0; i < 4; i++) {
        output[i] =
            inverseMatrix[i] * x +
            inverseMatrix[4 + i] * y +
            inverseMatrix[8 + i] * z +
            inverseMatrix[12 + i];
      }
      if (output[3] == 0) {
        throw ArgumentError('inverseMatrix does not unproject to a point');
      }
      return Vector3(
        output[0] / output[3],
        output[1] / output[3],
        output[2] / output[3],
      );
    }

    final near = unproject(-1);
    final far = unproject(1);
    return GlintRay(near, (far - near).normalized);
  }

  final Vector3 origin;
  final Vector3 direction;

  /// Möller–Trumbore intersection. Returns the distance along the ray to the
  /// triangle, or null when the ray misses or the triangle is behind it.
  double? intersectTriangle(Vector3 a, Vector3 b, Vector3 c) {
    const epsilon = 1e-9;
    final edge1 = b - a;
    final edge2 = c - a;
    final h = direction.cross(edge2);
    final determinant = edge1.dot(h);
    if (determinant > -epsilon && determinant < epsilon) return null;
    final inverseDeterminant = 1 / determinant;
    final s = origin - a;
    final u = s.dot(h) * inverseDeterminant;
    if (u < 0 || u > 1) return null;
    final q = s.cross(edge1);
    final v = direction.dot(q) * inverseDeterminant;
    if (v < 0 || u + v > 1) return null;
    final t = edge2.dot(q) * inverseDeterminant;
    return t > epsilon ? t : null;
  }

  /// Slab test against an axis-aligned box, counting hits behind the origin
  /// as misses.
  bool intersectsBounds(Vector3 minimum, Vector3 maximum) {
    var tNear = double.negativeInfinity;
    var tFar = double.infinity;
    for (final (start, delta, low, high) in [
      (origin.x, direction.x, minimum.x, maximum.x),
      (origin.y, direction.y, minimum.y, maximum.y),
      (origin.z, direction.z, minimum.z, maximum.z),
    ]) {
      if (delta == 0) {
        if (start < low || start > high) return false;
        continue;
      }
      final t1 = (low - start) / delta;
      final t2 = (high - start) / delta;
      tNear = math.max(tNear, math.min(t1, t2));
      tFar = math.min(tFar, math.max(t1, t2));
    }
    return tFar >= tNear && tFar >= 0;
  }
}

/// The nearest triangle a picking ray struck.
class GlintRayHit {
  const GlintRayHit({
    required this.distance,
    required this.position,
    required this.triangleIndex,
  });

  /// Distance from the ray origin, in the intersected mesh's units.
  final double distance;

  /// The struck point, in the intersected mesh's space.
  final Vector3 position;

  /// Index of the struck triangle within the mesh's index list.
  final int triangleIndex;
}

/// One boundary of a view frustum. Points with `a·x + b·y + c·z + d >= 0`
/// are on the visible side.
class GlintFrustumPlane {
  const GlintFrustumPlane(this.a, this.b, this.c, this.d);

  final double a;
  final double b;
  final double c;
  final double d;

  double distanceTo(Vector3 point) => a * point.x + b * point.y + c * point.z + d;
}

/// The six clip planes of a projection·view·model matrix, expressed in the
/// space the matrix maps from, for coarse visibility culling.
class GlintFrustum {
  GlintFrustum._(this.planes);

  /// Extracts planes from a 16-element column-major matrix
  /// (Gribb–Hartmann), matching `vector_math`'s `Matrix4.storage` layout.
  factory GlintFrustum.fromColumnMajor(List<double> m) {
    if (m.length != 16) {
      throw ArgumentError.value(m.length, 'm', 'must have 16 elements');
    }
    double row(int i, int j) => m[j * 4 + i];
    GlintFrustumPlane sum(int i, double sign) => GlintFrustumPlane(
      row(3, 0) + sign * row(i, 0),
      row(3, 1) + sign * row(i, 1),
      row(3, 2) + sign * row(i, 2),
      row(3, 3) + sign * row(i, 3),
    );
    return GlintFrustum._([
      sum(0, 1), // left
      sum(0, -1), // right
      sum(1, 1), // bottom
      sum(1, -1), // top
      sum(2, 1), // near
      sum(2, -1), // far
    ]);
  }

  final List<GlintFrustumPlane> planes;

  /// Whether an axis-aligned box could be visible. Conservative: a box fully
  /// outside any single plane is culled; everything else is kept.
  bool intersectsBounds(Vector3 minimum, Vector3 maximum) {
    for (final plane in planes) {
      final farthestInside = Vector3(
        plane.a >= 0 ? maximum.x : minimum.x,
        plane.b >= 0 ? maximum.y : minimum.y,
        plane.c >= 0 ? maximum.z : minimum.z,
      );
      if (plane.distanceTo(farthestInside) < 0) return false;
    }
    return true;
  }
}

/// Translation, Euler rotation (radians), and scale for a scene node.
class Transform3D {
  const Transform3D({
    this.position = Vector3.zero,
    this.rotation = Vector3.zero,
    this.scale = Vector3.one,
  });

  final Vector3 position;
  final Vector3 rotation;
  final Vector3 scale;

  Vector3 apply(Vector3 point) {
    var value = Vector3(
      point.x * scale.x,
      point.y * scale.y,
      point.z * scale.z,
    );
    final cx = math.cos(rotation.x), sx = math.sin(rotation.x);
    value = Vector3(
      value.x,
      value.y * cx - value.z * sx,
      value.y * sx + value.z * cx,
    );
    final cy = math.cos(rotation.y), sy = math.sin(rotation.y);
    value = Vector3(
      value.x * cy + value.z * sy,
      value.y,
      -value.x * sy + value.z * cy,
    );
    final cz = math.cos(rotation.z), sz = math.sin(rotation.z);
    value = Vector3(
      value.x * cz - value.y * sz,
      value.x * sz + value.y * cz,
      value.z,
    );
    return value + position;
  }
}
