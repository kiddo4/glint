import 'dart:math' as math;
import 'dart:typed_data';

/// A decoded Radiance (.hdr) image as linear floating-point RGB.
class GlintHdrImage {
  const GlintHdrImage({
    required this.width,
    required this.height,
    required this.rgb,
  });

  final int width;
  final int height;

  /// Linear radiance triplets, row-major from the top-left, length
  /// `width * height * 3`.
  final Float32List rgb;

  /// Whether [bytes] carry the Radiance `#?` signature.
  static bool hasSignature(Uint8List bytes) =>
      bytes.length >= 2 && bytes[0] == 0x23 && bytes[1] == 0x3f;

  /// Parses a Radiance RGBE image, supporting both flat and new-style
  /// run-length-encoded scanlines.
  static GlintHdrImage parse(
    Uint8List bytes, {
    String debugLabel = 'environment.hdr',
  }) {
    try {
      var offset = 0;
      String readLine() {
        final start = offset;
        while (offset < bytes.length && bytes[offset] != 0x0a) {
          offset++;
        }
        if (offset >= bytes.length) {
          throw const FormatException('Unexpected end of HDR header.');
        }
        return String.fromCharCodes(bytes.sublist(start, offset++));
      }

      if (!hasSignature(bytes)) {
        throw const FormatException('Missing Radiance #? signature.');
      }
      readLine();
      var formatSeen = false;
      for (var line = readLine(); line.isNotEmpty; line = readLine()) {
        if (line.startsWith('FORMAT=')) {
          if (line != 'FORMAT=32-bit_rle_rgbe') {
            throw FormatException('Unsupported HDR format: $line');
          }
          formatSeen = true;
        }
      }
      if (!formatSeen) {
        throw const FormatException('HDR header declares no RGBE format.');
      }
      final dimensions = RegExp(
        r'^-Y (\d+) \+X (\d+)$',
      ).firstMatch(readLine());
      if (dimensions == null) {
        throw const FormatException(
          'Only top-down, left-to-right HDR orientation is supported.',
        );
      }
      final height = int.parse(dimensions.group(1)!);
      final width = int.parse(dimensions.group(2)!);
      if (width <= 0 || height <= 0) {
        throw const FormatException('HDR dimensions must be positive.');
      }

      final rgb = Float32List(width * height * 3);
      final scanline = Uint8List(width * 4);
      int readByte() {
        if (offset >= bytes.length) {
          throw const FormatException('Unexpected end of HDR pixel data.');
        }
        return bytes[offset++];
      }

      for (var y = 0; y < height; y++) {
        final b0 = readByte(), b1 = readByte(), b2 = readByte(), b3 = readByte();
        if (b0 == 2 && b1 == 2 && ((b2 << 8) | b3) == width && width >= 8) {
          // New-style RLE: four separately encoded component planes.
          for (var component = 0; component < 4; component++) {
            var x = 0;
            while (x < width) {
              final count = readByte();
              if (count > 128) {
                final value = readByte();
                for (var i = 0; i < count - 128; i++) {
                  scanline[x++ * 4 + component] = value;
                }
              } else if (count > 0) {
                for (var i = 0; i < count; i++) {
                  scanline[x++ * 4 + component] = readByte();
                }
              } else {
                throw const FormatException('Zero-length HDR RLE run.');
              }
              if (x > width) {
                throw const FormatException('HDR RLE run overflows scanline.');
              }
            }
          }
        } else {
          // Flat RGBE pixels.
          scanline[0] = b0;
          scanline[1] = b1;
          scanline[2] = b2;
          scanline[3] = b3;
          for (var x = 4; x < width * 4; x++) {
            scanline[x] = readByte();
          }
        }
        for (var x = 0; x < width; x++) {
          final exponent = scanline[x * 4 + 3];
          final scale = exponent == 0
              ? 0.0
              : math.pow(2.0, exponent - 136).toDouble();
          final base = (y * width + x) * 3;
          rgb[base] = scanline[x * 4] * scale;
          rgb[base + 1] = scanline[x * 4 + 1] * scale;
          rgb[base + 2] = scanline[x * 4 + 2] * scale;
        }
      }
      return GlintHdrImage(width: width, height: height, rgb: rgb);
    } catch (error) {
      if (error is GlintHdrException) rethrow;
      throw GlintHdrException(debugLabel, 'HDR parsing failed', error);
    }
  }
}

/// An actionable HDR decoding error that retains the failing asset identity.
class GlintHdrException implements Exception {
  const GlintHdrException(this.asset, this.message, [this.cause]);

  final String asset;
  final String message;
  final Object? cause;

  @override
  String toString() =>
      'GlintHdrException($asset): $message'
      '${cause == null ? '' : ' — $cause'}';
}
