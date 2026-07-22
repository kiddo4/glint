import 'package:glint_box3d/glint_box3d.dart';
import 'package:glint_engine/glint_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(GlintBox3dWorld.ensureInitialized);

  test('simulates angular rigid bodies and supports self-excluding rays', () {
    final world = GlintBox3dWorld(fixedTimeStep: 1 / 120);
    final ground = world.createBody(
      const GlintRigidBodyConfig(type: GlintBodyType.static),
    );
    final groundCollider = ground.addCollider(
      const GlintBoxCollider(Vector3(10, .5, 10)),
      localPosition: const Vector3(0, -.5, 0),
      material: const GlintPhysicsMaterial(friction: .85),
    );
    expect(groundCollider.material.friction, .85);
    final body = world.createBody(
      const GlintRigidBodyConfig(position: Vector3(0, 3, 0)),
    );
    body.addCollider(
      const GlintBoxCollider(Vector3(.5, .5, .5)),
      material: const GlintPhysicsMaterial(density: 100),
    );
    body.applyImpulse(
      const Vector3(2, 0, 0),
      atWorldPoint: const Vector3(0, 3.5, 0),
    );
    for (var i = 0; i < 240; i++) {
      world.step(1 / 120);
    }
    expect(body.position.y, closeTo(.5, .08));
    expect(body.orientation, isNot(GlintQuaternion.identity));

    final hit = world.raycast(
      const GlintRay(Vector3(0, 5, 0), Vector3(0, -1, 0)),
      filter: GlintQueryFilter(excludedBodies: {body}),
    );
    expect(hit?.body, same(ground));
    world.dispose();
  });

  test('raycast vehicle settles on suspension and accelerates', () {
    final world = GlintBox3dWorld(fixedTimeStep: 1 / 120);
    final ground = world.createBody(
      const GlintRigidBodyConfig(type: GlintBodyType.static),
    );
    ground.addCollider(
      const GlintBoxCollider(Vector3(20, .5, 40)),
      localPosition: const Vector3(0, -.5, -10),
    );
    final chassis = world.createBody(
      const GlintRigidBodyConfig(
        position: Vector3(0, .72, 5),
        angularDamping: .2,
      ),
    );
    chassis.addCollider(
      const GlintBoxCollider(Vector3(.8, .25, 1.4)),
      material: const GlintPhysicsMaterial(density: 350),
    );
    final vehicle = GlintRaycastVehicle(
      world: world,
      chassis: chassis,
      config: const GlintVehicleConfig(
        wheels: [
          GlintVehicleWheel(
            name: 'fl',
            mount: Vector3(-.7, -.1, -1),
            axle: 0,
            powered: true,
            steered: true,
          ),
          GlintVehicleWheel(
            name: 'fr',
            mount: Vector3(.7, -.1, -1),
            axle: 0,
            powered: true,
            steered: true,
          ),
          GlintVehicleWheel(
            name: 'rl',
            mount: Vector3(-.7, -.1, 1),
            axle: 1,
            powered: true,
            handbrake: true,
          ),
          GlintVehicleWheel(
            name: 'rr',
            mount: Vector3(.7, -.1, 1),
            axle: 1,
            powered: true,
            handbrake: true,
          ),
        ],
      ),
    );
    for (var i = 0; i < 120; i++) {
      world.step(1 / 120);
    }
    expect(vehicle.isGrounded, isTrue);
    final settledPosition = chassis.position;
    final settledSpin = vehicle.wheelStates.first.spinAngle;
    final snapshot = world.captureSnapshot();
    vehicle.throttle = .5;
    for (var i = 0; i < 30; i++) {
      world.stepFixed();
    }
    world.restoreSnapshot(snapshot);
    expect(chassis.position.x, closeTo(settledPosition.x, 1e-9));
    expect(chassis.position.y, closeTo(settledPosition.y, 1e-9));
    expect(chassis.position.z, closeTo(settledPosition.z, 1e-9));
    expect(vehicle.throttle, 0);
    expect(vehicle.wheelStates.first.spinAngle, settledSpin);

    final startZ = chassis.position.z;
    vehicle.throttle = 1;
    for (var i = 0; i < 360; i++) {
      world.step(1 / 120);
    }
    expect(chassis.position.z, lessThan(startZ - 1));
    expect(vehicle.speedKilometersPerHour, greaterThan(1));
    expect(vehicle.engineRpm, greaterThanOrEqualTo(900));
    vehicle.steer = 1;
    for (var i = 0; i < 30; i++) {
      world.step(1 / 120);
    }
    final frontDirection = vehicle.wheelStates.first.orientation.rotate(
      const Vector3(0, 0, -1),
    );
    final rearDirection = vehicle.wheelStates.last.orientation.rotate(
      const Vector3(0, 0, -1),
    );
    expect(frontDirection.dot(rearDirection), lessThan(.999));
    vehicle.dispose();
    world.dispose();
  });

  test('vehicle suspension applies equal reaction to dynamic surfaces', () {
    final world = GlintBox3dWorld(
      gravity: Vector3.zero,
      fixedTimeStep: 1 / 120,
    );
    final platform = world.createBody(const GlintRigidBodyConfig());
    platform.addCollider(
      const GlintBoxCollider(Vector3(3, .1, 3)),
      material: const GlintPhysicsMaterial(density: 500),
    );
    final chassis = world.createBody(
      const GlintRigidBodyConfig(position: Vector3(0, .5, 0)),
    );
    chassis.addCollider(
      const GlintSphereCollider(.05),
      material: const GlintPhysicsMaterial(density: 100),
    );
    final vehicle = GlintRaycastVehicle(
      world: world,
      chassis: chassis,
      config: const GlintVehicleConfig(
        wheels: [
          GlintVehicleWheel(name: 'support', mount: Vector3.zero, axle: 0),
        ],
      ),
    );

    world.step(1 / 120);

    expect(chassis.linearVelocity.y, greaterThan(0));
    expect(platform.linearVelocity.y, lessThan(0));
    vehicle.dispose();
    world.dispose();
  });

  test('vehicle configuration rejects a non-dynamic chassis', () {
    final world = GlintBox3dWorld(gravity: Vector3.zero);
    final chassis = world.createBody(
      const GlintRigidBodyConfig(type: GlintBodyType.static),
    );

    expect(
      () => GlintRaycastVehicle(
        world: world,
        chassis: chassis,
        config: const GlintVehicleConfig(
          wheels: [
            GlintVehicleWheel(name: 'wheel', mount: Vector3.zero, axle: 0),
          ],
        ),
      ),
      throwsArgumentError,
    );
    world.dispose();
  });

  test('fixed-step input tape replays native body motion', () {
    final world = GlintBox3dWorld(
      gravity: Vector3.zero,
      fixedTimeStep: 1 / 120,
    );
    final body = world.createBody(const GlintRigidBodyConfig());
    body.addCollider(
      const GlintSphereCollider(.25),
      material: const GlintPhysicsMaterial(density: 20),
    );
    void apply(Vector3 impulse, double _) => body.applyImpulse(impulse);
    final recorder = GlintPhysicsReplayRecorder<Vector3>(
      world: world,
      applyInput: apply,
      digestQuantization: 1e-5,
    );
    for (final impulse in const [
      Vector3(1, 0, 0),
      Vector3(0, 2, 0),
      Vector3(0, 0, -1),
      Vector3(-.5, 0, .25),
    ]) {
      recorder.record(impulse);
    }

    final result = recorder.finish().play(world, apply);

    expect(result.deterministic, isTrue);
    world.dispose();
  });

  test('backend-neutral stress arena stays finite under mixed load', () async {
    final world = GlintBox3dWorld(fixedTimeStep: 1 / 120);

    final result = await GlintPhysicsStressRunner(
      world: world,
      config: const GlintPhysicsStressConfig(
        bodyCount: 32,
        vehicleCount: 1,
        steps: 120,
        queriesPerStep: 2,
        arenaHalfExtent: 16,
      ),
    ).run();

    expect(result.passed, isTrue, reason: '$result');
    expect(result.dynamicBodyCount, 33);
    expect(result.queryCount, 240);
    expect(result.queryHits, greaterThan(0));
    expect(result.contactEvents, greaterThan(0));
    world.dispose();
  });
}
