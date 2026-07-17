import 'package:flutter/material.dart';
import 'package:glint/glint.dart';

void main() => runApp(const GlintShowcase());

class GlintShowcase extends StatelessWidget {
  const GlintShowcase({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: Scaffold(
      body: Stack(
        children: [
          const GlintGpuFirstLight(
            fallback: Scene3D(autoRotate: true, scene: ProductShowroom()),
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
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .35),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Text('PNG MATERIAL  •  GPU SAMPLER'),
                    ),
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

class ProductShowroom extends Scene {
  const ProductShowroom();

  @override
  List<Node3D> get children => [
    Node3D(
      name: 'product',
      mesh: Mesh3D.cube(size: 2.4),
      transform: const Transform3D(rotation: Vector3(.25, 0, .12)),
      material: const Material3D(
        color: Color(0xffffb000),
        metallic: .65,
        roughness: .2,
      ),
    ),
  ];
}
