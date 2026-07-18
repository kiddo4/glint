import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glint/glint.dart';

Uint8List _flatHdr(int width, int height, List<List<int>> rgbePixels) {
  final builder = BytesBuilder()
    ..add('#?RADIANCE\n'.codeUnits)
    ..add('FORMAT=32-bit_rle_rgbe\n'.codeUnits)
    ..add('\n'.codeUnits)
    ..add('-Y $height +X $width\n'.codeUnits);
  for (final pixel in rgbePixels) {
    builder.add(pixel);
  }
  return builder.takeBytes();
}

double _decodeRgbm(ByteData pixels, int pixelIndex, int channel) {
  final value = pixels.getUint8(pixelIndex * 4 + channel) / 255;
  final multiplier = pixels.getUint8(pixelIndex * 4 + 3) / 255;
  return value * multiplier * GlintEnvironment.rgbmRange;
}

void main() {
  test('flat HDR scanlines decode RGBE to linear radiance', () {
    // Exponent 129 → scale 2^(129-136) = 1/128, so 128 decodes to 1.0.
    final image = GlintHdrImage.parse(
      _flatHdr(2, 1, [
        [128, 64, 32, 129],
        [128, 128, 128, 133],
      ]),
    );
    expect(image.width, 2);
    expect(image.height, 1);
    expect(image.rgb[0], closeTo(1, 1e-6));
    expect(image.rgb[1], closeTo(.5, 1e-6));
    expect(image.rgb[2], closeTo(.25, 1e-6));
    // Second pixel carries radiance above 1.0 — the point of HDR.
    expect(image.rgb[3], closeTo(16, 1e-6));
  });

  test('truncated and misdeclared HDR bytes raise actionable errors', () {
    expect(
      () => GlintHdrImage.parse(Uint8List.fromList('#?RADIANCE\n'.codeUnits)),
      throwsA(isA<GlintHdrException>()),
    );
    expect(
      () => GlintHdrImage.parse(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<GlintHdrException>()),
    );
  });

  testWidgets('bundled studio HDRI parses and carries radiance above 1.0', (
    tester,
  ) async {
    final bytes = await tester.runAsync(_loadStudioAsset);
    final image = GlintHdrImage.parse(bytes!);
    expect(image.width, 256);
    expect(image.height, 128);
    var peak = 0.0;
    for (final value in image.rgb) {
      if (value > peak) peak = value;
    }
    expect(peak, greaterThan(1.5));
  });

  test('a uniform environment prefilters to that same radiance everywhere', () {
    const width = 16;
    const height = 8;
    final rgb = Float32List(width * height * 3);
    for (var i = 0; i < width * height; i++) {
      rgb[i * 3] = 2;
      rgb[i * 3 + 1] = 1;
      rgb[i * 3 + 2] = .5;
    }
    final environment = GlintEnvironment.fromLinearRgb(rgb, width, height);
    // Center of the irradiance map: cosine-weighted average of a constant
    // field is the constant itself.
    final centerIndex =
        GlintEnvironment.irradianceHeight ~/
            2 *
            GlintEnvironment.irradianceWidth +
        GlintEnvironment.irradianceWidth ~/ 2;
    expect(
      _decodeRgbm(environment.irradiancePixels, centerIndex, 0),
      closeTo(2, .1),
    );
    expect(
      _decodeRgbm(environment.irradiancePixels, centerIndex, 1),
      closeTo(1, .06),
    );
    expect(
      _decodeRgbm(environment.irradiancePixels, centerIndex, 2),
      closeTo(.5, .04),
    );
    // Every radiance blur band preserves a constant field.
    for (var band = 0; band < GlintEnvironment.levelCount; band++) {
      final bandCenter =
          band *
              GlintEnvironment.radianceWidth *
              GlintEnvironment.radianceHeight +
          GlintEnvironment.radianceHeight ~/
              2 *
              GlintEnvironment.radianceWidth +
          GlintEnvironment.radianceWidth ~/ 2;
      expect(
        _decodeRgbm(environment.radiancePixels, bandCenter, 0),
        closeTo(2, .1),
        reason: 'band $band red',
      );
    }
  });

  test('RGBM encoding round-trips values across the whole range', () {
    const width = 4;
    const height = 2;
    for (final value in [.02, .2, 1.0, 3.0, 5.9]) {
      final rgb = Float32List(width * height * 3);
      for (var i = 0; i < width * height; i++) {
        rgb[i * 3] = value;
        rgb[i * 3 + 1] = value;
        rgb[i * 3 + 2] = value;
      }
      final environment = GlintEnvironment.fromLinearRgb(rgb, width, height);
      expect(
        _decodeRgbm(environment.radiancePixels, 0, 0),
        closeTo(value, value * .05 + .01),
        reason: 'value $value',
      );
    }
  });
}

Future<Uint8List> _loadStudioAsset() async {
  final data = await rootBundle.load(
    'packages/glint/assets/environments/studio.hdr',
  );
  return Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes);
}
