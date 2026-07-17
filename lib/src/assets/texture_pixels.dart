import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// Decoded, tightly packed RGBA pixels ready for a Glint GPU texture upload.
class GlintTexturePixels {
  const GlintTexturePixels({
    required this.width,
    required this.height,
    required this.bytes,
  });

  final int width;
  final int height;
  final ByteData bytes;

  /// Decodes a PNG or JPEG from a Flutter asset bundle.
  static Future<GlintTexturePixels> fromAsset(
    String assetKey, {
    AssetBundle? bundle,
  }) async {
    try {
      final data = await (bundle ?? rootBundle).load(assetKey);
      return decode(
        Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes),
        debugLabel: assetKey,
      );
    } catch (error) {
      if (error is GlintTextureException) rethrow;
      throw GlintTextureException(assetKey, 'Asset could not be loaded', error);
    }
  }

  /// Decodes encoded PNG or JPEG bytes to RGBA8 pixels.
  static Future<GlintTexturePixels> decode(
    Uint8List encoded, {
    String debugLabel = 'texture',
  }) async {
    if (!_hasPngSignature(encoded) && !_hasJpegSignature(encoded)) {
      throw GlintTextureException(
        debugLabel,
        'Unsupported or corrupt image. Glint v0.1 accepts PNG and JPEG.',
      );
    }
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(encoded);
      final frame = await codec.getNextFrame();
      image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        throw StateError('Flutter returned no RGBA pixel data.');
      }
      return GlintTexturePixels(
        width: image.width,
        height: image.height,
        bytes: data,
      );
    } catch (error) {
      throw GlintTextureException(
        debugLabel,
        'PNG/JPEG decoding failed',
        error,
      );
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  static bool _hasPngSignature(Uint8List bytes) =>
      bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a;

  static bool _hasJpegSignature(Uint8List bytes) =>
      bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff;
}

/// An actionable texture error that retains the failing asset identity.
class GlintTextureException implements Exception {
  const GlintTextureException(this.asset, this.message, [this.cause]);

  final String asset;
  final String message;
  final Object? cause;

  @override
  String toString() =>
      'GlintTextureException($asset): $message'
      '${cause == null ? '' : ' — $cause'}';
}
