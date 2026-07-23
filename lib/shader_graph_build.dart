/// Build-hook helpers for compiling Glint shader graphs into Flutter GPU
/// shader bundles. Import this file from an application's `hook/build.dart`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_gpu_shaders/build.dart';
import 'package:hooks/hooks.dart';

import 'src/shader_graph.dart';

export 'package:flutter_gpu_shaders/build.dart' show ShaderBundleAssetMode;

/// Compiles JSON graph files into one offline Flutter GPU shader bundle.
///
/// [graphs] maps the runtime fragment entry-point name to a package-root
/// relative graph JSON file. The returned bundle uses the standard
/// `build/shaderbundles/[bundleName].shaderbundle` asset path unless DataAssets
/// are enabled through [assetMode].
Future<ShaderBundleBuildResult> buildGlintShaderGraphBundle({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
  required Map<String, String> graphs,
  String bundleName = 'glint_materials',
  ShaderBundleAssetMode assetMode = ShaderBundleAssetMode.legacyOnly,
  String? dataAssetName,
  int? glesLanguageVersion,
}) async {
  final identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
  if (!identifier.hasMatch(bundleName) || graphs.isEmpty) {
    throw ArgumentError(
      'Bundle name must be valid and graphs must not be empty.',
    );
  }
  final glintLibrary = await Isolate.resolvePackageUri(
    Uri.parse('package:glint_engine/shader_graph_build.dart'),
  );
  if (glintLibrary == null) {
    throw StateError('Unable to resolve the glint_engine package root.');
  }
  final glintShaderDirectory = glintLibrary.resolve('../shaders/');
  final generatedRelative = 'build/glint_shader_graphs/';
  final generatedDirectory = Directory.fromUri(
    buildInput.packageRoot.resolve(generatedRelative),
  );
  await generatedDirectory.create(recursive: true);

  final manifest = <String, Object?>{};
  final compiler = GlintShaderGraphCompiler();
  for (final entry in graphs.entries) {
    if (!identifier.hasMatch(entry.key)) {
      throw ArgumentError.value(
        entry.key,
        'graphs',
        'invalid entry-point name',
      );
    }
    final graphUri = buildInput.packageRoot.resolve(entry.value);
    final graph = GlintShaderGraph.parse(
      await File.fromUri(graphUri).readAsString(),
    );
    final program = compiler.compile(graph);
    final shaderRelative = '$generatedRelative${entry.key}.frag';
    await File.fromUri(
      buildInput.packageRoot.resolve(shaderRelative),
    ).writeAsString(program.fragmentSource);
    manifest[entry.key] = {'type': 'fragment', 'file': shaderRelative};
    buildOutput.dependencies.add(graphUri);
  }

  final manifestRelative = '$generatedRelative$bundleName.shaderbundle.json';
  await File.fromUri(
    buildInput.packageRoot.resolve(manifestRelative),
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));
  buildOutput.dependencies.addAll([
    glintShaderDirectory.resolve('material_graph_types.glsl'),
    glintShaderDirectory.resolve('material_graph_pbr.glsl'),
  ]);
  return buildShaderBundleJson(
    buildInput: buildInput,
    buildOutput: buildOutput,
    manifestFileName: manifestRelative,
    includeDirectories: [glintShaderDirectory],
    assetMode: assetMode,
    dataAssetName: dataAssetName,
    glesLanguageVersion: glesLanguageVersion,
  );
}
