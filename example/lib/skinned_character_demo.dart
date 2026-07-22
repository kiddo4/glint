import 'package:flutter/material.dart';
import 'package:glint_engine/glint_engine.dart';

/// Minimal demonstration of skeletal skinning in the game loop: a real
/// animated character (vertex-level bone deformation, not the rigid
/// node-part animation Duck Dash's cargo box uses) crossfading between its
/// authored clips on a simple ground plane.
class SkinnedCharacterDemoPage extends StatefulWidget {
  const SkinnedCharacterDemoPage({super.key});

  @override
  State<SkinnedCharacterDemoPage> createState() =>
      _SkinnedCharacterDemoPageState();
}

class _SkinnedCharacterDemoPageState extends State<SkinnedCharacterDemoPage> {
  static const _foxAsset = 'packages/glint_engine/assets/models/fox.glb';
  var _time = 0.0;
  var _selectedAnimation = 1;
  GlintAnimationController? _animation;
  Object? _animationLoadError;

  static const _models = {
    'fox': Model.asset(_foxAsset),
    'ground': Model.asset('packages/glint_engine/assets/models/box.glb'),
  };

  static const _groundMaterial = Material3D(
    color: Color(0xff4a5a3d),
    metallic: 0,
    roughness: 1,
  );

  @override
  void initState() {
    super.initState();
    _loadAnimationRuntime();
  }

  Future<void> _loadAnimationRuntime() async {
    try {
      final rig = await GlintGlbRig.fromAsset(_foxAsset);
      if (!mounted) return;
      setState(() {
        _animation = GlintAnimationController(
          rig,
          initialAnimation: _selectedAnimation,
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _animationLoadError = error);
    }
  }

  void _play(int animationIndex) {
    _animation?.play(animationIndex, fadeDuration: .35, restart: false);
    setState(() => _selectedAnimation = animationIndex);
  }

  GlintGameFrame _buildFrame(double dt) {
    _time += dt;
    final animationPose = _animation?.update(dt).pose;
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
        const GlintGameInstance(
          model: 'ground',
          transform: Transform3D(
            position: Vector3(0, -1, 0),
            scale: Vector3(150, 1, 150),
          ),
          material: _groundMaterial,
        ),
        GlintGameInstance(
          model: 'fox',
          animationIndex: _selectedAnimation,
          animationTime: _time,
          animationPose: animationPose,
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
    body: Stack(
      children: [
        Positioned.fill(
          child: GlintGameView(
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
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: SafeArea(
            top: false,
            child: Center(
              child: Material(
                color: const Color(0xdd151822),
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: _animationLoadError == null
                      ? SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(value: 0, label: Text('Survey')),
                            ButtonSegment(value: 1, label: Text('Walk')),
                            ButtonSegment(value: 2, label: Text('Run')),
                          ],
                          selected: {_selectedAnimation},
                          onSelectionChanged: _animation == null
                              ? null
                              : (selection) => _play(selection.single),
                        )
                      : const Text('Animation runtime could not load'),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
