import 'package:flutter_test/flutter_test.dart';
import 'package:glint_engine/glint_engine.dart';
import 'package:glint_engine/src/gpu/punctual_lights.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  test('worldPointLight translates local position by the world matrix', () {
    final world = vm.Matrix4.translationValues(5, 2, -3);
    const local = PointLight(position: Vector3(0, 0, 1), intensity: 2.5);
    final transformed = worldPointLight(local, world);
    expect(transformed.position, const Vector3(5, 2, -2));
    // Non-positional fields pass through unchanged.
    expect(transformed.intensity, 2.5);
    expect(transformed.color, local.color);
    expect(transformed.range, local.range);
  });

  test('worldSpotLight rotates direction but ignores translation', () {
    final world = vm.Matrix4.translationValues(5, 2, -3);
    const local = SpotLight(
      position: Vector3(0, 0, 1),
      direction: Vector3(0, 0, 1),
    );
    final transformed = worldSpotLight(local, world);
    // Position is translated like a point...
    expect(transformed.position, const Vector3(5, 2, -2));
    // ...but direction is a vector, not a point, so translation must not
    // leak into it the way it would if this used the same point-transform
    // path as position.
    expect(transformed.direction, const Vector3(0, 0, 1));
  });

  test('worldSpotLight applies rotation to direction and position alike', () {
    // 90 degrees about Z: (1, 0, 0) -> (0, 1, 0).
    final world = vm.Matrix4.rotationZ(3.14159265359 / 2);
    const local = SpotLight(
      position: Vector3(1, 0, 0),
      direction: Vector3(1, 0, 0),
    );
    final transformed = worldSpotLight(local, world);
    expect(transformed.position.x, closeTo(0, 1e-6));
    expect(transformed.position.y, closeTo(1, 1e-6));
    expect(transformed.direction.x, closeTo(0, 1e-6));
    expect(transformed.direction.y, closeTo(1, 1e-6));
  });
}
