import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glint_engine/glint_engine.dart';

void main() {
  test(
    'compiles a typed graph with parameters and engine PBR includes',
    () async {
      final graph = GlintShaderGraph.parse(
        await File('test/fixtures/hologram.shadergraph.json').readAsString(),
      );
      final program = const GlintShaderGraphCompiler().compile(graph);

      expect(program.parameters['tint']?.slot, 0);
      expect(program.textureUniforms, isEmpty);
      expect(program.fragmentSource, contains('glint_graph_surface'));
      expect(program.fragmentSource, contains('material_graph_pbr.glsl'));
      expect(program.fragmentSource, contains('graph_info.runtime.x'));
    },
  );

  test('rejects graph cycles', () {
    final graph = GlintShaderGraph(
      nodes: const [
        GlintShaderNode(
          id: 'a',
          type: GlintShaderNodeType.add,
          inputs: {'a': 'b', 'b': 'b'},
        ),
        GlintShaderNode(
          id: 'b',
          type: GlintShaderNodeType.add,
          inputs: {'a': 'a', 'b': 'a'},
        ),
      ],
      output: const GlintShaderGraphOutput(baseColor: 'a'),
    );
    expect(
      () => const GlintShaderGraphCompiler().compile(graph),
      throwsFormatException,
    );
  });

  test('packs graph defaults and runtime overrides into reflected slots', () {
    final graph = GlintShaderGraph(
      nodes: const [
        GlintShaderNode(
          id: 'color',
          type: GlintShaderNodeType.parameter,
          properties: {
            'name': 'paint',
            'default': [1.0, 0.0, 0.0, 1.0],
          },
        ),
      ],
      output: const GlintShaderGraphOutput(baseColor: 'color'),
    );
    final program = const GlintShaderGraphCompiler().compile(graph);
    final material = GlintShaderGraphMaterial(
      bundleAsset: 'materials.shaderbundle',
      fragmentEntry: 'Paint',
      program: program,
      parameters: const {'paint': GlintParticleColor(0, 1, 0, .5)},
    );
    final packed = material.packUniforms(2.5);

    expect(packed.take(8), [2.5, 0, 0, 0, 0, 1, 0, .5]);
  });
}
