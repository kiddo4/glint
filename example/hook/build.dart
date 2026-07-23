import 'package:glint_engine/shader_graph_build.dart';
import 'package:hooks/hooks.dart';

Future<void> main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    await buildGlintShaderGraphBundle(
      buildInput: input,
      buildOutput: output,
      bundleName: 'glint_materials',
      graphs: const {
        'HologramFragment': 'assets/shaders/hologram.shadergraph.json',
      },
    );
  });
}
