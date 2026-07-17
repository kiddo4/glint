import 'package:flutter/material.dart';

import 'math.dart';

abstract class Camera3D {
  const Camera3D({this.position = const Vector3(0, 0, 6)});
  final Vector3 position;
}

class PerspectiveCamera extends Camera3D {
  const PerspectiveCamera({
    super.position,
    this.fieldOfView = 55,
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
}

class Node3D {
  const Node3D({
    this.name,
    this.transform = const Transform3D(),
    this.mesh,
    this.material = const Material3D(),
    this.children = const [],
  });
  final String? name;
  final Transform3D transform;
  final Mesh3D? mesh;
  final Material3D material;
  final List<Node3D> children;
}

/// A declarative scene supplied directly to [Scene3D].
abstract class Scene {
  const Scene();

  Camera3D get camera => const OrbitCamera();
  List<Light3D> get lights => const [AmbientLight(), DirectionalLight()];
  List<Node3D> get children;
}
