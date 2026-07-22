import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:box3d/box3d.dart' as b3;
import 'package:glint_engine/glint_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

vm.Vector3 _nativeVector(Vector3 value) =>
    vm.Vector3(value.x, value.y, value.z);
Vector3 _glintVector(vm.Vector3 value) => Vector3(value.x, value.y, value.z);
vm.Quaternion _nativeQuaternion(GlintQuaternion value) =>
    vm.Quaternion(value.x, value.y, value.z, value.w);
GlintQuaternion _glintQuaternion(vm.Quaternion value) =>
    GlintQuaternion(value.x, value.y, value.z, value.w).normalized;

class GlintBox3dWorld extends GlintPhysicsWorld {
  GlintBox3dWorld({
    super.gravity = const Vector3(0, -9.81, 0),
    super.fixedTimeStep,
    super.maxSubSteps,
    super.solverSubSteps,
  }) : _native = b3.Box3dWorld(gravity: _nativeVector(gravity));

  static Future<void> ensureInitialized() => b3.Box3d.ensureInitialized();

  final b3.Box3dWorld _native;
  final List<_Box3dBody> _bodies = [];
  final Map<int, _Box3dCollider> _colliders = {};
  final StreamController<GlintCollisionEvent> _events =
      StreamController<GlintCollisionEvent>.broadcast();
  bool _disposed = false;

  @override
  String get backendName => 'box3d';

  @override
  List<GlintRigidBody> get bodies => List.unmodifiable(_bodies);

  @override
  Stream<GlintCollisionEvent> get collisions => _events.stream;

  @override
  GlintRigidBody createBody(GlintRigidBodyConfig config) {
    if (_disposed) throw StateError('The physics world is disposed.');
    final native = _native.createBody(
      type: switch (config.type) {
        GlintBodyType.static => b3.Box3dBodyType.static_,
        GlintBodyType.dynamic => b3.Box3dBodyType.dynamic_,
        GlintBodyType.kinematic => b3.Box3dBodyType.kinematic,
      },
      position: _nativeVector(config.position),
      rotation: _nativeQuaternion(config.orientation),
    );
    final body = _Box3dBody(this, native, config);
    _bodies.add(body);
    return body;
  }

  @override
  GlintJoint createJoint(GlintJointConfig config) {
    final a = _body(config.bodyA);
    final b = _body(config.bodyB);
    b3.Box3dFrame frame(GlintJointFrame value) => b3.Box3dFrame(
      position: _nativeVector(value.position),
      rotation: _nativeQuaternion(value.orientation),
    );
    final native = switch (config) {
      GlintFixedJointConfig value => _native.createWeldJoint(
        a._native,
        b._native,
        frameA: frame(value.frameA),
        frameB: frame(value.frameB),
        collideConnected: value.collideConnected,
        linearHertz: value.linearFrequency,
        angularHertz: value.angularFrequency,
        linearDampingRatio: value.linearDampingRatio,
        angularDampingRatio: value.angularDampingRatio,
      ),
      GlintRevoluteJointConfig value => _native.createRevoluteJoint(
        a._native,
        b._native,
        frameA: frame(value.frameA),
        frameB: frame(value.frameB),
        collideConnected: value.collideConnected,
        lowerLimit: value.lowerLimit,
        upperLimit: value.upperLimit,
        motorSpeed: value.motorSpeed,
        maxMotorTorque: value.maxMotorTorque,
      ),
      GlintPrismaticJointConfig value => _native.createPrismaticJoint(
        a._native,
        b._native,
        frameA: frame(value.frameA),
        frameB: frame(value.frameB),
        collideConnected: value.collideConnected,
        lowerLimit: value.lowerLimit,
        upperLimit: value.upperLimit,
        motorSpeed: value.motorSpeed,
        maxMotorForce: value.maxMotorForce,
      ),
      GlintSphericalJointConfig value => _native.createSphericalJoint(
        a._native,
        b._native,
        frameA: frame(value.frameA),
        frameB: frame(value.frameB),
        collideConnected: value.collideConnected,
        coneAngle: value.coneAngle,
        lowerTwist: value.lowerTwist,
        upperTwist: value.upperTwist,
        maxMotorTorque: value.maxMotorTorque,
      ),
      GlintDistanceJointConfig value => _native.createDistanceJoint(
        a._native,
        b._native,
        length: value.length,
        frameA: frame(value.frameA),
        frameB: frame(value.frameB),
        collideConnected: value.collideConnected,
        minLength: value.minimumLength,
        maxLength: value.maximumLength,
        springHertz: value.springFrequency,
        springDampingRatio: value.springDampingRatio,
        motorSpeed: value.motorSpeed,
        maxMotorForce: value.maxMotorForce,
      ),
    };
    return _Box3dJoint(native);
  }

  _Box3dBody _body(GlintRigidBody body) {
    if (body is! _Box3dBody || body._world != this) {
      throw ArgumentError('Joint bodies must belong to this Box3D world.');
    }
    return body;
  }

  void _register(_Box3dCollider collider) {
    for (final shape in collider._shapes) {
      _colliders[shape.handle] = collider;
    }
  }

  void _forget(_Box3dCollider collider) {
    for (final shape in collider._shapes) {
      _colliders.remove(shape.handle);
    }
  }

  @override
  void updateBackendGravity(Vector3 gravity) {
    _native.gravity = _nativeVector(gravity);
  }

  @override
  void stepBackend(double fixedTimeStep, int solverSubSteps) {
    for (final body in _bodies) {
      body._beginStep();
    }
    _native.step(fixedTimeStep, subSteps: solverSubSteps);
    for (final body in _bodies) {
      body._endStep();
    }
    _drainEvents();
  }

  @override
  void updateInterpolation(double alpha) {}

  void _drainEvents() {
    final events = _native.drainEvents();
    for (final event in events.contactBegan) {
      final a = _colliders[event.shapeA];
      final b = _colliders[event.shapeB];
      if (a == null || b == null) continue;
      _events.add(
        GlintContactBegan(a, b, [
          for (final point in event.points)
            GlintContactPoint(
              position: _glintVector(point.position),
              normal: _glintVector(point.normal),
              impulse: point.impulse,
              separation: point.separation,
            ),
        ]),
      );
    }
    for (final event in events.contactEnded) {
      final a = _colliders[event.shapeA];
      final b = _colliders[event.shapeB];
      if (a != null && b != null) _events.add(GlintContactEnded(a, b));
    }
    for (final event in events.sensorBegan) {
      final a = _colliders[event.sensorShape];
      final b = _colliders[event.visitorShape];
      if (a != null && b != null) _events.add(GlintTriggerEntered(a, b));
    }
    for (final event in events.sensorEnded) {
      final a = _colliders[event.sensorShape];
      final b = _colliders[event.visitorShape];
      if (a != null && b != null) _events.add(GlintTriggerExited(a, b));
    }
  }

  bool _allows(_Box3dCollider collider, GlintQueryFilter filter) {
    if (filter.excludedBodies.contains(collider.body)) return false;
    if (collider.collisionLayer & filter.layerMask == 0) return false;
    if (collider.isTrigger && !filter.includeTriggers) return false;
    return switch (collider.body.type) {
      GlintBodyType.static => filter.includeStatic,
      GlintBodyType.dynamic => filter.includeDynamic,
      GlintBodyType.kinematic => filter.includeKinematic,
    };
  }

  GlintPhysicsRayHit? _resolve(b3.Box3dRayHit hit, GlintQueryFilter filter) {
    final collider = _colliders[hit.shape];
    if (collider == null || !_allows(collider, filter)) return null;
    return GlintPhysicsRayHit(
      body: collider.body,
      collider: collider,
      position: _glintVector(hit.point),
      normal: _glintVector(hit.normal),
      distance: hit.distance,
    );
  }

  @override
  GlintPhysicsRayHit? raycast(
    GlintRay ray, {
    double maxDistance = double.infinity,
    GlintQueryFilter filter = const GlintQueryFilter(),
  }) {
    final hits = raycastAll(ray, maxDistance: maxDistance, filter: filter);
    return hits.isEmpty ? null : hits.first;
  }

  @override
  List<GlintPhysicsRayHit> raycastAll(
    GlintRay ray, {
    double maxDistance = double.infinity,
    GlintQueryFilter filter = const GlintQueryFilter(),
  }) {
    final hits = _native.raycastAll(
      _nativeVector(ray.origin),
      _nativeVector(ray.direction),
      maxDistance: maxDistance.isFinite ? maxDistance : 1e6,
      mask: filter.layerMask,
    );
    final resolved = <GlintPhysicsRayHit>[
      for (final hit in hits) ?_resolve(hit, filter),
    ]..sort((a, b) => a.distance.compareTo(b.distance));
    return resolved;
  }

  List<GlintOverlapHit> _overlaps(List<int> handles, GlintQueryFilter filter) {
    final seen = <GlintColliderHandle>{};
    return [
      for (final handle in handles)
        if (_colliders[handle] case final collider?
            when _allows(collider, filter) && seen.add(collider))
          GlintOverlapHit(collider.body, collider),
    ];
  }

  @override
  List<GlintOverlapHit> overlapSphere(
    Vector3 center,
    double radius, {
    GlintQueryFilter filter = const GlintQueryFilter(),
  }) => _overlaps(
    _native.overlapSphere(
      _nativeVector(center),
      radius,
      mask: filter.layerMask,
    ),
    filter,
  );

  @override
  List<GlintOverlapHit> overlapBox(
    Vector3 center,
    Vector3 halfExtents, {
    GlintQuaternion orientation = GlintQuaternion.identity,
    GlintQueryFilter filter = const GlintQueryFilter(),
  }) => _overlaps(
    _native.overlapBox(
      _nativeVector(center),
      _nativeVector(halfExtents),
      rotation: _nativeQuaternion(orientation),
      mask: filter.layerMask,
    ),
    filter,
  );

  @override
  GlintPhysicsRayHit? shapeCast(
    GlintCollider collider,
    Vector3 origin,
    Vector3 direction, {
    GlintQuaternion orientation = GlintQuaternion.identity,
    double maxDistance = double.infinity,
    GlintQueryFilter filter = const GlintQueryFilter(),
  }) {
    final distance = maxDistance.isFinite ? maxDistance : 1e6;
    final hit = switch (collider) {
      GlintSphereCollider value => _native.shapeCastSphere(
        _nativeVector(origin),
        value.radius,
        _nativeVector(direction),
        maxDistance: distance,
        mask: filter.layerMask,
      ),
      GlintBoxCollider value => _native.shapeCastBox(
        _nativeVector(origin),
        _nativeVector(value.halfExtents),
        _nativeVector(direction),
        rotation: _nativeQuaternion(orientation),
        maxDistance: distance,
        mask: filter.layerMask,
      ),
      _ => throw UnsupportedError(
        'Box3D shape casts currently support sphere and box probes.',
      ),
    };
    return hit == null ? null : _resolve(hit, filter);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _events.close();
    _native.dispose();
    _bodies.clear();
    _colliders.clear();
  }
}

class _Box3dBody extends GlintRigidBody {
  _Box3dBody(this._world, this._native, GlintRigidBodyConfig config)
    : _type = config.type,
      _userData = config.userData,
      _previousPosition = config.position,
      _currentPosition = config.position,
      _previousOrientation = config.orientation,
      _currentOrientation = config.orientation {
    _native
      ..linearVelocity = _nativeVector(config.linearVelocity)
      ..angularVelocity = _nativeVector(config.angularVelocity)
      ..linearDamping = config.linearDamping
      ..angularDamping = config.angularDamping
      ..gravityScale = config.gravityScale
      ..isBullet = config.ccdEnabled
      ..sleepEnabled = config.sleepEnabled;
  }

  final GlintBox3dWorld _world;
  final b3.Box3dBody _native;
  final Object? _userData;
  final List<_Box3dCollider> _ownedColliders = [];
  GlintBodyType _type;
  Vector3 _previousPosition;
  Vector3 _currentPosition;
  GlintQuaternion _previousOrientation;
  GlintQuaternion _currentOrientation;
  bool _destroyed = false;

  @override
  GlintBodyType get type => _type;
  @override
  set type(GlintBodyType value) {
    _type = value;
    _native.type = switch (value) {
      GlintBodyType.static => b3.Box3dBodyType.static_,
      GlintBodyType.dynamic => b3.Box3dBodyType.dynamic_,
      GlintBodyType.kinematic => b3.Box3dBodyType.kinematic,
    };
  }

  @override
  Object? get userData => _userData;
  @override
  Vector3 get position => _glintVector(_native.position);
  @override
  GlintQuaternion get orientation => _glintQuaternion(_native.rotation);
  @override
  Vector3 get interpolatedPosition =>
      _previousPosition +
      (_currentPosition - _previousPosition) * _world.interpolationAlpha;
  @override
  GlintQuaternion get interpolatedOrientation => GlintQuaternion.slerp(
    _previousOrientation,
    _currentOrientation,
    _world.interpolationAlpha,
  );
  @override
  Vector3 get linearVelocity => _glintVector(_native.linearVelocity);
  @override
  set linearVelocity(Vector3 value) =>
      _native.linearVelocity = _nativeVector(value);
  @override
  Vector3 get angularVelocity => _glintVector(_native.angularVelocity);
  @override
  set angularVelocity(Vector3 value) =>
      _native.angularVelocity = _nativeVector(value);
  @override
  double get mass => _native.mass;
  @override
  bool get isSleeping => !_native.isAwake;

  void _beginStep() {
    _previousPosition = _currentPosition;
    _previousOrientation = _currentOrientation;
  }

  void _endStep() {
    _currentPosition = position;
    _currentOrientation = orientation;
  }

  @override
  void setTransform(Vector3 position, GlintQuaternion orientation) {
    _native.setTransform(
      _nativeVector(position),
      _nativeQuaternion(orientation),
    );
    _previousPosition = _currentPosition = position;
    _previousOrientation = _currentOrientation = orientation;
  }

  @override
  void setDamping({double? linear, double? angular}) {
    if (linear != null) _native.linearDamping = linear;
    if (angular != null) _native.angularDamping = angular;
  }

  @override
  void setGravityScale(double scale) => _native.gravityScale = scale;
  @override
  void setCcdEnabled(bool enabled) => _native.isBullet = enabled;
  @override
  void setMotionLocks({
    bool linearX = false,
    bool linearY = false,
    bool linearZ = false,
    bool angularX = false,
    bool angularY = false,
    bool angularZ = false,
  }) => _native.setMotionLocks(
    linearX: linearX,
    linearY: linearY,
    linearZ: linearZ,
    angularX: angularX,
    angularY: angularY,
    angularZ: angularZ,
  );
  @override
  void wakeUp() => _native.wakeUp();
  @override
  void putToSleep() => _native.sleep();
  @override
  void applyForce(Vector3 force, {Vector3? atWorldPoint}) => _native.applyForce(
    _nativeVector(force),
    point: atWorldPoint == null ? null : _nativeVector(atWorldPoint),
  );
  @override
  void applyImpulse(Vector3 impulse, {Vector3? atWorldPoint}) =>
      _native.applyImpulse(
        _nativeVector(impulse),
        point: atWorldPoint == null ? null : _nativeVector(atWorldPoint),
      );
  @override
  void applyTorque(Vector3 torque) =>
      _native.applyTorque(_nativeVector(torque));
  @override
  void applyAngularImpulse(Vector3 impulse) =>
      _native.applyAngularImpulse(_nativeVector(impulse));

  @override
  GlintColliderHandle addCollider(
    GlintCollider collider, {
    GlintPhysicsMaterial material = GlintPhysicsMaterial.standard,
    Vector3 localPosition = Vector3.zero,
    GlintQuaternion localOrientation = GlintQuaternion.identity,
    int collisionLayer = 1,
    int collisionMask = 0x7fffffff,
    bool isTrigger = false,
    Object? userData,
  }) {
    final shapes = _cookCollider(
      _native,
      collider,
      material,
      localPosition,
      localOrientation,
      isTrigger,
    );
    final result = _Box3dCollider(
      this,
      collider,
      material,
      shapes,
      collisionLayer,
      collisionMask,
      isTrigger,
      userData,
    );
    for (final shape in shapes) {
      shape
        ..setCollisionFilter(category: collisionLayer, mask: collisionMask)
        ..contactEventsEnabled = true
        ..sensorEventsEnabled = true;
    }
    _ownedColliders.add(result);
    _world._register(result);
    return result;
  }

  @override
  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    for (final collider in List.of(_ownedColliders)) {
      collider.destroy();
    }
    _native.destroy();
    _world._bodies.remove(this);
  }
}

class _Box3dCollider implements GlintColliderHandle {
  _Box3dCollider(
    this.body,
    this.collider,
    this.material,
    this._shapes,
    this.collisionLayer,
    this.collisionMask,
    this.isTrigger,
    this.userData,
  );

  @override
  final _Box3dBody body;
  @override
  final GlintCollider collider;
  @override
  final GlintPhysicsMaterial material;
  final List<b3.Box3dShape> _shapes;
  @override
  final int collisionLayer;
  @override
  final int collisionMask;
  @override
  final bool isTrigger;
  @override
  final Object? userData;
  bool _destroyed = false;

  @override
  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    body._world._forget(this);
    for (final shape in _shapes) {
      shape.destroy();
    }
    body._ownedColliders.remove(this);
  }
}

class _Box3dJoint implements GlintJoint {
  _Box3dJoint(this._native);
  final b3.Box3dJoint _native;
  @override
  void destroy() => _native.destroy();
}

List<b3.Box3dShape> _cookCollider(
  b3.Box3dBody body,
  GlintCollider collider,
  GlintPhysicsMaterial material,
  Vector3 position,
  GlintQuaternion orientation,
  bool trigger,
) {
  final nativeMaterial = b3.Box3dMaterial(
    friction: material.friction,
    restitution: material.restitution,
    density: material.density,
  );
  Float32List transform(Float32List source) {
    final output = Float32List(source.length);
    for (var i = 0; i < source.length; i += 3) {
      final point =
          orientation.rotate(Vector3(source[i], source[i + 1], source[i + 2])) +
          position;
      output[i] = point.x;
      output[i + 1] = point.y;
      output[i + 2] = point.z;
    }
    return output;
  }

  switch (collider) {
    case GlintSphereCollider value:
      return [
        body.addSphere(
          value.radius,
          center: _nativeVector(position),
          material: nativeMaterial,
          isSensor: trigger,
        ),
      ];
    case GlintBoxCollider value:
      if (position == Vector3.zero && orientation == GlintQuaternion.identity) {
        return [
          body.addBox(
            _nativeVector(value.halfExtents),
            material: nativeMaterial,
            isSensor: trigger,
          ),
        ];
      }
      final points = Float32List(24);
      var offset = 0;
      for (final x in [-value.halfExtents.x, value.halfExtents.x]) {
        for (final y in [-value.halfExtents.y, value.halfExtents.y]) {
          for (final z in [-value.halfExtents.z, value.halfExtents.z]) {
            final point = orientation.rotate(Vector3(x, y, z)) + position;
            points[offset++] = point.x;
            points[offset++] = point.y;
            points[offset++] = point.z;
          }
        }
      }
      final shape = body.addConvexHull(
        points,
        material: nativeMaterial,
        isSensor: trigger,
      );
      return shape == null ? const [] : [shape];
    case GlintCapsuleCollider value:
      final axis = orientation.rotate(const Vector3(0, 1, 0));
      return [
        body.addCapsule(
          value.radius,
          pointA: _nativeVector(position - axis * value.halfHeight),
          pointB: _nativeVector(position + axis * value.halfHeight),
          material: nativeMaterial,
          isSensor: trigger,
        ),
      ];
    case GlintCylinderCollider value:
      if (position == Vector3.zero && orientation == GlintQuaternion.identity) {
        return [
          body.addCylinder(
            value.halfHeight,
            value.radius,
            material: nativeMaterial,
            isSensor: trigger,
          ),
        ];
      }
      final points = Float32List(16 * 2 * 3);
      for (var ring = 0; ring < 2; ring++) {
        final y = ring == 0 ? -value.halfHeight : value.halfHeight;
        for (var i = 0; i < 16; i++) {
          final angle = i * math.pi * 2 / 16;
          final point =
              orientation.rotate(
                Vector3(
                  math.cos(angle) * value.radius,
                  y,
                  math.sin(angle) * value.radius,
                ),
              ) +
              position;
          final index = (ring * 16 + i) * 3;
          points[index] = point.x;
          points[index + 1] = point.y;
          points[index + 2] = point.z;
        }
      }
      final shape = body.addConvexHull(
        points,
        material: nativeMaterial,
        isSensor: trigger,
      );
      return shape == null ? const [] : [shape];
    case GlintConvexHullCollider value:
      final shape = body.addConvexHull(
        transform(value.points),
        material: nativeMaterial,
        isSensor: trigger,
      );
      return shape == null ? const [] : [shape];
    case GlintTriangleMeshCollider value:
      final shape = body.addTriMesh(
        transform(value.vertices),
        value.indices,
        material: nativeMaterial,
        isSensor: trigger,
      );
      return shape == null ? const [] : [shape];
    case GlintHeightFieldCollider value:
      if (position != Vector3.zero || orientation != GlintQuaternion.identity) {
        throw UnsupportedError(
          'Height fields must use the rigid body transform.',
        );
      }
      final shape = body.addHeightField(
        countX: value.width,
        countZ: value.depth,
        heights: value.heights,
        scale: _nativeVector(value.scale),
        material: nativeMaterial,
        isSensor: trigger,
      );
      return shape == null ? const [] : [shape];
    case GlintCompoundCollider value:
      return [
        for (final child in value.children)
          ..._cookCollider(
            body,
            child.collider,
            material,
            position + orientation.rotate(child.position),
            orientation * child.orientation,
            trigger,
          ),
      ];
  }
}
