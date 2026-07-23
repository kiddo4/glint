import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glint_engine/glint_engine.dart';
import 'package:glint_soloud/glint_soloud.dart';

class SystemsDemoPage extends StatefulWidget {
  const SystemsDemoPage({super.key});

  @override
  State<SystemsDemoPage> createState() => _SystemsDemoPageState();
}

class _SystemsDemoPageState extends State<SystemsDemoPage> {
  static const _camera = GlintGameCamera(
    position: Vector3(0, 2.4, 7),
    target: Vector3(0, .8, 0),
  );

  late final GlintParticleSystem _energy = GlintParticleSystem(
    const GlintParticleConfig(
      maxParticles: 1400,
      duration: 4,
      emissionRate: 180,
      lifetime: GlintDoubleRange(.45, 1.35),
      startSpeed: GlintDoubleRange(.8, 3.4),
      startSize: GlintDoubleRange(.025, .11),
      angularVelocity: GlintDoubleRange(-5, 5),
      startColor: GlintParticleColorRange(
        GlintParticleColor(.05, .65, 1),
        GlintParticleColor(.35, 1, 1),
      ),
      colorOverLifetime: GlintParticleGradient([
        GlintParticleColorKey(0, GlintParticleColor.white),
        GlintParticleColorKey(.55, GlintParticleColor(.2, .75, 1, .85)),
        GlintParticleColorKey(1, GlintParticleColor.transparent),
      ]),
      sizeOverLifetime: GlintScalarCurve([
        GlintScalarKey(0, .15),
        GlintScalarKey(.12, 1),
        GlintScalarKey(1, .05),
      ]),
      gravity: Vector3(0, -.75, 0),
      drag: .22,
      noise: GlintParticleNoise(
        strength: 2.2,
        frequency: 1.7,
        scrollSpeed: 2.4,
      ),
      shape: GlintSphereParticleShape(radius: 1.25, fromShell: true),
      blendMode: GlintParticleBlendMode.additive,
    ),
    seed: 0x51a7,
    transform: const Transform3D(position: Vector3(0, .8, 0)),
  );

  late final GlintParticleSystem _burst = GlintParticleSystem(
    const GlintParticleConfig(
      maxParticles: 800,
      duration: 1,
      looping: false,
      emissionRate: 0,
      lifetime: GlintDoubleRange(.55, 1.5),
      startSpeed: GlintDoubleRange(2.5, 6.5),
      startSize: GlintDoubleRange(.04, .14),
      startColor: GlintParticleColorRange(
        GlintParticleColor(1, .25, .05),
        GlintParticleColor(1, .9, .15),
      ),
      colorOverLifetime: GlintParticleGradient([
        GlintParticleColorKey(0, GlintParticleColor.white),
        GlintParticleColorKey(.35, GlintParticleColor(1, .42, .05, .9)),
        GlintParticleColorKey(1, GlintParticleColor.transparent),
      ]),
      sizeOverLifetime: GlintScalarCurve([
        GlintScalarKey(0, .3),
        GlintScalarKey(.15, 1),
        GlintScalarKey(1, .08),
      ]),
      gravity: Vector3(0, -4.5, 0),
      drag: .1,
      shape: GlintSphereParticleShape(radius: .25, fromShell: true),
      blendMode: GlintParticleBlendMode.additive,
    ),
    seed: 0xbad5eed,
    transform: const Transform3D(position: Vector3(0, .8, 0)),
    initiallyPlaying: false,
  );

  late final Future<GlintShaderGraphMaterial> _material = _loadMaterial();
  final GlintAudioEngine _audio = GlintAudioEngine(
    backend: GlintSoLoudAudioBackend(),
  );
  GlintAudioBus? _effects;
  GlintAudioClip? _pulse;
  String _audioState = 'audio starting';
  double _time = 0;

  @override
  void initState() {
    super.initState();
    _initializeAudio();
  }

  Future<GlintShaderGraphMaterial> _loadMaterial() async {
    final source = await rootBundle.loadString(
      'assets/shaders/hologram.shadergraph.json',
    );
    final program = const GlintShaderGraphCompiler().compile(
      GlintShaderGraph.parse(source),
    );
    return GlintShaderGraphMaterial(
      bundleAsset: 'build/shaderbundles/glint_materials.shaderbundle',
      fragmentEntry: 'HologramFragment',
      program: program,
      parameters: const {
        'tint': GlintParticleColor(.08, .75, 1, 1),
        'roughness': .22,
      },
    );
  }

  Future<void> _initializeAudio() async {
    try {
      await _audio.initialize(
        config: const GlintAudioConfig(maxActiveVoices: 48),
      );
      _effects = _audio.createBus('effects', volume: .7);
      _pulse = await _audio.load(
        GlintAudioSource.memory('generated-energy-pulse.wav', _pulseWav()),
      );
      _audio.listener = const GlintAudioListener(
        position: Vector3(0, 2.4, 7),
        forward: Vector3(0, -1.6, -7),
      );
      if (mounted) setState(() => _audioState = 'spatial audio ready');
    } catch (error) {
      if (mounted) setState(() => _audioState = 'audio unavailable');
    }
  }

  void _fireBurst() {
    _burst.emit(220);
    final pulse = _pulse;
    if (pulse != null) {
      _audio.playSpatial(
        pulse,
        const Vector3(0, .8, 0),
        bus: _effects,
        options: const GlintSpatialAudioOptions(
          volume: .9,
          minimumDistance: .5,
          maximumDistance: 24,
          rolloff: .75,
        ),
      );
    }
  }

  GlintGameFrame _frame(double delta) {
    _time += delta;
    _energy.update(delta);
    _burst.update(delta);
    return GlintGameFrame(
      camera: _camera,
      instances: [
        GlintGameInstance(
          model: 'relic',
          transform: Transform3D(
            position: const Vector3(0, .8, 0),
            rotation: Vector3(.15, _time * .7, 0),
            scale: const Vector3(.75, .75, .75),
          ),
        ),
      ],
      particles: [_energy.renderBatch, _burst.renderBatch],
    );
  }

  @override
  void dispose() {
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Advanced systems lab')),
    body: FutureBuilder<GlintShaderGraphMaterial>(
      future: _material,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Shader graph failed: ${snapshot.error}'));
        }
        final material = snapshot.data;
        if (material == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            GlintGameView(
              models: const {
                'relic': Model.asset('assets/models/cc0_gold_coin_blank.glb'),
              },
              onFrame: (delta) {
                final frame = _frame(delta);
                return GlintGameFrame(
                  camera: frame.camera,
                  instances: [
                    for (final instance in frame.instances)
                      GlintGameInstance(
                        model: instance.model,
                        transform: instance.transform,
                        shaderMaterial: material,
                      ),
                  ],
                  particles: frame.particles,
                );
              },
              backgroundColor: const Color(0xff020711),
              lightDirection: const Vector3(.4, -1, -.3),
              lightIntensity: 1.7,
              ambientIntensity: .16,
              showStats: true,
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 24,
              child: Card(
                color: const Color(0xdd0a1526),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Deterministic pooled particles + an offline typed '
                          'shader graph + generated 3D audio.',
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _fireBurst,
                        icon: const Icon(Icons.bolt),
                        label: Text(_audioState),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

Uint8List _pulseWav() {
  const sampleRate = 22050;
  const durationSeconds = .18;
  final sampleCount = (sampleRate * durationSeconds).round();
  final dataLength = sampleCount * 2;
  final data = ByteData(44 + dataLength);

  void text(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      data.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  text(0, 'RIFF');
  data.setUint32(4, 36 + dataLength, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, dataLength, Endian.little);
  for (var index = 0; index < sampleCount; index++) {
    final progress = index / sampleCount;
    final frequency = 180 + 540 * progress;
    final envelope = math.sin(math.pi * progress) * (1 - progress * .35);
    final sample = math.sin(2 * math.pi * frequency * index / sampleRate);
    data.setInt16(
      44 + index * 2,
      (sample * envelope * 24000).round(),
      Endian.little,
    );
  }
  return data.buffer.asUint8List();
}
