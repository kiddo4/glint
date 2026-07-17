import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// The first triangle primitive decoded from a binary glTF 2.0 asset.
class GlintGlbMesh {
  const GlintGlbMesh({
    required this.positions,
    required this.textureCoordinates,
    required this.normals,
    required this.indices,
    required this.uses32BitIndices,
    this.baseColorImageBytes,
    this.baseColorFactor = const [1, 1, 1, 1],
    this.metallicFactor = 1,
    this.roughnessFactor = 1,
  });

  final List<double> positions;
  final List<double> textureCoordinates;
  final List<double> normals;
  final List<int> indices;
  final bool uses32BitIndices;
  final Uint8List? baseColorImageBytes;
  final List<double> baseColorFactor;
  final double metallicFactor;
  final double roughnessFactor;

  int get vertexCount => positions.length ~/ 3;

  /// Loads a GLB from a Flutter asset bundle.
  static Future<GlintGlbMesh> fromAsset(
    String assetKey, {
    AssetBundle? bundle,
  }) async {
    try {
      final bytes = await (bundle ?? rootBundle).load(assetKey);
      return parse(bytes, debugLabel: assetKey);
    } catch (error) {
      if (error is GlintGlbException) rethrow;
      throw GlintGlbException(assetKey, 'Asset could not be loaded', error);
    }
  }

  /// Downloads and parses a GLB with bounded size and actionable HTTP errors.
  static Future<GlintGlbMesh> fromNetwork(
    Uri uri, {
    Duration timeout = const Duration(seconds: 20),
    int maximumBytes = 25 * 1024 * 1024,
  }) async {
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
          throw FormatException('GLB exceeds the $maximumBytes byte limit.');
        }
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      return parse(bytes.buffer.asByteData(), debugLabel: uri.toString());
    } catch (error) {
      if (error is GlintGlbException) rethrow;
      throw GlintGlbException(uri.toString(), 'Network GLB load failed', error);
    } finally {
      client.close(force: true);
    }
  }

  /// Parses a glTF 2.0 binary container and its first triangle primitive.
  static GlintGlbMesh parse(ByteData bytes, {String debugLabel = 'model.glb'}) {
    try {
      final data = ByteData.view(
        bytes.buffer,
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      if (data.lengthInBytes < 20 ||
          data.getUint32(0, Endian.little) != 0x46546c67) {
        throw const FormatException('Missing GLB magic header.');
      }
      final version = data.getUint32(4, Endian.little);
      final declaredLength = data.getUint32(8, Endian.little);
      if (version != 2) {
        throw FormatException('Expected glTF 2.0, found $version.');
      }
      if (declaredLength != data.lengthInBytes) {
        throw const FormatException(
          'GLB declared length does not match its bytes.',
        );
      }

      Map<String, dynamic>? document;
      ByteData? binary;
      var offset = 12;
      while (offset + 8 <= data.lengthInBytes) {
        final length = data.getUint32(offset, Endian.little);
        final type = data.getUint32(offset + 4, Endian.little);
        offset += 8;
        if (offset + length > data.lengthInBytes) {
          throw const FormatException(
            'GLB chunk exceeds the container length.',
          );
        }
        if (type == 0x4e4f534a) {
          final jsonBytes = Uint8List.view(
            data.buffer,
            data.offsetInBytes + offset,
            length,
          );
          document =
              jsonDecode(utf8.decode(jsonBytes).trim()) as Map<String, dynamic>;
        } else if (type == 0x004e4942) {
          binary = ByteData.view(
            data.buffer,
            data.offsetInBytes + offset,
            length,
          );
        }
        offset += length;
      }
      if (document == null || binary == null) {
        throw const FormatException('GLB requires JSON and BIN chunks.');
      }
      return _GlbReader(document, binary).readFirstMesh();
    } catch (error) {
      if (error is GlintGlbException) rethrow;
      throw GlintGlbException(debugLabel, 'GLB parsing failed', error);
    }
  }
}

class _GlbReader {
  _GlbReader(this.document, this.binary);
  final Map<String, dynamic> document;
  final ByteData binary;

  GlintGlbMesh readFirstMesh() {
    final meshes = _list(document['meshes'], 'meshes');
    final primitives = _list((meshes.first as Map)['primitives'], 'primitives');
    final primitive = primitives.first as Map;
    if ((primitive['mode'] as int? ?? 4) != 4) {
      throw const FormatException('Only TRIANGLES primitives are supported.');
    }
    final attributes = primitive['attributes'] as Map;
    final positionAccessor = attributes['POSITION'] as int?;
    final indexAccessor = primitive['indices'] as int?;
    if (positionAccessor == null || indexAccessor == null) {
      throw const FormatException('Primitive requires POSITION and indices.');
    }
    final positions = _readFloats(positionAccessor, 'VEC3');
    final vertexCount = positions.length ~/ 3;
    final uvAccessor = attributes['TEXCOORD_0'] as int?;
    final uvs = uvAccessor == null
        ? List<double>.filled(vertexCount * 2, 0)
        : _readFloats(uvAccessor, 'VEC2');
    if (uvs.length != vertexCount * 2) {
      throw const FormatException('TEXCOORD_0 count must match POSITION.');
    }
    final normalAccessor = attributes['NORMAL'] as int?;
    final normals = normalAccessor == null
        ? _generateNormals(positions, _readIndices(indexAccessor))
        : _readFloats(normalAccessor, 'VEC3');
    if (normals.length != positions.length) {
      throw const FormatException('NORMAL count must match POSITION.');
    }
    final accessor = _accessor(indexAccessor);
    final componentType = accessor['componentType'] as int;
    if (componentType != 5123 && componentType != 5125) {
      throw const FormatException(
        'Indices must be unsigned short or unsigned int.',
      );
    }
    return GlintGlbMesh(
      positions: positions,
      textureCoordinates: uvs,
      normals: normals,
      indices: _readIndices(indexAccessor),
      uses32BitIndices: componentType == 5125,
      baseColorImageBytes: _readBaseColorImage(primitive),
      baseColorFactor: _readBaseColorFactor(primitive),
      metallicFactor: _readMaterialNumber(primitive, 'metallicFactor', 1),
      roughnessFactor: _readMaterialNumber(primitive, 'roughnessFactor', 1),
    );
  }

  double _readMaterialNumber(Map primitive, String key, double fallback) {
    final materialIndex = primitive['material'] as int?;
    final materials = _optionalList(document['materials']);
    if (materialIndex == null || materialIndex >= materials.length) {
      return fallback;
    }
    final material = materials[materialIndex] as Map;
    final pbr = material['pbrMetallicRoughness'] as Map?;
    return (pbr?[key] as num?)?.toDouble() ?? fallback;
  }

  List<double> _generateNormals(List<double> positions, List<int> indices) {
    final normals = List<double>.filled(positions.length, 0);
    for (var i = 0; i + 2 < indices.length; i += 3) {
      final a = indices[i] * 3;
      final b = indices[i + 1] * 3;
      final c = indices[i + 2] * 3;
      final ab = [
        positions[b] - positions[a],
        positions[b + 1] - positions[a + 1],
        positions[b + 2] - positions[a + 2],
      ];
      final ac = [
        positions[c] - positions[a],
        positions[c + 1] - positions[a + 1],
        positions[c + 2] - positions[a + 2],
      ];
      final n = [
        ab[1] * ac[2] - ab[2] * ac[1],
        ab[2] * ac[0] - ab[0] * ac[2],
        ab[0] * ac[1] - ab[1] * ac[0],
      ];
      for (final vertex in [a, b, c]) {
        for (var axis = 0; axis < 3; axis++) {
          normals[vertex + axis] += n[axis];
        }
      }
    }
    for (var i = 0; i < normals.length; i += 3) {
      final length = math.sqrt(
        normals[i] * normals[i] +
            normals[i + 1] * normals[i + 1] +
            normals[i + 2] * normals[i + 2],
      );
      if (length > 0) {
        normals[i] /= length;
        normals[i + 1] /= length;
        normals[i + 2] /= length;
      }
    }
    return normals;
  }

  Uint8List? _readBaseColorImage(Map primitive) {
    final materialIndex = primitive['material'] as int?;
    if (materialIndex == null) return null;
    final materials = _optionalList(document['materials']);
    if (materialIndex >= materials.length) return null;
    final material = materials[materialIndex] as Map;
    final pbr = material['pbrMetallicRoughness'] as Map?;
    final textureInfo = pbr?['baseColorTexture'] as Map?;
    final textureIndex = textureInfo?['index'] as int?;
    if (textureIndex == null) return null;
    final textures = _optionalList(document['textures']);
    if (textureIndex >= textures.length) return null;
    final imageIndex = (textures[textureIndex] as Map)['source'] as int?;
    final images = _optionalList(document['images']);
    if (imageIndex == null || imageIndex >= images.length) return null;
    final image = images[imageIndex] as Map;
    final viewIndex = image['bufferView'] as int?;
    if (viewIndex == null) return null;
    final view = _view(viewIndex);
    final start = view['byteOffset'] as int? ?? 0;
    final length = view['byteLength'] as int;
    return Uint8List.fromList(
      Uint8List.view(binary.buffer, binary.offsetInBytes + start, length),
    );
  }

  List<double> _readBaseColorFactor(Map primitive) {
    final materialIndex = primitive['material'] as int?;
    final materials = _optionalList(document['materials']);
    if (materialIndex == null || materialIndex >= materials.length) {
      return const [1, 1, 1, 1];
    }
    final material = materials[materialIndex] as Map;
    final pbr = material['pbrMetallicRoughness'] as Map?;
    final factor = pbr?['baseColorFactor'] as List?;
    return factor?.map((value) => (value as num).toDouble()).toList() ??
        const [1, 1, 1, 1];
  }

  List<double> _readFloats(int index, String expectedType) {
    final accessor = _accessor(index);
    if (accessor['componentType'] != 5126 || accessor['type'] != expectedType) {
      throw FormatException(
        '$expectedType accessor must contain FLOAT values.',
      );
    }
    final components = expectedType == 'VEC3' ? 3 : 2;
    final view = _view(accessor['bufferView'] as int);
    final count = accessor['count'] as int;
    final start =
        (view['byteOffset'] as int? ?? 0) +
        (accessor['byteOffset'] as int? ?? 0);
    final stride = view['byteStride'] as int? ?? components * 4;
    final output = <double>[];
    for (var element = 0; element < count; element++) {
      for (var component = 0; component < components; component++) {
        output.add(
          binary.getFloat32(
            start + element * stride + component * 4,
            Endian.little,
          ),
        );
      }
    }
    return output;
  }

  List<int> _readIndices(int index) {
    final accessor = _accessor(index);
    if (accessor['type'] != 'SCALAR') {
      throw const FormatException('Index accessor must be SCALAR.');
    }
    final componentType = accessor['componentType'] as int;
    final width = componentType == 5125 ? 4 : 2;
    final view = _view(accessor['bufferView'] as int);
    final start =
        (view['byteOffset'] as int? ?? 0) +
        (accessor['byteOffset'] as int? ?? 0);
    final count = accessor['count'] as int;
    return List.generate(
      count,
      (i) => componentType == 5125
          ? binary.getUint32(start + i * width, Endian.little)
          : binary.getUint16(start + i * width, Endian.little),
    );
  }

  Map _accessor(int index) =>
      _list(document['accessors'], 'accessors')[index] as Map;
  Map _view(int index) =>
      _list(document['bufferViews'], 'bufferViews')[index] as Map;

  List _list(Object? value, String name) {
    if (value is! List || value.isEmpty) {
      throw FormatException('GLB contains no $name.');
    }
    return value;
  }

  List _optionalList(Object? value) => value is List ? value : const [];
}

class GlintGlbException implements Exception {
  const GlintGlbException(this.asset, this.message, [this.cause]);
  final String asset;
  final String message;
  final Object? cause;

  @override
  String toString() =>
      'GlintGlbException($asset): $message'
      '${cause == null ? '' : ' — $cause'}';
}
