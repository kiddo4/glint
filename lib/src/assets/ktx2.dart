import 'dart:typed_data';

import 'texture_pixels.dart';

const _ktx2Identifier = <int>[
  0xab,
  0x4b,
  0x54,
  0x58,
  0x20,
  0x32,
  0x30,
  0xbb,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
];

enum GlintKtx2Supercompression {
  none(0),
  basisLz(1),
  zstandard(2),
  zlib(3),
  uastcHdr6x6Intermediate(4),
  xuastcLdr(5),
  unknown(-1);

  const GlintKtx2Supercompression(this.value);
  final int value;

  static GlintKtx2Supercompression fromValue(int value) =>
      values.firstWhere((entry) => entry.value == value, orElse: () => unknown);
}

class GlintKtx2Level {
  const GlintKtx2Level({
    required this.index,
    required this.width,
    required this.height,
    required this.byteOffset,
    required this.byteLength,
    required this.uncompressedByteLength,
  });

  final int index;
  final int width;
  final int height;
  final int byteOffset;
  final int byteLength;
  final int uncompressedByteLength;
}

/// Validated KTX2 structure. The parser performs all offset arithmetic with
/// checked ranges before exposing slices to a transcoder.
class GlintKtx2Container {
  const GlintKtx2Container._({
    required this.bytes,
    required this.vkFormat,
    required this.typeSize,
    required this.width,
    required this.height,
    required this.depth,
    required this.layerCount,
    required this.faceCount,
    required this.supercompression,
    required this.levels,
    required this.isSrgb,
  });

  final Uint8List bytes;
  final int vkFormat;
  final int typeSize;
  final int width;
  final int height;
  final int depth;
  final int layerCount;
  final int faceCount;
  final GlintKtx2Supercompression supercompression;
  final List<GlintKtx2Level> levels;
  final bool isSrgb;

  bool get isBasisUniversal =>
      vkFormat == 0 ||
      supercompression == GlintKtx2Supercompression.basisLz ||
      supercompression == GlintKtx2Supercompression.xuastcLdr ||
      supercompression == GlintKtx2Supercompression.uastcHdr6x6Intermediate;

  static bool hasSignature(Uint8List bytes) {
    if (bytes.length < _ktx2Identifier.length) return false;
    for (var i = 0; i < _ktx2Identifier.length; i++) {
      if (bytes[i] != _ktx2Identifier[i]) return false;
    }
    return true;
  }

  static GlintKtx2Container parse(
    Uint8List bytes, {
    String debugLabel = 'texture.ktx2',
  }) {
    if (!hasSignature(bytes)) {
      throw GlintTextureException(debugLabel, 'Invalid KTX2 identifier.');
    }
    if (bytes.length < 104) {
      throw GlintTextureException(debugLabel, 'Truncated KTX2 header.');
    }
    final data = ByteData.sublistView(bytes);
    final vkFormat = data.getUint32(12, Endian.little);
    final typeSize = data.getUint32(16, Endian.little);
    final width = data.getUint32(20, Endian.little);
    final height = data.getUint32(24, Endian.little);
    final depth = data.getUint32(28, Endian.little);
    final layerCount = data.getUint32(32, Endian.little);
    final faceCount = data.getUint32(36, Endian.little);
    final declaredLevelCount = data.getUint32(40, Endian.little);
    final levelCount = declaredLevelCount == 0 ? 1 : declaredLevelCount;
    final supercompressionValue = data.getUint32(44, Endian.little);
    final dfdOffset = data.getUint32(48, Endian.little);
    final dfdLength = data.getUint32(52, Endian.little);
    final kvdOffset = data.getUint32(56, Endian.little);
    final kvdLength = data.getUint32(60, Endian.little);
    final sgdOffset = data.getUint64(64, Endian.little);
    final sgdLength = data.getUint64(72, Endian.little);

    if (width == 0 || height == 0) {
      throw GlintTextureException(
        debugLabel,
        'Glint requires a two-dimensional KTX2 texture with non-zero size.',
      );
    }
    if (depth != 0 || layerCount > 1 || faceCount != 1) {
      throw GlintTextureException(
        debugLabel,
        'Glint currently accepts one 2D KTX2 image (no volume, array, or cube).',
      );
    }
    final indexEnd = 80 + levelCount * 24;
    if (indexEnd > bytes.length) {
      throw GlintTextureException(debugLabel, 'Truncated KTX2 level index.');
    }
    _validateRange(bytes, dfdOffset, dfdLength, debugLabel, 'DFD');
    _validateRange(bytes, kvdOffset, kvdLength, debugLabel, 'key/value data');
    _validateRange(bytes, sgdOffset, sgdLength, debugLabel, 'global data');

    final levels = <GlintKtx2Level>[];
    for (var i = 0; i < levelCount; i++) {
      final offset = 80 + i * 24;
      final byteOffset = data.getUint64(offset, Endian.little);
      final byteLength = data.getUint64(offset + 8, Endian.little);
      final uncompressedLength = data.getUint64(offset + 16, Endian.little);
      if (byteLength == 0) {
        throw GlintTextureException(
          debugLabel,
          'KTX2 mip level $i has no image data.',
        );
      }
      _validateRange(bytes, byteOffset, byteLength, debugLabel, 'mip level $i');
      levels.add(
        GlintKtx2Level(
          index: i,
          width: (width >> i).clamp(1, width),
          height: (height >> i).clamp(1, height),
          byteOffset: byteOffset,
          byteLength: byteLength,
          uncompressedByteLength: uncompressedLength,
        ),
      );
    }

    var isSrgb = vkFormat == 43 || vkFormat == 50 || vkFormat == 29;
    if (dfdLength >= 16 && dfdOffset + 15 < bytes.length) {
      isSrgb = bytes[dfdOffset + 14] == 2;
    }
    return GlintKtx2Container._(
      bytes: bytes,
      vkFormat: vkFormat,
      typeSize: typeSize,
      width: width,
      height: height,
      depth: depth,
      layerCount: layerCount,
      faceCount: faceCount,
      supercompression: GlintKtx2Supercompression.fromValue(
        supercompressionValue,
      ),
      levels: List.unmodifiable(levels),
      isSrgb: isSrgb,
    );
  }

  GlintKtx2Level levelForMaximumDimension(int? maximumDimension) {
    if (maximumDimension == null) return levels.first;
    if (maximumDimension <= 0) {
      throw ArgumentError.value(
        maximumDimension,
        'maximumDimension',
        'must be positive',
      );
    }
    return levels.firstWhere(
      (level) =>
          level.width <= maximumDimension && level.height <= maximumDimension,
      orElse: () => levels.last,
    );
  }

  Uint8List bytesForLevel(GlintKtx2Level level) => Uint8List.sublistView(
    bytes,
    level.byteOffset,
    level.byteOffset + level.byteLength,
  );

  /// Directly reads uncompressed R8G8B8(A8) KTX2 data. Basis, Zstd, ASTC,
  /// ETC, and BC payloads are delegated to a transcoder backend.
  GlintTexturePixels decodeUncompressed({int? maximumDimension}) {
    if (supercompression != GlintKtx2Supercompression.none) {
      throw StateError('The KTX2 payload is supercompressed.');
    }
    final level = levelForMaximumDimension(maximumDimension);
    final source = bytesForLevel(level);
    final pixelCount = level.width * level.height;
    final output = Uint8List(pixelCount * 4);
    switch (vkFormat) {
      case 37: // VK_FORMAT_R8G8B8A8_UNORM
      case 43: // VK_FORMAT_R8G8B8A8_SRGB
        if (source.length < output.length) {
          throw StateError('KTX2 RGBA mip is truncated.');
        }
        output.setRange(0, output.length, source);
      case 23: // VK_FORMAT_R8G8B8_UNORM
      case 29: // VK_FORMAT_R8G8B8_SRGB
        if (source.length < pixelCount * 3) {
          throw StateError('KTX2 RGB mip is truncated.');
        }
        for (var i = 0; i < pixelCount; i++) {
          output[i * 4] = source[i * 3];
          output[i * 4 + 1] = source[i * 3 + 1];
          output[i * 4 + 2] = source[i * 3 + 2];
          output[i * 4 + 3] = 255;
        }
      case 44: // VK_FORMAT_B8G8R8A8_UNORM
      case 50: // VK_FORMAT_B8G8R8A8_SRGB
        if (source.length < output.length) {
          throw StateError('KTX2 BGRA mip is truncated.');
        }
        for (var i = 0; i < pixelCount; i++) {
          output[i * 4] = source[i * 4 + 2];
          output[i * 4 + 1] = source[i * 4 + 1];
          output[i * 4 + 2] = source[i * 4];
          output[i * 4 + 3] = source[i * 4 + 3];
        }
      default:
        throw UnsupportedError('KTX2 Vulkan format $vkFormat needs a backend.');
    }
    return GlintTexturePixels(
      width: level.width,
      height: level.height,
      bytes: ByteData.sublistView(output),
      colorSpace: isSrgb
          ? GlintTextureColorSpace.srgb
          : GlintTextureColorSpace.linear,
    );
  }
}

void _validateRange(
  Uint8List bytes,
  int offset,
  int length,
  String label,
  String section,
) {
  if (length == 0) return;
  if (offset < 0 || length < 0 || offset > bytes.length - length) {
    throw GlintTextureException(label, 'KTX2 $section lies outside the file.');
  }
}
