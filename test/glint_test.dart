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
}
