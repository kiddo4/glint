import 'dart:math' as math;
import 'dart:typed_data';

import 'math.dart';
import 'physics.dart';

enum GlintParticleSimulationSpace { local, world }

enum GlintParticleBlendMode { alpha, additive }

enum GlintParticleSortMode { none, backToFront }

class GlintDoubleRange {
  const GlintDoubleRange(this.minimum, this.maximum);
  const GlintDoubleRange.constant(double value) : this(value, value);

  final double minimum;
  final double maximum;

  double sample(GlintParticleRandom random) =>
      minimum + (maximum - minimum) * random.nextDouble();

  void validate(
    String name, {
    bool positive = false,
    bool nonNegative = false,
  }) {
    if (!minimum.isFinite || !maximum.isFinite || maximum < minimum) {
      throw ArgumentError.value(this, name, 'must be a finite ordered range');
    }
    if (positive && minimum <= 0) {
      throw ArgumentError.value(this, name, 'must contain positive values');
    }
    if (nonNegative && minimum < 0) {
      throw ArgumentError.value(this, name, 'must contain values >= 0');
    }
  }
}

class GlintParticleColor {
  const GlintParticleColor(this.r, this.g, this.b, [this.a = 1]);

  static const white = GlintParticleColor(1, 1, 1, 1);
  static const transparent = GlintParticleColor(1, 1, 1, 0);

  final double r;
  final double g;
  final double b;
  final double a;

  GlintParticleColor operator *(GlintParticleColor other) =>
      GlintParticleColor(r * other.r, g * other.g, b * other.b, a * other.a);

  static GlintParticleColor lerp(
    GlintParticleColor from,
    GlintParticleColor to,
    double t,
  ) => GlintParticleColor(
    from.r + (to.r - from.r) * t,
    from.g + (to.g - from.g) * t,
    from.b + (to.b - from.b) * t,
    from.a + (to.a - from.a) * t,
  );

  void validate(String name) {
    if (![r, g, b, a].every((value) => value.isFinite && value >= 0)) {
      throw ArgumentError.value(this, name, 'channels must be finite and >= 0');
    }
  }
}

class GlintParticleColorRange {
  const GlintParticleColorRange(this.minimum, this.maximum);
  const GlintParticleColorRange.constant(GlintParticleColor value)
    : this(value, value);

  final GlintParticleColor minimum;
  final GlintParticleColor maximum;

  GlintParticleColor sample(GlintParticleRandom random) =>
      GlintParticleColor.lerp(minimum, maximum, random.nextDouble());

  void validate(String name) {
    minimum.validate('$name.minimum');
    maximum.validate('$name.maximum');
    if (maximum.r < minimum.r ||
        maximum.g < minimum.g ||
        maximum.b < minimum.b ||
        maximum.a < minimum.a) {
      throw ArgumentError.value(
        this,
        name,
        'maximum channels must be >= minimum channels',
      );
    }
  }
}

class GlintScalarKey {
  const GlintScalarKey(this.time, this.value);
  final double time;
  final double value;
}

class GlintScalarCurve {
  const GlintScalarCurve(this.keys);

  static const one = GlintScalarCurve([
    GlintScalarKey(0, 1),
    GlintScalarKey(1, 1),
  ]);

  final List<GlintScalarKey> keys;

  double evaluate(double time) {
    final t = time.clamp(0.0, 1.0);
    if (keys.isEmpty) return 1;
    if (t <= keys.first.time) return keys.first.value;
    for (var i = 1; i < keys.length; i++) {
      final next = keys[i];
      if (t <= next.time) {
        final previous = keys[i - 1];
        final span = next.time - previous.time;
        final local = span == 0 ? 1.0 : (t - previous.time) / span;
        return previous.value + (next.value - previous.value) * local;
      }
    }
    return keys.last.value;
  }

  void validate(String name) {
    if (keys.isEmpty) {
      throw ArgumentError.value(keys, name, 'must contain at least one key');
    }
    var previous = -double.infinity;
    for (final key in keys) {
      if (!key.time.isFinite ||
          key.time < 0 ||
          key.time > 1 ||
          key.time < previous ||
          !key.value.isFinite) {
        throw ArgumentError.value(
          keys,
          name,
          'keys must be finite, ordered, and timed from 0 to 1',
        );
      }
      previous = key.time;
    }
  }
}

class GlintParticleColorKey {
  const GlintParticleColorKey(this.time, this.color);
  final double time;
  final GlintParticleColor color;
}

class GlintParticleGradient {
  const GlintParticleGradient(this.keys);

  static const white = GlintParticleGradient([
    GlintParticleColorKey(0, GlintParticleColor.white),
    GlintParticleColorKey(1, GlintParticleColor.white),
  ]);

  final List<GlintParticleColorKey> keys;

  GlintParticleColor evaluate(double time) {
    final t = time.clamp(0.0, 1.0);
    if (keys.isEmpty) return GlintParticleColor.white;
    if (t <= keys.first.time) return keys.first.color;
    for (var i = 1; i < keys.length; i++) {
      final next = keys[i];
      if (t <= next.time) {
        final previous = keys[i - 1];
        final span = next.time - previous.time;
        return GlintParticleColor.lerp(
          previous.color,
          next.color,
          span == 0 ? 1 : (t - previous.time) / span,
        );
      }
    }
    return keys.last.color;
  }

  void validate(String name) {
    if (keys.isEmpty) {
      throw ArgumentError.value(keys, name, 'must contain at least one key');
    }
    var previous = -double.infinity;
    for (final key in keys) {
      key.color.validate('$name.color');
      if (!key.time.isFinite ||
          key.time < 0 ||
          key.time > 1 ||
          key.time < previous) {
        throw ArgumentError.value(
          keys,
          name,
          'keys must be ordered and timed from 0 to 1',
        );
      }
      previous = key.time;
    }
  }
}

class GlintParticleBurst {
  const GlintParticleBurst({
    required this.time,
    required this.count,
    this.cycles = 1,
    this.interval = 0,
  });

  final double time;
  final int count;
  final int cycles;
  final double interval;

  void validate(double duration) {
    if (!time.isFinite || time < 0 || time > duration) {
      throw ArgumentError.value(time, 'time', 'must fall within duration');
    }
    if (count <= 0 || cycles <= 0) {
      throw ArgumentError('Particle burst count and cycles must be positive.');
    }
    if (!interval.isFinite || interval < 0) {
      throw ArgumentError.value(
        interval,
        'interval',
        'must be finite and >= 0',
      );
    }
    if (time + interval * (cycles - 1) > duration) {
      throw ArgumentError('Particle burst cycles extend beyond duration.');
    }
  }
}

class GlintParticleSpriteSheet {
  const GlintParticleSpriteSheet({
    required this.columns,
    required this.rows,
    this.frameOverLifetime = const GlintScalarCurve([
      GlintScalarKey(0, 0),
      GlintScalarKey(1, 1),
    ]),
    this.cycles = 1,
    this.randomStartFrame = false,
  });

  final int columns;
  final int rows;
  final GlintScalarCurve frameOverLifetime;
  final double cycles;
  final bool randomStartFrame;

  int get frameCount => columns * rows;

  void validate() {
    if (columns <= 0 || rows <= 0) {
      throw ArgumentError('Sprite-sheet columns and rows must be positive.');
    }
    if (!cycles.isFinite || cycles <= 0) {
      throw ArgumentError.value(
        cycles,
        'cycles',
        'must be finite and positive',
      );
    }
    frameOverLifetime.validate('frameOverLifetime');
  }
}

class GlintParticleNoise {
  const GlintParticleNoise({
    this.strength = 0,
    this.frequency = 1,
    this.scrollSpeed = 0,
  });

  final double strength;
  final double frequency;
  final double scrollSpeed;

  void validate() {
    if (![strength, frequency, scrollSpeed].every((value) => value.isFinite) ||
        strength < 0 ||
        frequency <= 0) {
      throw ArgumentError('Particle noise values are invalid.');
    }
  }
}

sealed class GlintParticleShape {
  const GlintParticleShape();

  (Vector3, Vector3) sample(GlintParticleRandom random);
  void validate();
}

class GlintPointParticleShape extends GlintParticleShape {
  const GlintPointParticleShape({
    this.direction = const Vector3(0, 1, 0),
    this.spread = 0,
  });

  final Vector3 direction;
  final double spread;

  @override
  (Vector3, Vector3) sample(GlintParticleRandom random) =>
      (Vector3.zero, _spreadDirection(direction, spread, random));

  @override
  void validate() {
    _validateDirection(direction);
    _validateAngle(spread, 'spread');
  }
}

class GlintBoxParticleShape extends GlintParticleShape {
  const GlintBoxParticleShape({
    required this.halfExtents,
    this.direction = const Vector3(0, 1, 0),
    this.spread = 0,
  });

  final Vector3 halfExtents;
  final Vector3 direction;
  final double spread;

  @override
  (Vector3, Vector3) sample(GlintParticleRandom random) => (
    Vector3(
      random.signed() * halfExtents.x,
      random.signed() * halfExtents.y,
      random.signed() * halfExtents.z,
    ),
    _spreadDirection(direction, spread, random),
  );

  @override
  void validate() {
    if (!_isFiniteVector(halfExtents) ||
        halfExtents.x < 0 ||
        halfExtents.y < 0 ||
        halfExtents.z < 0) {
      throw ArgumentError.value(halfExtents, 'halfExtents', 'must be >= 0');
    }
    _validateDirection(direction);
    _validateAngle(spread, 'spread');
  }
}

class GlintSphereParticleShape extends GlintParticleShape {
  const GlintSphereParticleShape({this.radius = 1, this.fromShell = false});

  final double radius;
  final bool fromShell;

  @override
  (Vector3, Vector3) sample(GlintParticleRandom random) {
    final direction = _randomUnitVector(random);
    final distance = fromShell
        ? radius
        : radius * math.pow(random.nextDouble(), 1 / 3);
    return (direction * distance.toDouble(), direction);
  }

  @override
  void validate() {
    if (!radius.isFinite || radius < 0) {
      throw ArgumentError.value(radius, 'radius', 'must be finite and >= 0');
    }
  }
}

class GlintConeParticleShape extends GlintParticleShape {
  const GlintConeParticleShape({
    this.direction = const Vector3(0, 1, 0),
    this.angle = math.pi / 8,
    this.baseRadius = 0,
  });

  final Vector3 direction;
  final double angle;
  final double baseRadius;

  @override
  (Vector3, Vector3) sample(GlintParticleRandom random) {
    final axis = direction.normalized;
    final emitted = _spreadDirection(axis, angle, random);
    final tangent = _orthogonal(axis);
    final bitangent = axis.cross(tangent).normalized;
    final radius = baseRadius * math.sqrt(random.nextDouble());
    final azimuth = random.nextDouble() * math.pi * 2;
    return (
      tangent * (math.cos(azimuth) * radius) +
          bitangent * (math.sin(azimuth) * radius),
      emitted,
    );
  }

  @override
  void validate() {
    _validateDirection(direction);
    _validateAngle(angle, 'angle');
    if (!baseRadius.isFinite || baseRadius < 0) {
      throw ArgumentError.value(
        baseRadius,
        'baseRadius',
        'must be finite and >= 0',
      );
    }
  }
}

class GlintParticleConfig {
  const GlintParticleConfig({
    this.maxParticles = 1024,
    this.duration = 5,
    this.looping = true,
    this.emissionRate = 10,
    this.bursts = const [],
    this.lifetime = const GlintDoubleRange.constant(1),
    this.startSpeed = const GlintDoubleRange.constant(1),
    this.startSize = const GlintDoubleRange.constant(1),
    this.startRotation = const GlintDoubleRange.constant(0),
    this.angularVelocity = const GlintDoubleRange.constant(0),
    this.startColor = const GlintParticleColorRange.constant(
      GlintParticleColor.white,
    ),
    this.colorOverLifetime = GlintParticleGradient.white,
    this.sizeOverLifetime = GlintScalarCurve.one,
    this.gravity = Vector3.zero,
    this.drag = 0,
    this.noise = const GlintParticleNoise(),
    this.shape = const GlintPointParticleShape(),
    this.simulationSpace = GlintParticleSimulationSpace.world,
    this.blendMode = GlintParticleBlendMode.alpha,
    this.sortMode = GlintParticleSortMode.backToFront,
    this.texture,
    this.spriteSheet,
    this.collisionBounce = .35,
    this.collisionFriction = .15,
    this.killOnCollision = false,
  });

  final int maxParticles;
  final double duration;
  final bool looping;
  final double emissionRate;
  final List<GlintParticleBurst> bursts;
  final GlintDoubleRange lifetime;
  final GlintDoubleRange startSpeed;
  final GlintDoubleRange startSize;
  final GlintDoubleRange startRotation;
  final GlintDoubleRange angularVelocity;
  final GlintParticleColorRange startColor;
  final GlintParticleGradient colorOverLifetime;
  final GlintScalarCurve sizeOverLifetime;
  final Vector3 gravity;
  final double drag;
  final GlintParticleNoise noise;
  final GlintParticleShape shape;
  final GlintParticleSimulationSpace simulationSpace;
  final GlintParticleBlendMode blendMode;
  final GlintParticleSortMode sortMode;

  /// Key into `GlintGameView.particleTextures`, or null for a white texel.
  final String? texture;

  final GlintParticleSpriteSheet? spriteSheet;
  final double collisionBounce;
  final double collisionFriction;
  final bool killOnCollision;

  void validate() {
    if (maxParticles <= 0) {
      throw ArgumentError.value(
        maxParticles,
        'maxParticles',
        'must be positive',
      );
    }
    if (!duration.isFinite || duration <= 0) {
      throw ArgumentError.value(duration, 'duration', 'must be positive');
    }
    if (!emissionRate.isFinite || emissionRate < 0) {
      throw ArgumentError.value(
        emissionRate,
        'emissionRate',
        'must be finite and >= 0',
      );
    }
    for (final burst in bursts) {
      burst.validate(duration);
    }
    lifetime.validate('lifetime', positive: true);
    startSpeed.validate('startSpeed');
    startSize.validate('startSize', nonNegative: true);
    startRotation.validate('startRotation');
    angularVelocity.validate('angularVelocity');
    startColor.validate('startColor');
    colorOverLifetime.validate('colorOverLifetime');
    sizeOverLifetime.validate('sizeOverLifetime');
    if (!_isFiniteVector(gravity)) {
      throw ArgumentError.value(gravity, 'gravity', 'must be finite');
    }
    if (!drag.isFinite || drag < 0) {
      throw ArgumentError.value(drag, 'drag', 'must be finite and >= 0');
    }
    noise.validate();
    shape.validate();
    spriteSheet?.validate();
    if (!collisionBounce.isFinite || collisionBounce < 0) {
      throw ArgumentError.value(collisionBounce, 'collisionBounce');
    }
    if (!collisionFriction.isFinite ||
        collisionFriction < 0 ||
        collisionFriction > 1) {
      throw ArgumentError.value(
        collisionFriction,
        'collisionFriction',
        'must be between 0 and 1',
      );
    }
  }
}

class GlintParticleCollision {
  const GlintParticleCollision({required this.position, required this.normal});
  final Vector3 position;
  final Vector3 normal;
}

abstract interface class GlintParticleCollisionResolver {
  GlintParticleCollision? trace(Vector3 from, Vector3 to);
}

/// Physics-world adapter for particle collision. It deliberately uses the
/// public query API, so every Glint physics backend gets particle collisions.
class GlintPhysicsParticleCollisionResolver
    implements GlintParticleCollisionResolver {
  const GlintPhysicsParticleCollisionResolver(
    this.world, {
    this.filter = const GlintQueryFilter(),
  });

  final GlintPhysicsWorld world;
  final GlintQueryFilter filter;

  @override
  GlintParticleCollision? trace(Vector3 from, Vector3 to) {
    final delta = to - from;
    final distance = delta.length;
    if (distance == 0) return null;
    final hit = world.raycast(
      GlintRay(from, delta * (1 / distance)),
      maxDistance: distance,
      filter: filter,
    );
    return hit == null
        ? null
        : GlintParticleCollision(position: hit.position, normal: hit.normal);
  }
}

enum GlintParticleEventType { collision, death }

class GlintParticleEvent {
  const GlintParticleEvent({
    required this.type,
    required this.position,
    required this.velocity,
  });

  final GlintParticleEventType type;

  /// World-space position at the event.
  final Vector3 position;

  /// World-space velocity at the event.
  final Vector3 velocity;
}

typedef GlintParticleEventCallback = void Function(GlintParticleEvent event);

/// Deterministic xorshift generator used instead of the SDK's Random so replay
/// recordings keep the same particle stream across platforms.
class GlintParticleRandom {
  GlintParticleRandom(int seed) : _state = seed == 0 ? 0x6d2b79f5 : seed;

  int _state;

  int nextUint32() {
    var value = _state & 0xffffffff;
    value ^= (value << 13) & 0xffffffff;
    value ^= value >>> 17;
    value ^= (value << 5) & 0xffffffff;
    _state = value & 0xffffffff;
    return _state;
  }

  double nextDouble() => nextUint32() / 0x100000000;
  double signed() => nextDouble() * 2 - 1;
}

/// Pooled particle simulation. All live state is stored in dense typed arrays;
/// dead particles are removed by swapping with the last live slot.
class GlintParticleSystem {
  GlintParticleSystem(
    this.config, {
    int seed = 1,
    Transform3D transform = const Transform3D(),
    this.onEvent,
    bool initiallyPlaying = true,
  }) : _random = GlintParticleRandom(seed),
       _transform = transform,
       _playing = initiallyPlaying,
       _positions = Float32List(config.maxParticles * 3),
       _velocities = Float32List(config.maxParticles * 3),
       _ages = Float32List(config.maxParticles),
       _lifetimes = Float32List(config.maxParticles),
       _sizes = Float32List(config.maxParticles),
       _rotations = Float32List(config.maxParticles),
       _angularVelocities = Float32List(config.maxParticles),
       _colors = Float32List(config.maxParticles * 4),
       _startFrames = Uint32List(config.maxParticles),
       _burstCycles = Uint32List(config.bursts.length) {
    config.validate();
    _validateParticleTransform(transform);
    _renderBatch = GlintParticleRenderBatch._(this);
  }

  final GlintParticleConfig config;
  final GlintParticleRandom _random;
  final GlintParticleEventCallback? onEvent;
  Transform3D _transform;

  Transform3D get transform => _transform;

  set transform(Transform3D value) {
    _validateParticleTransform(value);
    _transform = value;
  }

  final Float32List _positions;
  final Float32List _velocities;
  final Float32List _ages;
  final Float32List _lifetimes;
  final Float32List _sizes;
  final Float32List _rotations;
  final Float32List _angularVelocities;
  final Float32List _colors;
  final Uint32List _startFrames;
  final Uint32List _burstCycles;
  late final GlintParticleRenderBatch _renderBatch;

  int _count = 0;
  bool _playing;
  double _emitterTime = 0;
  double _emissionRemainder = 0;
  double _noiseTime = 0;

  int get particleCount => _count;
  bool get isPlaying => _playing;
  bool get isAlive => _playing || _count > 0;
  GlintParticleRenderBatch get renderBatch => _renderBatch;

  void play({bool restart = false}) {
    if (restart) {
      _emitterTime = 0;
      _emissionRemainder = 0;
      _burstCycles.fillRange(0, _burstCycles.length, 0);
    }
    _playing = true;
  }

  void stop({bool clear = false}) {
    _playing = false;
    if (clear) this.clear();
  }

  void clear() {
    _count = 0;
  }

  /// Immediately emits particles in addition to configured rate/bursts.
  void emit(int count, {Vector3? position, Vector3? velocity}) {
    if (count < 0) {
      throw ArgumentError.value(count, 'count', 'must be >= 0');
    }
    if (position != null && !_isFiniteVector(position)) {
      throw ArgumentError.value(position, 'position', 'must be finite');
    }
    if (velocity != null && !_isFiniteVector(velocity)) {
      throw ArgumentError.value(velocity, 'velocity', 'must be finite');
    }
    for (var i = 0; i < count && _count < config.maxParticles; i++) {
      _spawn(position: position, velocity: velocity);
    }
  }

  void prewarm({double? seconds, double step = 1 / 60}) {
    if (!step.isFinite || step <= 0) {
      throw ArgumentError.value(step, 'step', 'must be finite and positive');
    }
    var remaining = seconds ?? config.duration;
    if (!remaining.isFinite || remaining < 0) {
      throw ArgumentError.value(seconds, 'seconds', 'must be finite and >= 0');
    }
    while (remaining > 0) {
      final delta = math.min(step, remaining);
      update(delta);
      remaining -= delta;
    }
  }

  void update(double seconds, {GlintParticleCollisionResolver? collisions}) {
    if (!seconds.isFinite || seconds < 0) {
      throw ArgumentError.value(seconds, 'seconds', 'must be finite and >= 0');
    }
    if (seconds == 0) return;
    var remaining = seconds;
    while (remaining > 0) {
      final step = math.min(remaining, 1 / 30);
      _simulate(step, collisions);
      if (_playing) _advanceEmission(step);
      _noiseTime += step;
      remaining -= step;
    }
  }

  void _advanceEmission(double seconds) {
    final previous = _emitterTime;
    var next = previous + seconds;
    if (!config.looping && previous >= config.duration) {
      _playing = false;
      return;
    }

    final activeSeconds = config.looping
        ? seconds
        : math.min(seconds, config.duration - previous);
    _emissionRemainder += config.emissionRate * activeSeconds;
    final continuous = _emissionRemainder.floor();
    _emissionRemainder -= continuous;
    emit(continuous);

    for (var i = 0; i < config.bursts.length; i++) {
      final burst = config.bursts[i];
      var cycle = _burstCycles[i];
      while (cycle < burst.cycles) {
        final scheduled = burst.time + burst.interval * cycle;
        if (scheduled > next) break;
        if (scheduled >= previous) emit(burst.count);
        cycle++;
      }
      _burstCycles[i] = cycle;
    }

    if (next >= config.duration) {
      if (config.looping) {
        next %= config.duration;
        _burstCycles.fillRange(0, _burstCycles.length, 0);
        // A large substep cannot occur (update caps at 1/30), so at most one
        // wrap is crossed here. Emit any bursts in the wrapped segment.
        for (var i = 0; i < config.bursts.length; i++) {
          final burst = config.bursts[i];
          var cycle = 0;
          while (cycle < burst.cycles &&
              burst.time + burst.interval * cycle <= next) {
            emit(burst.count);
            cycle++;
          }
          _burstCycles[i] = cycle;
        }
      } else {
        next = config.duration;
        _playing = false;
      }
    }
    _emitterTime = next;
  }

  void _spawn({Vector3? position, Vector3? velocity}) {
    final index = _count++;
    final sampled = config.shape.sample(_random);
    final speed = config.startSpeed.sample(_random);
    var spawnPosition = position ?? sampled.$1;
    var spawnVelocity = velocity ?? sampled.$2 * speed;
    if (config.simulationSpace == GlintParticleSimulationSpace.world) {
      spawnPosition = transform.apply(spawnPosition);
      if (velocity == null) {
        final transformedTip = transform.apply(sampled.$2);
        final transformedOrigin = transform.apply(Vector3.zero);
        spawnVelocity = (transformedTip - transformedOrigin).normalized * speed;
      }
    }
    final p = index * 3;
    _positions[p] = spawnPosition.x;
    _positions[p + 1] = spawnPosition.y;
    _positions[p + 2] = spawnPosition.z;
    _velocities[p] = spawnVelocity.x;
    _velocities[p + 1] = spawnVelocity.y;
    _velocities[p + 2] = spawnVelocity.z;
    _ages[index] = 0;
    _lifetimes[index] = config.lifetime.sample(_random);
    _sizes[index] = config.startSize.sample(_random);
    _rotations[index] = config.startRotation.sample(_random);
    _angularVelocities[index] = config.angularVelocity.sample(_random);
    final color = config.startColor.sample(_random);
    final c = index * 4;
    _colors[c] = color.r;
    _colors[c + 1] = color.g;
    _colors[c + 2] = color.b;
    _colors[c + 3] = color.a;
    final frames = config.spriteSheet?.frameCount ?? 1;
    _startFrames[index] = config.spriteSheet?.randomStartFrame == true
        ? (_random.nextDouble() * frames).floor()
        : 0;
  }

  void _simulate(double seconds, GlintParticleCollisionResolver? collisions) {
    final damping = math.exp(-config.drag * seconds);
    var index = 0;
    while (index < _count) {
      final age = _ages[index] + seconds;
      if (age >= _lifetimes[index]) {
        _emitEvent(GlintParticleEventType.death, index);
        _remove(index);
        continue;
      }
      _ages[index] = age;
      final p = index * 3;
      var velocity = Vector3(
        _velocities[p],
        _velocities[p + 1],
        _velocities[p + 2],
      );
      velocity = (velocity + config.gravity * seconds) * damping;
      if (config.noise.strength > 0) {
        final phase =
            _noiseTime * config.noise.scrollSpeed +
            (_positions[p] +
                    _positions[p + 1] * 1.37 +
                    _positions[p + 2] * 2.11) *
                config.noise.frequency;
        final turbulence = Vector3(
          math.sin(phase * 1.13),
          math.cos(phase * .91 + 1.7),
          math.sin(phase * 1.41 + 3.1),
        );
        velocity = velocity + turbulence * (config.noise.strength * seconds);
      }
      final from = Vector3(_positions[p], _positions[p + 1], _positions[p + 2]);
      var to = from + velocity * seconds;
      final localSpace =
          config.simulationSpace == GlintParticleSimulationSpace.local;
      final traceFrom = localSpace ? transform.apply(from) : from;
      final traceTo = localSpace ? transform.apply(to) : to;
      final collision = collisions?.trace(traceFrom, traceTo);
      if (collision != null) {
        if (config.killOnCollision) {
          _emitEvent(
            GlintParticleEventType.collision,
            index,
            position: collision.position,
            velocity: localSpace
                ? _transformDirection(transform, velocity)
                : velocity,
            valuesAreWorldSpace: true,
          );
          _remove(index);
          continue;
        }
        final normal = collision.normal.normalized;
        var responseVelocity = localSpace
            ? _transformDirection(transform, velocity)
            : velocity;
        final normalSpeed = responseVelocity.dot(normal);
        final normalVelocity = normal * normalSpeed;
        final tangentVelocity = responseVelocity - normalVelocity;
        responseVelocity =
            tangentVelocity * (1 - config.collisionFriction) -
            normalVelocity * config.collisionBounce;
        if (localSpace) {
          velocity = _inverseTransformDirection(transform, responseVelocity);
          to = _inverseTransformPoint(
            transform,
            collision.position + normal * .001,
          );
        } else {
          velocity = responseVelocity;
          to = collision.position + normal * .001;
        }
        _emitEvent(
          GlintParticleEventType.collision,
          index,
          position: collision.position,
          velocity: responseVelocity,
          valuesAreWorldSpace: true,
        );
      }
      _positions[p] = to.x;
      _positions[p + 1] = to.y;
      _positions[p + 2] = to.z;
      _velocities[p] = velocity.x;
      _velocities[p + 1] = velocity.y;
      _velocities[p + 2] = velocity.z;
      _rotations[index] += _angularVelocities[index] * seconds;
      index++;
    }
  }

  void _emitEvent(
    GlintParticleEventType type,
    int index, {
    Vector3? position,
    Vector3? velocity,
    bool valuesAreWorldSpace = false,
  }) {
    final callback = onEvent;
    if (callback == null) return;
    final p = index * 3;
    var eventPosition =
        position ??
        Vector3(_positions[p], _positions[p + 1], _positions[p + 2]);
    var eventVelocity =
        velocity ??
        Vector3(_velocities[p], _velocities[p + 1], _velocities[p + 2]);
    if (!valuesAreWorldSpace &&
        config.simulationSpace == GlintParticleSimulationSpace.local) {
      eventPosition = transform.apply(eventPosition);
      eventVelocity = _transformDirection(transform, eventVelocity);
    }
    callback(
      GlintParticleEvent(
        type: type,
        position: eventPosition,
        velocity: eventVelocity,
      ),
    );
  }

  void _remove(int index) {
    final last = --_count;
    if (index == last) return;
    for (var axis = 0; axis < 3; axis++) {
      _positions[index * 3 + axis] = _positions[last * 3 + axis];
      _velocities[index * 3 + axis] = _velocities[last * 3 + axis];
    }
    for (var channel = 0; channel < 4; channel++) {
      _colors[index * 4 + channel] = _colors[last * 4 + channel];
    }
    _ages[index] = _ages[last];
    _lifetimes[index] = _lifetimes[last];
    _sizes[index] = _sizes[last];
    _rotations[index] = _rotations[last];
    _angularVelocities[index] = _angularVelocities[last];
    _startFrames[index] = _startFrames[last];
  }
}

/// Zero-copy rendering view over a [GlintParticleSystem]. Typed arrays are
/// read-only by convention and remain owned by the system.
class GlintParticleRenderBatch {
  const GlintParticleRenderBatch._(this._system);
  final GlintParticleSystem _system;

  GlintParticleConfig get config => _system.config;
  Transform3D get transform => _system.transform;
  int get count => _system._count;
  Float32List get positions => _system._positions;
  Float32List get ages => _system._ages;
  Float32List get lifetimes => _system._lifetimes;
  Float32List get startSizes => _system._sizes;
  Float32List get rotations => _system._rotations;
  Float32List get startColors => _system._colors;
  Uint32List get startFrames => _system._startFrames;

  double normalizedAge(int index) =>
      (ages[index] / lifetimes[index]).clamp(0.0, 1.0);

  Vector3 worldPosition(int index) {
    final offset = index * 3;
    final position = Vector3(
      positions[offset],
      positions[offset + 1],
      positions[offset + 2],
    );
    return config.simulationSpace == GlintParticleSimulationSpace.local
        ? transform.apply(position)
        : position;
  }

  double size(int index) =>
      startSizes[index] *
      config.sizeOverLifetime.evaluate(normalizedAge(index));

  GlintParticleColor color(int index) {
    final offset = index * 4;
    final start = GlintParticleColor(
      startColors[offset],
      startColors[offset + 1],
      startColors[offset + 2],
      startColors[offset + 3],
    );
    return start * config.colorOverLifetime.evaluate(normalizedAge(index));
  }

  int spriteFrame(int index) {
    final sheet = config.spriteSheet;
    if (sheet == null) return 0;
    final phase =
        sheet.frameOverLifetime.evaluate(normalizedAge(index)) * sheet.cycles;
    return (startFrames[index] + (phase * sheet.frameCount).floor()) %
        sheet.frameCount;
  }
}

Vector3 _randomUnitVector(GlintParticleRandom random) {
  final z = random.signed();
  final angle = random.nextDouble() * math.pi * 2;
  final radius = math.sqrt(math.max(0, 1 - z * z));
  return Vector3(radius * math.cos(angle), z, radius * math.sin(angle));
}

Vector3 _spreadDirection(
  Vector3 direction,
  double spread,
  GlintParticleRandom random,
) {
  final axis = direction.normalized;
  if (spread == 0) return axis;
  final cosine = 1 - random.nextDouble() * (1 - math.cos(spread));
  final sine = math.sqrt(math.max(0, 1 - cosine * cosine));
  final azimuth = random.nextDouble() * math.pi * 2;
  final tangent = _orthogonal(axis);
  final bitangent = axis.cross(tangent).normalized;
  return (axis * cosine +
          tangent * (sine * math.cos(azimuth)) +
          bitangent * (sine * math.sin(azimuth)))
      .normalized;
}

Vector3 _orthogonal(Vector3 axis) =>
    (axis.y.abs() < .99
            ? axis.cross(const Vector3(0, 1, 0))
            : axis.cross(const Vector3(1, 0, 0)))
        .normalized;

void _validateDirection(Vector3 direction) {
  if (!_isFiniteVector(direction) || direction.length == 0) {
    throw ArgumentError.value(
      direction,
      'direction',
      'must be finite and non-zero',
    );
  }
}

void _validateAngle(double value, String name) {
  if (!value.isFinite || value < 0 || value > math.pi) {
    throw ArgumentError.value(value, name, 'must be between 0 and pi');
  }
}

bool _isFiniteVector(Vector3 value) =>
    value.x.isFinite && value.y.isFinite && value.z.isFinite;

void _validateParticleTransform(Transform3D transform) {
  final orientation = transform.orientation;
  if (!_isFiniteVector(transform.position) ||
      !_isFiniteVector(transform.rotation) ||
      !_isFiniteVector(transform.scale) ||
      (orientation != null &&
          ![
            orientation.x,
            orientation.y,
            orientation.z,
            orientation.w,
          ].every((value) => value.isFinite))) {
    throw ArgumentError.value(transform, 'transform', 'must be finite');
  }
}

Vector3 _transformDirection(Transform3D transform, Vector3 value) =>
    transform.apply(value) - transform.position;

Vector3 _inverseTransformPoint(Transform3D transform, Vector3 value) =>
    _inverseTransformDirection(transform, value - transform.position);

Vector3 _inverseTransformDirection(Transform3D transform, Vector3 value) {
  var result = value;
  final orientation = transform.orientation;
  if (orientation != null) {
    result = orientation.normalized.conjugate.rotate(result);
  } else {
    final rz = -transform.rotation.z;
    final cz = math.cos(rz), sz = math.sin(rz);
    result = Vector3(
      result.x * cz - result.y * sz,
      result.x * sz + result.y * cz,
      result.z,
    );
    final ry = -transform.rotation.y;
    final cy = math.cos(ry), sy = math.sin(ry);
    result = Vector3(
      result.x * cy + result.z * sy,
      result.y,
      -result.x * sy + result.z * cy,
    );
    final rx = -transform.rotation.x;
    final cx = math.cos(rx), sx = math.sin(rx);
    result = Vector3(
      result.x,
      result.y * cx - result.z * sx,
      result.y * sx + result.z * cx,
    );
  }
  final scale = transform.scale;
  if (scale.x == 0 || scale.y == 0 || scale.z == 0) {
    throw StateError(
      'Local particle collisions need a non-zero emitter scale.',
    );
  }
  return Vector3(result.x / scale.x, result.y / scale.y, result.z / scale.z);
}
