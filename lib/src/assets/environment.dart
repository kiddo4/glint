import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'hdr.dart';
import 'texture_pixels.dart';

/// Prefiltered image-based lighting derived from an equirectangular
/// environment image.
///
/// Two RGBM-encoded RGBA8 maps are produced on the CPU at load time:
/// a cosine-convolved irradiance map for diffuse lighting, and a
/// [levelCount]-band atlas of progressively blurred radiance for specular
/// reflections, stacked vertically from sharp (band 0) to blurred.
class GlintEnvironment {
  const GlintEnvironment({
    required this.irradiancePixels,
    required this.radiancePixels,
  });

  static const int irradianceWidth = 32;
  static const int irradianceHeight = 16;
  static const int radianceWidth = 128;
  static const int radianceHeight = 64;
  static const int levelCount = 5;

  /// The multiplier RGBM encoding can express; must match the shader decode.
  static const double rgbmRange = 6;

  /// RGBM pixels, [irradianceWidth] x [irradianceHeight].
  final ByteData irradiancePixels;

  /// RGBM pixels, [radianceWidth] x [radianceHeight] * [levelCount].
  final ByteData radiancePixels;

  /// Loads a Radiance `.hdr` or PNG/JPEG equirectangular asset and prefilters
  /// it for rendering.
  static Future<GlintEnvironment> fromAsset(
    String assetKey, {
    AssetBundle? bundle,
  }) async {
    final data = await (bundle ?? rootBundle).load(assetKey);
    final bytes = Uint8List.view(
      data.buffer,
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (GlintHdrImage.hasSignature(bytes)) {
      final hdr = GlintHdrImage.parse(bytes, debugLabel: assetKey);
      return fromLinearRgb(hdr.rgb, hdr.width, hdr.height);
    }
    final pixels = await GlintTexturePixels.decode(bytes, debugLabel: assetKey);
    final rgb = Float32List(pixels.width * pixels.height * 3);
    for (var i = 0; i < pixels.width * pixels.height; i++) {
      for (var channel = 0; channel < 3; channel++) {
        final srgb = pixels.bytes.getUint8(i * 4 + channel) / 255;
        rgb[i * 3 + channel] = math.pow(srgb, 2.2).toDouble();
      }
    }
    return fromLinearRgb(rgb, pixels.width, pixels.height);
  }

  /// Prefilters linear equirectangular RGB radiance into the two maps.
  static GlintEnvironment fromLinearRgb(Float32List rgb, int width, int height) {
    if (rgb.length != width * height * 3 || width <= 0 || height <= 0) {
      throw ArgumentError('rgb must contain width*height RGB triplets');
    }
    final base = _resize(rgb, width, height, radianceWidth, radianceHeight);
    final radiance = ByteData(
      radianceWidth * radianceHeight * levelCount * 4,
    );
    var level = base;
    for (var band = 0; band < levelCount; band++) {
      _encodeRgbm(
        level,
        radiance,
        band * radianceWidth * radianceHeight * 4,
      );
      // Round-tripping through a shrunken copy behaves like a wide blur,
      // approximating rougher GGX lobes at each successive band.
      final shrunkWidth = math.max(2, radianceWidth >> (band + 2));
      final shrunkHeight = math.max(1, radianceHeight >> (band + 2));
      level = _resize(
        _resize(level, radianceWidth, radianceHeight, shrunkWidth, shrunkHeight),
        shrunkWidth,
        shrunkHeight,
        radianceWidth,
        radianceHeight,
      );
    }

    final small = _resize(
      rgb,
      width,
      height,
      irradianceWidth,
      irradianceHeight,
    );
    final irradiance = _cosineConvolve(
      small,
      irradianceWidth,
      irradianceHeight,
    );
    final irradiancePixels = ByteData(irradianceWidth * irradianceHeight * 4);
    _encodeRgbm(irradiance, irradiancePixels, 0);
    return GlintEnvironment(
      irradiancePixels: irradiancePixels,
      radiancePixels: radiance,
    );
  }

  /// Box-filter resize with horizontal wrap, suitable for equirect maps.
  static Float32List _resize(
    Float32List source,
    int sourceWidth,
    int sourceHeight,
    int targetWidth,
    int targetHeight,
  ) {
    final output = Float32List(targetWidth * targetHeight * 3);
    final scaleX = sourceWidth / targetWidth;
    final scaleY = sourceHeight / targetHeight;
    for (var y = 0; y < targetHeight; y++) {
      final y0 = (y * scaleY).floor();
      final y1 = math.min(((y + 1) * scaleY).ceil(), sourceHeight);
      for (var x = 0; x < targetWidth; x++) {
        final x0 = (x * scaleX).floor();
        final x1 = math.max(x0 + 1, ((x + 1) * scaleX).ceil());
        var r = 0.0, g = 0.0, b = 0.0, samples = 0;
        for (var sy = y0; sy < y1; sy++) {
          for (var sx = x0; sx < x1; sx++) {
            final index = (sy * sourceWidth + sx % sourceWidth) * 3;
            r += source[index];
            g += source[index + 1];
            b += source[index + 2];
            samples++;
          }
        }
        final base = (y * targetWidth + x) * 3;
        output[base] = r / samples;
        output[base + 1] = g / samples;
        output[base + 2] = b / samples;
      }
    }
    return output;
  }

  /// Convolves an equirect radiance map with a cosine lobe per output normal,
  /// producing normalized irradiance ready to multiply with albedo.
  static Float32List _cosineConvolve(Float32List rgb, int width, int height) {
    final directions = List.generate(width * height, (i) {
      final u = ((i % width) + .5) / width;
      final v = ((i ~/ width) + .5) / height;
      return _equirectDirection(u, v);
    });
    final solidAngles = List.generate(
      width * height,
      (i) => math.sin(((i ~/ width) + .5) / height * math.pi),
    );
    final output = Float32List(width * height * 3);
    for (var i = 0; i < width * height; i++) {
      final normal = directions[i];
      var r = 0.0, g = 0.0, b = 0.0, weightSum = 0.0;
      for (var j = 0; j < width * height; j++) {
        final cosine =
            normal[0] * directions[j][0] +
            normal[1] * directions[j][1] +
            normal[2] * directions[j][2];
        if (cosine <= 0) continue;
        final weight = cosine * solidAngles[j];
        r += rgb[j * 3] * weight;
        g += rgb[j * 3 + 1] * weight;
        b += rgb[j * 3 + 2] * weight;
        weightSum += weight;
      }
      output[i * 3] = r / weightSum;
      output[i * 3 + 1] = g / weightSum;
      output[i * 3 + 2] = b / weightSum;
    }
    return output;
  }

  /// Direction for equirect coordinates, matching the shader's mapping:
  /// `u = atan(z, x) / 2π + .5`, `v = acos(y) / π`.
  static List<double> _equirectDirection(double u, double v) {
    final phi = (u - .5) * 2 * math.pi;
    final theta = v * math.pi;
    final radius = math.sin(theta);
    return [radius * math.cos(phi), math.cos(theta), radius * math.sin(phi)];
  }

  static void _encodeRgbm(Float32List rgb, ByteData output, int byteOffset) {
    for (var i = 0; i < rgb.length ~/ 3; i++) {
      final r = rgb[i * 3], g = rgb[i * 3 + 1], b = rgb[i * 3 + 2];
      final peak = math.max(r, math.max(g, b));
      final multiplier = (peak / rgbmRange).clamp(0.0, 1.0);
      final quantized = (multiplier * 255).ceil();
      // Solve decode = (byte/255) * (quantized/255) * range for byte.
      final scale = quantized == 0 ? 0.0 : 65025 / (quantized * rgbmRange);
      output.setUint8(
        byteOffset + i * 4,
        (r * scale).clamp(0, 255).round(),
      );
      output.setUint8(
        byteOffset + i * 4 + 1,
        (g * scale).clamp(0, 255).round(),
      );
      output.setUint8(
        byteOffset + i * 4 + 2,
        (b * scale).clamp(0, 255).round(),
      );
      output.setUint8(byteOffset + i * 4 + 3, quantized);
    }
  }
}
