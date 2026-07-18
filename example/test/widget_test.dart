import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glint/glint.dart';
import 'package:glint_showcase/configurator.dart';
import 'package:glint_showcase/main.dart';

void main() {
  testWidgets('showcase embeds Glint First Light', (tester) async {
    await tester.pumpWidget(const GlintShowcase());
    expect(find.byType(GlintGpuFirstLight), findsOneWidget);
    expect(find.text('3D belongs in the widget tree.'), findsOneWidget);
  });

  testWidgets('configurator swatches restyle the product live', (
    tester,
  ) async {
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
