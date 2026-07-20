import 'package:flutter_test/flutter_test.dart';
import 'package:glint_engine/glint_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  test('identity clip volume keeps boxes inside and culls boxes outside', () {
    final frustum = GlintFrustum.fromColumnMajor(
      vm.Matrix4.identity().storage.toList(),
    );
    expect(
      frustum.intersectsBounds(
        const Vector3(-.5, -.5, -.5),
        const Vector3(.5, .5, .5),
      ),
      isTrue,
    );
    expect(
      frustum.intersectsBounds(
        const Vector3(-3, -.5, -.5),
        const Vector3(-1.5, .5, .5),
      ),
      isFalse,
    );
    expect(
      frustum.intersectsBounds(
        const Vector3(-.5, 1.5, -.5),
        const Vector3(.5, 3, .5),
      ),
      isFalse,
    );
  });

  test('a box straddling a clip plane is kept', () {
    final frustum = GlintFrustum.fromColumnMajor(
      vm.Matrix4.identity().storage.toList(),
    );
    expect(
      frustum.intersectsBounds(
        const Vector3(.9, -.5, -.5),
        const Vector3(2, .5, .5),
      ),
      isTrue,
    );
  });

  test('perspective camera culls by pan exactly like the renderer', () {
    final projection = vm.makePerspectiveMatrix(
      37.8 * 3.141592653589793 / 180,
      1,
      .1,
      100,
    );
    final view = vm.Matrix4.translationValues(0, 0, -6.4);
    const minimum = Vector3(-1.25, -1.25, -1.25);
    const maximum = Vector3(1.25, 1.25, 1.25);

    GlintFrustum frustumFor(double panX) {
      final model = vm.Matrix4.identity()..translateByDouble(panX, 0, 0, 1);
      final mvp = projection * view * model;
      return GlintFrustum.fromColumnMajor((mvp as vm.Matrix4).storage.toList());
    }

    expect(frustumFor(0).intersectsBounds(minimum, maximum), isTrue);
    expect(frustumFor(2).intersectsBounds(minimum, maximum), isTrue);
    expect(frustumFor(6).intersectsBounds(minimum, maximum), isFalse);
    expect(frustumFor(-6).intersectsBounds(minimum, maximum), isFalse);
  });

  test('a box behind the camera is culled', () {
    final projection = vm.makePerspectiveMatrix(
      37.8 * 3.141592653589793 / 180,
      1,
      .1,
      100,
    );
    final view = vm.Matrix4.translationValues(0, 0, 8);
    final mvp = projection * view;
    final frustum = GlintFrustum.fromColumnMajor(
      (mvp as vm.Matrix4).storage.toList(),
    );
    expect(
      frustum.intersectsBounds(
        const Vector3(-1.25, -1.25, -1.25),
        const Vector3(1.25, 1.25, 1.25),
      ),
      isFalse,
    );
  });

  test('rejects matrices that are not 16 elements', () {
    expect(
      () => GlintFrustum.fromColumnMajor(const [1, 2, 3]),
      throwsArgumentError,
    );
  });
}
