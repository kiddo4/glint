import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

import '../assets/environment.dart';
import '../assets/glb.dart';
import '../assets/model.dart';
import '../assets/texture_pixels.dart';
import '../math.dart';
import '../scene.dart';

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
    this.translucent = false,
  });

  /// Key into [GlintGameView.models].
  final String model;

  /// World placement in authored model units (no auto-centering or scaling).
  final Transform3D transform;

  /// Overrides the model's authored material for this instance only.
  final Material3D? material;

  /// Alpha-blends over opaque geometry without writing depth; drawn last.
  /// Use for blob shadows and other soft decals.
  final bool translucent;
}

/// Everything the renderer needs to draw one game frame.
class GlintGameFrame {
  const GlintGameFrame({required this.camera, required this.instances});

  final GlintGameCamera camera;
  final List<GlintGameInstance> instances;
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
    this.environmentAsset,
    this.width = 1024,
    this.height = 1024,
    this.lightDirection = const Vector3(.55, -1, -.65),
    this.lightIntensity = 2.6,
    this.ambientIntensity = .26,
    this.backgroundColor = const ui.Color(0xff090b13),
    this.fogColor,
    this.fogDistance = 0,
    this.fallback,
    this.onError,
  });

  /// The models this game draws, keyed by the names frames reference.
  final Map<String, Model> models;

  /// Advances the simulation by the elapsed seconds and describes the frame.
  final GlintGameFrame Function(double secondsElapsed) onFrame;

  final String? environmentAsset;
  final int width;
  final int height;
  final Vector3 lightDirection;
  final double lightIntensity;
  final double ambientIntensity;
  final ui.Color backgroundColor;

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
  bool _rendering = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _assets = _loadAssets();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void reassemble() {
    super.reassemble();
    _pipeline = null;
    _failed = false;
  }

  @override
  void didUpdateWidget(GlintGameView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.models != widget.models ||
        oldWidget.environmentAsset != widget.environmentAsset) {
      _assets = _loadAssets();
      _failed = false;
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
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
    _rendering = true;
    final next = _render(frame);
    setState(() {
      _image = next;
    });
    next.then(
      (_) => _rendering = false,
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
      models[entry.key] = await _GameModel.load(entry.value);
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
    return _GameAssets(
      models: models,
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
      'packages/glint/shaders/glint.shaderbundle',
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

  Future<ui.Image> _render(GlintGameFrame frame) async {
    try {
      final assets = await _assets;
      final context = gpu.gpuContext;
      final pipeline = _obtainPipeline(context);
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
      final hostBuffer = context.createHostBuffer();
      void draw(GlintGameInstance instance) {
        final model = assets.models[instance.model];
        if (model == null) {
          throw StateError('Unknown game model "${instance.model}".');
        }
        final world = _composeTransform(instance.transform);
        final mvp = viewProjection * world as vm.Matrix4;
        final visible = GlintFrustum.fromColumnMajor(
          mvp.storage,
        ).intersectsBounds(model.boundsMinimum, model.boundsMaximum);
        if (!visible) return;
        pass.bindVertexBuffer(
          gpu.BufferView(
            model.vertexBuffer,
            offsetInBytes: 0,
            lengthInBytes: model.vertexByteLength,
          ),
          model.vertexCount,
        );
        pass.bindIndexBuffer(
          gpu.BufferView(
            model.indexBuffer,
            offsetInBytes: 0,
            lengthInBytes: model.indexByteLength,
          ),
          model.indexType,
          model.indexCount,
        );
        final material = instance.material;
        pass.bindUniform(
          pipeline.vertexShader.getUniformSlot('VertInfo'),
          hostBuffer.emplace(
            _floats([
              ...mvp.storage,
              ...world.storage,
              ...material?.linearBaseColorFactor ??
                  model.mesh.baseColorFactor,
              widget.lightDirection.x,
              widget.lightDirection.y,
              widget.lightDirection.z,
              assets.environmentStrength,
              widget.ambientIntensity,
              widget.lightIntensity,
              material?.metallic ?? model.mesh.metallicFactor,
              material?.roughness ?? model.mesh.roughnessFactor,
              camera.position.x,
              camera.position.y,
              camera.position.z,
              0,
              ...fogUniform,
            ]),
          ),
        );
        pass.bindTexture(
          pipeline.fragmentShader.getUniformSlot('tex'),
          model.baseColorTexture,
          sampler: gpu.SamplerOptions(
            minFilter: gpu.MinMagFilter.linear,
            magFilter: gpu.MinMagFilter.linear,
            widthAddressMode: gpu.SamplerAddressMode.repeat,
            heightAddressMode: gpu.SamplerAddressMode.repeat,
          ),
        );
        pass.bindTexture(
          pipeline.fragmentShader.getUniformSlot('irradiance_map'),
          assets.irradianceTexture,
          sampler: environmentSampler,
        );
        pass.bindTexture(
          pipeline.fragmentShader.getUniformSlot('radiance_map'),
          assets.radianceTexture,
          sampler: environmentSampler,
        );
        pass.draw();
      }

      // Opaque geometry first with depth writes, then translucent instances
      // (blob shadows, glass) blended over it without disturbing the depth
      // buffer.
      for (final instance in frame.instances) {
        if (!instance.translucent) draw(instance);
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

      final completer = Completer<void>();
      commandBuffer.submit(
        completionCallback: (success) {
          success
              ? completer.complete()
              : completer.completeError(StateError('GPU submission failed.'));
        },
      );
      await completer.future;
      return texture.asImage();
    } catch (error) {
      debugPrint('Glint game render failed: $error');
      widget.onError?.call(error);
      rethrow;
    }
  }

  /// World matrix matching [Transform3D.apply]: scale, then X/Y/Z rotation,
  /// then translation.
  vm.Matrix4 _composeTransform(Transform3D transform) {
    final matrix = vm.Matrix4.identity()
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
    return matrix;
  }

  ByteData _floats(List<double> values) =>
      Float32List.fromList(values).buffer.asByteData();

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return widget.fallback ?? const SizedBox.expand();
    return FutureBuilder<ui.Image>(
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
}

class _GameAssets {
  const _GameAssets({
    required this.models,
    required this.irradianceTexture,
    required this.radianceTexture,
    required this.environmentStrength,
  });

  final Map<String, _GameModel> models;
  final gpu.Texture irradianceTexture;
  final gpu.Texture radianceTexture;
  final double environmentStrength;
}

/// A model resident on the GPU in its authored units — game transforms are
/// authoritative, so no centering or normalization is applied.
class _GameModel {
  const _GameModel({
    required this.mesh,
    required this.vertexBuffer,
    required this.vertexByteLength,
    required this.vertexCount,
    required this.indexBuffer,
    required this.indexByteLength,
    required this.indexCount,
    required this.indexType,
    required this.baseColorTexture,
    required this.boundsMinimum,
    required this.boundsMaximum,
  });

  final GlintGlbMesh mesh;
  final gpu.DeviceBuffer vertexBuffer;
  final int vertexByteLength;
  final int vertexCount;
  final gpu.DeviceBuffer indexBuffer;
  final int indexByteLength;
  final int indexCount;
  final gpu.IndexType indexType;
  final gpu.Texture baseColorTexture;
  final Vector3 boundsMinimum;
  final Vector3 boundsMaximum;

  static Future<_GameModel> load(Model source) async {
    final mesh = await source.load();
    // Untextured game props shade from their material factors alone, so the
    // sampler needs plain white — not the showcase grid.
    final pixels = mesh.baseColorImageBytes == null
        ? GlintTexturePixels(
            width: 1,
            height: 1,
            bytes: ByteData(4)
              ..setUint32(0, 0xffffffff),
          )
        : await GlintTexturePixels.decode(
            mesh.baseColorImageBytes!,
            debugLabel: 'embedded GLB base-color texture',
          );
    final context = gpu.gpuContext;
    final baseColorTexture = context.createTexture(
      gpu.StorageMode.hostVisible,
      pixels.width,
      pixels.height,
      coordinateSystem: gpu.TextureCoordinateSystem.uploadFromHost,
      enableRenderTargetUsage: false,
    );
    baseColorTexture.overwrite(pixels.bytes);
    final vertexData = Float32List(mesh.vertexCount * 8);
    for (var i = 0; i < mesh.vertexCount; i++) {
      final base = i * 8;
      for (var axis = 0; axis < 3; axis++) {
        vertexData[base + axis] = mesh.positions[i * 3 + axis];
        vertexData[base + 5 + axis] = mesh.normals[i * 3 + axis];
      }
      vertexData[base + 3] = mesh.textureCoordinates[i * 2];
      vertexData[base + 4] = mesh.textureCoordinates[i * 2 + 1];
    }
    final indexData = mesh.uses32BitIndices
        ? Uint32List.fromList(mesh.indices).buffer.asByteData()
        : Uint16List.fromList(mesh.indices).buffer.asByteData();
    return _GameModel(
      mesh: mesh,
      vertexBuffer: context.createDeviceBufferWithCopy(
        vertexData.buffer.asByteData(),
      ),
      vertexByteLength: vertexData.lengthInBytes,
      vertexCount: mesh.vertexCount,
      indexBuffer: context.createDeviceBufferWithCopy(indexData),
      indexByteLength: indexData.lengthInBytes,
      indexCount: mesh.indices.length,
      indexType: mesh.uses32BitIndices
          ? gpu.IndexType.int32
          : gpu.IndexType.int16,
      baseColorTexture: baseColorTexture,
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
    );
  }
}
