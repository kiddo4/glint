import 'package:flutter/material.dart';
import 'package:glint/glint.dart';

void main() => runApp(const GlintShowcase());

class GlintShowcase extends StatefulWidget {
  const GlintShowcase({super.key});

  @override
  State<GlintShowcase> createState() => _GlintShowcaseState();
}

class _GlintShowcaseState extends State<GlintShowcase> {
  static const _presets = <(String, Material3D?)>[
    ('Original vinyl', null),
    (
      'Brushed gold',
      Material3D(color: Color(0xffd9b23a), metallic: 1, roughness: .32),
    ),
    (
      'Cherry gloss',
      Material3D(color: Color(0xffb01230), metallic: .05, roughness: .12),
    ),
    (
      'Matte slate',
      Material3D(color: Color(0xff3f4650), metallic: 0, roughness: .85),
    ),
  ];

  var _presetIndex = 0;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: Scaffold(
      body: Stack(
        children: [
          // The engine's whole pitch in one expression: a declarative scene
          // in the widget tree, GPU-rendered.
          Scene3D(
            scene: ProductShowroom(finish: _presets[_presetIndex].$2),
            autoRotate: true,
            showStats: true,
            gpuFallback: const Center(
              child: Text(
                'Flutter GPU renderer unavailable.\n'
                'Launch with --enable-impeller --enable-flutter-gpu.',
                textAlign: TextAlign.center,
              ),
            ),
            // Milestone 2 deliverable: tap the product, restyle it live.
            onModelTap: (_) => setState(
              () => _presetIndex = (_presetIndex + 1) % _presets.length,
            ),
            // Milestone 3: real Flutter widgets pinned to the model, fading
            // or hiding as their anchor rotates behind the duck.
            labels: const [
              Label3D(
                anchor: Vector3(.96, 1.34, -.12),
                offset: Offset(0, -30),
                child: _Chip(text: 'FOOD-GRADE BEAK'),
              ),
              Label3D(
                anchor: Vector3(-.69, .52, -.02),
                offset: Offset(0, -30),
                occlusion: Label3DOcclusion.hide,
                child: _Chip(text: 'TAIL CURL'),
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'GLINT',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      letterSpacing: 5,
                      color: const Color(0xffffb000),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '3D belongs in the widget tree.',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  _Chip(text: 'FINISH  •  ${_presets[_presetIndex].$1}'),
                  const SizedBox(height: 12),
                  const _Chip(
                    text:
                        'TAP DUCK RESTYLE  •  DRAG ORBIT  •  PINCH ZOOM  •  '
                        'TWO-FINGER PAN',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .35),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: Colors.white12),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(text),
    ),
  );
}

class ProductShowroom extends Scene {
  const ProductShowroom({this.finish});

  /// Overrides the duck's authored vinyl; null keeps the original.
  final Material3D? finish;

  @override
  List<Light3D> get lights => const [
    AmbientLight(intensity: .26),
    DirectionalLight(direction: Vector3(.55, -1, -.65), intensity: .87),
    EnvironmentLight(
      asset: 'packages/glint/assets/environments/studio.hdr',
    ),
  ];

  @override
  List<Node3D> get children => [
    Node3D(
      name: 'product',
      model: const Model.asset('packages/glint/assets/models/duck.glb'),
      material: finish,
    ),
  ];
}
