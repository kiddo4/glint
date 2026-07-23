import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

import '../animation.dart';
import '../assets/environment.dart';
import '../assets/glb.dart';
import '../assets/model.dart';
import '../assets/texture_pixels.dart';
import '../math.dart';
import '../particles.dart';
import '../scene.dart';
import '../shader_graph.dart';
import 'punctual_lights.dart';
import 'render_stats.dart';

/// Fixed size of the `joint_matrices` uniform array in
/// `shaders/skinned_unlit.vert` — generous for typical mobile-game
/// character rigs, bounded so the uniform buffer size stays fixed and
/// known. A skin with more joints than this has the rest silently dropped,
/// with a debug-mode warning.
const kMaxJointsPerSkin = 64;

const _disabledShadowMatrix = <double>[
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
];

/// A free camera for game rendering: position and target in world units.
class GlintGameCamera {
  const GlintGameCamera({
    required this.position,
    required this.target,
    this.up = const Vector3(0, 1, 0),
    this.fieldOfViewDegrees = 50,
    this.near = .1,
    this.far = 300,
  });

  final Vector3 position;
  final Vector3 target;
  final Vector3 up;
  final double fieldOfViewDegrees;
  final double near;
  final double far;
}

/// One drawable occurrence of a loaded model in a game frame.
class GlintGameInstance {
  const GlintGameInstance({
    required this.model,
    this.transform = const Transform3D(),
    this.material,
    this.shaderMaterial,
    this.translucent = false,
    this.animationIndex = 0,
    this.animationTime = 0,
    this.animationLoop = true,
    this.animationPose,
    this.pointLights = const [],
    this.spotLights = const [],
  });

  /// Key into [GlintGameView.models].
  final String model;

  /// World placement in authored model units (no auto-centering or scaling).
  final Transform3D transform;

  /// Overrides the model's authored material for this instance only.
  final Material3D? material;

  /// Optional build-time shader graph material. It keeps the authored base
  /// material and texture available to the graph while replacing the standard
  /// fragment stage for this instance.
  final GlintShaderGraphMaterial? shaderMaterial;

  /// Alpha-blends over opaque geometry without writing depth; drawn last.
  /// Use for blob shadows and other soft decals.
  final bool translucent;

  /// Which of the model's animation clips to sample; ignored for models
  /// without animations.
  final int animationIndex;

  /// Seconds into the clip; it loops over the clip duration automatically,
  /// so passing a running game clock plays the animation continuously.
  final double animationTime;

  /// Whether sampling wraps after the clip duration. Set false to hold the
  /// final keyframe for one-shot actions.
  final bool animationLoop;

  /// A pose evaluated by [GlintAnimationController]. When supplied, it takes
  /// precedence over [animationIndex], [animationTime], and [animationLoop].
  final GlintAnimationPose? animationPose;

  /// Point lights in this instance's local space — a muzzle flash on a gun,
  /// a headlight on a car, a torch on a character — transformed by
  /// [transform] into world space every frame, so they track the instance
  /// automatically instead of requiring their position to be recomputed by
  /// hand. Combined with every other instance's and [GlintGameView]'s own
  /// [GlintGameView.pointLights]/[GlintGameView.spotLights], capped at
  /// [kMaxPunctualLights] total.
  final List<PointLight> pointLights;

  /// As [pointLights], for cone-narrowed lights.
  final List<SpotLight> spotLights;
}

/// Everything the renderer needs to draw one game frame.
class GlintGameFrame {
  const GlintGameFrame({
    required this.camera,
    required this.instances,
    this.particles = const [],
  });

  final GlintGameCamera camera;
  final List<GlintGameInstance> instances;

  /// Billboard batches produced by [GlintParticleSystem.renderBatch].
  final List<GlintParticleRenderBatch> particles;
}

/// A ticker-driven viewport that renders many model instances per frame with
/// a free camera — Glint's game loop. [onFrame] receives the seconds since
/// the previous frame, advances the game, and returns what to draw. The HUD
/// stays ordinary Flutter widgets layered above this view.
class GlintGameView extends StatefulWidget {
  const GlintGameView({
    super.key,
    required this.models,
    required this.onFrame,
    this.particleTextures = const {},
    this.shaderTextures = const {},
    this.textureDecoder = const GlintTextureDecoder(),
    this.environmentAsset,
    this.width = 1024,
    this.height = 1024,
    this.lightDirection = const Vector3(.55, -1, -.65),
    this.lightIntensity = 2.6,
    this.ambientIntensity = .26,
    this.pointLights = const [],
    this.spotLights = const [],
    this.backgroundColor = const ui.Color(0xff090b13),
    this.showStats = false,
    this.fogColor,
    this.fogDistance = 0,
    this.fallback,
    this.onError,
  });

  /// The models this game draws, keyed by the names frames reference.
  final Map<String, Model> models;

  /// Reusable texture sources keyed by particle configs. A particle system
  /// with no texture uses a white texel, which is useful for procedural color
  /// gradients and debugging.
  final Map<String, GlintTextureSource> particleTextures;

  /// Texture sources referenced by [GlintShaderGraphMaterial.textures].
  final Map<String, GlintTextureSource> shaderTextures;

  /// Shared PNG/JPEG/KTX2/Basis decoding policy for model and particle assets.
  final GlintTextureDecoder textureDecoder;

  /// Advances the simulation by the elapsed seconds and describes the frame.
  final GlintGameFrame Function(double secondsElapsed) onFrame;

  final String? environmentAsset;
  final int width;
  final int height;
  final Vector3 lightDirection;
  final double lightIntensity;
  final double ambientIntensity;

  /// Point lights placed in world space, in addition to the key light.
  /// Combined with [spotLights], capped at [kMaxPunctualLights]. Rebuilding
  /// this list every frame (e.g. tracking a moving instance) is expected —
  /// like [onFrame]'s instances, it's read fresh each frame, not cached.
  final List<PointLight> pointLights;

  /// Cone-narrowed point lights. Combined with [pointLights], capped at
  /// [kMaxPunctualLights].
  final List<SpotLight> spotLights;

  final ui.Color backgroundColor;

  /// Overlays live FPS, frame time, draw-call, and triangle counters.
  final bool showStats;

  /// Horizon color surfaces fade into with distance; defaults to
  /// [backgroundColor]. Pair it with the sky for a seamless horizon.
  final ui.Color? fogColor;

  /// World-space distance at which surfaces fully fog out; 0 disables fog.
  final double fogDistance;

  final Widget? fallback;
  final ValueChanged<Object>? onError;

  @override
  State<GlintGameView> createState() => _GlintGameViewState();
}

class _GlintGameViewState extends State<GlintGameView>
    with SingleTickerProviderStateMixin {
  late Future<_GameAssets> _assets;
  Future<ui.Image>? _image;
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;
  gpu.RenderPipeline? _pipeline;
  gpu.RenderPipeline? _skinnedPipeline;
  gpu.RenderPipeline? _particlePipeline;
  final Map<(String, String, bool), gpu.RenderPipeline> _graphPipelines = {};
  bool _rendering = false;
  bool _failed = false;

  final _stats = ValueNotifier<GlintRenderStats?>(null);
  final _frameTimestamps = <int>[];

  // Per-draw scratch state, reused every frame so the render loop allocates
  // nothing per instance. Holds DrawInfo only (mvp, world, base color,
  // material) — FrameInfo (lights, camera, fog) is built once per frame,
  // not per draw call, since it never changes within a frame.
  final _drawScratch = Float32List(40);
  // Skinned parts use a separate, wider scratch (mvp, world, base color,
  // material, plus kMaxJointsPerSkin joint matrices) instead of resizing
  // _drawScratch per draw, so unskinned draws — the majority — never touch
  // the larger buffer.
  final _skinnedDrawScratch = Float32List(40 + kMaxJointsPerSkin * 16);
  final _worldScratch = vm.Matrix4.zero();
  final _partWorldScratch = vm.Matrix4.zero();
  final _mvpScratch = vm.Matrix4.zero();
  final _cornerScratch = vm.Vector3.zero();
  Float32List _particleVertexScratch = Float32List(0);
  final List<int> _particleOrderScratch = [];
  double _shaderTime = 0;

  @override
  void initState() {
    super.initState();
    // ignore() marks early rejections handled; _render still observes them.
    _assets = _loadAssets()..ignore();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void reassemble() {
    super.reassemble();
    _pipeline = null;
    _skinnedPipeline = null;
    _particlePipeline = null;
    _graphPipelines.clear();
    _failed = false;
  }

  @override
  void didUpdateWidget(GlintGameView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.models != widget.models ||
        oldWidget.environmentAsset != widget.environmentAsset ||
        oldWidget.particleTextures != widget.particleTextures ||
        oldWidget.shaderTextures != widget.shaderTextures ||
        oldWidget.textureDecoder != widget.textureDecoder) {
      _assets = _loadAssets()..ignore();
      _failed = false;
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _stats.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final seconds = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (_rendering || _failed || !mounted) return;
    // Clamp pathological gaps (paused app) so physics never explodes.
    final frame = widget.onFrame(seconds.clamp(0, 1 / 15));
    _shaderTime += seconds.clamp(0, 1 / 15);
    _rendering = true;
    final next = _render(frame);
    setState(() {
      _image = next;
    });
    next.then<void>(
      (_) {
        _rendering = false;
      },
      onError: (Object _) {
        _rendering = false;
        _failed = true;
      },
    );
  }

  Future<_GameAssets> _loadAssets() async {
    final environment = widget.environmentAsset == null
        ? null
        : await GlintEnvironment.fromAsset(widget.environmentAsset!);
    final models = <String, _GameModel>{};
    for (final entry in widget.models.entries) {
      models[entry.key] = await _GameModel.load(
        entry.value,
        widget.textureDecoder,
      );
    }
    final context = gpu.gpuContext;
    gpu.Texture upload(ByteData bytes, int width, int height) {
      final texture = context.createTexture(
        gpu.StorageMode.hostVisible,
        width,
        height,
        coordinateSystem: gpu.TextureCoordinateSystem.uploadFromHost,
        enableRenderTargetUsage: false,
      );
      texture.overwrite(bytes);
      return texture;
    }

    final blackTexel = ByteData(4);
    final whiteTexel = ByteData(4)..setUint32(0, 0xffffffff);
    final whiteTexture = upload(whiteTexel, 1, 1);
    final particleTextures = <String, gpu.Texture>{};
    for (final entry in widget.particleTextures.entries) {
      final encoded = await entry.value.read();
      final pixels = await widget.textureDecoder.decode(
        encoded,
        debugLabel: entry.value.debugLabel,
        maximumDimension: 2048,
      );
      particleTextures[entry.key] = upload(
        pixels.bytes,
        pixels.width,
        pixels.height,
      );
    }
    final shaderTextures = <String, gpu.Texture>{};
    for (final entry in widget.shaderTextures.entries) {
      final encoded = await entry.value.read();
      final pixels = await widget.textureDecoder.decode(
        encoded,
        debugLabel: entry.value.debugLabel,
        maximumDimension: 2048,
      );
      shaderTextures[entry.key] = upload(
        pixels.bytes,
        pixels.width,
        pixels.height,
      );
    }
    return _GameAssets(
      models: models,
      whiteTexture: whiteTexture,
      particleTextures: particleTextures,
      shaderTextures: shaderTextures,
      irradianceTexture: environment == null
          ? upload(blackTexel, 1, 1)
          : upload(
              environment.irradiancePixels,
              GlintEnvironment.irradianceWidth,
              GlintEnvironment.irradianceHeight,
            ),
      radianceTexture: environment == null
          ? upload(blackTexel, 1, 1)
          : upload(
              environment.radiancePixels,
              GlintEnvironment.radianceWidth,
              GlintEnvironment.radianceHeight * GlintEnvironment.levelCount,
            ),
      environmentStrength: environment == null ? 0 : 1,
    );
  }

  gpu.RenderPipeline _obtainPipeline(gpu.GpuContext context) {
    final cached = _pipeline;
    if (cached != null) return cached;
    final library = gpu.ShaderLibrary.fromAsset(
      'packages/glint_engine/shaders/glint.shaderbundle',
    );
    if (library == null) {
      throw StateError('Glint shader bundle could not be loaded.');
    }
    final vertex = library['UnlitVertex'];
    final fragment = library['UnlitFragment'];
    if (vertex == null || fragment == null) {
      throw StateError('Glint shader entry points are missing.');
    }
    return _pipeline = context.createRenderPipeline(vertex, fragment);
  }

  gpu.RenderPipeline _obtainSkinnedPipeline(gpu.GpuContext context) {
    final cached = _skinnedPipeline;
    if (cached != null) return cached;
    final library = gpu.ShaderLibrary.fromAsset(
      'packages/glint_engine/shaders/glint.shaderbundle',
    );
    if (library == null) {
      throw StateError('Glint shader bundle could not be loaded.');
    }
    final vertex = library['SkinnedUnlitVertex'];
    final fragment = library['UnlitFragment'];
    if (vertex == null || fragment == null) {
      throw StateError('Glint skinned shader entry points are missing.');
    }
    return _skinnedPipeline = context.createRenderPipeline(vertex, fragment);
  }

  gpu.RenderPipeline _obtainParticlePipeline(gpu.GpuContext context) {
    final cached = _particlePipeline;
    if (cached != null) return cached;
    final library = gpu.ShaderLibrary.fromAsset(
      'packages/glint_engine/shaders/glint.shaderbundle',
    );
    if (library == null) {
      throw StateError('Glint shader bundle could not be loaded.');
    }
    final vertex = library['ParticleVertex'];
    final fragment = library['ParticleFragment'];
    if (vertex == null || fragment == null) {
      throw StateError('Glint particle shader entry points are missing.');
    }
    return _particlePipeline = context.createRenderPipeline(vertex, fragment);
  }

  gpu.RenderPipeline _obtainGraphPipeline(
    gpu.GpuContext context,
    GlintShaderGraphMaterial material, {
    required bool skinned,
  }) {
    final key = (material.bundleAsset, material.fragmentEntry, skinned);
    final cached = _graphPipelines[key];
    if (cached != null) return cached;
    final graphLibrary = gpu.ShaderLibrary.fromAsset(material.bundleAsset);
    if (graphLibrary == null) {
      throw StateError(
        'Shader graph bundle "${material.bundleAsset}" could not be loaded.',
      );
    }
    final fragment = graphLibrary[material.fragmentEntry];
    if (fragment == null) {
      throw StateError(
        'Shader graph fragment "${material.fragmentEntry}" is missing.',
      );
    }
    final vertex = skinned
        ? _obtainSkinnedPipeline(context).vertexShader
        : _obtainPipeline(context).vertexShader;
    return _graphPipelines[key] = context.createRenderPipeline(
      vertex,
      fragment,
    );
  }

  Future<ui.Image> _render(GlintGameFrame frame) async {
    try {
      final stopwatch = Stopwatch()..start();
      final assets = await _assets;
      final context = gpu.gpuContext;
      final pipeline = _obtainPipeline(context);
      final skinnedPipeline = _obtainSkinnedPipeline(context);
      final texture = context.createTexture(
        gpu.StorageMode.devicePrivate,
        widget.width,
        widget.height,
      );
      final depthTexture = context.createTexture(
        gpu.StorageMode.deviceTransient,
        widget.width,
        widget.height,
        format: context.defaultDepthStencilFormat,
      );
      final commandBuffer = context.createCommandBuffer();
      final pass = commandBuffer.createRenderPass(
        gpu.RenderTarget.singleColor(
          gpu.ColorAttachment(
            texture: texture,
            clearValue: vm.Vector4(
              widget.backgroundColor.r,
              widget.backgroundColor.g,
              widget.backgroundColor.b,
              widget.backgroundColor.a,
            ),
          ),
          depthStencilAttachment: gpu.DepthStencilAttachment(
            texture: depthTexture,
            depthClearValue: 1,
          ),
        ),
      );
      pass.bindPipeline(pipeline);
      pass.setDepthWriteEnable(true);
      pass.setDepthCompareOperation(gpu.CompareFunction.less);
      pass.setWindingOrder(gpu.WindingOrder.counterClockwise);
      pass.setCullMode(gpu.CullMode.backFace);

      final camera = frame.camera;
      final projection = vm.makePerspectiveMatrix(
        camera.fieldOfViewDegrees * 3.141592653589793 / 180,
        widget.width / widget.height,
        camera.near,
        camera.far,
      );
      final view = vm.makeViewMatrix(
        vm.Vector3(camera.position.x, camera.position.y, camera.position.z),
        vm.Vector3(camera.target.x, camera.target.y, camera.target.z),
        vm.Vector3(camera.up.x, camera.up.y, camera.up.z),
      );
      final viewProjection = projection * view as vm.Matrix4;

      final environmentSampler = gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.linear,
        magFilter: gpu.MinMagFilter.linear,
        widthAddressMode: gpu.SamplerAddressMode.repeat,
        heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
      );
      final fog = widget.fogColor ?? widget.backgroundColor;
      final fogUniform = widget.fogDistance <= 0
          ? const [0.0, 0.0, 0.0, 0.0]
          : [
              math.pow(fog.r, 2.2).toDouble(),
              math.pow(fog.g, 2.2).toDouble(),
              math.pow(fog.b, 2.2).toDouble(),
              widget.fogDistance,
            ];
      // One world-space frustum for the whole frame; instances test their
      // transformed bounds against it without per-draw plane extraction.
      final frustum = GlintFrustum.fromColumnMajor(viewProjection.storage);

      var drawCalls = 0;
      var triangles = 0;
      final hostBuffer = context.createHostBuffer();
      // FrameInfo never changes within a frame, so it's built and emplaced
      // once here and the resulting buffer view is rebound (not
      // re-emplaced) before every draw call below — the same pattern
      // already used for the frame-constant irradiance/radiance textures.
      //
      // Instance-attached lights are local-space, so they're resolved to
      // world space here — once per instance, reusing _worldScratch, which
      // is safe because every value is copied out into a new PointLight/
      // SpotLight before the draw loop below reuses the same scratch matrix.
      final combinedPointLights = widget.pointLights.toList();
      final combinedSpotLights = widget.spotLights.toList();
      for (final instance in frame.instances) {
        if (instance.pointLights.isEmpty && instance.spotLights.isEmpty) {
          continue;
        }
        final instanceWorld = _composeTransform(
          instance.transform,
          _worldScratch,
        );
        for (final light in instance.pointLights) {
          combinedPointLights.add(worldPointLight(light, instanceWorld));
        }
        for (final light in instance.spotLights) {
          combinedSpotLights.add(worldSpotLight(light, instanceWorld));
        }
      }
      // Over budget: keep the lights nearest the camera rather than
      // whichever happened to be first in instance order — a scrolling
      // game routinely has more lights alive (coins, muzzle flashes) than
      // the budget, and the ones worth keeping are the visible/near ones.
      if (combinedPointLights.length + combinedSpotLights.length >
          kMaxPunctualLights) {
        double distanceSquaredToCamera(Vector3 position) {
          final dx = position.x - camera.position.x;
          final dy = position.y - camera.position.y;
          final dz = position.z - camera.position.z;
          return dx * dx + dy * dy + dz * dz;
        }

        combinedPointLights.sort(
          (a, b) => distanceSquaredToCamera(
            a.position,
          ).compareTo(distanceSquaredToCamera(b.position)),
        );
        combinedSpotLights.sort(
          (a, b) => distanceSquaredToCamera(
            a.position,
          ).compareTo(distanceSquaredToCamera(b.position)),
        );
      }
      final punctualLights = GlintPackedPunctualLights(
        combinedPointLights,
        combinedSpotLights,
      );
      final frameInfo = hostBuffer.emplace(
        _floats([
          widget.lightDirection.x,
          widget.lightDirection.y,
          widget.lightDirection.z,
          assets.environmentStrength,
          widget.ambientIntensity,
          widget.lightIntensity,
          punctualLights.count.toDouble(),
          0,
          camera.position.x,
          camera.position.y,
          camera.position.z,
          0,
          ...fogUniform,
          ..._disabledShadowMatrix,
          ...punctualLights.positionRange,
          ...punctualLights.colorIntensity,
          ...punctualLights.directionOuterCos,
          ...punctualLights.innerCosFlags,
        ]),
      );
      // Tracks whichever pipeline is currently bound so consecutive parts of
      // the same kind (the common case — a frame is mostly static scenery)
      // don't rebind on every draw call.
      gpu.RenderPipeline? currentPipeline = pipeline;
      void useGeometryPipeline(gpu.RenderPipeline target) {
        if (identical(currentPipeline, target)) return;
        // Flutter GPU retains vertex/uniform bindings across pipeline
        // changes. The static and skinned pipelines have different vertex
        // strides and vertex-uniform layouts, so carrying those bindings
        // across corrupts the first draw after a switch.
        pass.clearBindings();
        pass.bindPipeline(target);
        // Depth-write and blend state are phase-scoped (opaque vs.
        // translucent, set around the two draw loops below), not
        // pipeline-scoped, so only winding/cull — identical for every
        // pipeline this renderer uses — need reapplying on switch.
        pass.setWindingOrder(gpu.WindingOrder.counterClockwise);
        pass.setCullMode(gpu.CullMode.backFace);
        currentPipeline = target;
      }

      void draw(GlintGameInstance instance) {
        final model = assets.models[instance.model];
        if (model == null) {
          throw StateError('Unknown game model "${instance.model}".');
        }
        final instanceWorld = _composeTransform(
          instance.transform,
          _worldScratch,
        );
        // Rigged models sample their clip once per instance; static models
        // draw their single part with the instance transform alone.
        final nodeWorlds = instance.animationPose == null
            ? model.rig?.nodeWorldTransforms(
                animation: instance.animationIndex,
                time: instance.animationTime,
                loop: instance.animationLoop,
              )
            : model.rig?.nodeWorldTransformsFromPose(instance.animationPose!);
        final material = instance.material;
        final shaderMaterial = instance.shaderMaterial;
        final graphInfo = shaderMaterial == null
            ? null
            : hostBuffer.emplace(
                shaderMaterial.packUniforms(_shaderTime).buffer.asByteData(),
              );
        final overrideFactor = material?.linearBaseColorFactor;
        for (final (nodeIndex, meshIndex) in model.parts) {
          final buffers = model.meshes[meshIndex];
          vm.Matrix4 world;
          if (nodeIndex < 0 || nodeWorlds == null) {
            world = instanceWorld;
          } else {
            world = _partWorldScratch
              ..setFrom(instanceWorld)
              ..multiply(vm.Matrix4.fromList(nodeWorlds[nodeIndex]));
          }
          // Bind-pose bounds are not conservative for animated skinning.
          // Keep skinned parts until dynamic bounds are available rather than
          // incorrectly popping limbs or whole characters out of view.
          if (!buffers.isSkinned &&
              !_worldBoundsVisible(
                frustum,
                world,
                buffers.boundsMinimum,
                buffers.boundsMaximum,
              )) {
            continue;
          }
          _mvpScratch.setFrom(viewProjection);
          _mvpScratch.multiply(world);

          List<List<double>>? jointMatrices;
          if (buffers.isSkinned) {
            final skinIndex = model.rig!.nodes[nodeIndex].skinIndex!;
            jointMatrices = model.rig!.jointMatricesFromWorldTransforms(
              skinIndex,
              nodeIndex,
              nodeWorlds!,
            );
          }
          final geometryPipeline = shaderMaterial == null
              ? (buffers.isSkinned ? skinnedPipeline : pipeline)
              : _obtainGraphPipeline(
                  context,
                  shaderMaterial,
                  skinned: buffers.isSkinned,
                );
          useGeometryPipeline(geometryPipeline);

          pass.bindVertexBuffer(
            gpu.BufferView(
              buffers.vertexBuffer,
              offsetInBytes: 0,
              lengthInBytes: buffers.vertexByteLength,
            ),
            buffers.vertexCount,
          );
          // One draw per material batch; an instance material override wins
          // over every submesh's authored factors.
          for (final submesh in buffers.submeshes) {
            final factor = overrideFactor ?? submesh.baseColorFactor;
            pass.bindIndexBuffer(
              gpu.BufferView(
                buffers.indexBuffer,
                offsetInBytes: submesh.indexOffset * buffers.indexByteSize,
                lengthInBytes: submesh.indexCount * buffers.indexByteSize,
              ),
              buffers.indexType,
              submesh.indexCount,
            );
            if (buffers.isSkinned) {
              for (var i = 0; i < 16; i++) {
                _skinnedDrawScratch[i] = _mvpScratch.storage[i];
                _skinnedDrawScratch[16 + i] = world.storage[i];
              }
              for (var i = 0; i < 4; i++) {
                _skinnedDrawScratch[32 + i] = factor[i];
              }
              _skinnedDrawScratch[36] =
                  material?.metallic ?? submesh.metallicFactor;
              _skinnedDrawScratch[37] =
                  material?.roughness ?? submesh.roughnessFactor;
              final jointCount = math.min(
                jointMatrices!.length,
                kMaxJointsPerSkin,
              );
              for (var j = 0; j < jointCount; j++) {
                final joint = jointMatrices[j];
                for (var i = 0; i < 16; i++) {
                  _skinnedDrawScratch[40 + j * 16 + i] = joint[i];
                }
              }
              pass.bindUniform(
                geometryPipeline.vertexShader.getUniformSlot('SkinnedDrawInfo'),
                hostBuffer.emplace(_skinnedDrawScratch.buffer.asByteData()),
              );
            } else {
              for (var i = 0; i < 16; i++) {
                _drawScratch[i] = _mvpScratch.storage[i];
                _drawScratch[16 + i] = world.storage[i];
              }
              for (var i = 0; i < 4; i++) {
                _drawScratch[32 + i] = factor[i];
              }
              _drawScratch[36] = material?.metallic ?? submesh.metallicFactor;
              _drawScratch[37] = material?.roughness ?? submesh.roughnessFactor;
              pass.bindUniform(
                geometryPipeline.vertexShader.getUniformSlot('DrawInfo'),
                hostBuffer.emplace(_drawScratch.buffer.asByteData()),
              );
            }
            pass.bindUniform(
              geometryPipeline.fragmentShader.getUniformSlot('FrameInfo'),
              frameInfo,
            );
            drawCalls++;
            triangles += submesh.indexCount ~/ 3;
            pass.bindTexture(
              geometryPipeline.fragmentShader.getUniformSlot('tex'),
              submesh.texture,
              sampler: gpu.SamplerOptions(
                minFilter: gpu.MinMagFilter.linear,
                magFilter: gpu.MinMagFilter.linear,
                widthAddressMode: gpu.SamplerAddressMode.repeat,
                heightAddressMode: gpu.SamplerAddressMode.repeat,
              ),
            );
            pass.bindTexture(
              geometryPipeline.fragmentShader.getUniformSlot('irradiance_map'),
              assets.irradianceTexture,
              sampler: environmentSampler,
            );
            pass.bindTexture(
              geometryPipeline.fragmentShader.getUniformSlot('radiance_map'),
              assets.radianceTexture,
              sampler: environmentSampler,
            );
            pass.bindTexture(
              geometryPipeline.fragmentShader.getUniformSlot('shadow_map'),
              assets.whiteTexture,
            );
            if (shaderMaterial != null) {
              pass.bindUniform(
                geometryPipeline.fragmentShader.getUniformSlot(
                  'GraphMaterialInfo',
                ),
                graphInfo!,
              );
              for (final entry
                  in shaderMaterial.program.textureUniforms.entries) {
                final textureKey = shaderMaterial.textures[entry.key]!;
                final texture = assets.shaderTextures[textureKey];
                if (texture == null) {
                  throw StateError(
                    'Unknown shader texture "$textureKey". Add it to '
                    'GlintGameView.shaderTextures.',
                  );
                }
                pass.bindTexture(
                  geometryPipeline.fragmentShader.getUniformSlot(entry.value),
                  texture,
                  sampler: gpu.SamplerOptions(
                    minFilter: gpu.MinMagFilter.linear,
                    magFilter: gpu.MinMagFilter.linear,
                    widthAddressMode: gpu.SamplerAddressMode.repeat,
                    heightAddressMode: gpu.SamplerAddressMode.repeat,
                  ),
                );
              }
            }
            pass.draw();
          }
        }
      }

      // Opaque geometry first with depth writes, then translucent instances
      // (blob shadows, glass) blended over it without disturbing the depth
      // buffer.
      bool usesSkinnedPipeline(GlintGameInstance instance) {
        final model = assets.models[instance.model];
        return model != null && model.meshes.any((mesh) => mesh.isSkinned);
      }

      // Flutter GPU currently corrupts the wider skinned vertex layout when
      // a static draw has already executed in the same pass. Opaque ordering
      // is depth-independent, so batch skinned geometry first and reduce the
      // frame to one safe skinned -> static transition.
      for (final instance in frame.instances) {
        if (!instance.translucent && usesSkinnedPipeline(instance)) {
          draw(instance);
        }
      }
      for (final instance in frame.instances) {
        if (!instance.translucent && !usesSkinnedPipeline(instance)) {
          draw(instance);
        }
      }
      if (frame.instances.any((instance) => instance.translucent)) {
        pass.setDepthWriteEnable(false);
        pass.setColorBlendEnable(true);
        pass.setColorBlendEquation(
          gpu.ColorBlendEquation(
            sourceColorBlendFactor: gpu.BlendFactor.sourceAlpha,
          ),
        );
        for (final instance in frame.instances) {
          if (instance.translucent) draw(instance);
        }
      }

      if (frame.particles.any((batch) => batch.count > 0)) {
        final particlePipeline = _obtainParticlePipeline(context);
        pass.clearBindings();
        pass.bindPipeline(particlePipeline);
        pass.setDepthWriteEnable(false);
        pass.setDepthCompareOperation(gpu.CompareFunction.less);
        pass.setCullMode(gpu.CullMode.none);
        pass.setColorBlendEnable(true);
        final particleFrameInfo = hostBuffer.emplace(
          Float32List.fromList(viewProjection.storage).buffer.asByteData(),
        );
        final forward = (camera.target - camera.position).normalized;
        var right = forward.cross(camera.up).normalized;
        if (right.length == 0) right = const Vector3(1, 0, 0);
        final billboardUp = right.cross(forward).normalized;

        for (final batch in frame.particles) {
          if (batch.count == 0) continue;
          final textureKey = batch.config.texture;
          final particleTexture = textureKey == null
              ? assets.whiteTexture
              : assets.particleTextures[textureKey];
          if (particleTexture == null) {
            throw StateError(
              'Unknown particle texture "$textureKey". Add it to '
              'GlintGameView.particleTextures.',
            );
          }
          pass.setColorBlendEquation(
            gpu.ColorBlendEquation(
              sourceColorBlendFactor: gpu.BlendFactor.sourceAlpha,
              destinationColorBlendFactor:
                  batch.config.blendMode == GlintParticleBlendMode.additive
                  ? gpu.BlendFactor.one
                  : gpu.BlendFactor.oneMinusSourceAlpha,
              sourceAlphaBlendFactor: gpu.BlendFactor.one,
              destinationAlphaBlendFactor:
                  batch.config.blendMode == GlintParticleBlendMode.additive
                  ? gpu.BlendFactor.one
                  : gpu.BlendFactor.oneMinusSourceAlpha,
            ),
          );
          final vertexView = _particleVertices(
            batch,
            camera.position,
            right,
            billboardUp,
          );
          final uploadedVertices = hostBuffer.emplace(vertexView);
          pass.bindVertexBuffer(uploadedVertices, batch.count * 6);
          pass.bindUniform(
            particlePipeline.vertexShader.getUniformSlot('ParticleFrameInfo'),
            particleFrameInfo,
          );
          pass.bindTexture(
            particlePipeline.fragmentShader.getUniformSlot('particle_texture'),
            particleTexture,
            sampler: gpu.SamplerOptions(
              minFilter: gpu.MinMagFilter.linear,
              magFilter: gpu.MinMagFilter.linear,
              widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
              heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
            ),
          );
          pass.draw();
          drawCalls++;
          triangles += batch.count * 2;
        }
      }

      final completer = Completer<void>();
      commandBuffer.submit(
        completionCallback: (success) {
          success
              ? completer.complete()
              : completer.completeError(StateError('GPU submission failed.'));
        },
      );
      await completer.future;
      _recordStats(stopwatch.elapsedMicroseconds / 1000, drawCalls, triangles);
      return texture.asImage();
    } catch (error) {
      debugPrint('Glint game render failed: $error');
      widget.onError?.call(error);
      rethrow;
    }
  }

  ByteData _floats(List<double> values) =>
      Float32List.fromList(values).buffer.asByteData();

  ByteData _particleVertices(
    GlintParticleRenderBatch batch,
    Vector3 cameraPosition,
    Vector3 right,
    Vector3 up,
  ) {
    const floatsPerVertex = 9;
    const verticesPerParticle = 6;
    final floatCount = batch.count * verticesPerParticle * floatsPerVertex;
    if (_particleVertexScratch.length < floatCount) {
      var capacity = math.max(256, _particleVertexScratch.length);
      while (capacity < floatCount) {
        capacity *= 2;
      }
      _particleVertexScratch = Float32List(capacity);
    }
    while (_particleOrderScratch.length < batch.count) {
      _particleOrderScratch.add(_particleOrderScratch.length);
    }
    for (var i = 0; i < batch.count; i++) {
      _particleOrderScratch[i] = i;
    }
    final order = _particleOrderScratch.sublist(0, batch.count);
    if (batch.config.sortMode == GlintParticleSortMode.backToFront) {
      double distanceSquared(int index) {
        final delta = batch.worldPosition(index) - cameraPosition;
        return delta.dot(delta);
      }

      order.sort((a, b) => distanceSquared(b).compareTo(distanceSquared(a)));
    }

    var cursor = 0;
    const corners = <(double, double, double, double)>[
      (-1, -1, 0, 1),
      (1, -1, 1, 1),
      (1, 1, 1, 0),
      (-1, -1, 0, 1),
      (1, 1, 1, 0),
      (-1, 1, 0, 0),
    ];
    for (final index in order) {
      final center = batch.worldPosition(index);
      final halfSize = batch.size(index) * .5;
      final rotation = batch.rotations[index];
      final cosine = math.cos(rotation);
      final sine = math.sin(rotation);
      final color = batch.color(index);
      final sheet = batch.config.spriteSheet;
      final frame = batch.spriteFrame(index);
      final columns = sheet?.columns ?? 1;
      final rows = sheet?.rows ?? 1;
      final column = frame % columns;
      final row = frame ~/ columns;
      final u0 = column / columns;
      final v0 = row / rows;
      final uScale = 1 / columns;
      final vScale = 1 / rows;
      for (final corner in corners) {
        final x = corner.$1 * halfSize;
        final y = corner.$2 * halfSize;
        final rotatedX = x * cosine - y * sine;
        final rotatedY = x * sine + y * cosine;
        final position = center + right * rotatedX + up * rotatedY;
        _particleVertexScratch[cursor++] = position.x;
        _particleVertexScratch[cursor++] = position.y;
        _particleVertexScratch[cursor++] = position.z;
        _particleVertexScratch[cursor++] = u0 + corner.$3 * uScale;
        _particleVertexScratch[cursor++] = v0 + corner.$4 * vScale;
        _particleVertexScratch[cursor++] = color.r;
        _particleVertexScratch[cursor++] = color.g;
        _particleVertexScratch[cursor++] = color.b;
        _particleVertexScratch[cursor++] = color.a;
      }
    }
    return _particleVertexScratch.buffer.asByteData(0, floatCount * 4);
  }

  /// World matrix matching [Transform3D.apply]: scale, then X/Y/Z rotation,
  /// then translation. Composes into [target] to avoid per-draw allocation.
  vm.Matrix4 _composeTransform(Transform3D transform, vm.Matrix4 target) {
    final orientation = transform.orientation;
    if (orientation != null) {
      target.setFromTranslationRotationScale(
        vm.Vector3(
          transform.position.x,
          transform.position.y,
          transform.position.z,
        ),
        vm.Quaternion(
          orientation.x,
          orientation.y,
          orientation.z,
          orientation.w,
        ),
        vm.Vector3(transform.scale.x, transform.scale.y, transform.scale.z),
      );
      return target;
    }
    target
      ..setIdentity()
      ..translateByDouble(
        transform.position.x,
        transform.position.y,
        transform.position.z,
        1,
      )
      ..rotateZ(transform.rotation.z)
      ..rotateY(transform.rotation.y)
      ..rotateX(transform.rotation.x)
      ..scaleByDouble(
        transform.scale.x,
        transform.scale.y,
        transform.scale.z,
        1,
      );
    return target;
  }

  /// Transforms local bounds corners to world space and tests the
  /// world-aligned box against the frame's frustum.
  bool _worldBoundsVisible(
    GlintFrustum frustum,
    vm.Matrix4 world,
    Vector3 boundsMinimum,
    Vector3 boundsMaximum,
  ) {
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = double.negativeInfinity,
        maxY = double.negativeInfinity,
        maxZ = double.negativeInfinity;
    for (var corner = 0; corner < 8; corner++) {
      _cornerScratch.setValues(
        corner & 1 == 0 ? boundsMinimum.x : boundsMaximum.x,
        corner & 2 == 0 ? boundsMinimum.y : boundsMaximum.y,
        corner & 4 == 0 ? boundsMinimum.z : boundsMaximum.z,
      );
      world.transform3(_cornerScratch);
      minX = math.min(minX, _cornerScratch.x);
      minY = math.min(minY, _cornerScratch.y);
      minZ = math.min(minZ, _cornerScratch.z);
      maxX = math.max(maxX, _cornerScratch.x);
      maxY = math.max(maxY, _cornerScratch.y);
      maxZ = math.max(maxZ, _cornerScratch.z);
    }
    return frustum.intersectsBounds(
      Vector3(minX, minY, minZ),
      Vector3(maxX, maxY, maxZ),
    );
  }

  void _recordStats(double frameMilliseconds, int drawCalls, int triangles) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _frameTimestamps
      ..add(now)
      ..removeWhere((timestamp) => now - timestamp > 1000);
    _stats.value = GlintRenderStats(
      framesPerSecond: _frameTimestamps.length,
      frameTimeMilliseconds: frameMilliseconds,
      drawCalls: drawCalls,
      triangleCount: triangles,
    );
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    Widget viewport;
    if (image == null) {
      // Still loading assets: hold the scene's background color rather than
      // flashing the GPU-unavailable fallback.
      viewport = _failed
          ? (widget.fallback ?? const SizedBox.expand())
          : ColoredBox(color: widget.backgroundColor);
    } else {
      viewport = FutureBuilder<ui.Image>(
        future: image,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return RawImage(image: snapshot.data, fit: BoxFit.cover);
          }
          if (snapshot.hasError) {
            return widget.fallback ?? const SizedBox.expand();
          }
          return const SizedBox.expand();
        },
      );
    }
    if (!widget.showStats) return viewport;
    return Stack(
      fit: StackFit.expand,
      children: [
        viewport,
        Positioned(
          top: 12,
          right: 12,
          child: IgnorePointer(
            child: ValueListenableBuilder<GlintRenderStats?>(
              valueListenable: _stats,
              builder: (_, stats, _) => stats == null
                  ? const SizedBox.shrink()
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xcc10131c),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Text(
                          '$stats',
                          style: const TextStyle(
                            color: Color(0xffc9d1e0),
                            fontSize: 12,
                            fontFeatures: [ui.FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GameAssets {
  const _GameAssets({
    required this.models,
    required this.whiteTexture,
    required this.particleTextures,
    required this.shaderTextures,
    required this.irradianceTexture,
    required this.radianceTexture,
    required this.environmentStrength,
  });

  final Map<String, _GameModel> models;
  final gpu.Texture whiteTexture;
  final Map<String, gpu.Texture> particleTextures;
  final Map<String, gpu.Texture> shaderTextures;
  final gpu.Texture irradianceTexture;
  final gpu.Texture radianceTexture;
  final double environmentStrength;
}

/// One material batch of a game model: an index span plus its GPU texture
/// and factors.
class _GameSubmesh {
  const _GameSubmesh({
    required this.indexOffset,
    required this.indexCount,
    required this.texture,
    required this.baseColorFactor,
    required this.metallicFactor,
    required this.roughnessFactor,
  });

  final int indexOffset;
  final int indexCount;
  final gpu.Texture texture;
  final List<double> baseColorFactor;
  final double metallicFactor;
  final double roughnessFactor;
}

/// One mesh's GPU residency: interleaved vertices, indices, and material
/// batches, in the mesh's own space.
class _MeshBuffers {
  const _MeshBuffers({
    required this.vertexBuffer,
    required this.vertexByteLength,
    required this.vertexCount,
    required this.indexBuffer,
    required this.indexType,
    required this.submeshes,
    required this.boundsMinimum,
    required this.boundsMaximum,
    required this.isSkinned,
  });

  final gpu.DeviceBuffer vertexBuffer;
  final int vertexByteLength;
  final int vertexCount;
  final gpu.DeviceBuffer indexBuffer;
  final gpu.IndexType indexType;
  final List<_GameSubmesh> submeshes;
  final Vector3 boundsMinimum;
  final Vector3 boundsMaximum;

  /// Whether this mesh's vertex buffer uses the wider skinned layout
  /// (position, uv, normal, joint indices, joint weights) and needs the
  /// SkinnedUnlitVertex pipeline instead of UnlitVertex.
  final bool isSkinned;

  int get indexByteSize => indexType == gpu.IndexType.int32 ? 4 : 2;

  static Future<_MeshBuffers> build(
    GlintGlbMesh mesh,
    gpu.GpuContext context,
    gpu.Texture whiteTexture,
    GlintTextureDecoder textureDecoder,
  ) async {
    gpu.Texture uploadPixels(GlintTexturePixels pixels) {
      final texture = context.createTexture(
        gpu.StorageMode.hostVisible,
        pixels.width,
        pixels.height,
        coordinateSystem: gpu.TextureCoordinateSystem.uploadFromHost,
        enableRenderTargetUsage: false,
      );
      texture.overwrite(pixels.bytes);
      return texture;
    }

    // Untextured materials shade from their factors alone and share the
    // white texel; textured materials decode capped at 1K so imported
    // photo-real assets stay within mobile memory budgets.
    final materialTextures = <gpu.Texture>[
      for (final material in mesh.materials)
        material.baseColorImageBytes == null
            ? whiteTexture
            : uploadPixels(
                await textureDecoder.decode(
                  material.baseColorImageBytes!,
                  debugLabel: 'embedded GLB base-color texture',
                  maximumDimension: 1024,
                ),
              ),
    ];
    final submeshes = mesh.submeshes.isEmpty
        ? [
            _GameSubmesh(
              indexOffset: 0,
              indexCount: mesh.indices.length,
              texture: materialTextures.isEmpty
                  ? whiteTexture
                  : materialTextures.first,
              baseColorFactor: mesh.baseColorFactor,
              metallicFactor: mesh.metallicFactor,
              roughnessFactor: mesh.roughnessFactor,
            ),
          ]
        : [
            for (final submesh in mesh.submeshes)
              _GameSubmesh(
                indexOffset: submesh.indexOffset,
                indexCount: submesh.indexCount,
                texture: materialTextures[submesh.materialIndex],
                baseColorFactor:
                    mesh.materials[submesh.materialIndex].baseColorFactor,
                metallicFactor:
                    mesh.materials[submesh.materialIndex].metallicFactor,
                roughnessFactor:
                    mesh.materials[submesh.materialIndex].roughnessFactor,
              ),
          ];
    // Skinned meshes get a wider stride (position, uv, normal, joint
    // indices, joint weights); unskinned meshes keep the original layout
    // unchanged — the vast majority of any scene's geometry is static and
    // shouldn't carry unused skinning data.
    final stride = mesh.isSkinned ? 16 : 8;
    final vertexData = Float32List(mesh.vertexCount * stride);
    for (var i = 0; i < mesh.vertexCount; i++) {
      final base = i * stride;
      for (var axis = 0; axis < 3; axis++) {
        vertexData[base + axis] = mesh.positions[i * 3 + axis];
        vertexData[base + 5 + axis] = mesh.normals[i * 3 + axis];
      }
      vertexData[base + 3] = mesh.textureCoordinates[i * 2];
      vertexData[base + 4] = mesh.textureCoordinates[i * 2 + 1];
      if (mesh.isSkinned) {
        for (var c = 0; c < 4; c++) {
          vertexData[base + 8 + c] = mesh.joints[i * 4 + c];
          vertexData[base + 12 + c] = mesh.weights[i * 4 + c];
        }
      }
    }
    final indexData = mesh.uses32BitIndices
        ? Uint32List.fromList(mesh.indices).buffer.asByteData()
        : Uint16List.fromList(mesh.indices).buffer.asByteData();
    return _MeshBuffers(
      vertexBuffer: context.createDeviceBufferWithCopy(
        vertexData.buffer.asByteData(),
      ),
      vertexByteLength: vertexData.lengthInBytes,
      vertexCount: mesh.vertexCount,
      indexBuffer: context.createDeviceBufferWithCopy(indexData),
      indexType: mesh.uses32BitIndices
          ? gpu.IndexType.int32
          : gpu.IndexType.int16,
      submeshes: submeshes,
      boundsMinimum: Vector3(
        mesh.boundsMinimum[0],
        mesh.boundsMinimum[1],
        mesh.boundsMinimum[2],
      ),
      boundsMaximum: Vector3(
        mesh.boundsMaximum[0],
        mesh.boundsMaximum[1],
        mesh.boundsMaximum[2],
      ),
      isSkinned: mesh.isSkinned,
    );
  }
}

/// A model resident on the GPU in its authored units — game transforms are
/// authoritative, so no centering or normalization is applied. Models with
/// animation clips or skins keep their node hierarchy as parts; plain static
/// models collapse to one baked part.
class _GameModel {
  const _GameModel({required this.meshes, required this.parts, this.rig});

  final List<_MeshBuffers> meshes;

  /// (node index or -1 for static, index into [meshes]) per drawable part.
  final List<(int, int)> parts;
  final GlintGlbRig? rig;

  static Future<_GameModel> load(
    Model source,
    GlintTextureDecoder textureDecoder,
  ) async {
    final context = gpu.gpuContext;
    final whiteTexture = context.createTexture(
      gpu.StorageMode.hostVisible,
      1,
      1,
      coordinateSystem: gpu.TextureCoordinateSystem.uploadFromHost,
      enableRenderTargetUsage: false,
    )..overwrite(ByteData(4)..setUint32(0, 0xffffffff));
    final bytes = await source.read();
    if (GlintGlbRig.probeAnimations(bytes) || GlintGlbRig.probeSkins(bytes)) {
      final rig = GlintGlbRig.parse(bytes, debugLabel: source.debugLabel);
      _validateRigForRenderer(rig, source.debugLabel);
      return _GameModel(
        meshes: [
          for (final mesh in rig.meshes)
            await _MeshBuffers.build(
              mesh,
              context,
              whiteTexture,
              textureDecoder,
            ),
        ],
        parts: [
          for (var i = 0; i < rig.nodes.length; i++)
            if (rig.nodes[i].meshIndex != null) (i, rig.nodes[i].meshIndex!),
        ],
        rig: rig,
      );
    }
    final mesh = GlintGlbMesh.parse(bytes, debugLabel: source.debugLabel);
    return _GameModel(
      meshes: [
        await _MeshBuffers.build(mesh, context, whiteTexture, textureDecoder),
      ],
      parts: const [(-1, 0)],
    );
  }

  static void _validateRigForRenderer(GlintGlbRig rig, String debugLabel) {
    for (var nodeIndex = 0; nodeIndex < rig.nodes.length; nodeIndex++) {
      final node = rig.nodes[nodeIndex];
      final meshIndex = node.meshIndex;
      if (meshIndex == null || !rig.meshes[meshIndex].isSkinned) continue;
      final skinIndex = node.skinIndex;
      if (skinIndex == null || skinIndex < 0 || skinIndex >= rig.skins.length) {
        throw GlintGlbException(
          debugLabel,
          'Skinned mesh node $nodeIndex does not reference a valid skin',
        );
      }
      final skin = rig.skins[skinIndex];
      if (skin.jointNodeIndices.length > kMaxJointsPerSkin) {
        throw GlintGlbException(
          debugLabel,
          'Skin $skinIndex has ${skin.jointNodeIndices.length} joints; '
          'the renderer supports at most $kMaxJointsPerSkin',
        );
      }
      for (final joint in rig.meshes[meshIndex].joints) {
        if (joint < 0 ||
            joint != joint.truncateToDouble() ||
            joint >= skin.jointNodeIndices.length) {
          throw GlintGlbException(
            debugLabel,
            'Mesh $meshIndex references joint $joint outside skin $skinIndex',
          );
        }
      }
    }
  }
}
