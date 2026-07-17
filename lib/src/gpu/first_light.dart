import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

import '../assets/texture_pixels.dart';
import '../assets/glb.dart';
import '../assets/model.dart';

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
    this.autoRotate = true,
    this.enableGestures = true,
  });

  final int width;
  final int height;
  final Widget? fallback;
  final ValueChanged<Object>? onError;
  final Model model;
  final bool autoRotate;
  final bool enableGestures;

  @override
  State<GlintGpuFirstLight> createState() => _GlintGpuFirstLightState();
}

class _GlintGpuFirstLightState extends State<GlintGpuFirstLight> {
  late Future<ui.Image> _image;
  late Future<(GlintGlbMesh, GlintTexturePixels)> _asset;
  Timer? _rotationTimer;
  double _yaw = 0;
  double _pitch = -.18;
  double _distance = 4.2;
  double _gestureDistance = 4.2;
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
    if (oldWidget.model != widget.model) {
      _asset = _loadAsset();
      _scheduleRender();
    }
    if (oldWidget.autoRotate != widget.autoRotate) {
      _syncRotationTimer();
    }
  }

  Future<(GlintGlbMesh, GlintTexturePixels)> _loadAsset() async {
    final mesh = await widget.model.load();
    final pixels = mesh.baseColorImageBytes == null
        ? await GlintTexturePixels.fromAsset(
            'packages/glint/assets/textures/glint-grid.png',
          )
        : await GlintTexturePixels.decode(
            mesh.baseColorImageBytes!,
            debugLabel: 'embedded GLB base-color texture',
          );
    return (mesh, pixels);
  }

  void _syncRotationTimer() {
    _rotationTimer?.cancel();
    if (widget.autoRotate) {
      _rotationTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
        _yaw += .025;
        _scheduleRender();
      });
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
    _rotationTimer?.cancel();
    super.dispose();
  }

  Future<ui.Image> _render() async {
    try {
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

      final context = gpu.gpuContext;
      final asset = await _asset;
      final mesh = asset.$1;
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
      final texturePixels = asset.$2;
      final sourceTexture = context.createTexture(
        gpu.StorageMode.hostVisible,
        texturePixels.width,
        texturePixels.height,
        coordinateSystem: gpu.TextureCoordinateSystem.uploadFromHost,
        enableRenderTargetUsage: false,
      );
      sourceTexture.overwrite(texturePixels.bytes);
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
      final pipeline = context.createRenderPipeline(vertex, fragment);
      pass.bindPipeline(pipeline);
      pass.setDepthWriteEnable(true);
      pass.setDepthCompareOperation(gpu.CompareFunction.less);
      pass.setCullMode(gpu.CullMode.backFace);

      final hostBuffer = context.createHostBuffer();
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
      final vertices = <double>[];
      for (var i = 0; i < mesh.vertexCount; i++) {
        vertices.addAll(
          List.generate(
            3,
            (axis) =>
                (mesh.positions[i * 3 + axis] - center[axis]) * assetScale,
          ),
        );
        vertices.addAll(mesh.textureCoordinates.skip(i * 2).take(2));
        vertices.addAll(mesh.normals.skip(i * 3).take(3));
      }
      pass.bindVertexBuffer(
        hostBuffer.emplace(_floats(vertices)),
        mesh.vertexCount,
      );
      pass.bindIndexBuffer(
        hostBuffer.emplace(
          mesh.uses32BitIndices
              ? Uint32List.fromList(mesh.indices).buffer.asByteData()
              : Uint16List.fromList(mesh.indices).buffer.asByteData(),
        ),
        mesh.uses32BitIndices ? gpu.IndexType.int32 : gpu.IndexType.int16,
        mesh.indices.length,
      );
      final projection = vm.makePerspectiveMatrix(
        55 * 3.141592653589793 / 180,
        widget.width / widget.height,
        .1,
        100,
      );
      final view = vm.Matrix4.translationValues(0, 0, -_distance);
      final model = vm.Matrix4.identity()
        ..translateByDouble(_panX, _panY, 0, 1)
        ..rotateX(_pitch)
        ..rotateY(_yaw);
      final mvp = projection * view * model;
      pass.bindUniform(
        pipeline.vertexShader.getUniformSlot('VertInfo'),
        hostBuffer.emplace(
          _floats([
            ...mvp.storage,
            ...model.storage,
            ...mesh.baseColorFactor,
            -1,
            -1,
            -1,
            0,
            .42,
            3.2,
            mesh.metallicFactor,
            mesh.roughnessFactor,
            0,
            0,
            _distance,
            0,
          ]),
        ),
      );
      pass.bindTexture(
        pipeline.fragmentShader.getUniformSlot('tex'),
        sourceTexture,
        sampler: gpu.SamplerOptions(
          minFilter: gpu.MinMagFilter.linear,
          magFilter: gpu.MinMagFilter.linear,
          widthAddressMode: gpu.SamplerAddressMode.repeat,
          heightAddressMode: gpu.SamplerAddressMode.repeat,
        ),
      );
      pass.draw();

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
        onScaleStart: (_) => _gestureDistance = _distance,
        onScaleUpdate: (details) {
          if (details.pointerCount > 1) {
            _panX += details.focalPointDelta.dx * .004;
            _panY -= details.focalPointDelta.dy * .004;
          } else {
            _yaw += details.focalPointDelta.dx * .008;
            _pitch = (_pitch + details.focalPointDelta.dy * .008).clamp(
              -1.4,
              1.4,
            );
          }
          _distance = (_gestureDistance / details.scale).clamp(2.5, 9);
          _scheduleRender();
        },
        child: viewport,
      );
    }
    return viewport;
  }
}
