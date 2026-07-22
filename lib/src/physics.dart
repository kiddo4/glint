import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'math.dart';

enum GlintBodyType { static, dynamic, kinematic }

class GlintPhysicsMaterial {
  const GlintPhysicsMaterial({
    this.friction = .6,
    this.restitution = 0,
    this.density = 1,
  });

  static const standard = GlintPhysicsMaterial();

  final double friction;
  final double restitution;
  final double density;
}

sealed class GlintCollider {
  const GlintCollider();
}

class GlintSphereCollider extends GlintCollider {
  const GlintSphereCollider(this.radius);
  final double radius;
}

class GlintBoxCollider extends GlintCollider {
  const GlintBoxCollider(this.halfExtents);
  final Vector3 halfExtents;
}

class GlintCapsuleCollider extends GlintCollider {
  const GlintCapsuleCollider({required this.radius, required this.halfHeight});
  final double radius;
  final double halfHeight;
}

class GlintCylinderCollider extends GlintCollider {
  const GlintCylinderCollider({required this.radius, required this.halfHeight});
  final double radius;
  final double halfHeight;
}

class GlintConvexHullCollider extends GlintCollider {
  const GlintConvexHullCollider(this.points);
  final Float32List points;
}

class GlintTriangleMeshCollider extends GlintCollider {
  const GlintTriangleMeshCollider({
    required this.vertices,
    required this.indices,
  });
  final Float32List vertices;
  final Uint32List indices;
}

class GlintHeightFieldCollider extends GlintCollider {
  const GlintHeightFieldCollider({
    required this.width,
    required this.depth,
    required this.heights,
    this.scale = Vector3.one,
  });
  final int width;
  final int depth;
  final Float32List heights;
  final Vector3 scale;
}

class GlintCompoundChild {
  const GlintCompoundChild({
    required this.collider,
    this.position = Vector3.zero,
    this.orientation = GlintQuaternion.identity,
  });
  final GlintCollider collider;
  final Vector3 position;
  final GlintQuaternion orientation;
}

class GlintCompoundCollider extends GlintCollider {
  const GlintCompoundCollider(this.children);
  final List<GlintCompoundChild> children;
}

class GlintRigidBodyConfig {
  const GlintRigidBodyConfig({
    this.type = GlintBodyType.dynamic,
    this.position = Vector3.zero,
    this.orientation = GlintQuaternion.identity,
    this.linearVelocity = Vector3.zero,
    this.angularVelocity = Vector3.zero,
    this.linearDamping = 0,
    this.angularDamping = 0,
    this.gravityScale = 1,
    this.ccdEnabled = false,
    this.sleepEnabled = true,
    this.userData,
  });

  final GlintBodyType type;
  final Vector3 position;
  final GlintQuaternion orientation;
  final Vector3 linearVelocity;
  final Vector3 angularVelocity;
  final double linearDamping;
  final double angularDamping;
  final double gravityScale;
  final bool ccdEnabled;
  final bool sleepEnabled;
  final Object? userData;
}

abstract interface class GlintColliderHandle {
  GlintRigidBody get body;
  GlintCollider get collider;

  /// The authored material, available to gameplay queries as well as the
  /// native contact solver (for example, terrain-dependent tire grip).
  GlintPhysicsMaterial get material;
  bool get isTrigger;
  int get collisionLayer;
  int get collisionMask;
  Object? get userData;
  void destroy();
}

abstract class GlintRigidBody {
  GlintBodyType get type;
  set type(GlintBodyType value);
  Object? get userData;
  Vector3 get position;
  GlintQuaternion get orientation;
  Vector3 get interpolatedPosition;
  GlintQuaternion get interpolatedOrientation;
  Vector3 get linearVelocity;
  set linearVelocity(Vector3 value);
  Vector3 get angularVelocity;
  set angularVelocity(Vector3 value);
  double get mass;
  bool get isSleeping;

  void setTransform(Vector3 position, GlintQuaternion orientation);
  void setDamping({double? linear, double? angular});
  void setGravityScale(double scale);
  void setCcdEnabled(bool enabled);
  void setMotionLocks({
    bool linearX = false,
    bool linearY = false,
    bool linearZ = false,
    bool angularX = false,
    bool angularY = false,
    bool angularZ = false,
  });
  void wakeUp();
  void putToSleep();
  void applyForce(Vector3 force, {Vector3? atWorldPoint});
  void applyImpulse(Vector3 impulse, {Vector3? atWorldPoint});
  void applyTorque(Vector3 torque);
  void applyAngularImpulse(Vector3 impulse);
  Vector3 velocityAtWorldPoint(Vector3 point) =>
      linearVelocity + angularVelocity.cross(point - position);

  GlintColliderHandle addCollider(
    GlintCollider collider, {
    GlintPhysicsMaterial material = GlintPhysicsMaterial.standard,
    Vector3 localPosition = Vector3.zero,
    GlintQuaternion localOrientation = GlintQuaternion.identity,
    int collisionLayer = 1,
    int collisionMask = 0x7fffffff,
    bool isTrigger = false,
    Object? userData,
  });

  Transform3D toTransform({Vector3 scale = Vector3.one}) => Transform3D(
    position: interpolatedPosition,
    orientation: interpolatedOrientation,
    scale: scale,
  );

  void destroy();
}

class GlintQueryFilter {
  const GlintQueryFilter({
    this.layerMask = 0x7fffffff,
    this.includeStatic = true,
    this.includeKinematic = true,
    this.includeDynamic = true,
    this.includeTriggers = false,
    this.excludedBodies = const {},
  });

  final int layerMask;
  final bool includeStatic;
  final bool includeKinematic;
  final bool includeDynamic;
  final bool includeTriggers;

  /// Bodies omitted without excluding every dynamic object in the world.
  final Set<GlintRigidBody> excludedBodies;
}

class GlintPhysicsRayHit {
  const GlintPhysicsRayHit({
    required this.body,
    required this.collider,
    required this.position,
    required this.normal,
    required this.distance,
  });
  final GlintRigidBody body;
  final GlintColliderHandle collider;
  final Vector3 position;
  final Vector3 normal;
  final double distance;
}

class GlintOverlapHit {
  const GlintOverlapHit(this.body, this.collider);
  final GlintRigidBody body;
  final GlintColliderHandle collider;
}

sealed class GlintCollisionEvent {
  const GlintCollisionEvent(this.colliderA, this.colliderB);
  final GlintColliderHandle colliderA;
  final GlintColliderHandle colliderB;
}

class GlintContactPoint {
  const GlintContactPoint({
    required this.position,
    required this.normal,
    required this.impulse,
    required this.separation,
  });
  final Vector3 position;
  final Vector3 normal;
  final double impulse;
  final double separation;
}

class GlintContactBegan extends GlintCollisionEvent {
  const GlintContactBegan(super.colliderA, super.colliderB, this.contacts);
  final List<GlintContactPoint> contacts;
}

class GlintContactEnded extends GlintCollisionEvent {
  const GlintContactEnded(super.colliderA, super.colliderB);
}

class GlintTriggerEntered extends GlintCollisionEvent {
  const GlintTriggerEntered(super.colliderA, super.colliderB);
}

class GlintTriggerExited extends GlintCollisionEvent {
  const GlintTriggerExited(super.colliderA, super.colliderB);
}

class GlintJointFrame {
  const GlintJointFrame({
    this.position = Vector3.zero,
    this.orientation = GlintQuaternion.identity,
  });
  final Vector3 position;
  final GlintQuaternion orientation;
}

sealed class GlintJointConfig {
  const GlintJointConfig({
    required this.bodyA,
    required this.bodyB,
    this.frameA = const GlintJointFrame(),
    this.frameB = const GlintJointFrame(),
    this.collideConnected = false,
  });
  final GlintRigidBody bodyA;
  final GlintRigidBody bodyB;
  final GlintJointFrame frameA;
  final GlintJointFrame frameB;
  final bool collideConnected;
}

class GlintFixedJointConfig extends GlintJointConfig {
  const GlintFixedJointConfig({
    required super.bodyA,
    required super.bodyB,
    super.frameA,
    super.frameB,
    super.collideConnected,
    this.linearFrequency = 0,
    this.angularFrequency = 0,
    this.linearDampingRatio = 0,
    this.angularDampingRatio = 0,
  });
  final double linearFrequency;
  final double angularFrequency;
  final double linearDampingRatio;
  final double angularDampingRatio;
}

class GlintRevoluteJointConfig extends GlintJointConfig {
  const GlintRevoluteJointConfig({
    required super.bodyA,
    required super.bodyB,
    required super.frameA,
    required super.frameB,
    super.collideConnected,
    this.lowerLimit,
    this.upperLimit,
    this.motorSpeed,
    this.maxMotorTorque,
  });
  final double? lowerLimit;
  final double? upperLimit;
  final double? motorSpeed;
  final double? maxMotorTorque;
}

class GlintPrismaticJointConfig extends GlintJointConfig {
  const GlintPrismaticJointConfig({
    required super.bodyA,
    required super.bodyB,
    required super.frameA,
    required super.frameB,
    super.collideConnected,
    this.lowerLimit,
    this.upperLimit,
    this.motorSpeed,
    this.maxMotorForce,
  });
  final double? lowerLimit;
  final double? upperLimit;
  final double? motorSpeed;
  final double? maxMotorForce;
}

class GlintSphericalJointConfig extends GlintJointConfig {
  const GlintSphericalJointConfig({
    required super.bodyA,
    required super.bodyB,
    super.frameA,
    super.frameB,
    super.collideConnected,
    this.coneAngle,
    this.lowerTwist,
    this.upperTwist,
    this.maxMotorTorque,
  });
  final double? coneAngle;
  final double? lowerTwist;
  final double? upperTwist;
  final double? maxMotorTorque;
}

class GlintDistanceJointConfig extends GlintJointConfig {
  const GlintDistanceJointConfig({
    required super.bodyA,
    required super.bodyB,
    required this.length,
    super.frameA,
    super.frameB,
    super.collideConnected,
    this.minimumLength,
    this.maximumLength,
    this.springFrequency,
    this.springDampingRatio = 0,
    this.motorSpeed,
    this.maxMotorForce,
  });
  final double length;
  final double? minimumLength;
  final double? maximumLength;
  final double? springFrequency;
  final double springDampingRatio;
  final double? motorSpeed;
  final double? maxMotorForce;
}

abstract interface class GlintJoint {
  void destroy();
}

typedef GlintFixedStepCallback = void Function(double fixedTimeStep);

/// A gameplay system whose state participates in physics rollback.
///
/// Vehicles, character motors, destructible controllers, and user-defined
/// simulation systems can register with [GlintPhysicsWorld] so a world
/// snapshot restores their fixed-step state alongside rigid bodies.
abstract interface class GlintPhysicsSnapshotParticipant {
  Object capturePhysicsState();
  void restorePhysicsState(Object state);
}

/// One rigid body's backend-neutral rollback state.
class GlintRigidBodySnapshot {
  const GlintRigidBodySnapshot({
    required this.body,
    required this.type,
    required this.position,
    required this.orientation,
    required this.linearVelocity,
    required this.angularVelocity,
    required this.isSleeping,
  });

  final GlintRigidBody body;
  final GlintBodyType type;
  final Vector3 position;
  final GlintQuaternion orientation;
  final Vector3 linearVelocity;
  final Vector3 angularVelocity;
  final bool isSleeping;
}

class GlintPhysicsParticipantSnapshot {
  const GlintPhysicsParticipantSnapshot({
    required this.participant,
    required this.state,
  });

  final GlintPhysicsSnapshotParticipant participant;
  final Object state;
}

/// An in-memory rollback point for one [GlintPhysicsWorld].
///
/// Snapshots intentionally retain body and participant identities. They are
/// safe for rewind, retry, replay verification, and rollback netcode within
/// the same live world. Portable replay files record inputs separately and
/// recreate the world through application-owned level loading.
class GlintPhysicsSnapshot {
  GlintPhysicsSnapshot._({
    required this._worldIdentity,
    required this.backendName,
    required this.simulationStep,
    required this.accumulator,
    required this.interpolationAlpha,
    required this.gravity,
    required Iterable<GlintRigidBodySnapshot> bodies,
    required Iterable<GlintPhysicsParticipantSnapshot> participants,
  }) : bodies = List.unmodifiable(bodies),
       participants = List.unmodifiable(participants);

  final Object _worldIdentity;
  final String backendName;
  final int simulationStep;
  final double accumulator;
  final double interpolationAlpha;
  final Vector3 gravity;
  final List<GlintRigidBodySnapshot> bodies;
  final List<GlintPhysicsParticipantSnapshot> participants;

  double simulationTime(double fixedTimeStep) => simulationStep * fixedTimeStep;
}

/// Backend-neutral, fixed-timestep 3D physics contract.
abstract class GlintPhysicsWorld {
  GlintPhysicsWorld({
    Vector3 gravity = const Vector3(0, -9.81, 0),
    this.fixedTimeStep = 1 / 60,
    this.maxSubSteps = 5,
    this.solverSubSteps = 4,
  }) {
    if (!fixedTimeStep.isFinite || fixedTimeStep <= 0) {
      throw ArgumentError.value(
        fixedTimeStep,
        'fixedTimeStep',
        'must be finite and > 0',
      );
    }
    if (maxSubSteps <= 0 || solverSubSteps <= 0) {
      throw ArgumentError(
        'maxSubSteps and solverSubSteps must both be greater than zero.',
      );
    }
    if (!_finiteVector(gravity)) {
      throw ArgumentError.value(gravity, 'gravity', 'must be finite');
    }
    _gravity = gravity;
  }

  final double fixedTimeStep;
  final int maxSubSteps;
  final int solverSubSteps;
  late Vector3 _gravity;
  double _accumulator = 0;
  double _interpolationAlpha = 0;
  int _simulationStep = 0;
  final Object _snapshotIdentity = Object();
  final List<GlintFixedStepCallback> _fixedStepCallbacks = [];
  final List<GlintPhysicsSnapshotParticipant> _snapshotParticipants = [];

  String get backendName;
  List<GlintRigidBody> get bodies;
  Stream<GlintCollisionEvent> get collisions;
  double get interpolationAlpha => _interpolationAlpha;
  int get simulationStep => _simulationStep;
  double get simulationTime => _simulationStep * fixedTimeStep;

  Vector3 get gravity => _gravity;
  set gravity(Vector3 value) {
    if (!_finiteVector(value)) {
      throw ArgumentError.value(value, 'gravity', 'must be finite');
    }
    _gravity = value;
    updateBackendGravity(value);
  }

  GlintRigidBody createBody(GlintRigidBodyConfig config);
  GlintJoint createJoint(GlintJointConfig config);

  void addFixedStepCallback(GlintFixedStepCallback callback) {
    if (!_fixedStepCallbacks.contains(callback)) {
      _fixedStepCallbacks.add(callback);
    }
  }

  void removeFixedStepCallback(GlintFixedStepCallback callback) =>
      _fixedStepCallbacks.remove(callback);

  void addSnapshotParticipant(GlintPhysicsSnapshotParticipant participant) {
    if (!_snapshotParticipants.contains(participant)) {
      _snapshotParticipants.add(participant);
    }
  }

  void removeSnapshotParticipant(GlintPhysicsSnapshotParticipant participant) =>
      _snapshotParticipants.remove(participant);

  /// Captures the fixed-step clock, bodies, and registered gameplay systems.
  /// Capture between calls to [step] or from a fixed-step callback, not while a
  /// backend step is executing.
  GlintPhysicsSnapshot captureSnapshot() => GlintPhysicsSnapshot._(
    worldIdentity: _snapshotIdentity,
    backendName: backendName,
    simulationStep: _simulationStep,
    accumulator: _accumulator,
    interpolationAlpha: _interpolationAlpha,
    gravity: gravity,
    bodies: [
      for (final body in bodies)
        GlintRigidBodySnapshot(
          body: body,
          type: body.type,
          position: body.position,
          orientation: body.orientation,
          linearVelocity: body.linearVelocity,
          angularVelocity: body.angularVelocity,
          isSleeping: body.isSleeping,
        ),
    ],
    participants: [
      for (final participant in _snapshotParticipants)
        GlintPhysicsParticipantSnapshot(
          participant: participant,
          state: participant.capturePhysicsState(),
        ),
    ],
  );

  /// Restores a snapshot captured from this world.
  ///
  /// With [strict] enabled, body and participant membership must still match;
  /// this catches accidental spawn/despawn differences during deterministic
  /// replay instead of silently restoring only part of the simulation.
  void restoreSnapshot(GlintPhysicsSnapshot snapshot, {bool strict = true}) {
    if (!identical(snapshot._worldIdentity, _snapshotIdentity)) {
      throw ArgumentError.value(
        snapshot,
        'snapshot',
        'was captured from a different physics world',
      );
    }
    final currentBodies = bodies;
    final savedBodies = snapshot.bodies.map((state) => state.body).toSet();
    final currentParticipants = _snapshotParticipants.toSet();
    final savedParticipants = snapshot.participants
        .map((state) => state.participant)
        .toSet();
    if (strict &&
        (currentBodies.length != snapshot.bodies.length ||
            currentBodies.any((body) => !savedBodies.contains(body)) ||
            currentParticipants.length != savedParticipants.length ||
            currentParticipants.any(
              (participant) => !savedParticipants.contains(participant),
            ))) {
      throw StateError(
        'Physics world membership changed after the snapshot was captured.',
      );
    }
    if (snapshot.bodies.any((state) => !currentBodies.contains(state.body))) {
      throw StateError('A body captured by the snapshot no longer exists.');
    }
    if (snapshot.participants.any(
      (state) => !_snapshotParticipants.contains(state.participant),
    )) {
      throw StateError(
        'A participant captured by the snapshot is no longer registered.',
      );
    }

    gravity = snapshot.gravity;
    for (final state in snapshot.bodies) {
      state.body
        ..type = state.type
        ..setTransform(state.position, state.orientation)
        ..linearVelocity = state.linearVelocity
        ..angularVelocity = state.angularVelocity;
      if (state.isSleeping) {
        state.body.putToSleep();
      } else {
        state.body.wakeUp();
      }
    }
    for (final state in snapshot.participants) {
      state.participant.restorePhysicsState(state.state);
    }
    _simulationStep = snapshot.simulationStep;
    _accumulator = snapshot.accumulator;
    _interpolationAlpha = snapshot.interpolationAlpha;
    snapshotRestored();
    updateInterpolation(_interpolationAlpha);
  }

  /// Advances exactly one simulation tick, bypassing frame-time accumulation.
  /// This is the preferred driver for deterministic replay and offline tests.
  void stepFixed() {
    _runFixedStep();
    _interpolationAlpha = (_accumulator / fixedTimeStep).clamp(0.0, 1.0);
    updateInterpolation(_interpolationAlpha);
  }

  int step(double elapsedSeconds) {
    if (!elapsedSeconds.isFinite || elapsedSeconds < 0) {
      throw ArgumentError.value(elapsedSeconds, 'elapsedSeconds');
    }
    _accumulator += math.min(elapsedSeconds, fixedTimeStep * maxSubSteps);
    var count = 0;
    while (_accumulator + 1e-12 >= fixedTimeStep && count < maxSubSteps) {
      _runFixedStep();
      _accumulator -= fixedTimeStep;
      count++;
    }
    if (count == maxSubSteps && _accumulator >= fixedTimeStep) {
      _accumulator %= fixedTimeStep;
    }
    _interpolationAlpha = (_accumulator / fixedTimeStep).clamp(0.0, 1.0);
    updateInterpolation(_interpolationAlpha);
    return count;
  }

  void _runFixedStep() {
    for (final callback in List.of(_fixedStepCallbacks)) {
      callback(fixedTimeStep);
    }
    stepBackend(fixedTimeStep, solverSubSteps);
    _simulationStep++;
  }

  GlintPhysicsRayHit? raycast(
    GlintRay ray, {
    double maxDistance = double.infinity,
    GlintQueryFilter filter = const GlintQueryFilter(),
  });
  List<GlintPhysicsRayHit> raycastAll(
    GlintRay ray, {
    double maxDistance = double.infinity,
    GlintQueryFilter filter = const GlintQueryFilter(),
  });
  List<GlintOverlapHit> overlapSphere(
    Vector3 center,
    double radius, {
    GlintQueryFilter filter = const GlintQueryFilter(),
  });
  List<GlintOverlapHit> overlapBox(
    Vector3 center,
    Vector3 halfExtents, {
    GlintQuaternion orientation = GlintQuaternion.identity,
    GlintQueryFilter filter = const GlintQueryFilter(),
  });
  GlintPhysicsRayHit? shapeCast(
    GlintCollider collider,
    Vector3 origin,
    Vector3 direction, {
    GlintQuaternion orientation = GlintQuaternion.identity,
    double maxDistance = double.infinity,
    GlintQueryFilter filter = const GlintQueryFilter(),
  });

  void updateBackendGravity(Vector3 gravity);
  void stepBackend(double fixedTimeStep, int solverSubSteps);
  void updateInterpolation(double alpha);

  /// Backend hook for invalidating interpolation/contact caches after rewind.
  void snapshotRestored() {}
  void dispose();
}

bool _finiteVector(Vector3 value) =>
    value.x.isFinite && value.y.isFinite && value.z.isFinite;
