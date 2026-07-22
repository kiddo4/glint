import 'package:flutter/material.dart';
import 'package:glint_engine/glint_engine.dart';

/// Minimal demonstration of skeletal skinning in the game loop: a real
/// animated character (vertex-level bone deformation, not the rigid
/// node-part animation Duck Dash's cargo box uses) cycling through its
/// authored walk animation on a simple ground plane.
class SkinnedCharacterDemoPage extends StatefulWidget {
  const SkinnedCharacterDemoPage({super.key});

  @override
  State<SkinnedCharacterDemoPage> createState() =>
      _SkinnedCharacterDemoPageState();
}

class _SkinnedCharacterDemoPageState extends State<SkinnedCharacterDemoPage> {
  var _time = 0.0;

  static const _models = {
    'fox': Model.asset('packages/glint_engine/assets/models/fox.glb'),
    'ground': Model.asset('packages/glint_engine/assets/models/box.glb'),
  };

  static const _groundMaterial = Material3D(
    color: Color(0xff4a5a3d),
    metallic: 0,
    roughness: 1,
  );

  GlintGameFrame _buildFrame(double dt) {
    _time += dt;
    return GlintGameFrame(
      // Fox.glb's authored bind-pose bounds are roughly 25 wide, 79 tall,
      // 155 deep (x/y/z) — framed well back and above to fit the whole
      // walk cycle, not the small/close guess a "typical" model scale
      // would suggest.
      camera: const GlintGameCamera(
        position: Vector3(0, 110, 260),
        target: Vector3(0, 40, -10),
        fieldOfViewDegrees: 45,
      ),
      instances: [
        // DIAGNOSTIC: ground temporarily hidden to isolate the fox's shape
        // unambiguously from the mangled-mesh screenshot.
        // const GlintGameInstance(
        //   model: 'ground',
        //   transform: Transform3D(
        //     position: Vector3(0, -1, 0),
        //     scale: Vector3(150, 1, 150),
        //   ),
        //   material: _groundMaterial,
        // ),
        GlintGameInstance(
          model: 'fox',
          animationIndex: 1,
          animationTime: _time,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBodyBehindAppBar: true,
    appBar: AppBar(
      title: const Text('Skinned character'),
      backgroundColor: Colors.transparent,
    ),
    body: GlintGameView(
      models: _models,
      onFrame: _buildFrame,
      lightDirection: const Vector3(.5, -1, -.4),
      lightIntensity: 3,
      ambientIntensity: .35,
      showStats: true,
      fallback: const Center(
        child: Text(
          'Flutter GPU renderer unavailable.\n'
          'Launch with --enable-impeller --enable-flutter-gpu.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}
