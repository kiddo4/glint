import 'math.dart';
import 'physics.dart';

typedef GlintReplayInputApplier<T> =
    void Function(T input, double fixedTimeStep);

/// A stable, quantized signature of backend-neutral rigid-body state.
class GlintPhysicsStateDigest {
  const GlintPhysicsStateDigest({
    required this.hash,
    required this.bodyCount,
    required this.quantization,
  });

  factory GlintPhysicsStateDigest.capture(
    GlintPhysicsWorld world, {
    double quantization = 1e-6,
  }) {
    if (!quantization.isFinite || quantization <= 0) {
      throw ArgumentError.value(
        quantization,
        'quantization',
        'must be finite and > 0',
      );
    }
    const mask = 0xffffffffffffffff;
    var hash = 0xcbf29ce484222325;
    void addInteger(int value) {
      var bits = value & mask;
      for (var byte = 0; byte < 8; byte++) {
        hash ^= bits & 0xff;
        hash = (hash * 0x100000001b3) & mask;
        bits >>= 8;
      }
    }

    int quantize(double value) {
      if (value.isNaN) return 0x7ff8000000000000;
      if (value == double.infinity) return 0x7ff0000000000000;
      if (value == double.negativeInfinity) return -0x10000000000000;
      return (value / quantization).round();
    }

    void addVector(Vector3 value) {
      addInteger(quantize(value.x));
      addInteger(quantize(value.y));
      addInteger(quantize(value.z));
    }

    addVector(world.gravity);
    final bodies = world.bodies;
    addInteger(bodies.length);
    for (final body in bodies) {
      addInteger(body.type.index);
      addInteger(body.isSleeping ? 1 : 0);
      addVector(body.position);
      final rotation = _canonicalQuaternion(body.orientation);
      addInteger(quantize(rotation.x));
      addInteger(quantize(rotation.y));
      addInteger(quantize(rotation.z));
      addInteger(quantize(rotation.w));
      addVector(body.linearVelocity);
      addVector(body.angularVelocity);
    }
    return GlintPhysicsStateDigest(
      hash: hash,
      bodyCount: bodies.length,
      quantization: quantization,
    );
  }

  factory GlintPhysicsStateDigest.fromJson(Map<String, Object?> json) {
    final encodedHash = json['hash'];
    final bodyCount = json['bodyCount'];
    final quantization = json['quantization'];
    if (encodedHash is! String || bodyCount is! num || quantization is! num) {
      throw const FormatException('Invalid Glint physics digest.');
    }
    return GlintPhysicsStateDigest(
      hash: int.parse(encodedHash, radix: 16),
      bodyCount: bodyCount.toInt(),
      quantization: quantization.toDouble(),
    );
  }

  final int hash;
  final int bodyCount;
  final double quantization;

  Map<String, Object?> toJson() => {
    'hash': hash.toRadixString(16).padLeft(16, '0'),
    'bodyCount': bodyCount,
    'quantization': quantization,
  };

  @override
  bool operator ==(Object other) =>
      other is GlintPhysicsStateDigest &&
      other.hash == hash &&
      other.bodyCount == bodyCount &&
      other.quantization == quantization;

  @override
  int get hashCode => Object.hash(hash, bodyCount, quantization);

  @override
  String toString() => '${hash.toRadixString(16).padLeft(16, '0')}/$bodyCount';
}

extension GlintPhysicsWorldDiagnostics on GlintPhysicsWorld {
  GlintPhysicsStateDigest stateDigest({double quantization = 1e-6}) =>
      GlintPhysicsStateDigest.capture(this, quantization: quantization);
}

/// One fixed-step input and its expected resulting world signature.
class GlintPhysicsReplayFrame<T> {
  const GlintPhysicsReplayFrame({required this.input, required this.digest});

  final T input;
  final GlintPhysicsStateDigest digest;
}

class GlintPhysicsReplayDivergence {
  const GlintPhysicsReplayDivergence({
    required this.frame,
    required this.expected,
    required this.actual,
  });

  final int frame;
  final GlintPhysicsStateDigest expected;
  final GlintPhysicsStateDigest actual;
}

class GlintPhysicsReplayResult {
  const GlintPhysicsReplayResult({
    required this.stepsPlayed,
    required this.divergences,
  });

  final int stepsPlayed;
  final List<GlintPhysicsReplayDivergence> divergences;

  bool get deterministic => divergences.isEmpty;
}

/// Immutable fixed-step input tape with optional same-world rollback state.
class GlintPhysicsReplay<T> {
  GlintPhysicsReplay({
    required this.fixedTimeStep,
    required Iterable<GlintPhysicsReplayFrame<T>> frames,
    this.initialSnapshot,
  }) : frames = List.unmodifiable(frames) {
    if (!fixedTimeStep.isFinite || fixedTimeStep <= 0) {
      throw ArgumentError.value(
        fixedTimeStep,
        'fixedTimeStep',
        'must be finite and > 0',
      );
    }
  }

  factory GlintPhysicsReplay.fromJson(
    Map<String, Object?> json, {
    required T Function(Object? json) decodeInput,
  }) {
    final version = json['version'];
    final fixedTimeStep = json['fixedTimeStep'];
    final encodedFrames = json['frames'];
    if (version != 1 || fixedTimeStep is! num || encodedFrames is! List) {
      throw const FormatException('Invalid Glint physics replay.');
    }
    return GlintPhysicsReplay<T>(
      fixedTimeStep: fixedTimeStep.toDouble(),
      frames: [
        for (final encoded in encodedFrames)
          if (encoded case {'input': final input, 'digest': final Map digest})
            GlintPhysicsReplayFrame<T>(
              input: decodeInput(input),
              digest: GlintPhysicsStateDigest.fromJson(
                digest.cast<String, Object?>(),
              ),
            )
          else
            throw const FormatException('Invalid replay frame.'),
      ],
    );
  }

  final double fixedTimeStep;
  final List<GlintPhysicsReplayFrame<T>> frames;

  /// Present for in-memory recordings, absent after portable JSON decoding.
  final GlintPhysicsSnapshot? initialSnapshot;

  double get duration => frames.length * fixedTimeStep;

  /// Replays each input at its exact fixed tick and compares state signatures.
  ///
  /// Set [restoreInitialState] false when replaying a portable tape into a
  /// freshly constructed world that already matches the recording's start.
  GlintPhysicsReplayResult play(
    GlintPhysicsWorld world,
    GlintReplayInputApplier<T> applyInput, {
    bool restoreInitialState = true,
    bool verifyDigests = true,
    bool stopOnDivergence = false,
  }) {
    if ((world.fixedTimeStep - fixedTimeStep).abs() > 1e-12) {
      throw ArgumentError.value(
        world.fixedTimeStep,
        'world',
        'fixed timestep does not match the replay ($fixedTimeStep)',
      );
    }
    if (restoreInitialState) {
      final initial = initialSnapshot;
      if (initial == null) {
        throw StateError(
          'This portable replay has no in-memory snapshot. Recreate its '
          'initial world and pass restoreInitialState: false.',
        );
      }
      world.restoreSnapshot(initial);
    }
    final divergences = <GlintPhysicsReplayDivergence>[];
    var stepsPlayed = 0;
    for (var frameIndex = 0; frameIndex < frames.length; frameIndex++) {
      final frame = frames[frameIndex];
      applyInput(frame.input, fixedTimeStep);
      world.stepFixed();
      stepsPlayed++;
      if (!verifyDigests) continue;
      final actual = world.stateDigest(quantization: frame.digest.quantization);
      if (actual != frame.digest) {
        divergences.add(
          GlintPhysicsReplayDivergence(
            frame: frameIndex,
            expected: frame.digest,
            actual: actual,
          ),
        );
        if (stopOnDivergence) break;
      }
    }
    return GlintPhysicsReplayResult(
      stepsPlayed: stepsPlayed,
      divergences: List.unmodifiable(divergences),
    );
  }

  Map<String, Object?> toJson(Object? Function(T input) encodeInput) => {
    'version': 1,
    'fixedTimeStep': fixedTimeStep,
    'frames': [
      for (final frame in frames)
        {'input': encodeInput(frame.input), 'digest': frame.digest.toJson()},
    ],
  };
}

/// Records inputs by applying exactly one input before exactly one fixed step.
class GlintPhysicsReplayRecorder<T> {
  GlintPhysicsReplayRecorder({
    required this.world,
    required this.applyInput,
    this.digestQuantization = 1e-6,
    bool captureInitialState = true,
  }) : initialSnapshot = captureInitialState ? world.captureSnapshot() : null {
    if (!digestQuantization.isFinite || digestQuantization <= 0) {
      throw ArgumentError.value(
        digestQuantization,
        'digestQuantization',
        'must be finite and > 0',
      );
    }
  }

  final GlintPhysicsWorld world;
  final GlintReplayInputApplier<T> applyInput;
  final double digestQuantization;
  final GlintPhysicsSnapshot? initialSnapshot;
  final List<GlintPhysicsReplayFrame<T>> _frames = [];

  int get length => _frames.length;

  void record(T input) {
    applyInput(input, world.fixedTimeStep);
    world.stepFixed();
    _frames.add(
      GlintPhysicsReplayFrame<T>(
        input: input,
        digest: world.stateDigest(quantization: digestQuantization),
      ),
    );
  }

  GlintPhysicsReplay<T> finish() => GlintPhysicsReplay<T>(
    fixedTimeStep: world.fixedTimeStep,
    frames: _frames,
    initialSnapshot: initialSnapshot,
  );
}

GlintQuaternion _canonicalQuaternion(GlintQuaternion value) {
  final normalized = value.normalized;
  final negate =
      normalized.w < 0 ||
      (normalized.w == 0 && normalized.z < 0) ||
      (normalized.w == 0 && normalized.z == 0 && normalized.y < 0) ||
      (normalized.w == 0 &&
          normalized.z == 0 &&
          normalized.y == 0 &&
          normalized.x < 0);
  return negate
      ? GlintQuaternion(
          -normalized.x,
          -normalized.y,
          -normalized.z,
          -normalized.w,
        )
      : normalized;
}
