import 'package:flutter/material.dart';
import 'package:glint_box3d/glint_box3d.dart';

import 'configurator.dart';
import 'duck_dash.dart';
import 'labels_demo.dart';
import 'physics_demo.dart';
import 'skinned_character_demo.dart';
import 'systems_demo.dart';
import 'viewer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GlintBox3dWorld.ensureInitialized();
  runApp(const GlintShowcase());
}

/// Launcher for the Glint demos: each entry is a self-contained example of
/// one slice of the engine.
class GlintShowcase extends StatelessWidget {
  const GlintShowcase({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffffb000),
        brightness: Brightness.dark,
      ),
    ),
    home: const _LauncherPage(),
  );
}

class _LauncherPage extends StatelessWidget {
  const _LauncherPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 16),
            Text(
              'GLINT',
              style: theme.textTheme.labelLarge?.copyWith(
                letterSpacing: 5,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '3D belongs in the widget tree.',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 32),
            _DemoCard(
              title: 'Duck Dash',
              subtitle:
                  'The flagship game: an endless runner with real glTF '
                  'models, animation, fog, and a Flutter HUD.',
              icon: Icons.directions_run,
              builder: (_) => const DuckDashScreen(),
            ),
            _DemoCard(
              title: 'Product configurator',
              subtitle:
                  'A scrollable product page: scroll-aware orbiting, live '
                  'material swatches, tap picking, anchored labels.',
              icon: Icons.tune,
              builder: (_) => const ConfiguratorPage(),
            ),
            _DemoCard(
              title: 'Model viewer',
              subtitle:
                  'The one-widget integration: a GLB with studio HDRI '
                  'lighting, orbit gestures, and renderer stats.',
              icon: Icons.view_in_ar,
              builder: (_) => const ViewerPage(),
            ),
            _DemoCard(
              title: 'Anchored labels',
              subtitle:
                  'Flutter widgets pinned to the model, fading or hiding '
                  'when the geometry occludes their anchor.',
              icon: Icons.label_outline,
              builder: (_) => const LabelsDemoPage(),
            ),
            _DemoCard(
              title: 'Skinned character',
              subtitle:
                  'Real vertex-level bone deformation in the game loop — a '
                  'skinned fox with interruption-safe clip crossfades.',
              icon: Icons.accessibility_new,
              builder: (_) => const SkinnedCharacterDemoPage(),
            ),
            _DemoCard(
              title: 'Arcade physics lab',
              subtitle:
                  'Full 3D rigid-body physics driving an arcade car: angular '
                  'motion, suspension, grip, gears, boost, and self-filtered rays.',
              icon: Icons.sports_motorsports,
              builder: (_) => const PhysicsDemoPage(),
            ),
            _DemoCard(
              title: 'Advanced systems lab',
              subtitle:
                  'Deterministic GPU particles, generated spatial audio, and '
                  'an offline-compiled custom shader graph working together.',
              icon: Icons.auto_awesome,
              builder: (_) => const SystemsDemoPage(),
            ),
          ],
        ),
      ),
    );
  }
}

class _DemoCard extends StatelessWidget {
  const _DemoCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.builder,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 12,
        ),
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: builder)),
      ),
    );
  }
}
