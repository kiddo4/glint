import 'dart:async';
import 'dart:math' as math;

import 'math.dart';
import 'physics.dart';
import 'physics_replay.dart';
import 'physics_vehicle.dart';

class GlintPhysicsStressConfig {
  const GlintPhysicsStressConfig({
    this.bodyCount = 256,
    this.vehicleCount = 1,
    this.steps = 600,
    this.queriesPerStep = 4,
    this.seed = 0x5eed,
    this.arenaHalfExtent = 32,
    this.minimumRealTimeFactor = 0,
  });

  final int bodyCount;
  final int vehicleCount;
  final int steps;
  final int queriesPerStep;
  final int seed;
  final double arenaHalfExtent;

  /// Optional machine-specific threshold. Zero keeps correctness checks only.
  final double minimumRealTimeFactor;
}

class GlintPhysicsStressResult {
  const GlintPhysicsStressResult({
    required this.backendName,
    required this.dynamicBodyCount,
    required this.vehicleCount,
    required this.steps,
    required this.simulatedDuration,
    required this.elapsed,
    required this.queryCount,
    required this.queryHits,
    required this.contactEvents,
    required this.sleepingBodies,
    required this.nonFiniteBodies,
    required this.escapedBodies,
    required this.minimumRealTimeFactor,
    required this.digest,
  });

  final String backendName;
  final int dynamicBodyCount;
  final int vehicleCount;
  final int steps;
  final double simulatedDuration;
  final Duration elapsed;
  final int queryCount;
  final int queryHits;
  final int contactEvents;
  final int sleepingBodies;
  final int nonFiniteBodies;
  final int escapedBodies;
  final double minimumRealTimeFactor;
  final GlintPhysicsStateDigest digest;

  double get elapsedSeconds => elapsed.inMicroseconds / 1000000;
  double get stepsPerSecond => elapsedSeconds == 0 ? 0 : steps / elapsedSeconds;
  double get realTimeFactor =>
      elapsedSeconds == 0 ? 0 : simulatedDuration / elapsedSeconds;
  bool get passed =>
      nonFiniteBodies == 0 &&
      escapedBodies == 0 &&
      realTimeFactor >= minimumRealTimeFactor;

  Map<String, Object?> toJson() => {
    'backend': backendName,
    'passed': passed,
    'dynamicBodies': dynamicBodyCount,
    'vehicles': vehicleCount,
    'steps': steps,
    'simulatedSeconds': simulatedDuration,
    'elapsedMilliseconds': elapsed.inMicroseconds / 1000,
    'stepsPerSecond': stepsPerSecond,
    'realTimeFactor': realTimeFactor,
    'queries': queryCount,
    'queryHits': queryHits,
    'contactEvents': contactEvents,
    'sleepingBodies': sleepingBodies,
    'nonFiniteBodies': nonFiniteBodies,
    'escapedBodies': escapedBodies,
    'digest': digest.toJson(),
  };

  @override
  String toString() =>
      '$backendName: ${passed ? 'PASS' : 'FAIL'}, $dynamicBodyCount bodies, '
      '$vehicleCount vehicles, ${realTimeFactor.toStringAsFixed(1)}x realtime, '
      '$queryCount queries, $contactEvents contact events';
}

/// Builds and measures a repeatable, backend-neutral rigid-body arena.
///
/// The world must be empty so body order and the resulting state digest stay
/// reproducible. The scenario combines four collider families, dense contact
/// stacks, impulses, ray/overlap/shape queries, and optional raycast vehicles.
class GlintPhysicsStressRunner {
  GlintPhysicsStressRunner({
    required this.world,
    this.config = const GlintPhysicsStressConfig(),
  }) {
    _validateConfig();
  }

  final GlintPhysicsWorld world;
  final GlintPhysicsStressConfig config;

  void _validateConfig() {
    if (config.bodyCount < 0 ||
        config.vehicleCount < 0 ||
        config.steps <= 0 ||
        config.queriesPerStep < 0 ||
        !config.arenaHalfExtent.isFinite ||
        config.arenaHalfExtent <= 4 ||
        !config.minimumRealTimeFactor.isFinite ||
        config.minimumRealTimeFactor < 0) {
      throw ArgumentError.value(config, 'config', 'contains invalid values');
    }
  }

  Future<GlintPhysicsStressResult> run() async {
    if (world.bodies.isNotEmpty) {
      throw StateError('Physics stress runner requires an empty world.');
    }
    var contactEvents = 0;
    final collisionSubscription = world.collisions.listen((event) {
      if (event is GlintContactBegan) contactEvents++;
    });
    final random = _GlintStressRandom(config.seed);
    _buildArena(random);
    final vehicles = _buildVehicles();
    final dynamicBodies = world.bodies
        .where((body) => body.type == GlintBodyType.dynamic)
        .toList(growable: false);
    var queryCount = 0;
    var queryHits = 0;

    final stopwatch = Stopwatch()..start();
    for (var step = 0; step < config.steps; step++) {
      for (var i = 0; i < vehicles.length; i++) {
        vehicles[i]
          ..throttle = step < config.steps * .8 ? 1 : 0
          ..steer = math.sin(step * .025 + i) * .7
          ..handbrake = step % 240 > 205 ? .65 : 0
          ..boost = step % 300 > 255;
      }
      if (dynamicBodies.isNotEmpty && step % 90 == 0) {
        final body = dynamicBodies[random.nextInt(dynamicBodies.length)];
        body.applyImpulse(
          Vector3(
            random.nextSigned() * 5,
            3 + random.nextDouble() * 5,
            random.nextSigned() * 5,
          ),
          atWorldPoint: body.position + const Vector3(.2, .3, -.15),
        );
      }
      for (var query = 0; query < config.queriesPerStep; query++) {
        final x = random.nextSigned() * config.arenaHalfExtent * .8;
        final z = random.nextSigned() * config.arenaHalfExtent * .8;
        switch ((step + query) % 3) {
          case 0:
            queryHits +=
                world.raycast(
                      GlintRay(Vector3(x, 18, z), const Vector3(0, -1, 0)),
                      maxDistance: 36,
                    ) ==
                    null
                ? 0
                : 1;
          case 1:
            queryHits += world.overlapSphere(Vector3(x, 1.5, z), 2.5).length;
          case 2:
            queryHits +=
                world.shapeCast(
                      const GlintSphereCollider(.35),
                      Vector3(x, 8, z),
                      const Vector3(0, -1, 0),
                      maxDistance: 16,
                    ) ==
                    null
                ? 0
                : 1;
        }
        queryCount++;
      }
      world.stepFixed();
    }
    stopwatch.stop();
    for (final vehicle in vehicles) {
      vehicle.dispose();
    }
    await Future<void>.delayed(Duration.zero);
    await collisionSubscription.cancel();

    var nonFiniteBodies = 0;
    var escapedBodies = 0;
    var sleepingBodies = 0;
    final escapeLimit = config.arenaHalfExtent * 4;
    for (final body in dynamicBodies) {
      if (!_finite(body.position) ||
          !_finite(body.linearVelocity) ||
          !_finite(body.angularVelocity) ||
          !_finiteQuaternion(body.orientation)) {
        nonFiniteBodies++;
      }
      final position = body.position;
      if (position.x.abs() > escapeLimit ||
          position.z.abs() > escapeLimit ||
          position.y < -20 ||
          position.y > escapeLimit) {
        escapedBodies++;
      }
      if (body.isSleeping) sleepingBodies++;
    }
    return GlintPhysicsStressResult(
      backendName: world.backendName,
      dynamicBodyCount: dynamicBodies.length,
      vehicleCount: vehicles.length,
      steps: config.steps,
      simulatedDuration: config.steps * world.fixedTimeStep,
      elapsed: stopwatch.elapsed,
      queryCount: queryCount,
      queryHits: queryHits,
      contactEvents: contactEvents,
      sleepingBodies: sleepingBodies,
      nonFiniteBodies: nonFiniteBodies,
      escapedBodies: escapedBodies,
      minimumRealTimeFactor: config.minimumRealTimeFactor,
      digest: world.stateDigest(),
    );
  }

  void _buildArena(_GlintStressRandom random) {
    final extent = config.arenaHalfExtent;
    final arena = world.createBody(
      const GlintRigidBodyConfig(type: GlintBodyType.static),
    );
    arena.addCollider(
      GlintBoxCollider(Vector3(extent, .5, extent)),
      localPosition: const Vector3(0, -.5, 0),
      material: const GlintPhysicsMaterial(friction: .9),
    );
    for (final (position, size) in [
      (Vector3(-extent, 2, 0), Vector3(.5, 2, extent)),
      (Vector3(extent, 2, 0), Vector3(.5, 2, extent)),
      (Vector3(0, 2, -extent), Vector3(extent, 2, .5)),
      (Vector3(0, 2, extent), Vector3(extent, 2, .5)),
    ]) {
      arena.addCollider(
        GlintBoxCollider(size),
        localPosition: position,
        material: const GlintPhysicsMaterial(friction: .7),
      );
    }

    final width = math.max(1, math.min(12, math.sqrt(config.bodyCount).ceil()));
    final layerSize = width * width;
    for (var i = 0; i < config.bodyCount; i++) {
      final column = i % width;
      final row = (i ~/ width) % width;
      final layer = i ~/ layerSize;
      final position = Vector3(
        (column - (width - 1) / 2) * 1.15 + random.nextSigned() * .025,
        .65 + layer * 1.15,
        (row - (width - 1) / 2) * 1.15 + random.nextSigned() * .025,
      );
      final body = world.createBody(
        GlintRigidBodyConfig(
          position: position,
          orientation: GlintQuaternion.axisAngle(
            const Vector3(0, 1, 0),
            random.nextSigned() * .08,
          ),
          angularDamping: .03,
          ccdEnabled: i % 17 == 0,
        ),
      );
      final collider = switch (i % 4) {
        0 => const GlintBoxCollider(Vector3(.48, .48, .48)),
        1 => const GlintSphereCollider(.5),
        2 => const GlintCapsuleCollider(radius: .3, halfHeight: .28),
        _ => const GlintCylinderCollider(radius: .42, halfHeight: .48),
      };
      body.addCollider(
        collider,
        material: GlintPhysicsMaterial(
          density: 15 + random.nextDouble() * 30,
          friction: .35 + random.nextDouble() * .55,
          restitution: i % 11 == 0 ? .35 : .04,
        ),
      );
    }
  }

  List<GlintRaycastVehicle> _buildVehicles() {
    final vehicles = <GlintRaycastVehicle>[];
    for (var i = 0; i < config.vehicleCount; i++) {
      final chassis = world.createBody(
        GlintRigidBodyConfig(
          position: Vector3(
            -config.arenaHalfExtent * .65 + i * 3.2,
            .9,
            config.arenaHalfExtent * .55,
          ),
          angularDamping: .18,
          ccdEnabled: true,
        ),
      );
      chassis.addCollider(
        const GlintBoxCollider(Vector3(.82, .24, 1.35)),
        material: const GlintPhysicsMaterial(density: 320, friction: .45),
      );
      vehicles.add(
        GlintRaycastVehicle(
          world: world,
          chassis: chassis,
          config: const GlintVehicleConfig(
            wheels: [
              GlintVehicleWheel(
                name: 'front-left',
                mount: Vector3(-.68, -.08, -1),
                axle: 0,
                powered: true,
                steered: true,
              ),
              GlintVehicleWheel(
                name: 'front-right',
                mount: Vector3(.68, -.08, -1),
                axle: 0,
                powered: true,
                steered: true,
              ),
              GlintVehicleWheel(
                name: 'rear-left',
                mount: Vector3(-.68, -.08, 1),
                axle: 1,
                powered: true,
                handbrake: true,
              ),
              GlintVehicleWheel(
                name: 'rear-right',
                mount: Vector3(.68, -.08, 1),
                axle: 1,
                powered: true,
                handbrake: true,
              ),
            ],
          ),
        ),
      );
    }
    return vehicles;
  }
}

class _GlintStressRandom {
  _GlintStressRandom(int seed) : _state = seed & 0xffffffff;

  int _state;

  int _next() {
    _state = (1664525 * _state + 1013904223) & 0xffffffff;
    return _state;
  }

  double nextDouble() => _next() / 0x100000000;
  double nextSigned() => nextDouble() * 2 - 1;
  int nextInt(int maximum) => _next() % maximum;
}

bool _finite(Vector3 value) =>
    value.x.isFinite && value.y.isFinite && value.z.isFinite;

bool _finiteQuaternion(GlintQuaternion value) =>
    value.x.isFinite &&
    value.y.isFinite &&
    value.z.isFinite &&
    value.w.isFinite;
