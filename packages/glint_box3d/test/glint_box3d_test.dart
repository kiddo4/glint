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
    ground.addCollider(
      const GlintBoxCollider(Vector3(10, .5, 10)),
      localPosition: const Vector3(0, -.5, 0),
    );
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
    final startZ = chassis.position.z;
    vehicle.throttle = 1;
    for (var i = 0; i < 360; i++) {
      world.step(1 / 120);
    }
    expect(chassis.position.z, lessThan(startZ - 1));
    expect(vehicle.speedKilometersPerHour, greaterThan(1));
    expect(vehicle.engineRpm, greaterThanOrEqualTo(900));
    vehicle.dispose();
    world.dispose();
  });
}
