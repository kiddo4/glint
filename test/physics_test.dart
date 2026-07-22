import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:glint_engine/glint_engine.dart';

void main() {
  test('physics worlds accumulate deterministic fixed steps', () {
    final world = _RecordingWorld(fixedTimeStep: .1);
    var callbacks = 0;
    world.addFixedStepCallback((dt) {
      expect(dt, .1);
      callbacks++;
    });

    expect(world.step(.04), 0);
    expect(world.step(.06), 1);
    expect(world.steps, [.1]);
    expect(callbacks, 1);
    expect(world.interpolationAlpha, closeTo(0, 1e-9));
  });

  test('quaternion transforms rotate without Euler conversion', () {
    final orientation = GlintQuaternion.axisAngle(
      const Vector3(0, 1, 0),
      3.141592653589793 / 2,
    );
    final transformed = Transform3D(
      orientation: orientation,
    ).apply(const Vector3(0, 0, -1));
    expect(transformed.x, closeTo(-1, 1e-9));
    expect(transformed.y, closeTo(0, 1e-9));
    expect(transformed.z, closeTo(0, 1e-9));
  });
}

class _RecordingWorld extends GlintPhysicsWorld {
  _RecordingWorld({required super.fixedTimeStep});

  final List<double> steps = [];

  @override
  String get backendName => 'test';
  @override
  List<GlintRigidBody> get bodies => const [];
  @override
  Stream<GlintCollisionEvent> get collisions => const Stream.empty();
  @override
  GlintRigidBody createBody(GlintRigidBodyConfig config) =>
      throw UnimplementedError();
  @override
  GlintJoint createJoint(GlintJointConfig config) => throw UnimplementedError();
  @override
  void updateBackendGravity(Vector3 gravity) {}
  @override
  void stepBackend(double fixedTimeStep, int solverSubSteps) =>
      steps.add(fixedTimeStep);
  @override
  void updateInterpolation(double alpha) {}
  @override
  GlintPhysicsRayHit? raycast(
    GlintRay ray, {
    double maxDistance = double.infinity,
    GlintQueryFilter filter = const GlintQueryFilter(),
  }) => null;
  @override
  List<GlintPhysicsRayHit> raycastAll(
    GlintRay ray, {
    double maxDistance = double.infinity,
    GlintQueryFilter filter = const GlintQueryFilter(),
  }) => const [];
  @override
  List<GlintOverlapHit> overlapSphere(
    Vector3 center,
    double radius, {
    GlintQueryFilter filter = const GlintQueryFilter(),
  }) => const [];
  @override
  List<GlintOverlapHit> overlapBox(
    Vector3 center,
    Vector3 halfExtents, {
    GlintQuaternion orientation = GlintQuaternion.identity,
    GlintQueryFilter filter = const GlintQueryFilter(),
  }) => const [];
  @override
  GlintPhysicsRayHit? shapeCast(
    GlintCollider collider,
    Vector3 origin,
    Vector3 direction, {
    GlintQuaternion orientation = GlintQuaternion.identity,
    double maxDistance = double.infinity,
    GlintQueryFilter filter = const GlintQueryFilter(),
  }) => null;
  @override
  void dispose() {}
}
