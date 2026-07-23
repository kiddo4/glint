import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    await CBuilder.library(
      name: 'glint_basis_native',
      assetName: 'glint_basis_native',
      sources: const [
        'native/shim/glint_basis.cpp',
        'native/basisu/transcoder/basisu_transcoder.cpp',
        'native/basisu/zstd/zstddeclib.c',
      ],
      includes: const [
        'native/shim',
        'native/basisu/transcoder',
        'native/basisu/zstd',
      ],
      defines: const {
        'BASISD_SUPPORT_KTX2': '1',
        'BASISD_SUPPORT_KTX2_ZSTD': '1',
      },
      language: Language.cpp,
      std: 'c++17',
    ).run(input: input, output: output);
  });
}
