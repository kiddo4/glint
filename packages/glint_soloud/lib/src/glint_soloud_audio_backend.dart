import 'package:flutter_soloud/flutter_soloud.dart' as soloud;
import 'package:glint_engine/glint_engine.dart';

/// Low-latency production backend with streaming, mixing buses, spatial
/// attenuation, and Doppler through SoLoud/miniaudio.
class GlintSoLoudAudioBackend implements GlintAudioBackend {
  GlintSoLoudAudioBackend({soloud.SoLoud? player})
    : _player = player ?? soloud.SoLoud.instance;

  final soloud.SoLoud _player;
  final Map<int, soloud.AudioSource> _clips = {};
  final Map<int, soloud.Bus> _buses = {};
  var _nextClipId = 1;

  @override
  Future<void> initialize(GlintAudioConfig config) async {
    await _player.init(
      sampleRate: config.sampleRate,
      bufferSize: config.bufferSize,
      lowLatency: config.lowLatency,
    );
    _player.setMaxActiveVoiceCount(config.maxActiveVoices);
    _player.set3dSoundSpeed(343 * config.worldUnitsPerMeter);
  }

  @override
  Future<void> dispose() async {
    if (_player.isInitialized) _player.deinit();
    _clips.clear();
    _buses.clear();
  }

  soloud.LoadMode _mode(GlintAudioLoadMode mode) =>
      mode == GlintAudioLoadMode.memory
      ? soloud.LoadMode.memory
      : soloud.LoadMode.disk;

  @override
  Future<int> load(GlintAudioSource source) async {
    final loaded = switch (source) {
      GlintAssetAudioSource value => _player.loadAsset(
        value.assetKey,
        mode: _mode(value.mode),
      ),
      GlintFileAudioSource value => _player.loadFile(
        value.path,
        mode: _mode(value.mode),
      ),
      GlintNetworkAudioSource value => _player.loadUrl(
        value.url,
        mode: _mode(value.mode),
      ),
      GlintMemoryAudioSource value => _player.loadMem(
        value.debugLabel,
        value.bytes,
        mode: _mode(value.mode),
      ),
    };
    final id = _nextClipId++;
    _clips[id] = await loaded;
    return id;
  }

  @override
  Future<void> unload(int clipId) async {
    final clip = _clips.remove(clipId);
    if (clip != null) await _player.disposeSource(clip);
  }

  @override
  int createBus(String name) {
    final bus = _player.createMixingBus(name: name)..playOnEngine();
    _buses[bus.busId] = bus;
    return bus.busId;
  }

  @override
  Future<void> destroyBus(int busId) async {
    _buses.remove(busId)?.dispose();
  }

  @override
  void setBusVolume(int busId, double volume) {
    final handle = _bus(busId).soundHandle;
    if (handle != null) _player.setVolume(handle, volume);
  }

  @override
  int play(
    int clipId, {
    required int busId,
    required GlintAudioPlayOptions options,
  }) {
    final handle = _player.play(
      _clip(clipId),
      busId: busId,
      volume: options.volume,
      pan: options.pan,
      paused: options.paused,
      looping: options.looping,
      loopingStartAt: options.loopStart,
    );
    _configureVoice(handle, options);
    return handle.id;
  }

  @override
  int playSpatial(
    int clipId,
    Vector3 position, {
    required int busId,
    required GlintSpatialAudioOptions options,
  }) {
    final velocity = options.velocity;
    final handle = _player.play3d(
      _clip(clipId),
      position.x,
      position.y,
      position.z,
      velX: velocity.x,
      velY: velocity.y,
      velZ: velocity.z,
      busId: busId,
      volume: options.volume,
      paused: options.paused,
      looping: options.looping,
      loopingStartAt: options.loopStart,
    );
    _configureVoice(handle, options);
    _player.set3dSourceMinMaxDistance(
      handle,
      options.minimumDistance,
      options.maximumDistance,
    );
    _player.set3dSourceAttenuation(
      handle,
      options.attenuation.index,
      options.rolloff,
    );
    _player.set3dSourceDopplerFactor(handle, options.dopplerFactor);
    return handle.id;
  }

  void _configureVoice(
    soloud.SoundHandle handle,
    GlintAudioPlayOptions options,
  ) {
    if (options.playbackRate != 1) {
      _player.setRelativePlaySpeed(handle, options.playbackRate);
    }
    if (options.protected) _player.setProtectVoice(handle, true);
  }

  @override
  bool isVoiceActive(int voiceId) =>
      _player.isInitialized &&
      _player.getIsValidVoiceHandle(soloud.SoundHandle(voiceId));

  @override
  Future<void> stopVoice(int voiceId) =>
      _player.stop(soloud.SoundHandle(voiceId));

  @override
  void pauseVoice(int voiceId, bool paused) =>
      _player.setPause(soloud.SoundHandle(voiceId), paused);

  @override
  void setVoiceVolume(int voiceId, double volume) =>
      _player.setVolume(soloud.SoundHandle(voiceId), volume);

  @override
  void fadeVoiceVolume(int voiceId, double volume, Duration duration) =>
      _player.fadeVolume(soloud.SoundHandle(voiceId), volume, duration);

  @override
  void setVoicePlaybackRate(int voiceId, double rate) =>
      _player.setRelativePlaySpeed(soloud.SoundHandle(voiceId), rate);

  @override
  void setVoiceSpatialState(int voiceId, Vector3 position, Vector3 velocity) =>
      _player.set3dSourceParameters(
        soloud.SoundHandle(voiceId),
        position.x,
        position.y,
        position.z,
        velocity.x,
        velocity.y,
        velocity.z,
      );

  @override
  void setListener(GlintAudioListener listener) {
    final forward = listener.forward.normalized;
    final up = listener.up.normalized;
    _player.set3dListenerParameters(
      listener.position.x,
      listener.position.y,
      listener.position.z,
      forward.x,
      forward.y,
      forward.z,
      up.x,
      up.y,
      up.z,
      listener.velocity.x,
      listener.velocity.y,
      listener.velocity.z,
    );
  }

  @override
  void setMasterVolume(double volume) => _player.setGlobalVolume(volume);

  soloud.AudioSource _clip(int id) =>
      _clips[id] ?? (throw StateError('Unknown audio clip $id.'));

  soloud.Bus _bus(int id) =>
      _buses[id] ?? (throw StateError('Unknown audio bus $id.'));
}
