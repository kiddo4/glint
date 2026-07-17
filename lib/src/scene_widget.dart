import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'math.dart';
import 'scene.dart';

/// A Flutter-native viewport that composes a Glint scene in the widget tree.
class Scene3D extends StatefulWidget {
  const Scene3D({
    super.key,
    this.scene,
    this.camera,
    this.lights,
    this.children,
    this.backgroundColor = const Color(0xff090b13),
    this.autoRotate = false,
    this.rotationSpeed = .55,
    this.enableGestures = true,
  }) : assert(
         scene != null || children != null,
         'Provide a scene or children.',
       );

  final Scene? scene;
  final Camera3D? camera;
  final List<Light3D>? lights;
  final List<Node3D>? children;
  final Color backgroundColor;
  final bool autoRotate;
  final double rotationSpeed;
  final bool enableGestures;

  @override
  State<Scene3D> createState() => _Scene3DState();
}

class _Scene3DState extends State<Scene3D> with SingleTickerProviderStateMixin {
  late final AnimationController _clock;
  double _yaw = 0;
  double _pitch = 0;
  double _zoom = 1;
  double _gestureZoom = 1;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController.unbounded(vsync: this)..addListener(_tick);
    if (widget.autoRotate) {
      _clock.repeat(min: 0, max: 100000, period: const Duration(days: 1));
    }
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(Scene3D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoRotate != oldWidget.autoRotate) {
      widget.autoRotate
          ? _clock.repeat(min: 0, max: 100000, period: const Duration(days: 1))
          : _clock.stop();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = widget.camera ?? widget.scene?.camera ?? const OrbitCamera();
    final lights =
        widget.lights ??
        widget.scene?.lights ??
        const [AmbientLight(), DirectionalLight()];
    final children = widget.children ?? widget.scene?.children ?? const [];
    final time = _clock.lastElapsedDuration?.inMicroseconds ?? 0;
    final autoYaw =
        time / Duration.microsecondsPerSecond * widget.rotationSpeed;
    Widget viewport = CustomPaint(
      painter: _ScenePainter(
        camera: camera,
        lights: lights,
        nodes: children,
        background: widget.backgroundColor,
        viewRotation: Vector3(_pitch, _yaw + autoYaw, 0),
        zoom: _zoom,
      ),
      child: const SizedBox.expand(),
    );
    if (widget.enableGestures) {
      viewport = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (_) => _gestureZoom = _zoom,
        onScaleUpdate: (details) => setState(() {
          _zoom = (_gestureZoom * details.scale).clamp(.45, 3);
          _yaw += details.focalPointDelta.dx * .008;
          _pitch = (_pitch + details.focalPointDelta.dy * .008).clamp(
            -1.2,
            1.2,
          );
        }),
        child: viewport,
      );
    }
    return ClipRect(child: viewport);
  }
}

class _Face {
  _Face(this.points, this.depth, this.color);
  final List<Offset> points;
  final double depth;
  final Color color;
}

class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required this.camera,
    required this.lights,
    required this.nodes,
    required this.background,
    required this.viewRotation,
    required this.zoom,
  });
  final Camera3D camera;
  final List<Light3D> lights;
  final List<Node3D> nodes;
  final Color background;
  final Vector3 viewRotation;
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final faces = <_Face>[];
    for (final node in nodes) {
      _collect(node, const Transform3D(), faces, size);
    }
    faces.sort((a, b) => a.depth.compareTo(b.depth));
    for (final face in faces) {
      final path = Path()..moveTo(face.points.first.dx, face.points.first.dy);
      for (final point in face.points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = face.color
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withValues(alpha: .1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  void _collect(
    Node3D node,
    Transform3D parent,
    List<_Face> output,
    Size size,
  ) {
    Vector3 world(Vector3 point) => parent.apply(node.transform.apply(point));
    final mesh = node.mesh;
    if (mesh != null) {
      final vertices = mesh.vertices
          .map(world)
          .map((v) => _rotate(v, viewRotation))
          .toList();
      for (final indices in mesh.faces) {
        final face = indices.map((i) => vertices[i]).toList();
        final normal = (face[1] - face[0]).cross(face[2] - face[0]).normalized;
        if (normal.z >= 0) continue;
        final projected = face.map((v) => _project(v, size)).toList();
        if (projected.any((p) => p == null)) continue;
        var light = lights.whereType<AmbientLight>().fold<double>(
          0,
          (sum, item) => sum + item.intensity,
        );
        for (final source in lights.whereType<DirectionalLight>()) {
          light +=
              math.max(0, normal.dot(source.direction.normalized * -1)) *
              source.intensity;
        }
        light = light.clamp(.08, 1.15);
        final base = node.material.color;
        output.add(
          _Face(
            projected.cast<Offset>(),
            face.fold(0.0, (sum, v) => sum + v.z) / face.length,
            Color.fromRGBO(
              (base.r * 255 * light).clamp(0, 255).round(),
              (base.g * 255 * light).clamp(0, 255).round(),
              (base.b * 255 * light).clamp(0, 255).round(),
              node.material.opacity,
            ),
          ),
        );
      }
    }
    final combined = Transform3D(
      position: parent.apply(node.transform.position),
      rotation: parent.rotation + node.transform.rotation,
      scale: Vector3(
        parent.scale.x * node.transform.scale.x,
        parent.scale.y * node.transform.scale.y,
        parent.scale.z * node.transform.scale.z,
      ),
    );
    for (final child in node.children) {
      _collect(child, combined, output, size);
    }
  }

  Vector3 _rotate(Vector3 value, Vector3 rotation) =>
      Transform3D(rotation: rotation).apply(value);

  Offset? _project(Vector3 point, Size size) {
    final relative = point - camera.position;
    final scale = switch (camera) {
      PerspectiveCamera c =>
        size.shortestSide *
            .5 *
            zoom /
            (math.tan(c.fieldOfView * math.pi / 360) * -relative.z),
      _ => size.shortestSide * .16 * zoom,
    };
    if (camera is PerspectiveCamera &&
        -relative.z <= (camera as PerspectiveCamera).near) {
      return null;
    }
    return Offset(
      size.width / 2 + relative.x * scale,
      size.height / 2 - relative.y * scale,
    );
  }

  @override
  bool shouldRepaint(covariant _ScenePainter oldDelegate) => true;
}
