import 'dart:convert';

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
    expect(world.simulationStep, 1);
    expect(world.simulationTime, .1);
    expect(world.interpolationAlpha, closeTo(0, 1e-9));
  });

  test('snapshots restore bodies, fixed-step clock, and participants', () {
    final world = _DeterministicWorld(fixedTimeStep: .1);
    final body = world.createBody(
      const GlintRigidBodyConfig(
        linearVelocity: Vector3(2, 0, 0),
        angularVelocity: Vector3(0, 1, 0),
      ),
    );
    final participant = _CounterParticipant(7);
    world.addSnapshotParticipant(participant);
    world.step(.15);
    final snapshot = world.captureSnapshot();

    body
      ..linearVelocity = const Vector3(9, 0, 0)
      ..putToSleep();
    participant.value = 99;
    world.gravity = Vector3.zero;
    world.stepFixed();
    world.restoreSnapshot(snapshot);

    expect(body.position.x, closeTo(.2, 1e-9));
    expect(body.linearVelocity, const Vector3(2, 0, 0));
    expect(body.angularVelocity, const Vector3(0, 1, 0));
    expect(body.isSleeping, isFalse);
    expect(participant.value, 7);
    expect(world.gravity, const Vector3(0, -9.81, 0));
    expect(world.simulationStep, 1);
    expect(world.interpolationAlpha, closeTo(.5, 1e-9));
  });

  test('strict snapshots detect body membership changes', () {
    final world = _DeterministicWorld(fixedTimeStep: .1);
    world.createBody(const GlintRigidBodyConfig());
    final snapshot = world.captureSnapshot();
    world.createBody(const GlintRigidBodyConfig());

    expect(() => world.restoreSnapshot(snapshot), throwsStateError);
  });

  test('fixed-step recordings replay deterministically and serialize', () {
    final world = _DeterministicWorld(fixedTimeStep: .05);
    final body = world.createBody(const GlintRigidBodyConfig());
    void apply(int input, double _) {
      body.linearVelocity = Vector3(input.toDouble(), 0, 0);
    }

    final recorder = GlintPhysicsReplayRecorder<int>(
      world: world,
      applyInput: apply,
    );
    for (final input in const [1, 2, 2, -1, 3]) {
      recorder.record(input);
    }
    final replay = recorder.finish();
    final recordedDigest = world.stateDigest();

    final result = replay.play(world, apply);
    expect(result.deterministic, isTrue);
    expect(result.stepsPlayed, 5);
    expect(world.stateDigest(), recordedDigest);

    final divergent = replay.play(world, (input, _) {
      body.linearVelocity = Vector3(input + .5, 0, 0);
    }, stopOnDivergence: true);
    expect(divergent.deterministic, isFalse);
    expect(divergent.divergences.single.frame, 0);

    final encoded =
        jsonDecode(jsonEncode(replay.toJson((input) => input)))
            as Map<String, Object?>;
    final portable = GlintPhysicsReplay<int>.fromJson(
      encoded,
      decodeInput: (value) => (value as num).toInt(),
    );
    final freshWorld = _DeterministicWorld(fixedTimeStep: .05);
    final freshBody = freshWorld.createBody(const GlintRigidBodyConfig());
    final portableResult = portable.play(freshWorld, (input, _) {
      freshBody.linearVelocity = Vector3(input.toDouble(), 0, 0);
    }, restoreInitialState: false);
    expect(portableResult.deterministic, isTrue);
  });

  test(
    'contacts persist across fixed steps and report profiling data',
    () async {
      final world = _DeterministicWorld(fixedTimeStep: .1);
      final a = world.createBody(const GlintRigidBodyConfig());
      final b = world.createBody(const GlintRigidBodyConfig());
      final colliderA = a.addCollider(const GlintSphereCollider(1));
      final colliderB = b.addCollider(const GlintSphereCollider(1));
      final events = <GlintCollisionEvent>[];
      final subscription = world.collisions.listen(events.add);
      GlintPhysicsStepStatistics? statistics;
      world.addStepCompletedCallback((value) => statistics = value);

      world.emitCollisionEvent(
        GlintContactBegan(colliderA, colliderB, const [
          GlintContactPoint(
            position: Vector3.zero,
            normal: Vector3(0, 1, 0),
            impulse: 2,
            separation: -.01,
          ),
        ]),
      );
      world.stepFixed();
      expect(world.activeContacts.single.steps, 1);
      expect(statistics?.activeContactCount, 1);
      expect(statistics?.bodyCount, 2);
      world.stepFixed();
      expect(events.whereType<GlintContactStayed>().single.steps, 2);

      world.emitCollisionEvent(GlintContactEnded(colliderB, colliderA));
      expect(world.activeContacts, isEmpty);
      expect(events.last, isA<GlintContactEnded>());
      await subscription.cancel();
      world.dispose();
    },
  );

  test('character motor accelerates, grounds, and jumps', () {
    final world = _GroundWorld(fixedTimeStep: .1);
    final character = GlintCharacterController.create(
      world: world,
      position: const Vector3(0, .9, 0),
      config: const GlintCharacterControllerConfig(
        groundAcceleration: 100,
        airAcceleration: 100,
      ),
    );
    character.desiredVelocity = const Vector3(2, 5, 0);

    world.stepFixed();
    expect(character.isGrounded, isTrue);
    expect(character.body.position.x, closeTo(.2, 1e-9));
    expect(character.velocity.y, closeTo(0, 1e-9));
    expect(character.jump(4), isTrue);
    world.stepFixed();
    expect(character.isGrounded, isFalse);
    expect(character.body.position.y, greaterThan(.9));

    character.dispose();
    world.dispose();
  });

  test('ragdolls map physics bodies back into a partial skeletal pose', () {
    const rig = GlintGlbRig(
      nodes: [
        GlintGlbNode(name: 'root', children: [1]),
        GlintGlbNode(name: 'hand', translation: [0, 1, 0]),
      ],
      rootNodes: [0],
      meshes: [],
      animations: [],
    );
    final world = _DeterministicWorld(fixedTimeStep: .1);
    final ragdoll = GlintRagdoll.create(
      world: world,
      rig: rig,
      simulated: false,
      definition: const GlintRagdollDefinition(
        parts: [
          GlintRagdollPart(
            id: 'root',
            nodeName: 'root',
            collider: GlintSphereCollider(.2),
          ),
          GlintRagdollPart(
            id: 'hand',
            nodeName: 'hand',
            collider: GlintSphereCollider(.1),
          ),
        ],
        constraints: [
          GlintRagdollConstraint(
            parentPart: 'root',
            childPart: 'hand',
            type: GlintRagdollJointType.fixed,
          ),
        ],
      ),
    );
    ragdoll
        .body('hand')
        .setTransform(const Vector3(2, 1, 0), GlintQuaternion.identity);

    final pose = ragdoll.poseFromPhysics(rig.bindPose());

    expect(pose.nodes[1].translation.x, closeTo(2, 1e-9));
    expect(pose.nodes[1].translation.y, closeTo(1, 1e-9));
    expect(pose.trsNodes, containsAll([0, 1]));
    ragdoll.dispose();
    world.dispose();
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

class _DeterministicWorld extends GlintPhysicsWorld {
  _DeterministicWorld({required super.fixedTimeStep});

  final List<_FakeBody> _bodies = [];

  @override
  String get backendName => 'deterministic-test';
  @override
  List<GlintRigidBody> get bodies => List.unmodifiable(_bodies);
  @override
  GlintRigidBody createBody(GlintRigidBodyConfig config) {
    final body = _FakeBody(config);
    _bodies.add(body);
    return body;
  }

  @override
  GlintJoint createJoint(GlintJointConfig config) => _FakeJoint();
  @override
  void updateBackendGravity(Vector3 gravity) {}
  @override
  void stepBackend(double fixedTimeStep, int solverSubSteps) {
    for (final body in _bodies) {
      if (body.type != GlintBodyType.static && !body.isSleeping) {
        body.setTransform(
          body.position + body.linearVelocity * fixedTimeStep,
          body.orientation,
        );
      }
    }
  }

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
  void dispose() {
    disposePhysicsState();
    _bodies.clear();
  }
}

class _GroundWorld extends _DeterministicWorld {
  _GroundWorld({required super.fixedTimeStep}) {
    _ground = createBody(
      const GlintRigidBodyConfig(type: GlintBodyType.static),
    );
    _groundCollider = _ground.addCollider(
      const GlintBoxCollider(Vector3(100, .1, 100)),
    );
  }

  late final GlintRigidBody _ground;
  late final GlintColliderHandle _groundCollider;

  @override
  GlintPhysicsRayHit? raycast(
    GlintRay ray, {
    double maxDistance = double.infinity,
    GlintQueryFilter filter = const GlintQueryFilter(),
  }) {
    if (ray.direction.y >= -1e-9) return null;
    final distance = ray.origin.y / -ray.direction.y;
    if (distance < 0 || distance > maxDistance) return null;
    final hit = ray.origin + ray.direction * distance;
    return GlintPhysicsRayHit(
      body: _ground,
      collider: _groundCollider,
      position: Vector3(hit.x, 0, hit.z),
      normal: const Vector3(0, 1, 0),
      distance: distance,
    );
  }

  @override
  GlintPhysicsRayHit? shapeCast(
    GlintCollider collider,
    Vector3 origin,
    Vector3 direction, {
    GlintQuaternion orientation = GlintQuaternion.identity,
    double maxDistance = double.infinity,
    GlintQueryFilter filter = const GlintQueryFilter(),
  }) {
    if (collider is! GlintSphereCollider || direction.y >= -1e-9) return null;
    final height = origin.y - collider.radius;
    if (height < -1e-9) return null;
    final distance = height / -direction.normalized.y;
    if (distance > maxDistance) return null;
    final centerAtHit = origin + direction.normalized * distance;
    return GlintPhysicsRayHit(
      body: _ground,
      collider: _groundCollider,
      position: Vector3(centerAtHit.x, 0, centerAtHit.z),
      normal: const Vector3(0, 1, 0),
      distance: distance.clamp(0, maxDistance).toDouble(),
    );
  }
}

class _FakeBody extends GlintRigidBody {
  _FakeBody(GlintRigidBodyConfig config)
    : _type = config.type,
      _position = config.position,
      _orientation = config.orientation,
      _linearVelocity = config.linearVelocity,
      _angularVelocity = config.angularVelocity,
      _userData = config.userData;

  GlintBodyType _type;
  Vector3 _position;
  GlintQuaternion _orientation;
  Vector3 _linearVelocity;
  Vector3 _angularVelocity;
  final Object? _userData;
  bool _sleeping = false;

  @override
  GlintBodyType get type => _type;
  @override
  set type(GlintBodyType value) => _type = value;
  @override
  Object? get userData => _userData;
  @override
  Vector3 get position => _position;
  @override
  GlintQuaternion get orientation => _orientation;
  @override
  Vector3 get interpolatedPosition => _position;
  @override
  GlintQuaternion get interpolatedOrientation => _orientation;
  @override
  Vector3 get linearVelocity => _linearVelocity;
  @override
  set linearVelocity(Vector3 value) => _linearVelocity = value;
  @override
  Vector3 get angularVelocity => _angularVelocity;
  @override
  set angularVelocity(Vector3 value) => _angularVelocity = value;
  @override
  double get mass => 1;
  @override
  bool get isSleeping => _sleeping;
  @override
  void setTransform(Vector3 position, GlintQuaternion orientation) {
    _position = position;
    _orientation = orientation;
  }

  @override
  void setDamping({double? linear, double? angular}) {}
  @override
  void setGravityScale(double scale) {}
  @override
  void setCcdEnabled(bool enabled) {}
  @override
  void setMotionLocks({
    bool linearX = false,
    bool linearY = false,
    bool linearZ = false,
    bool angularX = false,
    bool angularY = false,
    bool angularZ = false,
  }) {}
  @override
  void wakeUp() => _sleeping = false;
  @override
  void putToSleep() => _sleeping = true;
  @override
  void applyForce(Vector3 force, {Vector3? atWorldPoint}) {
    _linearVelocity += force;
  }

  @override
  void applyImpulse(Vector3 impulse, {Vector3? atWorldPoint}) {
    _linearVelocity += impulse;
  }

  @override
  void applyTorque(Vector3 torque) => _angularVelocity += torque;
  @override
  void applyAngularImpulse(Vector3 impulse) => _angularVelocity += impulse;
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
  }) => _FakeCollider(
    body: this,
    collider: collider,
    material: material,
    isTrigger: isTrigger,
    collisionLayer: collisionLayer,
    collisionMask: collisionMask,
    userData: userData,
  );
  @override
  void destroy() {}
}

class _FakeCollider implements GlintColliderHandle {
  const _FakeCollider({
    required this.body,
    required this.collider,
    required this.material,
    required this.isTrigger,
    required this.collisionLayer,
    required this.collisionMask,
    required this.userData,
  });

  @override
  final GlintRigidBody body;
  @override
  final GlintCollider collider;
  @override
  final GlintPhysicsMaterial material;
  @override
  final bool isTrigger;
  @override
  final int collisionLayer;
  @override
  final int collisionMask;
  @override
  final Object? userData;
  @override
  void destroy() {}
}

class _FakeJoint implements GlintJoint {
  @override
  void destroy() {}
}

class _CounterParticipant implements GlintPhysicsSnapshotParticipant {
  _CounterParticipant(this.value);

  int value;

  @override
  Object capturePhysicsState() => value;
  @override
  void restorePhysicsState(Object state) => value = state as int;
}
