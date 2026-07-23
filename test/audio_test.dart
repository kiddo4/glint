import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glint_engine/glint_engine.dart';

void main() {
  test('memory sources cache only when they share the encoded buffer', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final first = GlintAudioSource.memory('tone.wav', bytes);
    final same = GlintAudioSource.memory('tone.wav', bytes);
    final copy = GlintAudioSource.memory(
      'tone.wav',
      Uint8List.fromList([1, 2, 3]),
    );

    expect(first, same);
    expect(first, isNot(copy));
  });

  test('audio facade caches clips and forwards spatial state', () async {
    final backend = _FakeAudioBackend();
    final audio = GlintAudioEngine(backend: backend);
    await audio.initialize(
      config: const GlintAudioConfig(
        maxActiveVoices: 96,
        worldUnitsPerMeter: 2,
      ),
    );
    final source = const GlintAudioSource.asset('audio/engine.ogg');
    final first = await audio.load(source);
    final second = await audio.load(source);
    final effects = audio.createBus('effects', volume: .8);
    final voice = audio.playSpatial(
      first,
      const Vector3(1, 2, 3),
      bus: effects,
      options: const GlintSpatialAudioOptions(
        velocity: Vector3(4, 0, 0),
        looping: true,
        minimumDistance: 2,
        maximumDistance: 80,
        dopplerFactor: 1.4,
      ),
    );
    audio.listener = const GlintAudioListener(
      position: Vector3(0, 2, -4),
      forward: Vector3(0, 0, 1),
    );
    voice.setSpatialState(
      const Vector3(2, 2, 3),
      velocity: const Vector3(5, 0, 0),
    );

    expect(identical(first, second), isTrue);
    expect(backend.loadCalls, 1);
    expect(backend.config?.maxActiveVoices, 96);
    expect(backend.lastSpatialPosition, const Vector3(2, 2, 3));
    expect(backend.lastSpatialOptions?.looping, isTrue);
    expect(backend.listener?.position, const Vector3(0, 2, -4));

    await audio.dispose();
    expect(backend.disposed, isTrue);
  });

  test(
    'validates mixer and spatial values before reaching a backend',
    () async {
      final backend = _FakeAudioBackend();
      final audio = GlintAudioEngine(backend: backend);
      await audio.initialize();
      final clip = await audio.load(const GlintAudioSource.asset('impact.wav'));

      expect(
        () => audio.play(
          clip,
          options: const GlintAudioPlayOptions(playbackRate: 0),
        ),
        throwsArgumentError,
      );
      expect(
        () => audio.playSpatial(
          clip,
          Vector3.zero,
          options: const GlintSpatialAudioOptions(
            minimumDistance: 10,
            maximumDistance: 5,
          ),
        ),
        throwsArgumentError,
      );
    },
  );
}

class _FakeAudioBackend implements GlintAudioBackend {
  GlintAudioConfig? config;
  int loadCalls = 0;
  int _nextClip = 1;
  int _nextBus = 1;
  int _nextVoice = 1;
  bool disposed = false;
  Vector3? lastSpatialPosition;
  GlintSpatialAudioOptions? lastSpatialOptions;
  GlintAudioListener? listener;

  @override
  Future<void> initialize(GlintAudioConfig config) async {
    this.config = config;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  Future<int> load(GlintAudioSource source) async {
    loadCalls++;
    return _nextClip++;
  }

  @override
  Future<void> unload(int clipId) async {}

  @override
  int createBus(String name) => _nextBus++;

  @override
  Future<void> destroyBus(int busId) async {}

  @override
  void setBusVolume(int busId, double volume) {}

  @override
  int play(
    int clipId, {
    required int busId,
    required GlintAudioPlayOptions options,
  }) => _nextVoice++;

  @override
  int playSpatial(
    int clipId,
    Vector3 position, {
    required int busId,
    required GlintSpatialAudioOptions options,
  }) {
    lastSpatialPosition = position;
    lastSpatialOptions = options;
    return _nextVoice++;
  }

  @override
  bool isVoiceActive(int voiceId) => true;

  @override
  Future<void> stopVoice(int voiceId) async {}

  @override
  void pauseVoice(int voiceId, bool paused) {}

  @override
  void setVoiceVolume(int voiceId, double volume) {}

  @override
  void fadeVoiceVolume(int voiceId, double volume, Duration duration) {}

  @override
  void setVoicePlaybackRate(int voiceId, double rate) {}

  @override
  void setVoiceSpatialState(int voiceId, Vector3 position, Vector3 velocity) {
    lastSpatialPosition = position;
  }

  @override
  void setListener(GlintAudioListener listener) {
    this.listener = listener;
  }

  @override
  void setMasterVolume(double volume) {}
}
