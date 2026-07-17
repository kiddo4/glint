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
}

class AssetModel extends Model {
  const AssetModel(this.assetKey);
  final String assetKey;

  @override
  Future<GlintGlbMesh> load() => GlintGlbMesh.fromAsset(assetKey);

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
  bool operator ==(Object other) =>
      other is NetworkModel &&
      other.url == url &&
      other.maximumBytes == maximumBytes &&
      other.timeout == timeout;
  @override
  int get hashCode => Object.hash(url, maximumBytes, timeout);
}
