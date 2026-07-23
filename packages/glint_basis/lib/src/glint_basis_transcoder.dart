import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:glint_engine/glint_engine.dart';

import 'native_bindings.dart';

/// Official Basis Universal reference transcoder backend for Glint.
class GlintBasisTranscoder implements GlintBasisTextureTranscoder {
  const GlintBasisTranscoder();

  @override
  Future<GlintTexturePixels> transcodeKtx2(
    GlintKtx2Container container, {
    int? maximumDimension,
    required String debugLabel,
  }) async {
    final level = container.levelForMaximumDimension(maximumDimension).index;
    final result = await Isolate.run(
      () => _transcode(container.bytes, level, ktx2: true),
    );
    return GlintTexturePixels(
      width: result.width,
      height: result.height,
      bytes: ByteData.sublistView(result.bytes),
      colorSpace: result.srgb
          ? GlintTextureColorSpace.srgb
          : GlintTextureColorSpace.linear,
    );
  }

  @override
  Future<GlintTexturePixels> transcodeBasis(
    Uint8List bytes, {
    int? maximumDimension,
    required String debugLabel,
  }) async {
    final result = await Isolate.run(
      () => _transcode(bytes, null, ktx2: false, maximum: maximumDimension),
    );
    return GlintTexturePixels(
      width: result.width,
      height: result.height,
      bytes: ByteData.sublistView(result.bytes),
      colorSpace: result.srgb
          ? GlintTextureColorSpace.srgb
          : GlintTextureColorSpace.linear,
    );
  }
}

final class _NativeTextureResult {
  const _NativeTextureResult({
    required this.width,
    required this.height,
    required this.srgb,
    required this.bytes,
  });

  final int width;
  final int height;
  final bool srgb;
  final Uint8List bytes;
}

_NativeTextureResult _transcode(
  Uint8List bytes,
  int? requestedLevel, {
  required bool ktx2,
  int? maximum,
}) {
  final input = calloc<Uint8>(bytes.length);
  final info = calloc<Uint32>(5);
  try {
    input.asTypedList(bytes.length).setAll(0, bytes);
    final infoCode = ktx2
        ? glintBasisKtx2Info(input, bytes.length, info)
        : glintBasisFileInfo(input, bytes.length, info);
    _check(infoCode);
    if (info[4] != 0) {
      throw UnsupportedError(
        'Glint currently renders LDR textures; the Basis payload is HDR.',
      );
    }
    var level = requestedLevel ?? 0;
    if (requestedLevel == null && maximum != null) {
      while (level + 1 < info[2] &&
          ((info[0] >> level) > maximum || (info[1] >> level) > maximum)) {
        level++;
      }
    }
    final width = (info[0] >> level).clamp(1, info[0]);
    final height = (info[1] >> level).clamp(1, info[1]);
    final byteLength = width * height * 4;
    final output = calloc<Uint8>(byteLength);
    try {
      final code = ktx2
          ? glintBasisKtx2TranscodeRgba8(
              input,
              bytes.length,
              level,
              output,
              byteLength,
            )
          : glintBasisFileTranscodeRgba8(
              input,
              bytes.length,
              level,
              output,
              byteLength,
            );
      _check(code);
      return _NativeTextureResult(
        width: width,
        height: height,
        srgb: info[3] != 0,
        bytes: Uint8List.fromList(output.asTypedList(byteLength)),
      );
    } finally {
      calloc.free(output);
    }
  } finally {
    calloc.free(info);
    calloc.free(input);
  }
}

void _check(int code) {
  if (code == 0) return;
  final error = glintBasisLastError();
  throw FormatException(
    error == nullptr
        ? 'Basis transcoding failed ($code).'
        : error.toDartString(),
  );
}
