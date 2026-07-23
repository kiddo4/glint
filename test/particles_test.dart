import 'package:flutter_test/flutter_test.dart';
import 'package:glint_engine/glint_engine.dart';

void main() {
  test('seeded particle systems simulate deterministically', () {
    const config = GlintParticleConfig(
      maxParticles: 32,
      emissionRate: 12,
      lifetime: GlintDoubleRange(1, 2),
      startSpeed: GlintDoubleRange(2, 4),
      shape: GlintConeParticleShape(angle: .4, baseRadius: .2),
      gravity: Vector3(0, -9.81, 0),
      drag: .1,
      noise: GlintParticleNoise(strength: 2, frequency: 1.5),
    );
    final a = GlintParticleSystem(config, seed: 42);
    final b = GlintParticleSystem(config, seed: 42);

    for (var i = 0; i < 60; i++) {
      a.update(1 / 60);
      b.update(1 / 60);
    }

    expect(a.particleCount, b.particleCount);
    expect(
      a.renderBatch.positions.take(a.particleCount * 3),
      b.renderBatch.positions.take(b.particleCount * 3),
    );
  });

  test(
    'bursts, curves, gradients, and sprite animation feed render batches',
    () {
      final system = GlintParticleSystem(
        const GlintParticleConfig(
          maxParticles: 8,
          emissionRate: 0,
          bursts: [GlintParticleBurst(time: 0, count: 3)],
          lifetime: GlintDoubleRange.constant(2),
          startSize: GlintDoubleRange.constant(2),
          sizeOverLifetime: GlintScalarCurve([
            GlintScalarKey(0, 1),
            GlintScalarKey(1, 0),
          ]),
          colorOverLifetime: GlintParticleGradient([
            GlintParticleColorKey(0, GlintParticleColor.white),
            GlintParticleColorKey(1, GlintParticleColor.transparent),
          ]),
          spriteSheet: GlintParticleSpriteSheet(columns: 4, rows: 2),
        ),
        seed: 7,
      );

      system.update(.01);
      system.update(.99);
      final batch = system.renderBatch;

      expect(batch.count, 3);
      expect(batch.size(0), closeTo(1, .02));
      expect(batch.color(0).a, closeTo(.5, .02));
      expect(batch.spriteFrame(0), inInclusiveRange(3, 4));
    },
  );

  test('physics-independent collision resolver can bounce particles', () {
    final collisions = <GlintParticleEvent>[];
    final system = GlintParticleSystem(
      const GlintParticleConfig(
        maxParticles: 1,
        emissionRate: 0,
        lifetime: GlintDoubleRange.constant(2),
        startSpeed: GlintDoubleRange.constant(4),
        shape: GlintPointParticleShape(direction: Vector3(0, -1, 0)),
        collisionBounce: 1,
        collisionFriction: 0,
      ),
      onEvent: collisions.add,
    )..emit(1);

    system.update(.5, collisions: const _GroundResolver());
    system.update(.1);

    expect(
      collisions.any((event) => event.type == GlintParticleEventType.collision),
      isTrue,
    );
    expect(system.renderBatch.worldPosition(0).y, greaterThan(0));
  });

  test('local simulation follows its emitter transform at render time', () {
    final system = GlintParticleSystem(
      const GlintParticleConfig(
        maxParticles: 1,
        emissionRate: 0,
        simulationSpace: GlintParticleSimulationSpace.local,
      ),
      transform: const Transform3D(position: Vector3(1, 0, 0)),
    )..emit(1, position: Vector3.zero, velocity: Vector3.zero);
    system.transform = const Transform3D(position: Vector3(5, 0, 0));

    expect(system.renderBatch.worldPosition(0), const Vector3(5, 0, 0));
  });

  test('local-space collision traces and responses use world space', () {
    final resolver = _RecordingPlaneResolver(planeY: 9.5);
    final system = GlintParticleSystem(
      const GlintParticleConfig(
        maxParticles: 1,
        emissionRate: 0,
        lifetime: GlintDoubleRange.constant(2),
        simulationSpace: GlintParticleSimulationSpace.local,
        collisionBounce: 1,
        collisionFriction: 0,
      ),
      transform: const Transform3D(position: Vector3(0, 10, 0)),
    )..emit(1, position: Vector3.zero, velocity: const Vector3(0, -4, 0));

    system.update(.25, collisions: resolver);

    expect(resolver.firstTraceFrom?.y, closeTo(10, 1e-6));
    expect(system.renderBatch.worldPosition(0).y, greaterThan(9.5));
  });
}

class _GroundResolver implements GlintParticleCollisionResolver {
  const _GroundResolver();

  @override
  GlintParticleCollision? trace(Vector3 from, Vector3 to) {
    if (from.y >= 0 && to.y < 0) {
      return const GlintParticleCollision(
        position: Vector3.zero,
        normal: Vector3(0, 1, 0),
      );
    }
    return null;
  }
}

class _RecordingPlaneResolver implements GlintParticleCollisionResolver {
  _RecordingPlaneResolver({required this.planeY});

  final double planeY;
  Vector3? firstTraceFrom;

  @override
  GlintParticleCollision? trace(Vector3 from, Vector3 to) {
    firstTraceFrom ??= from;
    if (from.y >= planeY && to.y < planeY) {
      return GlintParticleCollision(
        position: Vector3(0, planeY, 0),
        normal: const Vector3(0, 1, 0),
      );
    }
    return null;
  }
}
