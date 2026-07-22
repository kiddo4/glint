import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../math.dart';
import '../scene.dart';

/// Transforms [light]'s local-space position into world space via [world] —
/// typically a game instance's own composed transform — so a light attached
/// to a moving object (a muzzle flash on a gun, a headlight on a car) tracks
/// it automatically instead of requiring its world position to be
/// recomputed by hand every frame.
PointLight worldPointLight(PointLight light, vm.Matrix4 world) {
  final position = world.transform3(
    vm.Vector3(light.position.x, light.position.y, light.position.z),
  );
  return PointLight(
    position: Vector3(position.x, position.y, position.z),
    color: light.color,
    intensity: light.intensity,
    range: light.range,
  );
}

/// As [worldPointLight], additionally rotating [light]'s direction by
/// [world]'s rotation (no translation, since a direction has no position).
SpotLight worldSpotLight(SpotLight light, vm.Matrix4 world) {
  final position = world.transform3(
    vm.Vector3(light.position.x, light.position.y, light.position.z),
  );
  final direction = world.rotate3(
    vm.Vector3(light.direction.x, light.direction.y, light.direction.z),
  );
  return SpotLight(
    position: Vector3(position.x, position.y, position.z),
    direction: Vector3(direction.x, direction.y, direction.z),
    color: light.color,
    intensity: light.intensity,
    range: light.range,
    innerConeAngle: light.innerConeAngle,
    outerConeAngle: light.outerConeAngle,
  );
}

/// Packs point/spot lights into the four parallel float arrays the
/// `FrameInfo.punctual_*` shader uniforms expect (`shaders/unlit.frag`),
/// shared by both GPU renderers ([GlintGpuFirstLight] and [GlintGameView])
/// so the packing logic and truncation behavior stay in one place.
///
/// Combined lights beyond [kMaxPunctualLights] (point lights first, then
/// spot lights, each in the order given) are dropped. Games routinely spawn
/// more transient lights (coins, muzzle flashes) than the budget — that's
/// expected steady-state behavior, not a mistake — so this only prints a
/// one-time-per-call debug warning rather than asserting/crashing. Callers
/// that care which lights survive (e.g. [GlintGameView]) should sort by
/// relevance — typically camera distance — before calling this.
class GlintPackedPunctualLights {
  factory GlintPackedPunctualLights(
    List<PointLight> pointLights,
    List<SpotLight> spotLights,
  ) {
    assert(() {
      final total = pointLights.length + spotLights.length;
      if (total > kMaxPunctualLights) {
        debugPrint(
          'Glint: $total combined point/spot lights, but only '
          '$kMaxPunctualLights render at once; the rest are dropped this '
          'frame.',
        );
      }
      return true;
    }());
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
