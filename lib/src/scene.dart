import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'assets/model.dart';
import 'math.dart';

abstract class Camera3D {
  const Camera3D({this.position = const Vector3(0, 0, 6)});
  final Vector3 position;
}

class PerspectiveCamera extends Camera3D {
  const PerspectiveCamera({
    super.position,
    // Product-photography default; wide lenses fisheye close-up models.
    this.fieldOfView = 37.8,
    this.near = 0.1,
    this.far = 100,
  });
  final double fieldOfView;
  final double near;
  final double far;
}

/// The v1 camera contract: perspective projection with orbit interaction.
class OrbitCamera extends PerspectiveCamera {
  const OrbitCamera({
    super.position,
    super.fieldOfView,
    super.near,
    super.far,
    this.target = Vector3.zero,
  });

  final Vector3 target;
}

abstract class Light3D {
  const Light3D({this.color = Colors.white, this.intensity = 1});
  final Color color;
  final double intensity;
}

class AmbientLight extends Light3D {
  const AmbientLight({super.color, super.intensity = .25});
}

class DirectionalLight extends Light3D {
  const DirectionalLight({
    this.direction = const Vector3(-1, -1, -1),
    super.color,
    super.intensity = .85,
  });
  final Vector3 direction;
}

/// Image-based lighting from an equirectangular `.hdr` (or PNG/JPEG) asset.
/// When present in a scene's lights, the GPU renderer replaces its ambient
/// term with the environment's irradiance and reflections.
class EnvironmentLight extends Light3D {
  const EnvironmentLight({required this.asset, super.intensity = 1});
  final String asset;
}

/// The GPU renderers carry punctual lights (point + spot) in a fixed-size
/// uniform array. Scenes declaring more than this many combined get the
/// first [kMaxPunctualLights] in list order; the rest are dropped (with a
/// debug-mode warning). Keep this in sync with `MAX_PUNCTUAL_LIGHTS` in
/// `shaders/unlit.frag`.
const kMaxPunctualLights = 4;

/// A light that radiates in all directions from a world-space point,
/// falling off with distance. Field names follow glTF's `KHR_lights_punctual`
/// extension, since a [SpotLight] is modeled as the same light plus a cone.
class PointLight extends Light3D {
  const PointLight({
    required this.position,
    super.color,
    super.intensity = 1,
    this.range = 0,
  });
  final Vector3 position;

  /// Distance at which the light's contribution reaches zero. `0` means no
  /// cutoff — pure inverse-square falloff.
  final double range;

  @override
  bool operator ==(Object other) =>
      other is PointLight &&
      other.position == position &&
      other.color == color &&
      other.intensity == intensity &&
      other.range == range;

  @override
  int get hashCode => Object.hash(position, color, intensity, range);
}

/// A [PointLight] additionally narrowed to a cone, like a flashlight or a
/// car headlight. [innerConeAngle] and [outerConeAngle] are radians measured
/// from [direction]; intensity is full strength inside the inner cone and
/// smoothly fades to zero at the outer cone.
class SpotLight extends Light3D {
  const SpotLight({
    required this.position,
    required this.direction,
    super.color,
    super.intensity = 1,
    this.range = 0,
    this.innerConeAngle = 0,
    this.outerConeAngle = math.pi / 4,
  });
  final Vector3 position;
  final Vector3 direction;
  final double range;
  final double innerConeAngle;
  final double outerConeAngle;

  @override
  bool operator ==(Object other) =>
      other is SpotLight &&
      other.position == position &&
      other.direction == direction &&
      other.color == color &&
      other.intensity == intensity &&
      other.range == range &&
      other.innerConeAngle == innerConeAngle &&
      other.outerConeAngle == outerConeAngle;

  @override
  int get hashCode => Object.hash(
        position,
        direction,
        color,
        intensity,
        range,
        innerConeAngle,
        outerConeAngle,
      );
}

class Material3D {
  const Material3D({
    this.color = const Color(0xff7c5cff),
    this.metallic = .15,
    this.roughness = .35,
    this.opacity = 1,
  });
  final Color color;
  final double metallic;
  final double roughness;
  final double opacity;

  /// This material as a glTF-style linear RGBA base-color factor.
  /// [color] is sRGB, as all Flutter colors are, so the channels are
  /// linearized before they can scale linear-space lighting.
  List<double> get linearBaseColorFactor => [
    math.pow(color.r, 2.2).toDouble(),
    math.pow(color.g, 2.2).toDouble(),
    math.pow(color.b, 2.2).toDouble(),
    color.a * opacity,
  ];

  @override
  bool operator ==(Object other) =>
      other is Material3D &&
      other.color == color &&
      other.metallic == metallic &&
      other.roughness == roughness &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(color, metallic, roughness, opacity);
}

class Mesh3D {
  const Mesh3D({required this.vertices, required this.faces});
  final List<Vector3> vertices;
  final List<List<int>> faces;

  factory Mesh3D.cube({double size = 2}) {
    final h = size / 2;
    return Mesh3D(
      vertices: [
        Vector3(-h, -h, -h),
        Vector3(h, -h, -h),
        Vector3(h, h, -h),
        Vector3(-h, h, -h),
        Vector3(-h, -h, h),
        Vector3(h, -h, h),
        Vector3(h, h, h),
        Vector3(-h, h, h),
      ],
      faces: const [
        [0, 1, 2, 3],
        [5, 4, 7, 6],
        [4, 0, 3, 7],
        [1, 5, 6, 2],
        [3, 2, 6, 7],
        [4, 5, 1, 0],
      ],
    );
  }

  /// A UV sphere suitable for lightweight procedural previews and game pieces.
  factory Mesh3D.sphere({
    double radius = 1,
    int segments = 16,
    int rings = 10,
  }) {
    assert(segments >= 3);
    assert(rings >= 2);
    final vertices = <Vector3>[];
    final faces = <List<int>>[];
    for (var ring = 0; ring <= rings; ring++) {
      final latitude = math.pi * ring / rings;
      final y = math.cos(latitude) * radius;
      final ringRadius = math.sin(latitude) * radius;
      for (var segment = 0; segment < segments; segment++) {
        final longitude = math.pi * 2 * segment / segments;
        vertices.add(
          Vector3(
            math.cos(longitude) * ringRadius,
            y,
            math.sin(longitude) * ringRadius,
          ),
        );
      }
    }
    for (var ring = 0; ring < rings; ring++) {
      for (var segment = 0; segment < segments; segment++) {
        final next = (segment + 1) % segments;
        final a = ring * segments + segment;
        final b = ring * segments + next;
        final c = (ring + 1) * segments + next;
        final d = (ring + 1) * segments + segment;
        faces.add([a, b, c, d]);
      }
    }
    return Mesh3D(vertices: vertices, faces: faces);
  }
}

class Node3D {
  const Node3D({
    this.name,
    this.transform = const Transform3D(),
    this.mesh,
    this.model,
    this.material,
    this.children = const [],
  });
  final String? name;
  final Transform3D transform;

  /// Prototype geometry rendered by the CPU preview painter.
  final Mesh3D? mesh;

  /// A real asset rendered by the GPU renderer. A scene containing any
  /// model node is routed to the GPU path by [Scene3D].
  final Model? model;

  /// Surface override. Null keeps a [model]'s own authored material, or the
  /// default preview material for prototype meshes.
  final Material3D? material;
  final List<Node3D> children;
}

/// A declarative scene supplied directly to [Scene3D].
abstract class Scene {
  const Scene();

  Camera3D get camera => const OrbitCamera();
  List<Light3D> get lights => const [AmbientLight(), DirectionalLight()];
  List<Node3D> get children;
}
