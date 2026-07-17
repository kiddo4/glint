import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

/// The first verified Glint render pass: a triangle produced by `flutter_gpu`.
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
      final commandBuffer = context.createCommandBuffer();
      final target = gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
          texture: texture,
          clearValue: vm.Vector4(9 / 255, 11 / 255, 19 / 255, 1),
        ),
      );
      final pass = commandBuffer.createRenderPass(target);
      final pipeline = context.createRenderPipeline(vertex, fragment);
      pass.bindPipeline(pipeline);

      final hostBuffer = context.createHostBuffer();
      pass.bindVertexBuffer(
        hostBuffer.emplace(
          _floats(const [-0.72, 0.58, 0.0, -0.72, 0.72, 0.58]),
        ),
        3,
      );
      pass.bindUniform(
        pipeline.vertexShader.getUniformSlot('VertInfo'),
        hostBuffer.emplace(
          _floats(const [
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
            1,
            .69,
            0,
            1,
          ]),
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
