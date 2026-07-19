import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'glb.dart';

/// A reusable model source for Glint's GPU renderer.
sealed class Model {
  const Model();

  const factory Model.asset(String assetKey) = AssetModel;
  const factory Model.network(
    String url, {
    int maximumBytes,
    Duration timeout,
  }) = NetworkModel;

  Future<GlintGlbMesh> load();

  /// The raw GLB bytes, for callers that parse rigs or probe metadata.
  Future<ByteData> read();

  /// A human-readable identity for error messages.
  String get debugLabel;
}

class AssetModel extends Model {
  const AssetModel(this.assetKey);
  final String assetKey;

  @override
  Future<GlintGlbMesh> load() => GlintGlbMesh.fromAsset(assetKey);

  @override
  Future<ByteData> read() => rootBundle.load(assetKey);

  @override
  String get debugLabel => assetKey;

  @override
  bool operator ==(Object other) =>
      other is AssetModel && other.assetKey == assetKey;
  @override
  int get hashCode => assetKey.hashCode;
}

class NetworkModel extends Model {
  const NetworkModel(
    this.url, {
    this.maximumBytes = 25 * 1024 * 1024,
    this.timeout = const Duration(seconds: 20),
  });

  final String url;
  final int maximumBytes;
  final Duration timeout;

  @override
  Future<GlintGlbMesh> load() => GlintGlbMesh.fromNetwork(
    Uri.parse(url),
    maximumBytes: maximumBytes,
    timeout: timeout,
  );

  @override
  Future<ByteData> read() async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final builder = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in response.timeout(timeout)) {
        received += chunk.length;
        if (received > maximumBytes) {
          throw FormatException('GLB exceeds the $maximumBytes byte limit.');
        }
        builder.add(chunk);
      }
      return builder.takeBytes().buffer.asByteData();
    } catch (error) {
      if (error is GlintGlbException) rethrow;
      throw GlintGlbException(url, 'Network GLB load failed', error);
    } finally {
      client.close(force: true);
    }
  }

  @override
  String get debugLabel => url;

  @override
  bool operator ==(Object other) =>
      other is NetworkModel &&
      other.url == url &&
      other.maximumBytes == maximumBytes &&
      other.timeout == timeout;
  @override
  int get hashCode => Object.hash(url, maximumBytes, timeout);
}
