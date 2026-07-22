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

/// One node of a preserved glTF scene hierarchy.
class GlintGlbNode {
  const GlintGlbNode({
    this.name,
    this.children = const [],
    this.meshIndex,
    this.translation = const [0, 0, 0],
    this.rotationQuaternion = const [0, 0, 0, 1],
    this.scale = const [1, 1, 1],
    this.matrix,
    this.skinIndex,
  });

  final String? name;
  final List<int> children;
  final int? meshIndex;
  final List<double> translation;

  /// x, y, z, w.
  final List<double> rotationQuaternion;
  final List<double> scale;

  /// Authored column-major matrix; when present it replaces the TRS unless
  /// an animation channel targets this node.
  final List<double>? matrix;

  /// Index into [GlintGlbRig.skins] when this node's mesh is skinned.
  final int? skinIndex;
}

/// A glTF skin: which nodes are joints, and each joint's inverse bind
/// matrix (mapping the mesh's bind-pose space into that joint's own local
/// space).
class GlintGlbSkin {
  const GlintGlbSkin({
    required this.jointNodeIndices,
    required this.inverseBindMatrices,
  });

  /// Node indices, in joint order — a vertex's JOINTS_0 values index into
  /// this list, not directly into the node array.
  final List<int> jointNodeIndices;

  /// One column-major mat4 per joint, index-aligned with [jointNodeIndices].
  final List<List<double>> inverseBindMatrices;
}

/// What a [GlintGlbAnimationChannel] animates on its node.
enum GlintGlbAnimationPath { translation, rotation, scale }

/// How values between two glTF animation keyframes are sampled.
enum GlintGlbInterpolation { linear, step, cubicSpline }

/// Keyframes driving one property of one node.
class GlintGlbAnimationChannel {
  const GlintGlbAnimationChannel({
    required this.nodeIndex,
    required this.path,
    required this.inputTimes,
    required this.output,
    GlintGlbInterpolation interpolation = GlintGlbInterpolation.linear,
    bool stepInterpolation = false,
  }) : interpolation = stepInterpolation
           ? GlintGlbInterpolation.step
           : interpolation;

  final int nodeIndex;
  final GlintGlbAnimationPath path;

  /// Ascending keyframe times in seconds.
  final List<double> inputTimes;

  /// Keyframe values, 3 components per key (4 for rotation, x y z w).
  /// CUBICSPLINE channels store an in-tangent, value, and out-tangent for
  /// each key, as prescribed by glTF 2.0.
  final List<double> output;

  final GlintGlbInterpolation interpolation;

  /// Compatibility shorthand for callers written before interpolation was
  /// exposed as an enum.
  bool get stepInterpolation => interpolation == GlintGlbInterpolation.step;
}

/// One named animation clip.
class GlintGlbAnimation {
  const GlintGlbAnimation({
    required this.name,
    required this.channels,
    required this.duration,
  });

  final String name;
  final List<GlintGlbAnimationChannel> channels;

  /// Seconds to the last keyframe across all channels.
  final double duration;
}

/// One node's local transform in an evaluated animation pose.
class GlintAnimationNodePose {
  const GlintAnimationNodePose({
    required this.translation,
    required this.rotation,
    required this.scale,
  });

  final Vector3 translation;
  final GlintQuaternion rotation;
  final Vector3 scale;
}

/// A model-local animation pose, with one transform per glTF node.
///
/// [trsNodes] records the nodes whose translation/rotation/scale should
/// replace an authored node matrix. This distinction preserves matrix-authored
/// bind poses while still allowing animation channels and animation layers to
/// take control of those nodes.
class GlintAnimationPose {
  GlintAnimationPose({
    required Iterable<GlintAnimationNodePose> nodes,
    Iterable<int> trsNodes = const [],
  }) : nodes = List.unmodifiable(nodes),
       trsNodes = Set.unmodifiable(trsNodes);

  final List<GlintAnimationNodePose> nodes;
  final Set<int> trsNodes;
}

/// A glTF scene with its hierarchy and animations preserved: meshes stay in
/// their local spaces and node transforms are evaluated per frame, which is
/// what animated rendering needs — unlike [GlintGlbMesh]'s baked aggregate.
class GlintGlbRig {
  const GlintGlbRig({
    required this.nodes,
    required this.rootNodes,
    required this.meshes,
    required this.animations,
    this.skins = const [],
  });

  final List<GlintGlbNode> nodes;
  final List<GlintGlbSkin> skins;
  final List<int> rootNodes;

  /// Local-space geometry, index-aligned with the glTF meshes array.
  final List<GlintGlbMesh> meshes;
  final List<GlintGlbAnimation> animations;

  static Future<GlintGlbRig> fromAsset(
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

  static GlintGlbRig parse(ByteData bytes, {String debugLabel = 'model.glb'}) {
    try {
      return GlintGlbMesh._containerReader(bytes).readRig();
    } catch (error) {
      if (error is GlintGlbException) rethrow;
      throw GlintGlbException(debugLabel, 'GLB rig parsing failed', error);
    }
  }

  /// Whether [bytes] declare any animation clips, without reading geometry.
  static bool probeAnimations(ByteData bytes) {
    try {
      final animations = GlintGlbMesh._containerReader(
        bytes,
      ).document['animations'];
      return animations is List && animations.isNotEmpty;
    } on Object {
      return false;
    }
  }

  /// Whether [bytes] declare one or more skins, without reading geometry.
  static bool probeSkins(ByteData bytes) {
    try {
      final skins = GlintGlbMesh._containerReader(bytes).document['skins'];
      return skins is List && skins.isNotEmpty;
    } on Object {
      return false;
    }
  }

  /// The model's authored local bind pose.
  GlintAnimationPose bindPose() => GlintAnimationPose(
    nodes: [
      for (final node in nodes)
        GlintAnimationNodePose(
          translation: Vector3(
            node.translation[0],
            node.translation[1],
            node.translation[2],
          ),
          rotation: GlintQuaternion(
            node.rotationQuaternion[0],
            node.rotationQuaternion[1],
            node.rotationQuaternion[2],
            node.rotationQuaternion[3],
          ).normalized,
          scale: Vector3(node.scale[0], node.scale[1], node.scale[2]),
        ),
    ],
  );

  /// Samples one clip into a reusable, model-local pose. Pass animation -1
  /// for the bind pose. Time wraps for looping clips and clamps for one-shots.
  GlintAnimationPose sampleAnimation({
    int animation = 0,
    double time = 0,
    bool loop = true,
  }) {
    final bind = bindPose();
    final poses = bind.nodes.toList();
    final animated = <int>{};
    if (animation >= 0 && animation < animations.length) {
      final clip = animations[animation];
      final localTime = clip.duration <= 0
          ? 0.0
          : loop
          ? time % clip.duration
          : time.clamp(0.0, clip.duration).toDouble();
      for (final channel in clip.channels) {
        animated.add(channel.nodeIndex);
        final value = _sample(channel, localTime);
        final current = poses[channel.nodeIndex];
        switch (channel.path) {
          case GlintGlbAnimationPath.translation:
            poses[channel.nodeIndex] = GlintAnimationNodePose(
              translation: Vector3(value[0], value[1], value[2]),
              rotation: current.rotation,
              scale: current.scale,
            );
          case GlintGlbAnimationPath.rotation:
            poses[channel.nodeIndex] = GlintAnimationNodePose(
              translation: current.translation,
              rotation: GlintQuaternion(
                value[0],
                value[1],
                value[2],
                value[3],
              ).normalized,
              scale: current.scale,
            );
          case GlintGlbAnimationPath.scale:
            poses[channel.nodeIndex] = GlintAnimationNodePose(
              translation: current.translation,
              rotation: current.rotation,
              scale: Vector3(value[0], value[1], value[2]),
            );
        }
      }
    }

    return GlintAnimationPose(nodes: poses, trsNodes: animated);
  }

  /// Column-major world transforms per node, sampling [animation] at [time]
  /// (looped over the clip's duration). Pass animation -1 for the bind pose.
  List<List<double>> nodeWorldTransforms({
    int animation = 0,
    double time = 0,
    bool loop = true,
  }) => nodeWorldTransformsFromPose(
    sampleAnimation(animation: animation, time: time, loop: loop),
  );

  /// Resolves a sampled or mixed local [pose] through the glTF hierarchy.
  List<List<double>> nodeWorldTransformsFromPose(GlintAnimationPose pose) {
    if (pose.nodes.length != nodes.length) {
      throw ArgumentError.value(
        pose.nodes.length,
        'pose',
        'must contain one transform for each of the ${nodes.length} nodes',
      );
    }
    final worlds = List<List<double>>.filled(nodes.length, const []);
    final visiting = <int>{};
    final visited = <int>{};
    void visit(int index, vm.Matrix4 parent) {
      if (index < 0 || index >= nodes.length) {
        throw StateError('glTF node index $index is out of range.');
      }
      if (visited.contains(index)) return;
      if (!visiting.add(index)) {
        throw StateError(
          'glTF node hierarchy contains a cycle at node $index.',
        );
      }
      final node = nodes[index];
      final nodePose = pose.nodes[index];
      final vm.Matrix4 local;
      if (node.matrix != null && !pose.trsNodes.contains(index)) {
        local = vm.Matrix4.fromList(node.matrix!);
      } else {
        local = vm.Matrix4.compose(
          vm.Vector3(
            nodePose.translation.x,
            nodePose.translation.y,
            nodePose.translation.z,
          ),
          vm.Quaternion(
            nodePose.rotation.x,
            nodePose.rotation.y,
            nodePose.rotation.z,
            nodePose.rotation.w,
          ),
          vm.Vector3(nodePose.scale.x, nodePose.scale.y, nodePose.scale.z),
        );
      }
      final world = parent * local as vm.Matrix4;
      worlds[index] = world.storage.toList();
      for (final child in node.children) {
        visit(child, world);
      }
      visiting.remove(index);
      visited.add(index);
    }

    for (final root in rootNodes) {
      visit(root, vm.Matrix4.identity());
    }
    for (var i = 0; i < worlds.length; i++) {
      if (worlds[i].isEmpty) {
        worlds[i] = vm.Matrix4.identity().storage.toList();
      }
    }
    return worlds;
  }

  /// Column-major joint matrices for [skinIndex], expressed relative to
  /// [meshNodeIndex]'s own space — the space a skinned mesh's vertex
  /// positions are authored in. For each joint: the joint's current-pose
  /// world transform, combined with its inverse bind matrix (bind pose ->
  /// joint local space) and the mesh node's own inverse world transform,
  /// so the result composes correctly with whatever per-instance/per-node
  /// world transform the caller applies at draw time on top of this.
  List<List<double>> jointMatrices(
    int skinIndex,
    int meshNodeIndex, {
    int animation = 0,
    double time = 0,
    bool loop = true,
  }) {
    final worlds = nodeWorldTransforms(
      animation: animation,
      time: time,
      loop: loop,
    );
    return jointMatricesFromWorldTransforms(skinIndex, meshNodeIndex, worlds);
  }

  /// Computes skin matrices from transforms already sampled for this frame.
  /// Renderers can use this to avoid evaluating the same animation twice.
  List<List<double>> jointMatricesFromWorldTransforms(
    int skinIndex,
    int meshNodeIndex,
    List<List<double>> worlds,
  ) {
    if (skinIndex < 0 || skinIndex >= skins.length) {
      throw RangeError.index(skinIndex, skins, 'skinIndex');
    }
    if (meshNodeIndex < 0 || meshNodeIndex >= nodes.length) {
      throw RangeError.index(meshNodeIndex, nodes, 'meshNodeIndex');
    }
    if (worlds.length != nodes.length ||
        worlds.any((matrix) => matrix.length != 16)) {
      throw ArgumentError.value(
        worlds.length,
        'worlds',
        'must contain one mat4 per node',
      );
    }
    final meshWorldInverse = vm.Matrix4.fromList(worlds[meshNodeIndex]);
    final determinant = meshWorldInverse.invert();
    if (determinant == 0 ||
        meshWorldInverse.storage.any((value) => !value.isFinite)) {
      throw StateError('Skinned mesh node $meshNodeIndex is not invertible.');
    }
    final skin = skins[skinIndex];
    return [
      for (var i = 0; i < skin.jointNodeIndices.length; i++)
        (meshWorldInverse *
                    vm.Matrix4.fromList(worlds[skin.jointNodeIndices[i]]) *
                    vm.Matrix4.fromList(skin.inverseBindMatrices[i])
                as vm.Matrix4)
            .storage
            .toList(),
    ];
  }

  List<double> _sample(GlintGlbAnimationChannel channel, double time) {
    final times = channel.inputTimes;
    final stride = channel.path == GlintGlbAnimationPath.rotation ? 4 : 3;
    final cubic = channel.interpolation == GlintGlbInterpolation.cubicSpline;
    List<double> key(int index) => [
      for (var c = 0; c < stride; c++)
        channel.output[index * stride * (cubic ? 3 : 1) +
            (cubic ? stride : 0) +
            c],
    ];
    if (times.isEmpty) return List.filled(stride, 0);
    if (time <= times.first) return key(0);
    if (time >= times.last) return key(times.length - 1);
    var next = 1;
    while (times[next] < time) {
      next++;
    }
    final previous = next - 1;
    if (channel.interpolation == GlintGlbInterpolation.step) {
      return key(previous);
    }
    final span = times[next] - times[previous];
    final t = span <= 0 ? 0.0 : (time - times[previous]) / span;
    final a = key(previous);
    final b = key(next);
    if (cubic) {
      final t2 = t * t;
      final t3 = t2 * t;
      final h00 = 2 * t3 - 3 * t2 + 1;
      final h10 = t3 - 2 * t2 + t;
      final h01 = -2 * t3 + 3 * t2;
      final h11 = t3 - t2;
      final previousBase = previous * stride * 3;
      final nextBase = next * stride * 3;
      final value = [
        for (var c = 0; c < stride; c++)
          h00 * a[c] +
              h10 * span * channel.output[previousBase + stride * 2 + c] +
              h01 * b[c] +
              h11 * span * channel.output[nextBase + c],
      ];
      return channel.path == GlintGlbAnimationPath.rotation
          ? _normalizeQuaternion(value)
          : value;
    }
    if (channel.path != GlintGlbAnimationPath.rotation) {
      return [for (var c = 0; c < stride; c++) a[c] + (b[c] - a[c]) * t];
    }
    return _slerp(a, b, t);
  }

  /// Shortest-path spherical interpolation with a linear fallback when the
  /// quaternions are nearly parallel.
  List<double> _slerp(List<double> a, List<double> b, double t) {
    var dot = a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3];
    var bx = b[0], by = b[1], bz = b[2], bw = b[3];
    if (dot < 0) {
      dot = -dot;
      bx = -bx;
      by = -by;
      bz = -bz;
      bw = -bw;
    }
    double weightA, weightB;
    if (dot > .9995) {
      weightA = 1 - t;
      weightB = t;
    } else {
      final theta = math.acos(dot.clamp(-1, 1));
      final sine = math.sin(theta);
      weightA = math.sin((1 - t) * theta) / sine;
      weightB = math.sin(t * theta) / sine;
    }
    final x = a[0] * weightA + bx * weightB;
    final y = a[1] * weightA + by * weightB;
    final z = a[2] * weightA + bz * weightB;
    final w = a[3] * weightA + bw * weightB;
    return _normalizeQuaternion([x, y, z, w]);
  }

  List<double> _normalizeQuaternion(List<double> value) {
    final length = math.sqrt(value.fold(0.0, (sum, v) => sum + v * v));
    return length == 0
        ? const [0, 0, 0, 1]
        : [for (final component in value) component / length];
  }
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
    this.isSkinned = false,
    this.joints = const [],
    this.weights = const [],
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

  /// Whether any primitive declared JOINTS_0/WEIGHTS_0 — when true, [joints]
  /// and [weights] hold real per-vertex data; when false they're zero-filled
  /// and unused (dead data, kept only so the vertex arrays stay index-aligned
  /// with [positions] uniformly regardless of skin status).
  final bool isSkinned;

  /// Up to 4 joint indices per vertex (into the mesh's
  /// [GlintGlbRig.skins]' [GlintGlbSkin.jointNodeIndices], not directly into
  /// the node array), 4 floats per vertex.
  final List<double> joints;

  /// Blend weights matching [joints], 4 per vertex.
  final List<double> weights;

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
    return hit != null &&
        hit.distance < distance - (tolerance ?? distance * .01);
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
      return _containerReader(bytes).readFirstMesh();
    } catch (error) {
      if (error is GlintGlbException) rethrow;
      throw GlintGlbException(debugLabel, 'GLB parsing failed', error);
    }
  }

  /// Splits a GLB container into its JSON document and binary chunk.
  /// Library-internal: rig parsing shares it.
  static _GlbReader _containerReader(ByteData bytes) {
    {
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
      return _GlbReader(document, binary);
    }
  }
}

class _GlbReader {
  _GlbReader(this.document, this.binary);
  final Map<String, dynamic> document;
  final ByteData binary;

  GlintGlbMesh readFirstMesh() => _aggregate(_meshInstances());

  /// Reads the scene with hierarchy and animations preserved: every glTF
  /// mesh parsed once in local space plus nodes and animation clips.
  GlintGlbRig readRig() {
    final meshCount = _list(document['meshes'], 'meshes').length;
    final documentNodes = _optionalList(document['nodes']);
    final nodes = <GlintGlbNode>[];
    for (final value in documentNodes) {
      final node = value as Map;
      final meshIndex = node['mesh'] as int?;
      if (meshIndex != null && (meshIndex < 0 || meshIndex >= meshCount)) {
        throw const FormatException('Node mesh index is out of range.');
      }
      final rotation = (node['rotation'] as List?) ?? const [0, 0, 0, 1];
      final translation = (node['translation'] as List?) ?? const [0, 0, 0];
      final scale = (node['scale'] as List?) ?? const [1, 1, 1];
      nodes.add(
        GlintGlbNode(
          name: node['name'] as String?,
          children: ((node['children'] as List?) ?? const []).cast<int>(),
          meshIndex: meshIndex,
          translation: [for (final v in translation) (v as num).toDouble()],
          rotationQuaternion: [for (final v in rotation) (v as num).toDouble()],
          scale: [for (final v in scale) (v as num).toDouble()],
          matrix: (node['matrix'] as List?)
              ?.map((v) => (v as num).toDouble())
              .toList(),
          skinIndex: node['skin'] as int?,
        ),
      );
    }
    final skins = <GlintGlbSkin>[];
    for (final value in _optionalList(document['skins'])) {
      final skin = value as Map;
      final jointNodeIndices = ((skin['joints'] as List?) ?? const [])
          .cast<int>();
      if (jointNodeIndices.isEmpty) {
        throw const FormatException('A skin must declare at least one joint.');
      }
      if (jointNodeIndices.any((index) => index < 0 || index >= nodes.length)) {
        throw const FormatException('Skin joint index is out of range.');
      }
      final inverseBindMatricesAccessor = skin['inverseBindMatrices'] as int?;
      final flatMatrices = inverseBindMatricesAccessor == null
          ? null
          : _readFloats(inverseBindMatricesAccessor, 'MAT4');
      if (flatMatrices != null &&
          flatMatrices.length != jointNodeIndices.length * 16) {
        throw const FormatException(
          'Inverse bind matrix count must match the skin joint count.',
        );
      }
      skins.add(
        GlintGlbSkin(
          jointNodeIndices: jointNodeIndices,
          inverseBindMatrices: [
            for (var i = 0; i < jointNodeIndices.length; i++)
              flatMatrices == null
                  ? vm.Matrix4.identity().storage.toList()
                  : flatMatrices.sublist(i * 16, i * 16 + 16),
          ],
        ),
      );
    }
    for (final node in nodes) {
      final skinIndex = node.skinIndex;
      if (skinIndex != null && (skinIndex < 0 || skinIndex >= skins.length)) {
        throw const FormatException('Node skin index is out of range.');
      }
    }
    final scenes = _optionalList(document['scenes']);
    final activeScene = (document['scene'] as int?) ?? 0;
    if (scenes.isNotEmpty &&
        (activeScene < 0 || activeScene >= scenes.length)) {
      throw const FormatException('Active scene index is out of range.');
    }
    final childNodes = {
      for (final node in nodes)
        for (final child in node.children) child,
    };
    if (childNodes.any((index) => index < 0 || index >= nodes.length)) {
      throw const FormatException('Child node index is out of range.');
    }
    final rootNodes = scenes.isEmpty
        ? [
            for (var i = 0; i < nodes.length; i++)
              if (!childNodes.contains(i)) i,
          ]
        : ((scenes[activeScene] as Map)['nodes'] as List? ?? const [])
              .cast<int>();
    if (rootNodes.any((index) => index < 0 || index >= nodes.length)) {
      throw const FormatException('Root node index is out of range.');
    }
    final animations = <GlintGlbAnimation>[];
    var clipIndex = 0;
    for (final value in _optionalList(document['animations'])) {
      final animation = value as Map;
      final samplers = _list(animation['samplers'], 'animation samplers');
      final channels = <GlintGlbAnimationChannel>[];
      var duration = 0.0;
      for (final channelValue in _list(
        animation['channels'],
        'animation channels',
      )) {
        final channel = channelValue as Map;
        final target = channel['target'] as Map;
        final nodeIndex = target['node'] as int?;
        final path = switch (target['path'] as String?) {
          'translation' => GlintGlbAnimationPath.translation,
          'rotation' => GlintGlbAnimationPath.rotation,
          'scale' => GlintGlbAnimationPath.scale,
          _ => null, // weights (morph targets) are outside v0.1.
        };
        if (nodeIndex == null || path == null) continue;
        if (nodeIndex < 0 || nodeIndex >= nodes.length) {
          throw const FormatException(
            'Animation target node index is out of range.',
          );
        }
        final samplerIndex = channel['sampler'] as int;
        if (samplerIndex < 0 || samplerIndex >= samplers.length) {
          throw const FormatException(
            'Animation sampler index is out of range.',
          );
        }
        final sampler = samplers[samplerIndex] as Map;
        final interpolation = switch (sampler['interpolation'] as String? ??
            'LINEAR') {
          'LINEAR' => GlintGlbInterpolation.linear,
          'STEP' => GlintGlbInterpolation.step,
          'CUBICSPLINE' => GlintGlbInterpolation.cubicSpline,
          final value => throw FormatException(
            'Unsupported animation interpolation $value.',
          ),
        };
        final inputTimes = _readFloats(sampler['input'] as int, 'SCALAR');
        final output = _readFloats(
          sampler['output'] as int,
          path == GlintGlbAnimationPath.rotation ? 'VEC4' : 'VEC3',
        );
        for (var i = 1; i < inputTimes.length; i++) {
          if (inputTimes[i] <= inputTimes[i - 1]) {
            throw const FormatException(
              'Animation keyframe times must be strictly increasing.',
            );
          }
        }
        final components = path == GlintGlbAnimationPath.rotation ? 4 : 3;
        final expectedOutputLength =
            inputTimes.length *
            components *
            (interpolation == GlintGlbInterpolation.cubicSpline ? 3 : 1);
        if (output.length != expectedOutputLength) {
          throw const FormatException(
            'Animation output count does not match its input keyframes.',
          );
        }
        if (inputTimes.isNotEmpty && inputTimes.last > duration) {
          duration = inputTimes.last;
        }
        channels.add(
          GlintGlbAnimationChannel(
            nodeIndex: nodeIndex,
            path: path,
            inputTimes: inputTimes,
            output: output,
            interpolation: interpolation,
          ),
        );
      }
      animations.add(
        GlintGlbAnimation(
          name: (animation['name'] as String?) ?? 'animation $clipIndex',
          channels: channels,
          duration: duration,
        ),
      );
      clipIndex++;
    }
    return GlintGlbRig(
      nodes: nodes,
      rootNodes: rootNodes,
      meshes: [
        for (var i = 0; i < meshCount; i++)
          _aggregate([(i, vm.Matrix4.identity())]),
      ],
      animations: animations,
      skins: skins,
    );
  }

  GlintGlbMesh _aggregate(List<(int, vm.Matrix4)> meshInstances) {
    final meshes = _list(document['meshes'], 'meshes');
    final positions = <double>[];
    final uvs = <double>[];
    final normals = <double>[];
    final joints = <double>[];
    final weights = <double>[];
    // Indices grouped by material (-1 for the glTF default material) so
    // each material becomes one contiguous submesh span.
    final indicesByMaterial = <int, List<int>>{};
    Map? firstPrimitive;
    var uses32BitIndices = false;
    var isSkinned = false;
    for (final instance in meshInstances) {
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
        if (positionAccessor == null) {
          throw const FormatException('Primitive requires POSITION.');
        }
        final localPositions = _readFloats(positionAccessor, 'VEC3');
        // glTF allows omitting indices entirely: vertices are then drawn in
        // sequential order, three at a time, with no index buffer.
        final indexAccessor = primitive['indices'] as int?;
        final primitiveIndices = indexAccessor == null
            ? List<int>.generate(localPositions.length ~/ 3, (i) => i)
            : _readIndices(indexAccessor);
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
        final jointsAccessor = attributes['JOINTS_0'] as int?;
        final weightsAccessor = attributes['WEIGHTS_0'] as int?;
        if ((jointsAccessor == null) != (weightsAccessor == null)) {
          throw const FormatException(
            'JOINTS_0 and WEIGHTS_0 must be declared together.',
          );
        }
        final primitiveJoints = jointsAccessor == null
            ? List<double>.filled(vertexCount * 4, 0)
            : _readJointIndices(jointsAccessor);
        if (primitiveJoints.length != vertexCount * 4) {
          throw const FormatException('JOINTS_0 count must match POSITION.');
        }
        final primitiveWeights = weightsAccessor == null
            ? List<double>.filled(vertexCount * 4, 0)
            : _readWeights(weightsAccessor);
        if (primitiveWeights.length != vertexCount * 4) {
          throw const FormatException('WEIGHTS_0 count must match POSITION.');
        }
        if (jointsAccessor != null) isSkinned = true;
        if (indexAccessor != null) {
          final componentType =
              _accessor(indexAccessor)['componentType'] as int;
          if (componentType != 5123 && componentType != 5125) {
            throw const FormatException(
              'Indices must be unsigned short or unsigned int.',
            );
          }
          uses32BitIndices = uses32BitIndices || componentType == 5125;
        }
        uses32BitIndices = uses32BitIndices || vertexOffset > 65535;
        positions.addAll(transformedPositions);
        uvs.addAll(primitiveUvs);
        normals.addAll(transformedNormals);
        joints.addAll(primitiveJoints);
        weights.addAll(primitiveWeights);
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
    // If one primitive in a mesh is skinned, the whole mesh uses the skinned
    // vertex pipeline. Give primitives without explicit influences a stable
    // identity-like fallback instead of letting a zero matrix collapse them.
    if (isSkinned) {
      for (var vertex = 0; vertex < positions.length ~/ 3; vertex++) {
        final base = vertex * 4;
        final total =
            weights[base] +
            weights[base + 1] +
            weights[base + 2] +
            weights[base + 3];
        if (total == 0) weights[base] = 1;
      }
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
      isSkinned: isSkinned,
      joints: joints,
      weights: weights,
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
    final components = switch (expectedType) {
      'SCALAR' => 1,
      'VEC2' => 2,
      'VEC3' => 3,
      'VEC4' => 4,
      'MAT4' => 16,
      _ => throw FormatException('Unsupported accessor type $expectedType.'),
    };
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

  /// Reads glTF skin weights. Besides FLOAT, the format permits normalized
  /// UNSIGNED_BYTE and UNSIGNED_SHORT values, which are common in compact
  /// mobile assets. Values are normalized again per vertex to avoid drift
  /// from quantization or imperfect exporters.
  List<double> _readWeights(int index) {
    final accessor = _accessor(index);
    if (accessor['type'] != 'VEC4') {
      throw const FormatException('WEIGHTS_0 accessor must be VEC4.');
    }
    final componentType = accessor['componentType'] as int;
    final width = switch (componentType) {
      5121 => 1,
      5123 => 2,
      5126 => 4,
      _ => throw const FormatException(
        'WEIGHTS_0 must contain FLOAT or normalized unsigned integer values.',
      ),
    };
    if (componentType != 5126 && accessor['normalized'] != true) {
      throw const FormatException(
        'Integer WEIGHTS_0 accessors must be normalized.',
      );
    }
    final view = _view(accessor['bufferView'] as int);
    final count = accessor['count'] as int;
    final start =
        (view['byteOffset'] as int? ?? 0) +
        (accessor['byteOffset'] as int? ?? 0);
    final stride = view['byteStride'] as int? ?? width * 4;
    final output = List<double>.filled(count * 4, 0);
    for (var element = 0; element < count; element++) {
      for (var component = 0; component < 4; component++) {
        final byteOffset = start + element * stride + component * width;
        final value = switch (componentType) {
          5121 => binary.getUint8(byteOffset) / 255,
          5123 => binary.getUint16(byteOffset, Endian.little) / 65535,
          _ => binary.getFloat32(byteOffset, Endian.little),
        };
        if (!value.isFinite || value < 0) {
          throw const FormatException(
            'WEIGHTS_0 values must be finite and non-negative.',
          );
        }
        output[element * 4 + component] = value;
      }
      // Preserve authored FLOAT weights byte-for-byte. Normalized integer
      // accessors still need conversion to 0..1, but a second normalization
      // of FLOAT data can perturb assets that were already validated by the
      // exporter and was implicated in a GPU skinning regression.
    }
    return output;
  }

  /// Reads an UNSIGNED_BYTE/UNSIGNED_SHORT VEC4 accessor as doubles — glTF's
  /// JOINTS_0 attribute has integer (not float) components, unlike every
  /// other attribute this file reads, so it needs its own reader rather
  /// than reusing [_readFloats]. Values become joint indices into the
  /// vertex buffer as floats, matching Glint's float-only vertex format.
  List<double> _readJointIndices(int index) {
    final accessor = _accessor(index);
    if (accessor['type'] != 'VEC4') {
      throw const FormatException('JOINTS_0 accessor must be VEC4.');
    }
    final componentType = accessor['componentType'] as int;
    if (componentType != 5121 && componentType != 5123) {
      throw const FormatException(
        'JOINTS_0 must be UNSIGNED_BYTE or UNSIGNED_SHORT.',
      );
    }
    final width = componentType == 5121 ? 1 : 2;
    final view = _view(accessor['bufferView'] as int);
    final count = accessor['count'] as int;
    final start =
        (view['byteOffset'] as int? ?? 0) +
        (accessor['byteOffset'] as int? ?? 0);
    final stride = view['byteStride'] as int? ?? width * 4;
    final output = <double>[];
    for (var element = 0; element < count; element++) {
      for (var component = 0; component < 4; component++) {
        final byteOffset = start + element * stride + component * width;
        final value = componentType == 5121
            ? binary.getUint8(byteOffset)
            : binary.getUint16(byteOffset, Endian.little);
        output.add(value.toDouble());
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
