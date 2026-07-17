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
