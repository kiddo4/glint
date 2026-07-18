import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glint/glint.dart';
import 'package:glint_showcase/aether_tilt.dart';
import 'package:glint_showcase/configurator.dart';

void main() {
  test('first level has a complete gravity-shift solution', () {
    final game = AetherGame();
    expect(game.tilt(TiltDirection.right), isNotEmpty);
    expect(game.tilt(TiltDirection.up), isNotEmpty);
    expect(game.tilt(TiltDirection.left), isNotEmpty);
    expect(game.tilt(TiltDirection.right), isNotEmpty);
    expect(game.won, isTrue);
    expect(game.collectedShards, 3);
    expect(game.moves, 4);
  });

  testWidgets('Aether Tilt presents a playable portrait HUD', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const AetherTiltApp());
    expect(find.text('AETHER TILT'), findsOneWidget);
    expect(find.textContaining('THE FIRST SIGNAL'), findsOneWidget);
    expect(find.byType(Scene3D), findsOneWidget);
    expect(find.byKey(const ValueKey('tilt-right')), findsOneWidget);
    expect(find.text('0/3'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tilt-right')));
    await tester.pumpAndSettle();
    expect(find.text('1/3'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('configurator swatches restyle the product live', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const ConfiguratorPage(),
      ),
    );
    // Original finish: model keeps its authored material, slider disabled.
    expect(find.text('Original vinyl'), findsOneWidget);
    expect(
      find.text('Pick a custom finish to adjust surface roughness.'),
      findsOneWidget,
    );
    var scene = tester.widget<Scene3D>(find.byType(Scene3D));
    expect(scene.scene!.children.single.material, isNull);
    expect(scene.gestureMode, GlintGestureMode.scrollAware);
    expect(scene.labels, hasLength(2));

    // Selecting the gold swatch overrides the material and enables the
    // roughness slider at the preset's value.
    await tester.tap(find.byKey(const ValueKey('finish-swatch-1')));
    await tester.pump();
    expect(find.text('Brushed gold'), findsOneWidget);
    scene = tester.widget<Scene3D>(find.byType(Scene3D));
    final material = scene.scene!.children.single.material;
    expect(material, isNotNull);
    expect(material!.metallic, 1);
    expect(material.roughness, closeTo(.32, 1e-9));
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
  });
}
