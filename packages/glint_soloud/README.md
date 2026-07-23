# glint_soloud

Production audio for Glint Engine through SoLoud/miniaudio: low-latency sound
effects, streamed music, gapless loops, protected voices, mixing buses, 3D
attenuation, moving listeners/sources, and Doppler.

```dart
final audio = GlintAudioEngine(backend: GlintSoLoudAudioBackend());
await audio.initialize();

final effects = audio.createBus('effects');
final impact = await audio.load(
  const GlintAudioSource.asset('assets/audio/impact.ogg'),
);
audio.playSpatial(impact, hitPosition, bus: effects);
```

Encoded bytes are supported too, so generated WAV data, encrypted asset
archives, and application-managed download caches do not need temporary files:

```dart
final generated = await audio.load(
  GlintAudioSource.memory('generated.wav', wavBytes),
);
```

Use `GlintAudioLoadMode.stream` for long music/ambience and memory mode for
latency-sensitive effects. Update the listener and moving spatial voices from
the game loop; Glint forwards position and velocity for attenuation and
Doppler.

The host needs CMake to build `flutter_soloud` (for example,
`brew install cmake` on macOS). The backend is optional: applications that do
not depend on `glint_soloud` do not inherit its native build.
