import 'package:flutter/material.dart';
import 'package:glint/glint.dart';

/// The minimal Glint integration: one widget, one model, studio lighting,
/// orbit gestures, and live renderer stats.
class ViewerPage extends StatelessWidget {
  const ViewerPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBodyBehindAppBar: true,
    appBar: AppBar(
      title: const Text('Model viewer'),
      backgroundColor: Colors.transparent,
    ),
    body: const GlintGpuFirstLight(
      model: Model.asset('packages/glint/assets/models/duck.glb'),
      environmentAsset: 'packages/glint/assets/environments/studio.hdr',
      showStats: true,
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
