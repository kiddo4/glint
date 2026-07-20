import 'package:flutter/material.dart';
import 'package:glint_engine/glint_engine.dart';

/// Flutter widgets pinned to points on the model: anchors live in the
/// model's own coordinate space, track it while it orbits, and obey their
/// occlusion policy when the geometry hides them.
class LabelsDemoPage extends StatelessWidget {
  const LabelsDemoPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBodyBehindAppBar: true,
    appBar: AppBar(
      title: const Text('Anchored labels'),
      backgroundColor: Colors.transparent,
    ),
    body: const GlintGpuFirstLight(
      model: Model.asset('packages/glint_engine/assets/models/duck.glb'),
      environmentAsset: 'packages/glint_engine/assets/environments/studio.hdr',
      labels: [
        Label3D(
          anchor: Vector3(.96, 1.34, -.12),
          offset: Offset(0, -30),
          child: _LabelChip(text: 'FADES WHEN OCCLUDED'),
        ),
        Label3D(
          anchor: Vector3(-.69, .52, -.02),
          offset: Offset(0, -30),
          occlusion: Label3DOcclusion.hide,
          child: _LabelChip(text: 'HIDES WHEN OCCLUDED'),
        ),
      ],
      fallback: Center(
        child: Text(
          'Flutter GPU renderer unavailable.\n'
          'Launch with --enable-impeller --enable-flutter-gpu.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
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
