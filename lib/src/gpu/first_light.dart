import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

import '../assets/environment.dart';
import '../assets/texture_pixels.dart';
import '../assets/glb.dart';
import '../assets/model.dart';
import '../math.dart';
import '../scene.dart';
import 'render_stats.dart';

/// Glint's first verified asset pass: a textured GLB mesh rendered on the GPU.
///
/// Run an app containing this widget with `flutter run --enable-flutter-gpu`.
/// [fallback] is shown with a useful error when Flutter GPU is unavailable.
class GlintGpuFirstLight extends StatefulWidget {
  const GlintGpuFirstLight({
    super.key,
    this.width = 1024,
    this.height = 1024,
    this.fallback,
    this.onError,
    this.model = const Model.asset('packages/glint/assets/models/duck.glb'),
    this.environmentAsset,
    this.material,
    this.autoRotate = true,
    this.enableGestures = true,
    this.showStats = false,
    this.onModelTap,
  });

  final int width;
  final int height;
  final Widget? fallback;
  final ValueChanged<Object>? onError;
  final Model model;

  /// Equirectangular `.hdr` (or PNG/JPEG) asset used for image-based
  /// lighting. When null, the built-in key light and hemisphere ambient
  /// light the model instead.
  final String? environmentAsset;

  /// Overrides the model's own base color, metallic, and roughness at
  /// render time. Swapping this re-renders immediately without reloading
  /// geometry or textures; null restores the glTF material factors.
  final Material3D? material;

  final bool autoRotate;
  final bool enableGestures;

  /// Overlays live FPS, frame time, draw-call, and triangle counters.
  final bool showStats;

  /// Called with the nearest struck triangle when a tap lands on the model.
  /// Taps on empty space do not fire. Requires [enableGestures].
  final ValueChanged<GlintRayHit>? onModelTap;

  @override
  State<GlintGpuFirstLight> createState() => _GlintGpuFirstLightState();
}

class _GlintGpuFirstLightState extends State<GlintGpuFirstLight>
    // Auto-rotate creates a fresh ticker after every pause, so the state needs
    // the multi-ticker provider despite driving one ticker at a time.
    with TickerProviderStateMixin {
  late Future<ui.Image> _image;
  late Future<_PreparedModel> _asset;
  _PreparedModel? _prepared;
  final _stats = ValueNotifier<GlintRenderStats?>(null);
  final _frameTimestamps = <int>[];
  static const double _initialPitch = -.18;
  static const double _initialDistance = 6.4;

  Ticker? _rotationTicker;
  Duration _lastTick = Duration.zero;
  Timer? _resumeTimer;
  gpu.RenderPipeline? _pipeline;
  double _yaw = 0;
  double _pitch = _initialPitch;
  double _distance = _initialDistance;
  double _gestureDistance = _initialDistance;
  double _panX = 0;
  double _panY = 0;
  bool _rendering = false;

  @override
  void initState() {
    super.initState();
    _asset = _loadAsset();
    _image = _render();
    _syncRotationTimer();
  }

  @override
  void didUpdateWidget(GlintGpuFirstLight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.width != widget.width || oldWidget.height != widget.height) {
      _scheduleRender();
    }
    if (oldWidget.model != widget.model ||
        oldWidget.environmentAsset != widget.environmentAsset) {
      _prepared = null;
      _asset = _loadAsset();
      _scheduleRender();
    }
    if (oldWidget.autoRotate != widget.autoRotate) {
      _syncRotationTimer();
    }
    if (oldWidget.material != widget.material) {
      _scheduleRender();
    }
  }

  /// Decodes the model once and uploads its immutable GPU resources —
  /// interleaved vertices, indices, and the base-color texture — so per-frame
  /// work is limited to uniforms and the render pass itself.
  Future<_PreparedModel> _loadAsset() async {
    final mesh = await widget.model.load();
    final pixels = mesh.baseColorImageBytes == null
        ? await GlintTexturePixels.fromAsset(
            'packages/glint/assets/textures/glint-grid.png',
          )
        : await GlintTexturePixels.decode(
            mesh.baseColorImageBytes!,
            debugLabel: 'embedded GLB base-color texture',
          );
    final environment = widget.environmentAsset == null
        ? null
        : await GlintEnvironment.fromAsset(widget.environmentAsset!);
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

    final baseColorTexture = upload(pixels.bytes, pixels.width, pixels.height);
    // The shader always samples both IBL maps, so absent environments bind
    // one black texel instead of branching on a missing resource.
    final blackTexel = ByteData(4);
    final irradianceTexture = environment == null
        ? upload(blackTexel, 1, 1)
        : upload(
            environment.irradiancePixels,
            GlintEnvironment.irradianceWidth,
            GlintEnvironment.irradianceHeight,
          );
    final radianceTexture = environment == null
        ? upload(blackTexel, 1, 1)
        : upload(
            environment.radiancePixels,
            GlintEnvironment.radianceWidth,
            GlintEnvironment.radianceHeight * GlintEnvironment.levelCount,
          );
    final center = [
      (mesh.boundsMinimum[0] + mesh.boundsMaximum[0]) / 2,
      (mesh.boundsMinimum[1] + mesh.boundsMaximum[1]) / 2,
      (mesh.boundsMinimum[2] + mesh.boundsMaximum[2]) / 2,
    ];
    final largestExtent = List.generate(
      3,
      (i) => mesh.boundsMaximum[i] - mesh.boundsMinimum[i],
    ).reduce((a, b) => a > b ? a : b);
    final assetScale = largestExtent == 0 ? 1.0 : 2.5 / largestExtent;
    final vertexData = Float32List(mesh.vertexCount * 8);
    for (var i = 0; i < mesh.vertexCount; i++) {
      final base = i * 8;
      for (var axis = 0; axis < 3; axis++) {
        vertexData[base + axis] =
            (mesh.positions[i * 3 + axis] - center[axis]) * assetScale;
        vertexData[base + 5 + axis] = mesh.normals[i * 3 + axis];
      }
      vertexData[base + 3] = mesh.textureCoordinates[i * 2];
      vertexData[base + 4] = mesh.textureCoordinates[i * 2 + 1];
    }
    final indexData = mesh.uses32BitIndices
        ? Uint32List.fromList(mesh.indices).buffer.asByteData()
        : Uint16List.fromList(mesh.indices).buffer.asByteData();
    return _PreparedModel(
      mesh: mesh,
      vertexBuffer: context.createDeviceBufferWithCopy(
        vertexData.buffer.asByteData(),
      ),
      vertexByteLength: vertexData.lengthInBytes,
      indexBuffer: context.createDeviceBufferWithCopy(indexData),
      indexByteLength: indexData.lengthInBytes,
      indexType: mesh.uses32BitIndices
          ? gpu.IndexType.int32
          : gpu.IndexType.int16,
      baseColorTexture: baseColorTexture,
      irradianceTexture: irradianceTexture,
      radianceTexture: radianceTexture,
      environmentStrength: environment == null ? 0 : 1,
      center: Vector3(center[0], center[1], center[2]),
      assetScale: assetScale,
      boundsMinimum: Vector3(
        (mesh.boundsMinimum[0] - center[0]) * assetScale,
        (mesh.boundsMinimum[1] - center[1]) * assetScale,
        (mesh.boundsMinimum[2] - center[2]) * assetScale,
      ),
      boundsMaximum: Vector3(
        (mesh.boundsMaximum[0] - center[0]) * assetScale,
        (mesh.boundsMaximum[1] - center[1]) * assetScale,
        (mesh.boundsMaximum[2] - center[2]) * assetScale,
      ),
    );
  }

  void _stopAutoRotate() {
    _rotationTicker?.dispose();
    _rotationTicker = null;
  }

  void _syncRotationTimer() {
    _stopAutoRotate();
    if (widget.autoRotate) {
      _lastTick = Duration.zero;
      _rotationTicker = createTicker((elapsed) {
        final seconds = (elapsed - _lastTick).inMicroseconds / 1e6;
        _lastTick = elapsed;
        _yaw += seconds * .3;
        _scheduleRender();
      })..start();
    }
  }

  void _scheduleRender() {
    if (!mounted || _rendering) return;
    _rendering = true;
    final next = _render();
    setState(() {
      _image = next;
    });
    next.then((_) => _rendering = false, onError: (_) => _rendering = false);
  }

  @override
  void dispose() {
    _stopAutoRotate();
    _resumeTimer?.cancel();
    _stats.dispose();
    super.dispose();
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

  /// The camera matrix for the current orbit state, shared by rendering and
  /// tap picking so both always agree on what is on screen.
  vm.Matrix4 _modelViewProjection() {
    // Match the narrow lens of Duck.glb's authored camera (yfov ~37.8°);
    // a wide FOV up close fisheyes the model at head-on yaw angles.
    final projection = vm.makePerspectiveMatrix(
      37.8 * 3.141592653589793 / 180,
      widget.width / widget.height,
      .1,
      100,
    );
    final view = vm.Matrix4.translationValues(0, 0, -_distance);
    return projection * view * _modelMatrix() as vm.Matrix4;
  }

  vm.Matrix4 _modelMatrix() => vm.Matrix4.identity()
    ..translateByDouble(_panX, _panY, 0, 1)
    ..rotateX(_pitch)
    ..rotateY(_yaw);

  void _handleTap(Offset localPosition) {
    final prepared = _prepared;
    final onModelTap = widget.onModelTap;
    final size = context.size;
    if (prepared == null ||
        onModelTap == null ||
        size == null ||
        size.isEmpty) {
      return;
    }
    // Invert the RawImage's BoxFit.cover mapping to find where the tap lands
    // on the render texture, rejecting taps in any letterboxed gutter.
    final coverScale = math.max(
      size.width / widget.width,
      size.height / widget.height,
    );
    final displayedWidth = widget.width * coverScale;
    final displayedHeight = widget.height * coverScale;
    final u =
        (localPosition.dx - (size.width - displayedWidth) / 2) / displayedWidth;
    final v =
        (localPosition.dy - (size.height - displayedHeight) / 2) /
        displayedHeight;
    if (u < 0 || u > 1 || v < 0 || v > 1) return;
    final inverse = vm.Matrix4.zero();
    if (inverse.copyInverse(_modelViewProjection()) == 0) return;
    final ray = GlintRay.fromNdc(u * 2 - 1, 1 - v * 2, inverse.storage);
    // The ray is in the renderer's normalized space; map it back to the
    // mesh's own space, where the CPU-side triangle data lives.
    final meshRay = GlintRay(
      Vector3(
        ray.origin.x / prepared.assetScale + prepared.center.x,
        ray.origin.y / prepared.assetScale + prepared.center.y,
        ray.origin.z / prepared.assetScale + prepared.center.z,
      ),
      ray.direction,
    );
    final hit = prepared.mesh.intersectRay(meshRay);
    if (hit != null) onModelTap(hit);
  }

  Future<ui.Image> _render() async {
    try {
      final stopwatch = Stopwatch()..start();
      // Await the asset before anything that can throw synchronously, so a
      // failed load is always observed here instead of becoming an
      // unhandled async error.
      final prepared = await _asset;
      final context = gpu.gpuContext;
      _prepared = prepared;
      final mesh = prepared.mesh;
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
      final target = gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
          texture: texture,
          clearValue: vm.Vector4(9 / 255, 11 / 255, 19 / 255, 1),
        ),
        depthStencilAttachment: gpu.DepthStencilAttachment(
          texture: depthTexture,
          depthClearValue: 1,
        ),
      );
      final pass = commandBuffer.createRenderPass(target);
      pass.bindPipeline(pipeline);
      pass.setDepthWriteEnable(true);
      pass.setDepthCompareOperation(gpu.CompareFunction.less);
      // glTF front faces wind counter-clockwise; Impeller defaults to
      // clockwise, which would cull the outside of the model and expose its
      // interior shell.
      pass.setWindingOrder(gpu.WindingOrder.counterClockwise);
      pass.setCullMode(gpu.CullMode.backFace);

      final hostBuffer = context.createHostBuffer();
      pass.bindVertexBuffer(
        gpu.BufferView(
          prepared.vertexBuffer,
          offsetInBytes: 0,
          lengthInBytes: prepared.vertexByteLength,
        ),
        mesh.vertexCount,
      );
      pass.bindIndexBuffer(
        gpu.BufferView(
          prepared.indexBuffer,
          offsetInBytes: 0,
          lengthInBytes: prepared.indexByteLength,
        ),
        prepared.indexType,
        mesh.indices.length,
      );
      final model = _modelMatrix();
      final mvp = _modelViewProjection();
      final material = widget.material;
      pass.bindUniform(
        pipeline.vertexShader.getUniformSlot('VertInfo'),
        hostBuffer.emplace(
          _floats([
            ...mvp.storage,
            ...model.storage,
            ...material?.linearBaseColorFactor ?? mesh.baseColorFactor,
            // Key light rakes in from the upper left, matching the Khronos
            // sample viewer, so form shading stays visible while orbiting.
            // The fourth component switches the shader to image-based
            // ambient lighting when an environment is loaded.
            .55,
            -1,
            -.65,
            prepared.environmentStrength,
            .26,
            2.6,
            material?.metallic ?? mesh.metallicFactor,
            material?.roughness ?? mesh.roughnessFactor,
            0,
            0,
            _distance,
            0,
          ]),
        ),
      );
      pass.bindTexture(
        pipeline.fragmentShader.getUniformSlot('tex'),
        prepared.baseColorTexture,
        sampler: gpu.SamplerOptions(
          minFilter: gpu.MinMagFilter.linear,
          magFilter: gpu.MinMagFilter.linear,
          widthAddressMode: gpu.SamplerAddressMode.repeat,
          heightAddressMode: gpu.SamplerAddressMode.repeat,
        ),
      );
      // Equirect maps wrap horizontally (longitude) and clamp vertically so
      // the poles and the radiance atlas bands never bleed.
      final environmentSampler = gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.linear,
        magFilter: gpu.MinMagFilter.linear,
        widthAddressMode: gpu.SamplerAddressMode.repeat,
        heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
      );
      pass.bindTexture(
        pipeline.fragmentShader.getUniformSlot('irradiance_map'),
        prepared.irradianceTexture,
        sampler: environmentSampler,
      );
      pass.bindTexture(
        pipeline.fragmentShader.getUniformSlot('radiance_map'),
        prepared.radianceTexture,
        sampler: environmentSampler,
      );
      // Coarse frustum culling: when pan or zoom pushes the model fully
      // off-screen, submit the cleared target without a draw call.
      final visible = GlintFrustum.fromColumnMajor(
        mvp.storage,
      ).intersectsBounds(prepared.boundsMinimum, prepared.boundsMaximum);
      if (visible) {
        pass.draw();
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
      _recordStats(
        stopwatch.elapsedMicroseconds / 1000,
        visible ? 1 : 0,
        visible ? mesh.indices.length ~/ 3 : 0,
      );
      return texture.asImage();
    } catch (error) {
      debugPrint('Glint Flutter GPU render failed: $error');
      widget.onError?.call(error);
      rethrow;
    }
  }

  ByteData _floats(List<double> values) =>
      Float32List.fromList(values).buffer.asByteData();

  @override
  Widget build(BuildContext context) {
    Widget viewport = FutureBuilder<ui.Image>(
      future: _image,
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
    if (widget.enableGestures) {
      viewport = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: widget.onModelTap == null
            ? null
            : (details) => _handleTap(details.localPosition),
        // Double tap recovers from any orbit the user gets lost in.
        onDoubleTap: () {
          _resumeTimer?.cancel();
          _yaw = 0;
          _pitch = _initialPitch;
          _distance = _initialDistance;
          _gestureDistance = _initialDistance;
          _panX = 0;
          _panY = 0;
          _syncRotationTimer();
          _scheduleRender();
        },
        onScaleStart: (_) {
          // The user has taken control: auto-rotate must not fight the drag.
          _stopAutoRotate();
          _resumeTimer?.cancel();
          _gestureDistance = _distance;
        },
        onScaleUpdate: (details) {
          if (details.pointerCount > 1) {
            _panX += details.focalPointDelta.dx * .004;
            _panY -= details.focalPointDelta.dy * .004;
          } else {
            _yaw += details.focalPointDelta.dx * .008;
            // ±60° keeps the orbit shy of the poles, where a model flattens
            // into an unrecognizable top-down silhouette.
            _pitch = (_pitch + details.focalPointDelta.dy * .008).clamp(
              -1.05,
              1.05,
            );
          }
          _distance = (_gestureDistance / details.scale).clamp(4, 13);
          _scheduleRender();
        },
        onScaleEnd: (_) {
          _resumeTimer?.cancel();
          _resumeTimer = Timer(
            const Duration(milliseconds: 2500),
            _syncRotationTimer,
          );
        },
        child: viewport,
      );
    }
    if (widget.showStats) {
      viewport = Stack(
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
    return viewport;
  }
}

/// A model's immutable GPU residency: geometry and base-color texture are
/// uploaded once per asset, leaving uniforms as the only per-frame traffic.
class _PreparedModel {
  const _PreparedModel({
    required this.mesh,
    required this.vertexBuffer,
    required this.vertexByteLength,
    required this.indexBuffer,
    required this.indexByteLength,
    required this.indexType,
    required this.baseColorTexture,
    required this.irradianceTexture,
    required this.radianceTexture,
    required this.environmentStrength,
    required this.center,
    required this.assetScale,
    required this.boundsMinimum,
    required this.boundsMaximum,
  });

  final GlintGlbMesh mesh;
  final gpu.DeviceBuffer vertexBuffer;
  final int vertexByteLength;
  final gpu.DeviceBuffer indexBuffer;
  final int indexByteLength;
  final gpu.IndexType indexType;
  final gpu.Texture baseColorTexture;

  /// Prefiltered IBL maps; one black texel each when no environment is set.
  final gpu.Texture irradianceTexture;
  final gpu.Texture radianceTexture;
  final double environmentStrength;

  /// The centering translation and uniform scale applied to the uploaded
  /// vertices, needed to map picking rays back into the source mesh's space.
  final Vector3 center;
  final double assetScale;

  /// Model-space bounds after the centering and normalization applied to the
  /// uploaded vertices, ready for frustum tests against the full MVP.
  final Vector3 boundsMinimum;
  final Vector3 boundsMaximum;
}
