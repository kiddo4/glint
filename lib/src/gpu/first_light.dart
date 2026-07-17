import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

/// Glint's first verified 3D pass: an indexed, depth-tested GPU cube.
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
  });

  final int width;
  final int height;
  final Widget? fallback;
  final ValueChanged<Object>? onError;

  @override
  State<GlintGpuFirstLight> createState() => _GlintGpuFirstLightState();
}

class _GlintGpuFirstLightState extends State<GlintGpuFirstLight> {
  late Future<ui.Image> _image;

  @override
  void initState() {
    super.initState();
    _image = _render();
  }

  @override
  void didUpdateWidget(GlintGpuFirstLight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.width != widget.width || oldWidget.height != widget.height) {
      _image = _render();
    }
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
      final pipeline = context.createRenderPipeline(vertex, fragment);
      pass.bindPipeline(pipeline);
      pass.setDepthWriteEnable(true);
      pass.setDepthCompareOperation(gpu.CompareFunction.less);
      pass.setCullMode(gpu.CullMode.backFace);

      final hostBuffer = context.createHostBuffer();
      pass.bindVertexBuffer(hostBuffer.emplace(_floats(_cubeVertices)), 8);
      pass.bindIndexBuffer(
        hostBuffer.emplace(
          Uint16List.fromList(_cubeIndices).buffer.asByteData(),
        ),
        gpu.IndexType.int16,
        _cubeIndices.length,
      );
      final projection = vm.makePerspectiveMatrix(
        55 * 3.141592653589793 / 180,
        widget.width / widget.height,
        .1,
        100,
      );
      final view = vm.Matrix4.translationValues(0, 0, -4.2);
      final model = vm.Matrix4.identity()
        ..rotateX(-.48)
        ..rotateY(.72);
      final mvp = projection * view * model;
      pass.bindUniform(
        pipeline.vertexShader.getUniformSlot('VertInfo'),
        hostBuffer.emplace(_floats([...mvp.storage, 1, 1, 1, 1])),
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
  Widget build(BuildContext context) => FutureBuilder<ui.Image>(
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
}

const _cubeVertices = <double>[
  -1,
  -1,
  -1,
  1,
  -1,
  -1,
  1,
  1,
  -1,
  -1,
  1,
  -1,
  -1,
  -1,
  1,
  1,
  -1,
  1,
  1,
  1,
  1,
  -1,
  1,
  1,
];

const _cubeIndices = <int>[
  0,
  2,
  1,
  0,
  3,
  2,
  4,
  5,
  6,
  4,
  6,
  7,
  0,
  4,
  7,
  0,
  7,
  3,
  1,
  2,
  6,
  1,
  6,
  5,
  3,
  7,
  6,
  3,
  6,
  2,
  0,
  1,
  5,
  0,
  5,
  4,
];
