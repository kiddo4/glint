import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../math.dart';

/// One material an aggregated mesh draws with.
class GlintGlbMaterial {
  const GlintGlbMaterial({
    this.baseColorImageBytes,
    this.baseColorFactor = const [1, 1, 1, 1],
    this.metallicFactor = 1,
    this.roughnessFactor = 1,
  });

  final Uint8List? baseColorImageBytes;
  final List<double> baseColorFactor;
  final double metallicFactor;
  final double roughnessFactor;
}

/// A contiguous index range of an aggregated mesh sharing one material.
class GlintGlbSubmesh {
  const GlintGlbSubmesh({
    required this.indexOffset,
    required this.indexCount,
    required this.materialIndex,
  });

  final int indexOffset;
  final int indexCount;

  /// Index into [GlintGlbMesh.materials].
  final int materialIndex;
}

/// Triangle geometry aggregated from the active scene of a binary glTF asset.
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
    this.materials = const [GlintGlbMaterial()],
    this.submeshes = const [],
    this.worldTransform = const [
      1,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      1,
    ],
    required this.boundsMinimum,
    required this.boundsMaximum,
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

  /// Every material the scene's primitives reference; indices in [indices]
  /// are grouped so each [GlintGlbSubmesh] is one contiguous span.
  final List<GlintGlbMaterial> materials;

  /// Per-material index ranges. Empty for meshes built before submesh
  /// support; treat the whole index buffer as one span in that case.
  final List<GlintGlbSubmesh> submeshes;

  final List<double> worldTransform;
  final List<double> boundsMinimum;
  final List<double> boundsMaximum;

  int get vertexCount => positions.length ~/ 3;

  /// Intersects a ray in this mesh's space against every triangle and returns
  /// the nearest hit, or null when the ray misses the mesh entirely.
  GlintRayHit? intersectRay(GlintRay ray) {
    if (!ray.intersectsBounds(
      Vector3(boundsMinimum[0], boundsMinimum[1], boundsMinimum[2]),
      Vector3(boundsMaximum[0], boundsMaximum[1], boundsMaximum[2]),
    )) {
      return null;
    }
    GlintRayHit? nearest;
    for (var i = 0; i + 2 < indices.length; i += 3) {
      final distance = ray.intersectTriangle(
        _position(indices[i]),
        _position(indices[i + 1]),
        _position(indices[i + 2]),
      );
      if (distance != null &&
          (nearest == null || distance < nearest.distance)) {
        nearest = GlintRayHit(
          distance: distance,
          position: ray.origin + ray.direction * distance,
          triangleIndex: i ~/ 3,
        );
      }
    }
    return nearest;
  }

  /// Whether geometry blocks the line of sight from [origin] to [target],
  /// both in this mesh's space. Surfaces within [tolerance] of the target do
  /// not count, so anchors sitting on the surface stay visible.
  bool occludes(Vector3 origin, Vector3 target, {double? tolerance}) {
    final delta = target - origin;
    final distance = delta.length;
    if (distance == 0) return false;
    final hit = intersectRay(GlintRay(origin, delta * (1 / distance)));
    return hit != null && hit.distance < distance - (tolerance ?? distance * .01);
  }

  Vector3 _position(int index) => Vector3(
    positions[index * 3],
    positions[index * 3 + 1],
    positions[index * 3 + 2],
  );

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

  /// Parses and aggregates supported triangle primitives in the active scene.
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
    final positions = <double>[];
    final uvs = <double>[];
    final normals = <double>[];
    // Indices grouped by material (-1 for the glTF default material) so
    // each material becomes one contiguous submesh span.
    final indicesByMaterial = <int, List<int>>{};
    Map? firstPrimitive;
    var uses32BitIndices = false;
    for (final instance in _meshInstances()) {
      final meshIndex = instance.$1;
      if (meshIndex < 0 || meshIndex >= meshes.length) {
        throw const FormatException('Mesh index is out of range.');
      }
      final primitives = _list(
        (meshes[meshIndex] as Map)['primitives'],
        'primitives',
      );
      for (final value in primitives) {
        final primitive = value as Map;
        if ((primitive['mode'] as int? ?? 4) != 4) continue;
        firstPrimitive ??= primitive;
        final attributes = primitive['attributes'] as Map;
        final positionAccessor = attributes['POSITION'] as int?;
        final indexAccessor = primitive['indices'] as int?;
        if (positionAccessor == null || indexAccessor == null) {
          throw const FormatException(
            'Primitive requires POSITION and indices.',
          );
        }
        final localPositions = _readFloats(positionAccessor, 'VEC3');
        final primitiveIndices = _readIndices(indexAccessor);
        final vertexOffset = positions.length ~/ 3;
        final transformedPositions = _transformPositions(
          localPositions,
          instance.$2,
        );
        final vertexCount = transformedPositions.length ~/ 3;
        final uvAccessor = attributes['TEXCOORD_0'] as int?;
        final primitiveUvs = uvAccessor == null
            ? List<double>.filled(vertexCount * 2, 0)
            : _readFloats(uvAccessor, 'VEC2');
        if (primitiveUvs.length != vertexCount * 2) {
          throw const FormatException('TEXCOORD_0 count must match POSITION.');
        }
        final normalAccessor = attributes['NORMAL'] as int?;
        final localNormals = normalAccessor == null
            ? _generateNormals(localPositions, primitiveIndices)
            : _readFloats(normalAccessor, 'VEC3');
        final transformedNormals = _transformNormals(localNormals, instance.$2);
        if (transformedNormals.length != transformedPositions.length) {
          throw const FormatException('NORMAL count must match POSITION.');
        }
        final componentType = _accessor(indexAccessor)['componentType'] as int;
        if (componentType != 5123 && componentType != 5125) {
          throw const FormatException(
            'Indices must be unsigned short or unsigned int.',
          );
        }
        uses32BitIndices =
            uses32BitIndices || componentType == 5125 || vertexOffset > 65535;
        positions.addAll(transformedPositions);
        uvs.addAll(primitiveUvs);
        normals.addAll(transformedNormals);
        final documentMaterials = _optionalList(document['materials']);
        var materialIndex = primitive['material'] as int? ?? -1;
        if (materialIndex >= documentMaterials.length) materialIndex = -1;
        (indicesByMaterial[materialIndex] ??= []).addAll(
          primitiveIndices.map((index) => index + vertexOffset),
        );
      }
    }
    if (firstPrimitive == null || positions.isEmpty) {
      throw const FormatException(
        'Active scene contains no supported TRIANGLES primitives.',
      );
    }
    final materials = [
      for (final material in _optionalList(document['materials']))
        _parseMaterial(material as Map),
    ];
    var defaultMaterialIndex = -1;
    if (indicesByMaterial.containsKey(-1) || materials.isEmpty) {
      materials.add(const GlintGlbMaterial());
      defaultMaterialIndex = materials.length - 1;
    }
    final indices = <int>[];
    final submeshes = <GlintGlbSubmesh>[];
    for (final entry in indicesByMaterial.entries) {
      submeshes.add(
        GlintGlbSubmesh(
          indexOffset: indices.length,
          indexCount: entry.value.length,
          materialIndex: entry.key == -1 ? defaultMaterialIndex : entry.key,
        ),
      );
      indices.addAll(entry.value);
    }
    final bounds = _bounds(positions);
    return GlintGlbMesh(
      positions: positions,
      textureCoordinates: uvs,
      normals: normals,
      indices: indices,
      uses32BitIndices: uses32BitIndices || positions.length ~/ 3 > 65535,
      materials: materials,
      submeshes: submeshes,
      baseColorImageBytes: _readBaseColorImage(firstPrimitive),
      baseColorFactor: _readBaseColorFactor(firstPrimitive),
      metallicFactor: _readMaterialNumber(firstPrimitive, 'metallicFactor', 1),
      roughnessFactor: _readMaterialNumber(
        firstPrimitive,
        'roughnessFactor',
        1,
      ),
      worldTransform: vm.Matrix4.identity().storage.toList(),
      boundsMinimum: bounds.$1,
      boundsMaximum: bounds.$2,
    );
  }

  List<(int, vm.Matrix4)> _meshInstances() {
    final nodes = _optionalList(document['nodes']);
    final scenes = _optionalList(document['scenes']);
    if (nodes.isEmpty || scenes.isEmpty) {
      return [(0, vm.Matrix4.identity())];
    }
    final activeScene = (document['scene'] as int?) ?? 0;
    if (activeScene < 0 || activeScene >= scenes.length) {
      throw const FormatException('Active scene index is out of range.');
    }
    final roots = ((scenes[activeScene] as Map)['nodes'] as List?) ?? const [];
    final instances = <(int, vm.Matrix4)>[];
    for (final root in roots.cast<int>()) {
      _collectMeshInstances(
        root,
        vm.Matrix4.identity(),
        nodes,
        <int>{},
        instances,
      );
    }
    return instances;
  }

  void _collectMeshInstances(
    int nodeIndex,
    vm.Matrix4 parent,
    List nodes,
    Set<int> path,
    List<(int, vm.Matrix4)> output,
  ) {
    if (nodeIndex < 0 || nodeIndex >= nodes.length) {
      throw const FormatException('Node index is out of range.');
    }
    if (!path.add(nodeIndex)) {
      throw const FormatException('Node hierarchy contains a cycle.');
    }
    final node = nodes[nodeIndex] as Map;
    final world = parent * _localTransform(node);
    final mesh = node['mesh'] as int?;
    if (mesh != null) output.add((mesh, world));
    for (final child in ((node['children'] as List?) ?? const []).cast<int>()) {
      _collectMeshInstances(child, world, nodes, {...path}, output);
    }
  }

  vm.Matrix4 _localTransform(Map node) {
    final matrix = node['matrix'] as List?;
    if (matrix != null) {
      if (matrix.length != 16) {
        throw const FormatException('Node matrix must have 16 elements.');
      }
      return vm.Matrix4.fromList(
        matrix.map((value) => (value as num).toDouble()).toList(),
      );
    }
    final t = (node['translation'] as List?) ?? const [0, 0, 0];
    final r = (node['rotation'] as List?) ?? const [0, 0, 0, 1];
    final s = (node['scale'] as List?) ?? const [1, 1, 1];
    return vm.Matrix4.compose(
      vm.Vector3(
        (t[0] as num).toDouble(),
        (t[1] as num).toDouble(),
        (t[2] as num).toDouble(),
      ),
      vm.Quaternion(
        (r[0] as num).toDouble(),
        (r[1] as num).toDouble(),
        (r[2] as num).toDouble(),
        (r[3] as num).toDouble(),
      ),
      vm.Vector3(
        (s[0] as num).toDouble(),
        (s[1] as num).toDouble(),
        (s[2] as num).toDouble(),
      ),
    );
  }

  List<double> _transformPositions(List<double> values, vm.Matrix4 matrix) {
    final output = <double>[];
    for (var i = 0; i < values.length; i += 3) {
      final value = matrix.transform3(
        vm.Vector3(values[i], values[i + 1], values[i + 2]),
      );
      output.addAll([value.x, value.y, value.z]);
    }
    return output;
  }

  List<double> _transformNormals(List<double> values, vm.Matrix4 matrix) {
    final normalMatrix = vm.Matrix3.zero()..copyNormalMatrix(matrix);
    final output = <double>[];
    for (var i = 0; i < values.length; i += 3) {
      final value = normalMatrix.transform(
        vm.Vector3(values[i], values[i + 1], values[i + 2]),
      )..normalize();
      output.addAll([value.x, value.y, value.z]);
    }
    return output;
  }

  (List<double>, List<double>) _bounds(List<double> positions) {
    final minimum = [double.infinity, double.infinity, double.infinity];
    final maximum = [
      double.negativeInfinity,
      double.negativeInfinity,
      double.negativeInfinity,
    ];
    for (var i = 0; i < positions.length; i += 3) {
      for (var axis = 0; axis < 3; axis++) {
        minimum[axis] = math.min(minimum[axis], positions[i + axis]);
        maximum[axis] = math.max(maximum[axis], positions[i + axis]);
      }
    }
    return (minimum, maximum);
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

  GlintGlbMaterial _parseMaterial(Map material) {
    final pbr = material['pbrMetallicRoughness'] as Map?;
    final factor = (pbr?['baseColorFactor'] as List?)
        ?.map((value) => (value as num).toDouble())
        .toList();
    return GlintGlbMaterial(
      baseColorImageBytes: _materialImage(material),
      baseColorFactor: factor ?? const [1, 1, 1, 1],
      metallicFactor: (pbr?['metallicFactor'] as num?)?.toDouble() ?? 1,
      roughnessFactor: (pbr?['roughnessFactor'] as num?)?.toDouble() ?? 1,
    );
  }

  Uint8List? _readBaseColorImage(Map primitive) {
    final materialIndex = primitive['material'] as int?;
    if (materialIndex == null) return null;
    final materials = _optionalList(document['materials']);
    if (materialIndex >= materials.length) return null;
    return _materialImage(materials[materialIndex] as Map);
  }

  Uint8List? _materialImage(Map material) {
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
