import 'dart:async';
import 'dart:typed_data';

import 'math.dart';

/// How an audio clip is kept after it has been loaded.
enum GlintAudioLoadMode {
  /// Decode into memory for the lowest playback latency.
  memory,

  /// Stream from storage to reduce memory use for music and ambience.
  stream,
}

/// Distance falloff used by a spatial voice.
enum GlintAudioAttenuation { none, inverse, linear, exponential }

/// Device and mixer configuration for [GlintAudioEngine].
class GlintAudioConfig {
  const GlintAudioConfig({
    this.sampleRate = 48000,
    this.bufferSize = 1024,
    this.maxActiveVoices = 64,
    this.lowLatency = true,
    this.worldUnitsPerMeter = 1,
  });

  final int sampleRate;
  final int bufferSize;
  final int maxActiveVoices;
  final bool lowLatency;

  /// Glint units represented by one physical metre. This keeps Doppler pitch
  /// correct in worlds whose authored scale is not one unit per metre.
  final double worldUnitsPerMeter;

  void validate() {
    if (sampleRate <= 0) {
      throw ArgumentError.value(sampleRate, 'sampleRate', 'must be positive');
    }
    if (bufferSize <= 0) {
      throw ArgumentError.value(bufferSize, 'bufferSize', 'must be positive');
    }
    if (maxActiveVoices <= 0 || maxActiveVoices > 4095) {
      throw ArgumentError.value(
        maxActiveVoices,
        'maxActiveVoices',
        'must be between 1 and 4095',
      );
    }
    if (!worldUnitsPerMeter.isFinite || worldUnitsPerMeter <= 0) {
      throw ArgumentError.value(
        worldUnitsPerMeter,
        'worldUnitsPerMeter',
        'must be finite and positive',
      );
    }
  }
}

/// A loadable audio location.
sealed class GlintAudioSource {
  const GlintAudioSource({this.mode = GlintAudioLoadMode.memory});

  const factory GlintAudioSource.asset(
    String assetKey, {
    GlintAudioLoadMode mode,
  }) = GlintAssetAudioSource;

  const factory GlintAudioSource.file(String path, {GlintAudioLoadMode mode}) =
      GlintFileAudioSource;

  const factory GlintAudioSource.network(
    String url, {
    GlintAudioLoadMode mode,
  }) = GlintNetworkAudioSource;

  /// Encoded audio bytes (for example WAV, Ogg, MP3, or FLAC), identified by
  /// [debugLabel] for decoder errors and backend caches.
  factory GlintAudioSource.memory(
    String debugLabel,
    Uint8List bytes, {
    GlintAudioLoadMode mode,
  }) = GlintMemoryAudioSource;

  final GlintAudioLoadMode mode;
}

class GlintAssetAudioSource extends GlintAudioSource {
  const GlintAssetAudioSource(
    this.assetKey, {
    super.mode = GlintAudioLoadMode.memory,
  });

  final String assetKey;

  @override
  bool operator ==(Object other) =>
      other is GlintAssetAudioSource &&
      other.assetKey == assetKey &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(assetKey, mode);
}

class GlintFileAudioSource extends GlintAudioSource {
  const GlintFileAudioSource(
    this.path, {
    super.mode = GlintAudioLoadMode.memory,
  });

  final String path;

  @override
  bool operator ==(Object other) =>
      other is GlintFileAudioSource && other.path == path && other.mode == mode;

  @override
  int get hashCode => Object.hash(path, mode);
}

class GlintNetworkAudioSource extends GlintAudioSource {
  const GlintNetworkAudioSource(
    this.url, {
    super.mode = GlintAudioLoadMode.stream,
  });

  final String url;

  @override
  bool operator ==(Object other) =>
      other is GlintNetworkAudioSource &&
      other.url == url &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(url, mode);
}

class GlintMemoryAudioSource extends GlintAudioSource {
  GlintMemoryAudioSource(
    this.debugLabel,
    this.bytes, {
    super.mode = GlintAudioLoadMode.memory,
  }) {
    if (debugLabel.trim().isEmpty) {
      throw ArgumentError.value(debugLabel, 'debugLabel', 'must not be empty');
    }
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'must not be empty');
    }
  }

  final String debugLabel;
  final Uint8List bytes;

  @override
  bool operator ==(Object other) =>
      other is GlintMemoryAudioSource &&
      other.debugLabel == debugLabel &&
      identical(other.bytes, bytes) &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(debugLabel, identityHashCode(bytes), mode);
}

/// Camera/listener state used for spatial mixing and Doppler.
class GlintAudioListener {
  const GlintAudioListener({
    required this.position,
    required this.forward,
    this.up = const Vector3(0, 1, 0),
    this.velocity = Vector3.zero,
  });

  final Vector3 position;
  final Vector3 forward;
  final Vector3 up;
  final Vector3 velocity;

  void validate() {
    if (forward.length == 0) {
      throw ArgumentError.value(forward, 'forward', 'must not be zero');
    }
    if (up.length == 0) {
      throw ArgumentError.value(up, 'up', 'must not be zero');
    }
  }
}

/// Parameters shared by 2D and spatial voice creation.
class GlintAudioPlayOptions {
  const GlintAudioPlayOptions({
    this.volume = 1,
    this.pan = 0,
    this.looping = false,
    this.loopStart = Duration.zero,
    this.paused = false,
    this.protected = false,
    this.playbackRate = 1,
  });

  final double volume;
  final double pan;
  final bool looping;
  final Duration loopStart;
  final bool paused;

  /// Prevent long-running music or ambience from being selected for voice
  /// stealing when the active-voice budget is exhausted.
  final bool protected;

  /// Pitch-preserving is backend dependent; the default backend changes both
  /// speed and pitch, which is useful for engines and tyre sounds.
  final double playbackRate;

  void validate() {
    if (!volume.isFinite || volume < 0) {
      throw ArgumentError.value(volume, 'volume', 'must be finite and >= 0');
    }
    if (!pan.isFinite || pan < -1 || pan > 1) {
      throw ArgumentError.value(pan, 'pan', 'must be between -1 and 1');
    }
    if (!playbackRate.isFinite || playbackRate <= 0) {
      throw ArgumentError.value(
        playbackRate,
        'playbackRate',
        'must be finite and positive',
      );
    }
    if (loopStart.isNegative) {
      throw ArgumentError.value(loopStart, 'loopStart', 'must not be negative');
    }
  }
}

/// Additional parameters for a world-space voice.
class GlintSpatialAudioOptions extends GlintAudioPlayOptions {
  const GlintSpatialAudioOptions({
    super.volume,
    super.looping,
    super.loopStart,
    super.paused,
    super.protected,
    super.playbackRate,
    this.velocity = Vector3.zero,
    this.minimumDistance = 1,
    this.maximumDistance = 100,
    this.attenuation = GlintAudioAttenuation.inverse,
    this.rolloff = 1,
    this.dopplerFactor = 1,
  });

  final Vector3 velocity;
  final double minimumDistance;
  final double maximumDistance;
  final GlintAudioAttenuation attenuation;
  final double rolloff;
  final double dopplerFactor;

  @override
  void validate() {
    super.validate();
    if (!minimumDistance.isFinite || minimumDistance < 0) {
      throw ArgumentError.value(
        minimumDistance,
        'minimumDistance',
        'must be finite and >= 0',
      );
    }
    if (!maximumDistance.isFinite || maximumDistance <= minimumDistance) {
      throw ArgumentError.value(
        maximumDistance,
        'maximumDistance',
        'must be finite and greater than minimumDistance',
      );
    }
    if (!rolloff.isFinite || rolloff < 0) {
      throw ArgumentError.value(rolloff, 'rolloff', 'must be finite and >= 0');
    }
    if (!dopplerFactor.isFinite || dopplerFactor < 0) {
      throw ArgumentError.value(
        dopplerFactor,
        'dopplerFactor',
        'must be finite and >= 0',
      );
    }
  }
}

/// Backend contract kept intentionally handle-based so engines can be tested
/// without opening an audio device and alternative native mixers can plug in.
abstract interface class GlintAudioBackend {
  Future<void> initialize(GlintAudioConfig config);
  Future<void> dispose();

  Future<int> load(GlintAudioSource source);
  Future<void> unload(int clipId);

  int createBus(String name);
  Future<void> destroyBus(int busId);
  void setBusVolume(int busId, double volume);

  int play(
    int clipId, {
    required int busId,
    required GlintAudioPlayOptions options,
  });

  int playSpatial(
    int clipId,
    Vector3 position, {
    required int busId,
    required GlintSpatialAudioOptions options,
  });

  bool isVoiceActive(int voiceId);
  Future<void> stopVoice(int voiceId);
  void pauseVoice(int voiceId, bool paused);
  void setVoiceVolume(int voiceId, double volume);
  void fadeVoiceVolume(int voiceId, double volume, Duration duration);
  void setVoicePlaybackRate(int voiceId, double rate);
  void setVoiceSpatialState(int voiceId, Vector3 position, Vector3 velocity);
  void setListener(GlintAudioListener listener);
  void setMasterVolume(double volume);
}

/// A loaded, reusable sound owned by a [GlintAudioEngine].
class GlintAudioClip {
  GlintAudioClip._(this._engine, this.source, this._id);

  final GlintAudioEngine _engine;
  final GlintAudioSource source;
  final int _id;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  Future<void> dispose() => _engine.unload(this);
}

/// A mixer group, such as music, effects, ambience, or dialogue.
class GlintAudioBus {
  GlintAudioBus._(this._engine, this.name, this._id);

  final GlintAudioEngine _engine;
  final String name;
  final int _id;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  set volume(double value) {
    if (_disposed) throw StateError('Audio bus "$name" is disposed.');
    _validateGain(value, 'volume');
    _engine._backend.setBusVolume(_id, value);
  }

  Future<void> dispose() => _engine.destroyBus(this);
}

/// One playing occurrence of a clip.
class GlintAudioVoice {
  GlintAudioVoice._(this._engine, this._id, {required this.spatial});

  final GlintAudioEngine _engine;
  final int _id;
  final bool spatial;

  bool get isActive =>
      !_engine._disposed && _engine._backend.isVoiceActive(_id);

  Future<void> stop() => _engine._backend.stopVoice(_id);

  set paused(bool value) => _engine._backend.pauseVoice(_id, value);

  set volume(double value) {
    _validateGain(value, 'volume');
    _engine._backend.setVoiceVolume(_id, value);
  }

  void fadeTo(double volume, Duration duration) {
    _validateGain(volume, 'volume');
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'must not be negative');
    }
    _engine._backend.fadeVoiceVolume(_id, volume, duration);
  }

  set playbackRate(double value) {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError.value(
        value,
        'playbackRate',
        'must be finite and positive',
      );
    }
    _engine._backend.setVoicePlaybackRate(_id, value);
  }

  void setSpatialState(Vector3 position, {Vector3 velocity = Vector3.zero}) {
    if (!spatial) {
      throw StateError('Only spatial voices have world-space state.');
    }
    _engine._backend.setVoiceSpatialState(_id, position, velocity);
  }
}

/// Glint's game-audio facade: cached clips, mixer buses, voice control, and
/// listener/source spatial state over a replaceable backend.
class GlintAudioEngine {
  factory GlintAudioEngine({required GlintAudioBackend backend}) =>
      GlintAudioEngine._(backend);

  GlintAudioEngine._(this._backend);

  final GlintAudioBackend _backend;
  final Map<GlintAudioSource, GlintAudioClip> _clips = {};
  final Set<GlintAudioBus> _buses = {};
  bool _initialized = false;
  bool _disposed = false;

  bool get isInitialized => _initialized && !_disposed;

  Future<void> initialize({
    GlintAudioConfig config = const GlintAudioConfig(),
  }) async {
    if (_disposed) throw StateError('The audio engine is disposed.');
    if (_initialized) return;
    config.validate();
    await _backend.initialize(config);
    _initialized = true;
  }

  Future<GlintAudioClip> load(GlintAudioSource source) async {
    _requireInitialized();
    final cached = _clips[source];
    if (cached != null && !cached._disposed) return cached;
    final clip = GlintAudioClip._(this, source, await _backend.load(source));
    _clips[source] = clip;
    return clip;
  }

  Future<void> unload(GlintAudioClip clip) async {
    _requireOwnedClip(clip);
    if (clip._disposed) return;
    await _backend.unload(clip._id);
    clip._disposed = true;
    _clips.remove(clip.source);
  }

  GlintAudioBus createBus(String name, {double volume = 1}) {
    _requireInitialized();
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    _validateGain(volume, 'volume');
    final bus = GlintAudioBus._(this, name, _backend.createBus(name));
    _buses.add(bus);
    bus.volume = volume;
    return bus;
  }

  Future<void> destroyBus(GlintAudioBus bus) async {
    if (!identical(bus._engine, this)) {
      throw ArgumentError('The audio bus belongs to another engine.');
    }
    if (bus._disposed) return;
    await _backend.destroyBus(bus._id);
    bus._disposed = true;
    _buses.remove(bus);
  }

  GlintAudioVoice play(
    GlintAudioClip clip, {
    GlintAudioBus? bus,
    GlintAudioPlayOptions options = const GlintAudioPlayOptions(),
  }) {
    _requireOwnedClip(clip);
    _requireBus(bus);
    options.validate();
    return GlintAudioVoice._(
      this,
      _backend.play(clip._id, busId: bus?._id ?? 0, options: options),
      spatial: false,
    );
  }

  GlintAudioVoice playSpatial(
    GlintAudioClip clip,
    Vector3 position, {
    GlintAudioBus? bus,
    GlintSpatialAudioOptions options = const GlintSpatialAudioOptions(),
  }) {
    _requireOwnedClip(clip);
    _requireBus(bus);
    options.validate();
    return GlintAudioVoice._(
      this,
      _backend.playSpatial(
        clip._id,
        position,
        busId: bus?._id ?? 0,
        options: options,
      ),
      spatial: true,
    );
  }

  set listener(GlintAudioListener value) {
    _requireInitialized();
    value.validate();
    _backend.setListener(value);
  }

  set masterVolume(double value) {
    _requireInitialized();
    _validateGain(value, 'masterVolume');
    _backend.setMasterVolume(value);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    for (final bus in _buses.toList()) {
      await destroyBus(bus);
    }
    for (final clip in _clips.values.toList()) {
      await unload(clip);
    }
    await _backend.dispose();
    _initialized = false;
    _disposed = true;
  }

  void _requireInitialized() {
    if (!isInitialized) {
      throw StateError('Call GlintAudioEngine.initialize() first.');
    }
  }

  void _requireOwnedClip(GlintAudioClip clip) {
    _requireInitialized();
    if (!identical(clip._engine, this)) {
      throw ArgumentError('The audio clip belongs to another engine.');
    }
    if (clip._disposed) throw StateError('The audio clip is disposed.');
  }

  void _requireBus(GlintAudioBus? bus) {
    if (bus == null) return;
    if (!identical(bus._engine, this)) {
      throw ArgumentError('The audio bus belongs to another engine.');
    }
    if (bus._disposed) throw StateError('The audio bus is disposed.');
  }
}

void _validateGain(double value, String name) {
  if (!value.isFinite || value < 0) {
    throw ArgumentError.value(value, name, 'must be finite and >= 0');
  }
}
