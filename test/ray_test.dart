import 'package:flutter_test/flutter_test.dart';
import 'package:glint/glint.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  test('unprojecting the NDC center through identity yields a forward ray', () {
    final ray = GlintRay.fromNdc(0, 0, vm.Matrix4.identity().storage.toList());
    expect(ray.origin.x, closeTo(0, 1e-9));
    expect(ray.origin.y, closeTo(0, 1e-9));
    expect(ray.origin.z, closeTo(-1, 1e-9));
    expect(ray.direction.z, closeTo(1, 1e-9));
  });

  test('ray-triangle intersection hits, misses, and rejects behind', () {
    const triangleA = Vector3(-1, -1, 5);
    const triangleB = Vector3(1, -1, 5);
    const triangleC = Vector3(0, 1, 5);
    const forward = GlintRay(Vector3.zero, Vector3(0, 0, 1));
    expect(
      forward.intersectTriangle(triangleA, triangleB, triangleC),
      closeTo(5, 1e-9),
    );
    const wide = GlintRay(Vector3(5, 0, 0), Vector3(0, 0, 1));
    expect(wide.intersectTriangle(triangleA, triangleB, triangleC), isNull);
    const backward = GlintRay(Vector3.zero, Vector3(0, 0, -1));
    expect(backward.intersectTriangle(triangleA, triangleB, triangleC), isNull);
    const parallel = GlintRay(Vector3.zero, Vector3(1, 0, 0));
    expect(parallel.intersectTriangle(triangleA, triangleB, triangleC), isNull);
  });

  test('ray-bounds slab test handles hits, misses, and inside origins', () {
    const minimum = Vector3(-1, -1, -1);
    const maximum = Vector3(1, 1, 1);
    const towards = GlintRay(Vector3(0, 0, -5), Vector3(0, 0, 1));
    expect(towards.intersectsBounds(minimum, maximum), isTrue);
    const away = GlintRay(Vector3(0, 0, -5), Vector3(0, 0, -1));
    expect(away.intersectsBounds(minimum, maximum), isFalse);
    const offAxis = GlintRay(Vector3(5, 5, -5), Vector3(0, 0, 1));
    expect(offAxis.intersectsBounds(minimum, maximum), isFalse);
    const inside = GlintRay(Vector3.zero, Vector3(0, 0, 1));
    expect(inside.intersectsBounds(minimum, maximum), isTrue);
  });

  test('projecting to NDC handles center, offsets, and behind-camera', () {
    final identity = vm.Matrix4.identity().storage.toList();
    final centered = glintProjectToNdc(identity, const Vector3(.5, -.25, 0));
    expect(centered!.x, closeTo(.5, 1e-9));
    expect(centered.y, closeTo(-.25, 1e-9));

    final projection = vm.makePerspectiveMatrix(
      37.8 * 3.141592653589793 / 180,
      1,
      .1,
      100,
    );
    final view = vm.Matrix4.translationValues(0, 0, -6.4);
    final mvp = (projection * view as vm.Matrix4).storage.toList();
    final onAxis = glintProjectToNdc(mvp, Vector3.zero);
    expect(onAxis!.x, closeTo(0, 1e-9));
    expect(onAxis.y, closeTo(0, 1e-9));
    final above = glintProjectToNdc(mvp, const Vector3(0, 1, 0));
    expect(above!.y, greaterThan(0));
    // A point behind the camera has no screen position.
    expect(glintProjectToNdc(mvp, const Vector3(0, 0, 10)), isNull);
    expect(
      () => glintProjectToNdc(const [1, 2], Vector3.zero),
      throwsArgumentError,
    );
  });

  testWidgets('the duck occludes anchors on its far side', (tester) async {
    final mesh = await tester.runAsync(
      () => GlintGlbMesh.fromAsset('packages/glint/assets/models/duck.glb'),
    );
    // The beak tip faces +x; seen from the front it is clear, while from
    // behind the duck's body blocks the line of sight.
    const beak = Vector3(.96, 1.34, -.12);
    expect(mesh!.occludes(const Vector3(10, 1.34, -.12), beak), isFalse);
    expect(mesh.occludes(const Vector3(-10, 1.34, -.12), beak), isTrue);
    // Nothing between the camera and a point floating off the model.
    expect(
      mesh.occludes(const Vector3(10, 5, 0), const Vector3(5, 5, 0)),
      isFalse,
    );
  });

  testWidgets('a ray through the Duck GLB reports the nearest surface', (
    tester,
  ) async {
    final mesh = await tester.runAsync(
      () => GlintGlbMesh.fromAsset('packages/glint/assets/models/duck.glb'),
    );
    final center = Vector3(
      (mesh!.boundsMinimum[0] + mesh.boundsMaximum[0]) / 2,
      (mesh.boundsMinimum[1] + mesh.boundsMaximum[1]) / 2,
      (mesh.boundsMinimum[2] + mesh.boundsMaximum[2]) / 2,
    );
    final towards = GlintRay(
      Vector3(center.x, center.y, mesh.boundsMaximum[2] + 10),
      const Vector3(0, 0, -1),
    );
    final hit = mesh.intersectRay(towards);
    expect(hit, isNotNull);
    expect(hit!.distance, greaterThan(0));
    expect(hit.position.z, lessThanOrEqualTo(mesh.boundsMaximum[2] + 1e-6));
    expect(hit.position.z, greaterThanOrEqualTo(mesh.boundsMinimum[2] - 1e-6));

    final away = GlintRay(
      Vector3(center.x, center.y, mesh.boundsMaximum[2] + 10),
      const Vector3(0, 0, 1),
    );
    expect(mesh.intersectRay(away), isNull);
  });
}
