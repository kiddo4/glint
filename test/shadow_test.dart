import 'package:flutter_test/flutter_test.dart';
import 'package:glint_engine/glint_engine.dart';
import 'package:glint_engine/src/gpu/shadow.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  test('directionalLightViewProjection maps the bounds center to the '
      'clip-space origin', () {
    final viewProjection = directionalLightViewProjection(
      lightDirection: const Vector3(0, -1, 0),
      boundsCenter: const Vector3(3, 1, -2),
      radius: 5,
    );
    final clip = viewProjection.transform(
      vm.Vector4(3, 1, -2, 1),
    );
    // The bounds center is the orthographic frustum's look-at target, so it
    // must land at clip-space (0, 0) regardless of light direction — the
    // property everything else (the shadow UV remap) depends on.
    expect(clip.x / clip.w, closeTo(0, 1e-6));
    expect(clip.y / clip.w, closeTo(0, 1e-6));
  });

  test('directionalLightViewProjection stays well-defined for a light '
      'pointing straight down', () {
    // A light direction with y close to -1 makes the default "up" vector
    // (0, 1, 0) parallel to the view direction, which degenerates
    // makeViewMatrix unless the fallback up vector kicks in.
    final viewProjection = directionalLightViewProjection(
      lightDirection: const Vector3(0, -1, 0),
      boundsCenter: Vector3.zero,
      radius: 2,
    );
    for (final value in viewProjection.storage) {
      expect(value.isFinite, isTrue);
    }
  });
}
