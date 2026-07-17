import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

import '../assets/texture_pixels.dart';
import '../assets/glb.dart';

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
      final mesh = await GlintGlbMesh.fromAsset(
        'packages/glint/assets/models/duck.glb',
      );
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
      final texturePixels = mesh.baseColorImageBytes == null
          ? await GlintTexturePixels.fromAsset(
              'packages/glint/assets/textures/glint-grid.png',
            )
          : await GlintTexturePixels.decode(
              mesh.baseColorImageBytes!,
              debugLabel: 'embedded GLB base-color texture',
            );
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
      final bounds = _bounds(mesh.positions);
      final center = [
        (bounds.$1[0] + bounds.$2[0]) / 2,
        (bounds.$1[1] + bounds.$2[1]) / 2,
        (bounds.$1[2] + bounds.$2[2]) / 2,
      ];
      final largestExtent = List.generate(
        3,
        (i) => bounds.$2[i] - bounds.$1[i],
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
      final view = vm.Matrix4.translationValues(0, 0, -4.2);
      final model = vm.Matrix4.identity()
        ..rotateX(-.48)
        ..rotateY(.72);
      final mvp = projection * view * model;
      pass.bindUniform(
        pipeline.vertexShader.getUniformSlot('VertInfo'),
        hostBuffer.emplace(_floats([...mvp.storage, ...mesh.baseColorFactor])),
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

  (List<double>, List<double>) _bounds(List<double> positions) {
    final minimum = [double.infinity, double.infinity, double.infinity];
    final maximum = [
      double.negativeInfinity,
      double.negativeInfinity,
      double.negativeInfinity,
    ];
    for (var i = 0; i < positions.length; i += 3) {
      for (var axis = 0; axis < 3; axis++) {
        final value = positions[i + axis];
        if (value < minimum[axis]) {
          minimum[axis] = value;
        }
        if (value > maximum[axis]) {
          maximum[axis] = value;
        }
      }
    }
    return (minimum, maximum);
  }

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
