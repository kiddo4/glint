import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../math.dart';
import '../scene.dart';

/// Packs point/spot lights into the four parallel float arrays the
/// `FrameInfo.punctual_*` shader uniforms expect (`shaders/unlit.vert`),
/// shared by both GPU renderers ([GlintGpuFirstLight] and [GlintGameView])
/// so the packing logic and truncation behavior stay in one place.
///
/// Combined lights beyond [kMaxPunctualLights] (point lights first, then
/// spot lights) are dropped, with a debug-mode assertion.
class GlintPackedPunctualLights {
  factory GlintPackedPunctualLights(
    List<PointLight> pointLights,
    List<SpotLight> spotLights,
  ) {
    assert(
      pointLights.length + spotLights.length <= kMaxPunctualLights,
      'Scene declares ${pointLights.length + spotLights.length} combined '
      'point/spot lights; only the first $kMaxPunctualLights are rendered.',
    );
    final positionRange = Float32List(kMaxPunctualLights * 4);
    final colorIntensity = Float32List(kMaxPunctualLights * 4);
    final directionOuterCos = Float32List(kMaxPunctualLights * 4);
    final innerCosFlags = Float32List(kMaxPunctualLights * 4);

    void writeCommon(int index, Vector3 position, Color color,
        double intensity, double range) {
      final base = index * 4;
      positionRange[base] = position.x;
      positionRange[base + 1] = position.y;
      positionRange[base + 2] = position.z;
      positionRange[base + 3] = range;
      // Colors are sRGB, like every Flutter Color; linearize before the
      // shader's linear-space lighting consumes them.
      colorIntensity[base] = math.pow(color.r, 2.2).toDouble();
      colorIntensity[base + 1] = math.pow(color.g, 2.2).toDouble();
      colorIntensity[base + 2] = math.pow(color.b, 2.2).toDouble();
      colorIntensity[base + 3] = intensity;
    }

    var count = 0;
    for (final light in pointLights) {
      if (count >= kMaxPunctualLights) break;
      writeCommon(
        count,
        light.position,
        light.color,
        light.intensity,
        light.range,
      );
      // direction_outer_cos/inner_cos_flags stay zero: inner_cos_flags.y
      // (the spot flag) defaults to 0, marking this slot as a point light.
      count++;
    }
    for (final light in spotLights) {
      if (count >= kMaxPunctualLights) break;
      writeCommon(
        count,
        light.position,
        light.color,
        light.intensity,
        light.range,
      );
      final base = count * 4;
      final direction = light.direction.normalized;
      directionOuterCos[base] = direction.x;
      directionOuterCos[base + 1] = direction.y;
      directionOuterCos[base + 2] = direction.z;
      directionOuterCos[base + 3] = math.cos(light.outerConeAngle);
      innerCosFlags[base] = math.cos(light.innerConeAngle);
      innerCosFlags[base + 1] = 1;
      count++;
    }

    return GlintPackedPunctualLights._(
      count: count,
      positionRange: positionRange,
      colorIntensity: colorIntensity,
      directionOuterCos: directionOuterCos,
      innerCosFlags: innerCosFlags,
    );
  }

  const GlintPackedPunctualLights._({
    required this.count,
    required this.positionRange,
    required this.colorIntensity,
    required this.directionOuterCos,
    required this.innerCosFlags,
  });

  /// Empty singleton for renderers with no punctual lights, avoiding a
  /// reallocation of four zeroed arrays every frame in the common case.
  static final GlintPackedPunctualLights empty = GlintPackedPunctualLights(
    const [],
    const [],
  );

  final int count;
  final Float32List positionRange;
  final Float32List colorIntensity;
  final Float32List directionOuterCos;
  final Float32List innerCosFlags;
}
