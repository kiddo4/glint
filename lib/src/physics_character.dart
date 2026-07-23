import 'dart:math' as math;

import 'math.dart';
import 'physics.dart';

/// Tuning for Glint's backend-neutral kinematic character motor.
class GlintCharacterControllerConfig {
  const GlintCharacterControllerConfig({
    this.height = 1.8,
    this.radius = .35,
    this.stepHeight = .3,
    this.slopeLimitRadians = .7853981633974483,
    this.skinWidth = .02,
    this.groundSnapDistance = .15,
    this.groundAcceleration = 35,
    this.airAcceleration = 10,
    this.gravityScale = 1,
    this.maximumFallSpeed = 55,
    this.maxSweepIterations = 5,
    this.collisionLayer = 1,
    this.collisionMask = 0x7fffffff,
    this.material = const GlintPhysicsMaterial(friction: 0, density: 1),
    this.up = const Vector3(0, 1, 0),
    this.automaticStepping = true,
  });

  /// Total capsule height, including both rounded ends.
  final double height;
  final double radius;
  final double stepHeight;
  final double slopeLimitRadians;
  final double skinWidth;
  final double groundSnapDistance;
  final double groundAcceleration;
  final double airAcceleration;
  final double gravityScale;
  final double maximumFallSpeed;
  final int maxSweepIterations;
  final int collisionLayer;
  final int collisionMask;
  final GlintPhysicsMaterial material;
  final Vector3 up;

  /// Registers the motor with the world's fixed-step callbacks when true.
  final bool automaticStepping;
}

/// Ground information produced by the most recent controller update.
class GlintCharacterGroundState {
  const GlintCharacterGroundState({
    required this.body,
    required this.collider,
    required this.position,
    required this.normal,
    required this.velocity,
  });

  final GlintRigidBody body;
  final GlintColliderHandle collider;
  final Vector3 position;
  final Vector3 normal;

  /// Velocity of the support body at [position], useful for moving platforms.
  final Vector3 velocity;
}

/// A capsule-shaped kinematic character motor implemented using public Glint
/// queries, so it works with any physics backend that supports sphere casts.
///
/// It provides acceleration, gravity, slopes, ground snapping, step climbing,
/// moving-platform inheritance, sweep-and-slide collision, jumping, rollback,
/// and manual or world-managed fixed stepping. Gameplay owns input and camera
/// policy through [desiredVelocity].
class GlintCharacterController implements GlintPhysicsSnapshotParticipant {
  factory GlintCharacterController.create({
    required GlintPhysicsWorld world,
    required Vector3 position,
    GlintQuaternion orientation = GlintQuaternion.identity,
    GlintCharacterControllerConfig config =
        const GlintCharacterControllerConfig(),
    Object? userData,
  }) {
    _validateConfig(config);
    final body = world.createBody(
      GlintRigidBodyConfig(
        type: GlintBodyType.kinematic,
        position: position,
        orientation: orientation,
        gravityScale: 0,
        sleepEnabled: false,
        userData: userData,
      ),
    );
    final halfHeight = config.height * .5 - config.radius;
    final collider = body.addCollider(
      GlintCapsuleCollider(radius: config.radius, halfHeight: halfHeight),
      material: config.material,
      collisionLayer: config.collisionLayer,
      collisionMask: config.collisionMask,
      userData: userData,
    );
    return GlintCharacterController._(
      world: world,
      body: body,
      collider: collider,
      config: config,
      ownsBody: true,
    );
  }

  /// Wraps an existing kinematic body. Its authored collider should match the
  /// dimensions in [config]; the controller's sweeps use those dimensions.
  factory GlintCharacterController.forBody({
    required GlintPhysicsWorld world,
    required GlintRigidBody body,
    GlintCharacterControllerConfig config =
        const GlintCharacterControllerConfig(),
  }) {
    _validateConfig(config);
    if (body.type != GlintBodyType.kinematic) {
      throw ArgumentError.value(body, 'body', 'must be kinematic');
    }
    if (!world.bodies.contains(body)) {
      throw ArgumentError.value(body, 'body', 'must belong to world');
    }
    return GlintCharacterController._(
      world: world,
      body: body,
      config: config,
      ownsBody: false,
    );
  }

  GlintCharacterController._({
    required this.world,
    required this.body,
    required this.config,
    required this._ownsBody,
    GlintColliderHandle? collider,
  }) : _ownedCollider = collider,
       _up = config.up.normalized,
       _slopeCosine = math.cos(config.slopeLimitRadians) {
    if (config.automaticStepping) world.addFixedStepCallback(fixedUpdate);
    world.addSnapshotParticipant(this);
  }

  final GlintPhysicsWorld world;
  final GlintRigidBody body;
  final GlintCharacterControllerConfig config;
  final bool _ownsBody;
  final GlintColliderHandle? _ownedCollider;
  final Vector3 _up;
  final double _slopeCosine;

  Vector3 _desiredVelocity = Vector3.zero;
  Vector3 _velocity = Vector3.zero;
  GlintCharacterGroundState? _ground;
  bool _disposed = false;

  Vector3 get desiredVelocity => _desiredVelocity;
  set desiredVelocity(Vector3 value) {
    if (!_finite(value)) {
      throw ArgumentError.value(value, 'desiredVelocity', 'must be finite');
    }
    _desiredVelocity = _onPlane(value);
  }

  Vector3 get velocity => _velocity;
  bool get isGrounded => _ground != null;
  GlintCharacterGroundState? get ground => _ground;
  Vector3 get up => _up;

  /// Requests an immediate upward velocity. Returns false while airborne.
  bool jump(double speed) {
    if (!speed.isFinite || speed <= 0) {
      throw ArgumentError.value(speed, 'speed', 'must be finite and > 0');
    }
    if (!isGrounded) return false;
    _velocity = _onPlane(_velocity) + _up * speed;
    _ground = null;
    return true;
  }

  void teleport(
    Vector3 position, {
    GlintQuaternion? orientation,
    bool clearVelocity = true,
  }) {
    if (!_finite(position)) {
      throw ArgumentError.value(position, 'position', 'must be finite');
    }
    body.setTransform(position, orientation ?? body.orientation);
    if (clearVelocity) _velocity = Vector3.zero;
    _ground = null;
  }

  /// Runs one controller tick. Call this manually only when
  /// [GlintCharacterControllerConfig.automaticStepping] is false.
  void fixedUpdate(double deltaSeconds) {
    if (_disposed) return;
    if (!deltaSeconds.isFinite || deltaSeconds <= 0) {
      throw ArgumentError.value(
        deltaSeconds,
        'deltaSeconds',
        'must be finite and > 0',
      );
    }

    var position = body.position;
    final startingProbe = _probeGround(position, config.groundSnapDistance);
    final startingGround = startingProbe?.state;
    _ground = startingGround;

    final targetPlanar = _onPlane(_desiredVelocity);
    final currentPlanar = _onPlane(_velocity);
    final acceleration = isGrounded
        ? config.groundAcceleration
        : config.airAcceleration;
    final planar = _moveToward(
      currentPlanar,
      targetPlanar,
      acceleration * deltaSeconds,
    );
    var verticalSpeed = _velocity.dot(_up);
    if (isGrounded && verticalSpeed < 0) verticalSpeed = 0;
    verticalSpeed +=
        world.gravity.dot(_up) * config.gravityScale * deltaSeconds;
    verticalSpeed = math.max(verticalSpeed, -config.maximumFallSpeed);
    _velocity = planar + _up * verticalSpeed;

    final supportVelocity = startingGround?.velocity ?? Vector3.zero;
    var remaining = (_velocity + supportVelocity) * deltaSeconds;
    var groundedDuringMove = verticalSpeed > 0 ? null : startingGround;

    for (
      var iteration = 0;
      iteration < config.maxSweepIterations &&
          remaining.length > config.skinWidth * .25;
      iteration++
    ) {
      final hit = _castCapsule(position, remaining, remaining.length);
      if (hit == null) {
        position += remaining;
        remaining = Vector3.zero;
        break;
      }

      final travel = math.max(0.0, hit.distance - config.skinWidth);
      if (travel > 0) position += remaining.normalized * travel;
      final untraveled = remaining.length - travel;
      var next = remaining.normalized * math.max(0, untraveled);

      final normal = hit.normal.normalized;
      final walkable = _isWalkable(normal);
      if (walkable) {
        groundedDuringMove = _groundFromHit(hit);
        if (_velocity.dot(_up) < 0) _velocity = _onPlane(_velocity);
      } else if (startingGround != null && config.stepHeight > 0) {
        final stepped = _tryStep(position, next);
        if (stepped != null) {
          position = stepped.$1;
          groundedDuringMove = stepped.$2;
          remaining = Vector3.zero;
          break;
        }
      }

      final intoSurface = next.dot(normal);
      if (intoSurface < 0) next -= normal * intoSurface;
      if (next.length >= remaining.length - 1e-9 && travel == 0) break;
      remaining = next;
    }

    final shouldSnap = _velocity.dot(_up) <= 0;
    final snapped = shouldSnap
        ? _probeGround(position, config.groundSnapDistance)
        : null;
    if (snapped != null) {
      // Ray-derived separation also corrects small initial penetrations, which
      // shape casts intentionally ignore on several native solvers.
      position -= _up * (snapped.separation - config.skinWidth);
      groundedDuringMove = snapped.state;
      if (_velocity.dot(_up) < 0) _velocity = _onPlane(_velocity);
    }

    _ground = groundedDuringMove;
    // Kinematic velocity lets the native solver sweep the body and transfer
    // motion to dynamic objects. Teleporting here would bypass that response.
    body.linearVelocity = (position - body.position) * (1 / deltaSeconds);
  }

  _GlintCharacterGroundProbe? _probeGround(Vector3 position, double distance) {
    final halfHeight = config.height * .5;
    final hit = world.raycast(
      GlintRay(position, -_up),
      maxDistance: halfHeight + distance + config.skinWidth,
      filter: GlintQueryFilter(
        layerMask: config.collisionMask,
        excludedBodies: {body},
      ),
    );
    if (hit == null || !_isWalkable(hit.normal)) return null;
    return _GlintCharacterGroundProbe(
      state: _groundFromHit(hit),
      separation: hit.distance - halfHeight,
    );
  }

  GlintPhysicsRayHit? _castCapsule(
    Vector3 position,
    Vector3 direction,
    double distance,
  ) {
    if (direction.length == 0 || distance <= 0) return null;
    final unit = direction.normalized;
    final halfSegment = config.height * .5 - config.radius;
    final filter = GlintQueryFilter(
      layerMask: config.collisionMask,
      excludedBodies: {body},
    );
    GlintPhysicsRayHit? closest;
    for (final offset
        in halfSegment <= 0 ? const [0.0] : [-halfSegment, 0.0, halfSegment]) {
      final hit = world.shapeCast(
        GlintSphereCollider(config.radius),
        position + _up * offset,
        unit,
        maxDistance: distance,
        filter: filter,
      );
      if (hit != null && (closest == null || hit.distance < closest.distance)) {
        closest = hit;
      }
    }
    return closest;
  }

  (Vector3, GlintCharacterGroundState)? _tryStep(
    Vector3 position,
    Vector3 remaining,
  ) {
    final planar = _onPlane(remaining);
    if (planar.length <= config.skinWidth) return null;
    final raisedDistance = config.stepHeight + config.skinWidth;
    if (_castCapsule(position, _up, raisedDistance) != null) return null;
    final raised = position + _up * config.stepHeight;
    if (_castCapsule(raised, planar, planar.length) != null) return null;
    final advanced = raised + planar;
    final downDistance =
        config.stepHeight + config.groundSnapDistance + config.skinWidth;
    final landing = _castCapsule(advanced, -_up, downDistance);
    if (landing == null || !_isWalkable(landing.normal)) return null;
    final target =
        advanced - _up * math.max(0, landing.distance - config.skinWidth);
    return (target, _groundFromHit(landing));
  }

  bool _isWalkable(Vector3 normal) =>
      normal.normalized.dot(_up) >= _slopeCosine;

  GlintCharacterGroundState _groundFromHit(GlintPhysicsRayHit hit) =>
      GlintCharacterGroundState(
        body: hit.body,
        collider: hit.collider,
        position: hit.position,
        normal: hit.normal.normalized,
        velocity: hit.body.velocityAtWorldPoint(hit.position),
      );

  Vector3 _onPlane(Vector3 value) => value - _up * value.dot(_up);

  @override
  Object capturePhysicsState() => _GlintCharacterSnapshot(
    desiredVelocity: _desiredVelocity,
    velocity: _velocity,
    ground: _ground,
  );

  @override
  void restorePhysicsState(Object state) {
    if (state is! _GlintCharacterSnapshot) {
      throw ArgumentError.value(state, 'state', 'is not a character snapshot');
    }
    _desiredVelocity = state.desiredVelocity;
    _velocity = state.velocity;
    _ground = state.ground;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    world
      ..removeFixedStepCallback(fixedUpdate)
      ..removeSnapshotParticipant(this);
    if (_ownsBody) {
      _ownedCollider?.destroy();
      body.destroy();
    }
  }

  static void _validateConfig(GlintCharacterControllerConfig config) {
    final finite = [
      config.height,
      config.radius,
      config.stepHeight,
      config.slopeLimitRadians,
      config.skinWidth,
      config.groundSnapDistance,
      config.groundAcceleration,
      config.airAcceleration,
      config.gravityScale,
      config.maximumFallSpeed,
    ].every((value) => value.isFinite);
    if (!finite ||
        config.radius <= 0 ||
        config.height < config.radius * 2 ||
        config.stepHeight < 0 ||
        config.skinWidth < 0 ||
        config.groundSnapDistance < 0 ||
        config.groundAcceleration < 0 ||
        config.airAcceleration < 0 ||
        config.maximumFallSpeed <= 0 ||
        config.maxSweepIterations <= 0 ||
        config.up.length == 0 ||
        config.slopeLimitRadians < 0 ||
        config.slopeLimitRadians >= math.pi * .5) {
      throw ArgumentError.value(config, 'config', 'contains invalid values');
    }
  }
}

class _GlintCharacterSnapshot {
  const _GlintCharacterSnapshot({
    required this.desiredVelocity,
    required this.velocity,
    required this.ground,
  });

  final Vector3 desiredVelocity;
  final Vector3 velocity;
  final GlintCharacterGroundState? ground;
}

class _GlintCharacterGroundProbe {
  const _GlintCharacterGroundProbe({
    required this.state,
    required this.separation,
  });

  final GlintCharacterGroundState state;
  final double separation;
}

Vector3 _moveToward(Vector3 from, Vector3 to, double maximumDelta) {
  final delta = to - from;
  if (delta.length <= maximumDelta || delta.length == 0) return to;
  return from + delta.normalized * maximumDelta;
}

bool _finite(Vector3 value) =>
    value.x.isFinite && value.y.isFinite && value.z.isFinite;
