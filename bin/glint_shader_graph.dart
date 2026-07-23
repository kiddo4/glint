import 'dart:io';

import 'package:glint_engine/src/shader_graph.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run glint_engine:glint_shader_graph '
      '<graph.json> <output.frag>',
    );
    exitCode = 64;
    return;
  }
  try {
    final graph = GlintShaderGraph.parse(
      await File(arguments[0]).readAsString(),
    );
    final program = const GlintShaderGraphCompiler().compile(graph);
    await File(arguments[1]).writeAsString(program.fragmentSource);
    stdout.writeln(
      'Generated ${arguments[1]} '
      '(${program.parameters.length} parameters, '
      '${program.textureUniforms.length} textures).',
    );
  } catch (error) {
    stderr.writeln('Shader graph compilation failed: $error');
    exitCode = 1;
  }
}
