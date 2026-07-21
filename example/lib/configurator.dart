import 'package:flutter/material.dart';
import 'package:glint_engine/glint_engine.dart';

/// The flagship demo: a scrollable product page whose hero is a live 3D
/// configurator. Ordinary Flutter widgets restyle the model, labels stay
/// anchored to its surface, and the page still scrolls like any other.
class ConfiguratorPage extends StatefulWidget {
  const ConfiguratorPage({super.key});

  @override
  State<ConfiguratorPage> createState() => _ConfiguratorPageState();
}

class _Finish {
  const _Finish(this.name, this.swatch, {this.metallic, this.roughness});

  final String name;
  final Color swatch;
  final double? metallic;
  final double? roughness;

  bool get isOriginal => metallic == null;
}

class _ConfiguratorPageState extends State<ConfiguratorPage> {
  static const _finishes = [
    _Finish('Original vinyl', Color(0xffe8c51d)),
    _Finish('Brushed gold', Color(0xffd9b23a), metallic: 1, roughness: .32),
    _Finish('Cherry gloss', Color(0xffb01230), metallic: .05, roughness: .12),
    _Finish('Matte slate', Color(0xff3f4650), metallic: 0, roughness: .85),
  ];

  var _finishIndex = 0;
  var _roughness = .32;

  _Finish get _finish => _finishes[_finishIndex];

  Material3D? get _material => _finish.isOriginal
      ? null
      : Material3D(
          color: _finish.swatch,
          metallic: _finish.metallic!,
          roughness: _roughness,
        );

  void _selectFinish(int index) => setState(() {
    _finishIndex = index;
    _roughness = _finishes[index].roughness ?? .32;
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Duck Classic No. 1'),
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            height: 440,
            child: Scene3D(
              scene: _ConfiguratorScene(finish: _material),
              autoRotate: true,
              // Inside a scrolling page: horizontal drags orbit, vertical
              // drags keep scrolling, pinch zooms.
              gestureMode: GlintGestureMode.scrollAware,
              backgroundColor: scheme.surface,
              onModelTap: (_) =>
                  _selectFinish((_finishIndex + 1) % _finishes.length),
              labels: const [
                Label3D(
                  anchor: Vector3(.96, 1.34, -.12),
                  offset: Offset(0, -30),
                  child: _LabelChip(text: 'FOOD-GRADE BEAK'),
                ),
                Label3D(
                  anchor: Vector3(-.69, .52, -.02),
                  offset: Offset(0, -30),
                  occlusion: Label3DOcclusion.hide,
                  child: _LabelChip(text: 'TAIL CURL'),
                ),
              ],
              gpuFallback: const Center(
                child: Text(
                  'Flutter GPU renderer unavailable.\n'
                  'Launch with --enable-impeller --enable-flutter-gpu.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GLINT COLLECTION',
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 3,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        'Duck Classic No. 1',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text('\$24', style: theme.textTheme.headlineSmall),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'The 1998 Khronos duck, reissued. Drag sideways to orbit, '
                  'pinch to zoom, tap the duck or a swatch to restyle it — '
                  'the page keeps scrolling like any other.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'FINISH',
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 3,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(_finish.name, style: theme.textTheme.labelLarge),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (var i = 0; i < _finishes.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _Swatch(
                          key: ValueKey('finish-swatch-$i'),
                          color: _finishes[i].swatch,
                          selected: i == _finishIndex,
                          onTap: () => _selectFinish(i),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'SURFACE ROUGHNESS',
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 3,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      _finish.isOriginal ? '—' : _roughness.toStringAsFixed(2),
                      style: theme.textTheme.labelLarge,
                    ),
                  ],
                ),
                Slider(
                  value: _roughness,
                  min: .05,
                  max: 1,
                  onChanged: _finish.isOriginal
                      ? null
                      : (value) => setState(() => _roughness = value),
                ),
                if (_finish.isOriginal)
                  Text(
                    'Pick a custom finish to adjust surface roughness.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => ScaffoldMessenger.of(context)
                      ..clearSnackBars()
                      ..showSnackBar(
                        SnackBar(
                          behavior: SnackBarBehavior.floating,
                          content: Text(
                            'Added Duck Classic No. 1 — ${_finish.name}.',
                          ),
                        ),
                      ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('Add to cart'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfiguratorScene extends Scene {
  const _ConfiguratorScene({this.finish});

  final Material3D? finish;

  @override
  List<Light3D> get lights => const [
    AmbientLight(intensity: .26),
    DirectionalLight(direction: Vector3(.55, -1, -.65), intensity: .87),
    EnvironmentLight(asset: 'packages/glint_engine/assets/environments/studio.hdr'),
    // A warm accent light off to one side — the kind of rim highlight a
    // product shot would use, distinct from the cool key/ambient setup.
    // Positions are in the model's normalized space (the largest extent is
    // scaled to fit ~2.5 units), so this sits just off the duck's shoulder.
    PointLight(
      position: Vector3(1.7, 1.3, 1.9),
      color: Color(0xffffc266),
      intensity: 3.5,
    ),
  ];

  @override
  List<Node3D> get children => [
    Node3D(
      name: 'product',
      model: const Model.asset('packages/glint_engine/assets/models/duck.glb'),
      material: finish,
    ),
  ];
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 3 : 1,
          ),
        ),
      ),
    );
  }
}

class _LabelChip extends StatelessWidget {
  const _LabelChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .45),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: Colors.white12),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, letterSpacing: 1.2),
      ),
    ),
  );
}
