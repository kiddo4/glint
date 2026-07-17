import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glint/glint.dart';

void main() {
  test('transform applies scale and translation', () {
    const transform = Transform3D(
      position: Vector3(1, 2, 3),
      scale: Vector3(2, 2, 2),
    );
    expect(transform.apply(const Vector3(1, 1, 1)), const Vector3(3, 4, 5));
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
    expect(mesh!.vertexCount, 6);
    expect(mesh.indices, hasLength(24));
    expect(mesh.textureCoordinates, hasLength(12));
    expect(mesh.uses32BitIndices, isFalse);
  });
}
