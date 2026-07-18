import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glint/glint.dart';

void main() {
  test('material converts sRGB color to a linear glTF factor', () {
    const white = Material3D(color: Color(0xffffffff));
    expect(white.linearBaseColorFactor, [1, 1, 1, 1]);
    const black = Material3D(color: Color(0xff000000), opacity: .5);
    final blackFactor = black.linearBaseColorFactor;
    expect(blackFactor[0], 0);
    expect(blackFactor[3], closeTo(.5, 1e-6));
    const gray = Material3D(color: Color(0xff808080));
    // sRGB mid-gray is ~21.6% linear, the classic gamma-2.2 checkpoint.
    expect(gray.linearBaseColorFactor[1], closeTo(.216, .005));
  });

  test('materials with equal fields compare equal for rebuild detection', () {
    const a = Material3D(color: Color(0xffd9b23a), metallic: 1, roughness: .3);
    const b = Material3D(color: Color(0xffd9b23a), metallic: 1, roughness: .3);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(const Material3D(color: Color(0xffd9b23a), metallic: 0)));
  });

  test('render stats format compactly for the debug overlay', () {
    const stats = GlintRenderStats(
      framesPerSecond: 60,
      frameTimeMilliseconds: 4.16,
      drawCalls: 1,
      triangleCount: 4212,
    );
    expect('$stats', '60 fps • 4.2 ms • 1 draw • 4212 tris');
  });

  testWidgets('stats overlay builds without a GPU backend', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: GlintGpuFirstLight(showStats: true, autoRotate: false),
      ),
    );
    await tester.pump();
    expect(find.byType(GlintGpuFirstLight), findsOneWidget);
  });

  test('transform applies scale and translation', () {
    const transform = Transform3D(
      position: Vector3(1, 2, 3),
      scale: Vector3(2, 2, 2),
    );
    expect(transform.apply(const Vector3(1, 1, 1)), const Vector3(3, 4, 5));
  });

  testWidgets('Scene3D routes model scenes to the GPU renderer', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scene3D(
          children: [
            Node3D(
              model: Model.asset('packages/glint/assets/models/duck.glb'),
            ),
          ],
          autoRotate: false,
        ),
      ),
    );
    expect(find.byType(GlintGpuFirstLight), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Scene3D),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
  });

  testWidgets('Scene3D keeps mesh-only scenes on the preview painter', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scene3D(children: [Node3D(mesh: Mesh3D.cube())]),
      ),
    );
    expect(find.byType(GlintGpuFirstLight), findsNothing);
  });

  testWidgets('Scene3D composes with Flutter widgets', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Scene3D(children: [Node3D(mesh: Mesh3D.cube())]),
            const Text('Flutter overlay'),
          ],
        ),
      ),
    );
    expect(find.byType(Scene3D), findsOneWidget);
    expect(find.text('Flutter overlay'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PNG bytes decode to tightly packed RGBA pixels', (tester) async {
    final pixels = await tester.runAsync(
      () => GlintTexturePixels.decode(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
          '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
        debugLabel: 'one-pixel.png',
      ),
    );
    expect(pixels!.width, 1);
    expect(pixels.height, 1);
    expect(pixels.bytes.lengthInBytes, 4);
  });

  test('invalid image bytes produce an actionable Glint error', () async {
    await expectLater(
      GlintTexturePixels.decode(
        Uint8List.fromList([1, 2, 3]),
        debugLabel: 'broken.jpg',
      ),
      throwsA(
        isA<GlintTextureException>().having(
          (error) => error.asset,
          'asset',
          'broken.jpg',
        ),
      ),
    );
  });

  testWidgets('packaged GLB decodes mesh accessors', (tester) async {
    final mesh = await tester.runAsync(
      () => GlintGlbMesh.fromAsset(
        'packages/glint/assets/models/glint-prism.glb',
      ),
    );
    expect(mesh!.vertexCount, 24);
    expect(mesh.indices, hasLength(96));
    expect(mesh.textureCoordinates, hasLength(48));
    expect(mesh.uses32BitIndices, isFalse);
    expect(mesh.boundsMinimum[0], closeTo(-3, 0.0001));
    expect(mesh.boundsMaximum[0], closeTo(4, 0.0001));
    expect(mesh.boundsMinimum[1], closeTo(-1.35, 0.0001));
    expect(mesh.boundsMaximum[1], closeTo(1.35, 0.0001));
    expect(mesh.boundsMinimum[2], closeTo(-1, 0.0001));
    expect(mesh.boundsMaximum[2], closeTo(4, 0.0001));
  });

  testWidgets('real Khronos GLB exposes its embedded material image', (
    tester,
  ) async {
    final mesh = await tester.runAsync(
      () => GlintGlbMesh.fromAsset('packages/glint/assets/models/duck.glb'),
    );
    expect(mesh!.vertexCount, greaterThan(1000));
    expect(mesh.indices, isNotEmpty);
    expect(mesh.baseColorImageBytes, isNotNull);
    expect(mesh.normals, hasLength(mesh.positions.length));
    final pixels = await tester.runAsync(
      () => GlintTexturePixels.decode(
        mesh.baseColorImageBytes!,
        debugLabel: 'Duck embedded texture',
      ),
    );
    expect(pixels!.width, greaterThan(1));
    expect(pixels.height, greaterThan(1));
  });
}
