import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'ktx2.dart';

enum GlintTextureColorSpace { linear, srgb }

/// Optional production backend for Basis Universal `.ktx2` and `.basis`
/// payloads. `glint_basis` supplies the reference implementation.
abstract interface class GlintBasisTextureTranscoder {
  Future<GlintTexturePixels> transcodeKtx2(
    GlintKtx2Container container, {
    int? maximumDimension,
    required String debugLabel,
  });

  Future<GlintTexturePixels> transcodeBasis(
    Uint8List bytes, {
    int? maximumDimension,
    required String debugLabel,
  });
}

/// Decoder policy shared by imported model textures and standalone textures.
class GlintTextureDecoder {
  const GlintTextureDecoder({this.basisTranscoder});

  final GlintBasisTextureTranscoder? basisTranscoder;

  Future<GlintTexturePixels> decode(
    Uint8List encoded, {
    String debugLabel = 'texture',
    int? maximumDimension,
  }) async {
    if (maximumDimension != null && maximumDimension <= 0) {
      throw ArgumentError.value(
        maximumDimension,
        'maximumDimension',
        'must be positive',
      );
    }
    if (GlintKtx2Container.hasSignature(encoded)) {
      final container = GlintKtx2Container.parse(
        encoded,
        debugLabel: debugLabel,
      );
      try {
        if (!container.isBasisUniversal &&
            container.supercompression == GlintKtx2Supercompression.none) {
          return container.decodeUncompressed(
            maximumDimension: maximumDimension,
          );
        }
      } on UnsupportedError {
        // A backend may understand the contained GPU format even when the
        // portable RGBA path does not.
      } on StateError catch (error) {
        throw GlintTextureException(
          debugLabel,
          'Uncompressed KTX2 decoding failed',
          error,
        );
      }
      final transcoder = basisTranscoder;
      if (transcoder == null) {
        throw GlintTextureException(
          debugLabel,
          'This KTX2 payload needs a Basis transcoder. Add glint_basis and '
          'pass GlintTextureDecoder(basisTranscoder: GlintBasisTranscoder()).',
        );
      }
      return transcoder.transcodeKtx2(
        container,
        maximumDimension: maximumDimension,
        debugLabel: debugLabel,
      );
    }
    if (_hasBasisSignature(encoded)) {
      final transcoder = basisTranscoder;
      if (transcoder == null) {
        throw GlintTextureException(
          debugLabel,
          'Standalone Basis texture needs glint_basis.',
        );
      }
      return transcoder.transcodeBasis(
        encoded,
        maximumDimension: maximumDimension,
        debugLabel: debugLabel,
      );
    }
    return GlintTexturePixels._decodeRaster(
      encoded,
      debugLabel: debugLabel,
      maximumDimension: maximumDimension,
    );
  }
}

/// Decoded, tightly packed RGBA pixels ready for a Glint GPU texture upload.
class GlintTexturePixels {
  const GlintTexturePixels({
    required this.width,
    required this.height,
    required this.bytes,
    this.colorSpace = GlintTextureColorSpace.srgb,
  });

  final int width;
  final int height;
  final ByteData bytes;
  final GlintTextureColorSpace colorSpace;

  /// Decodes a PNG or JPEG from a Flutter asset bundle.
  static Future<GlintTexturePixels> fromAsset(
    String assetKey, {
    AssetBundle? bundle,
    GlintTextureDecoder decoder = const GlintTextureDecoder(),
    int? maximumDimension,
  }) async {
    try {
      final data = await (bundle ?? rootBundle).load(assetKey);
      return decoder.decode(
        Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes),
        debugLabel: assetKey,
        maximumDimension: maximumDimension,
      );
    } catch (error) {
      if (error is GlintTextureException) rethrow;
      throw GlintTextureException(assetKey, 'Asset could not be loaded', error);
    }
  }

  /// Decodes encoded PNG or JPEG bytes to RGBA8 pixels. When
  /// [maximumDimension] is set, larger images are downscaled to fit it —
  /// UV mapping is unaffected and GPU memory stays bounded.
  static Future<GlintTexturePixels> decode(
    Uint8List encoded, {
    String debugLabel = 'texture',
    int? maximumDimension,
    GlintTextureDecoder decoder = const GlintTextureDecoder(),
  }) => decoder.decode(
    encoded,
    debugLabel: debugLabel,
    maximumDimension: maximumDimension,
  );

  static Future<GlintTexturePixels> _decodeRaster(
    Uint8List encoded, {
    required String debugLabel,
    int? maximumDimension,
  }) async {
    if (!_hasPngSignature(encoded) && !_hasJpegSignature(encoded)) {
      throw GlintTextureException(
        debugLabel,
        'Unsupported or corrupt texture. Expected PNG, JPEG, KTX2, or Basis.',
      );
    }
    ui.Codec? codec;
    ui.Image? image;
    try {
      if (maximumDimension == null) {
        codec = await ui.instantiateImageCodec(encoded);
      } else {
        final buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        final scale =
            maximumDimension /
            math.max(1, math.max(descriptor.width, descriptor.height));
        codec = await descriptor.instantiateCodec(
          targetWidth: scale >= 1
              ? descriptor.width
              : (descriptor.width * scale).round(),
          targetHeight: scale >= 1
              ? descriptor.height
              : (descriptor.height * scale).round(),
        );
      }
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
        colorSpace: GlintTextureColorSpace.srgb,
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

bool _hasBasisSignature(Uint8List bytes) =>
    bytes.length >= 2 && bytes[0] == 0x73 && bytes[1] == 0x42;

/// Reusable texture source for particles and custom materials.
sealed class GlintTextureSource {
  const GlintTextureSource();

  const factory GlintTextureSource.asset(String assetKey) =
      GlintAssetTextureSource;
  const factory GlintTextureSource.file(String path) = GlintFileTextureSource;
  const factory GlintTextureSource.network(
    String url, {
    int maximumBytes,
    Duration timeout,
  }) = GlintNetworkTextureSource;
  factory GlintTextureSource.memory(String debugLabel, Uint8List bytes) =
      GlintMemoryTextureSource;

  Future<Uint8List> read();
  String get debugLabel;
}

class GlintAssetTextureSource extends GlintTextureSource {
  const GlintAssetTextureSource(this.assetKey);
  final String assetKey;

  @override
  Future<Uint8List> read() async {
    final data = await rootBundle.load(assetKey);
    return Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes);
  }

  @override
  String get debugLabel => assetKey;

  @override
  bool operator ==(Object other) =>
      other is GlintAssetTextureSource && other.assetKey == assetKey;

  @override
  int get hashCode => assetKey.hashCode;
}

class GlintFileTextureSource extends GlintTextureSource {
  const GlintFileTextureSource(this.path);
  final String path;

  @override
  Future<Uint8List> read() => File(path).readAsBytes();

  @override
  String get debugLabel => path;

  @override
  bool operator ==(Object other) =>
      other is GlintFileTextureSource && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

class GlintNetworkTextureSource extends GlintTextureSource {
  const GlintNetworkTextureSource(
    this.url, {
    this.maximumBytes = 32 * 1024 * 1024,
    this.timeout = const Duration(seconds: 20),
  });

  final String url;
  final int maximumBytes;
  final Duration timeout;

  @override
  Future<Uint8List> read() async {
    if (maximumBytes <= 0) {
      throw ArgumentError.value(
        maximumBytes,
        'maximumBytes',
        'must be positive',
      );
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
    final uri = Uri.parse(url);
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final builder = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in response.timeout(timeout)) {
        received += chunk.length;
        if (received > maximumBytes) {
          throw const FormatException('Texture exceeds maximumBytes.');
        }
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  @override
  String get debugLabel => url;

  @override
  bool operator ==(Object other) =>
      other is GlintNetworkTextureSource &&
      other.url == url &&
      other.maximumBytes == maximumBytes &&
      other.timeout == timeout;

  @override
  int get hashCode => Object.hash(url, maximumBytes, timeout);
}

/// Encoded texture bytes supplied by an application cache, archive, editor, or
/// procedural asset pipeline without a temporary file.
class GlintMemoryTextureSource extends GlintTextureSource {
  GlintMemoryTextureSource(this.debugLabel, this.bytes) {
    if (debugLabel.trim().isEmpty) {
      throw ArgumentError.value(debugLabel, 'debugLabel', 'must not be empty');
    }
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'must not be empty');
    }
  }

  @override
  final String debugLabel;
  final Uint8List bytes;

  @override
  Future<Uint8List> read() async => bytes;

  @override
  bool operator ==(Object other) =>
      other is GlintMemoryTextureSource &&
      other.debugLabel == debugLabel &&
      identical(other.bytes, bytes);

  @override
  int get hashCode => Object.hash(debugLabel, identityHashCode(bytes));
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
