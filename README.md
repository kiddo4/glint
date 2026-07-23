<p align="center">
  <img alt="Glint" width="640" src="https://glint.kiddobuild.dev/og.png">
</p>

<h1 align="center">Glint</h1>

<p align="center"><b>A Flutter-first 3D engine built on Flutter GPU.</b></p>

<p align="center">
  <a title="Pub" href="https://pub.dev/packages/glint_engine"><img src="https://img.shields.io/pub/v/glint_engine.svg?style=popout"/></a>
  <a title="Pub points" href="https://pub.dev/packages/glint_engine/score"><img src="https://img.shields.io/pub/points/glint_engine"/></a>
  <a title="License" href="LICENSE"><img src="https://img.shields.io/github/license/kiddo4/glint"/></a>
</p>

<p align="center">
  <a href="https://glint.kiddobuild.dev">Website</a> ·
  <a href="https://pub.dev/packages/glint_engine">pub.dev</a> ·
  <a href="https://pub.dev/documentation/glint_engine/latest/">API docs</a> ·
  <a href="https://glint.kiddobuild.dev/#showcase">See it running</a> ·
  <a href="#faq">FAQ</a>
</p>

Glint renders real glTF/GLB models — textures, multi-material meshes, PBR
lighting, HDRI reflections, animations — as ordinary Flutter widgets. No
platform views or WebViews. The renderer and physics contract stay in Dart;
the optional high-performance Box3D backend uses native assets. Overlay Flutter UI on your
scene, restyle materials with `setState`, pin widgets to points on a model,
and run a real-time game loop, all from Dart.

```dart
Scene3D(
  scene: ProductShowroom(),          // declarative scene description
  onModelTap: (hit) => restyle(hit), // CPU-accurate tap picking
  labels: [
    Label3D(                          // a real Flutter widget, pinned to
      anchor: Vector3(.96, 1.34, 0),  // a point on the model's surface
      child: PriceTag(),
    ),
  ],
)
```

**[Watch Duck Dash run at 60 fps on iPhone →](https://glint.kiddobuild.dev/#showcase)**
An endless runner built entirely on the engine below — imported models,
animation, fog, a chase camera, and a Flutter HUD.

## What's inside

| Capability | Detail |
| --- | --- |
| glTF 2.0 loading | Binary `.glb` from assets or network; scene hierarchy, node transforms, 16/32-bit indices, normals (parsed or generated) |
| Materials | Per-primitive material batches: base-color textures + factors, metallic, roughness; embedded PNG/JPEG textures (auto-capped at 1K for mobile memory) |
| Lighting | GGX metallic-roughness PBR, directional/point/spot lights, directional shadows, HDRI image-based lighting (`.hdr` decoder + irradiance/specular prefiltering built in), distance fog |
| Animation | glTF node and skeletal animation: vertex skinning, LINEAR/STEP/CUBICSPLINE sampling, crossfades, additive/override layers, bone masks, events, state machines, and root motion |
| Physics | Backend-neutral fixed stepping plus an optional Box3D backend: angular rigid bodies, CCD, sleeping, compound/convex/mesh/heightfield colliders, joints, persistent contacts, ray/overlap/shape queries, character and vehicle motors, ragdolls, profiling, rollback snapshots, and deterministic replay |
| Vehicle dynamics | Optional raycast vehicle layer with self-excluding wheel rays, spring/damper suspension, material-aware tire grip, dynamic-surface reactions, anti-roll, automatic gears, brakes/handbrake, aero, boost, runtime grip hooks, and telemetry |
| Particles | Deterministic pooled simulation with point/box/sphere/cone emitters, rate and burst emission, curves, gradients, noise, local/world space, sprite sheets, physics-backed collision, alpha/additive blending, and GPU billboards |
| Audio | Backend-neutral cached clips, memory/file/asset/network sources, streaming policy, mixer buses, voice control, listener/source motion, attenuation, and Doppler; optional native SoLoud/miniaudio backend |
| Compressed textures | Validated KTX2 parsing, `KHR_texture_basisu` resolution, mip selection, uncompressed KTX2 decoding, and optional official Basis Universal native transcoding on a background isolate |
| Shader graphs | Typed JSON graphs with cycle/type validation, parameters and custom textures, engine PBR/IBL/lights/fog integration, offline Impeller compilation, and static or skinned runtime materials |
| Interaction | Orbit/pan/zoom gestures, scroll-aware mode for scrollable pages, tap picking via CPU raycasting (Möller–Trumbore) |
| Widgets in 3D | `Label3D`: project any widget onto a model anchor with fade/hide occlusion policies |
| Game loop | `GlintGameView`: ticker-driven frames, unlimited model instances with per-node transforms, free look-at camera, translucent blob shadows, frustum culling |
| Diagnostics | Live FPS / frame time / draw call / triangle overlay; deterministic physics state digests; repeatable mixed body/contact/query/vehicle stress harness; typed asset errors |

> **Status:** the published v0.1 line is validated at 60 fps with ~160 draw
> calls per frame on a physical iPhone and on macOS. The current development
> line expands Glint into skeletal animation and general 3D physics. Like
> [Flutter GPU](https://github.com/flutter/flutter/blob/main/docs/engine/impeller/Flutter-GPU.md)
> itself, Glint is early — expect APIs to keep maturing before 1.0.

## Getting started

### 1. Install

```sh
flutter pub add glint_engine
```

### 2. Enable Flutter GPU (one-time, per app)

Glint renders through Flutter GPU, which ships behind a flag. Bake it into
your app so no run flags are ever needed:

**iOS and macOS** — add to `ios/Runner/Info.plist` and
`macos/Runner/Info.plist`:

```xml
<key>FLTEnableFlutterGPU</key>
<true/>
<!-- macOS only, Impeller is already the default on iOS: -->
<key>FLTEnableImpeller</key>
<true/>
```

**Android** — add inside `<application>` in
`android/app/src/main/AndroidManifest.xml`:

```xml
<meta-data
    android:name="io.flutter.embedding.android.EnableFlutterGPU"
    android:value="true" />
```

(For a quick trial without editing manifests:
`flutter run --enable-impeller --enable-flutter-gpu`.)

### 3. Render a model

```dart
import 'package:glint_engine/glint_engine.dart';

GlintGpuFirstLight(
  model: Model.asset('assets/product.glb'),           // or Model.network(url)
  environmentAsset: 'assets/studio.hdr',              // optional HDRI
  fallback: const Text('Flutter GPU unavailable'),    // shown when disabled
)
```

### 4. Or describe a scene declaratively

```dart
class Showroom extends Scene {
  const Showroom({this.finish});
  final Material3D? finish;

  @override
  List<Light3D> get lights => const [
    DirectionalLight(direction: Vector3(.55, -1, -.65), intensity: .87),
    EnvironmentLight(asset: 'assets/studio.hdr'),
  ];

  @override
  List<Node3D> get children => [
    Node3D(
      model: const Model.asset('assets/product.glb'),
      material: finish, // null keeps the model's own material
    ),
  ];
}

// Restyling is just state:
Scene3D(scene: Showroom(finish: selected))
```

### 5. Build a game

```dart
GlintGameView(
  models: const {
    'hero': Model.asset('assets/hero.glb'),
    'crate': Model.asset('assets/crate.glb'),   // animated GLBs just work
  },
  fogColor: sky, fogDistance: 95,
  onFrame: (dt) {
    world.step(dt);                              // your simulation
    return GlintGameFrame(
      camera: GlintGameCamera(position: eye, target: focus),
      instances: [
        for (final thing in world.things)
          GlintGameInstance(
            model: thing.kind,
            transform: thing.transform,
            animationTime: world.clock,          // loops the model's clip
          ),
      ],
    );
  },
)
```

The example app ships a complete endless runner (Duck Dash) built this way.

### 6. Blend character animation

```dart
final rig = await GlintGlbRig.fromAsset('assets/hero.glb');
final animation = GlintAnimationController(
  rig,
  initialAnimation: 0,
  events: const [
    GlintAnimationEvent(animationIndex: 1, time: .24, name: 'footstep'),
  ],
);

// Switch clips without popping. Interrupted fades start at the visible pose.
animation.play(1, fadeDuration: .25);

// Inside GlintGameView.onFrame:
final animated = animation.update(dt);
final hero = GlintGameInstance(model: 'hero', animationPose: animated.pose);
for (final event in animated.events) {
  if (event.event.name == 'footstep') playFootstep();
}
```

`GlintAnimationController` also supports masked override layers, additive
layers, loop-safe root-motion extraction, reverse playback, and a parameter-
driven `GlintAnimationStateMachine`.

### 7. Add physics

The engine package defines the portable contract. Choose a backend separately;
the repository ships `packages/glint_box3d` for production-grade 3D dynamics.

```dart
await GlintBox3dWorld.ensureInitialized();
final physics = GlintBox3dWorld(fixedTimeStep: 1 / 120);
final player = physics.createBody(
  const GlintRigidBodyConfig(
    position: Vector3(0, 4, 0),
    ccdEnabled: true,
  ),
);
player.addCollider(
  const GlintCapsuleCollider(radius: .45, halfHeight: .7),
  material: const GlintPhysicsMaterial(density: 80, friction: .8),
);

// Inside GlintGameView.onFrame:
physics.step(dt);
final instance = GlintGameInstance(
  model: 'player',
  transform: player.toTransform(),
);
```

`GlintPhysicsWorld` is not car-specific. It supports general rigid-body games,
product interactions, characters, destructible props, triggers, constraints,
and spatial queries. `GlintRaycastVehicle` is a higher-level consumer of the
same API and can be omitted entirely.

The reusable character motor is also backend-neutral. It owns input policy
instead of assuming a particular genre, while the engine handles capsule
sweeps, slopes, steps, moving platforms, ground snap, acceleration, and jump
state:

```dart
final character = GlintCharacterController.create(
  world: physics,
  position: const Vector3(0, 1, 0),
);
character.desiredVelocity = inputDirection * runSpeed;
character.jump(6);
```

Contacts remain queryable after their begin event and emit
`GlintContactStayed` each fixed tick. This supports damage volumes, pressure
plates, feet, tire/surface state, and interaction prompts without maintaining a
second pair cache:

```dart
for (final contact in physics.activeContacts) {
  if (contact.involves(player)) handleContact(contact);
}

physics.addStepCompletedCallback((stats) {
  telemetry.recordPhysics(stats.backendTime, stats.activeContactCount);
});
```

`GlintRagdollDefinition` maps any chosen rig nodes to colliders and fixed,
revolute, or spherical constraints. A `GlintRagdoll` can follow animation as
kinematic bodies, switch to simulation, accept per-part impulses, and return a
partially or fully physics-driven `GlintAnimationPose` for the skinned renderer.

### 8. Record and verify physics

Snapshots restore rigid bodies, the fixed-step clock, gravity, and registered
gameplay systems such as `GlintRaycastVehicle`:

```dart
final checkpoint = physics.captureSnapshot();

// Simulate a risky move, rollback netcode frame, retry, etc.
physics.restoreSnapshot(checkpoint);
```

For deterministic replays, record one immutable input per fixed tick. Each
frame stores a quantized state digest so a regression reports the exact first
divergent tick instead of merely looking different on screen:

```dart
final recorder = GlintPhysicsReplayRecorder<CarInput>(
  world: physics,
  applyInput: (input, fixedDt) => car.apply(input),
);

recorder.record(const CarInput(throttle: 1));
final replay = recorder.finish();
final result = replay.play(physics, (input, fixedDt) => car.apply(input));
assert(result.deterministic);
```

Input tapes can be JSON encoded with an application-provided input codec. The
in-memory world snapshot is intentionally not serialized; portable playback
recreates the level normally, then applies the recorded fixed-step inputs.

### 9. Stress a physics backend

`GlintPhysicsStressRunner` builds the same seeded mixed workload on any
backend: dense box/sphere/capsule/cylinder contacts, impulses, ray/overlap/
shape queries, and optional raycast vehicles. The Box3D package includes a CI-
friendly launcher:

```sh
cd packages/glint_box3d
flutter test benchmark/physics_stress_test.dart --reporter expanded
```

Scale it through Dart defines such as `GLINT_STRESS_BODIES`,
`GLINT_STRESS_VEHICLES`, `GLINT_STRESS_STEPS`, `GLINT_STRESS_QUERIES`, and
`GLINT_STRESS_MINIMUM_REALTIME`.

### 10. Build particle effects

Particle simulation is independent of rendering, seeded for replay-friendly
results, and stored in dense reusable typed arrays. Feed its zero-copy render
batch to any `GlintGameFrame`:

```dart
final sparks = GlintParticleSystem(
  const GlintParticleConfig(
    maxParticles: 2000,
    emissionRate: 240,
    lifetime: GlintDoubleRange(.25, 1.1),
    startSpeed: GlintDoubleRange(2, 8),
    shape: GlintConeParticleShape(angle: .35, baseRadius: .1),
    gravity: Vector3(0, -9.81, 0),
    blendMode: GlintParticleBlendMode.additive,
  ),
  seed: 42,
);

// In onFrame:
sparks.update(dt, collisions: GlintPhysicsParticleCollisionResolver(world));
return GlintGameFrame(
  camera: camera,
  instances: instances,
  particles: [sparks.renderBatch],
);
```

Use `simulationSpace: local` for an emitter that follows a moving transform,
or `world` for trails that remain behind. Collision queries and emitted events
are world-space in both modes.

### 11. Add spatial audio

The core audio contract does not lock a game to one mixer. The optional
`glint_soloud` package supplies the production SoLoud/miniaudio backend:

```dart
final audio = GlintAudioEngine(backend: GlintSoLoudAudioBackend());
await audio.initialize(
  config: const GlintAudioConfig(maxActiveVoices: 96),
);
final effects = audio.createBus('effects');
final impact = await audio.load(
  const GlintAudioSource.asset('assets/audio/impact.ogg'),
);

audio.listener = GlintAudioListener(
  position: camera.position,
  forward: camera.target - camera.position,
);
audio.playSpatial(
  impact,
  hit.position,
  bus: effects,
  options: const GlintSpatialAudioOptions(
    minimumDistance: 1,
    maximumDistance: 80,
    dopplerFactor: 1,
  ),
);
```

Assets, files, URLs, and encoded memory buffers are supported. Mark music as
streamed and protected; keep short gameplay effects in memory for low latency.

### 12. Load KTX2 and Basis textures

Uncompressed RGBA/RGB/BGRA KTX2 works through the core decoder. BasisLZ,
UASTC, Zstd-supercompressed KTX2, and standalone `.basis` use the optional
native reference transcoder:

```dart
final decoder = GlintTextureDecoder(
  basisTranscoder: const GlintBasisTranscoder(),
);

GlintGameView(
  textureDecoder: decoder,
  particleTextures: const {
    'smoke': GlintTextureSource.asset('assets/smoke.ktx2'),
  },
  // ...
)
```

Glint also follows `KHR_texture_basisu.source` inside embedded GLB materials,
including assets that retain a PNG/JPEG fallback. The selected mip is decoded
on a background isolate. Flutter GPU does not yet expose ASTC/ETC/BC texture
formats or per-mip uploads, so compressed assets currently become RGBA8 before
GPU upload; this saves download/package size, but not final GPU texture memory.

### 13. Compile custom shader graphs

Graphs are JSON assets, type-checked before shader compilation, and compiled
offline by Impeller. They can drive base color, opacity, emissive, metallic,
roughness, and world-space normal from UV/time/world inputs, arithmetic,
parameters, custom textures, Fresnel, and procedural noise.

Create `hook/build.dart` in the application:

```dart
import 'package:glint_engine/shader_graph_build.dart';
import 'package:hooks/hooks.dart';

Future<void> main(List<String> args) => build(args, (input, output) async {
  await buildGlintShaderGraphBundle(
    buildInput: input,
    buildOutput: output,
    graphs: const {'Hologram': 'assets/hologram.shadergraph.json'},
  );
});
```

List `build/shaderbundles/glint_materials.shaderbundle` in `flutter.assets`,
then reference the compiled fragment on an instance. Glint reuses its static or
skinned vertex stage and preserves PBR, HDRI, punctual lights, fog, and shadow
uniforms around the graph surface:

```dart
final graph = GlintShaderGraph.parse(await rootBundle.loadString(graphAsset));
final program = const GlintShaderGraphCompiler().compile(graph);
final material = GlintShaderGraphMaterial(
  bundleAsset: 'build/shaderbundles/glint_materials.shaderbundle',
  fragmentEntry: 'Hologram',
  program: program,
  parameters: const {'glow': 2.5},
);
```

For CI or editor validation without a Flutter build, run
`dart run glint_engine:glint_shader_graph input.json output.frag`.

## Examples

`example/` is a launcher with seven demos, each a compact reference:

- **Duck Dash** — endless runner: imported multi-material models, animation
  playback, fog, blob shadows, swipe input, Flutter HUD.
- **Product configurator** — a scrollable product page with scroll-aware
  orbiting, live material swatches, tap-to-restyle, anchored labels.
- **Model viewer** — the minimal one-widget integration.
- **Anchored labels** — `Label3D` occlusion policies in isolation.
- **Skinned character** — a walking Fox driven by vertex-level bone
  deformation.
- **Arcade physics lab** — a compound-body car with four-wheel suspension,
  tire grip, gears, drift brake, boost, dynamic props, and a chase camera.
- **Advanced systems lab** — two pooled particle emitters, a generated
  in-memory 3D sound, and an offline-compiled hologram shader graph.

```sh
git clone https://github.com/kiddo4/glint.git
cd glint/example
flutter run   # manifests already carry the GPU flags
```

## Gesture routing in scrollable pages

Inside a `ListView`, pass `gestureMode: GlintGestureMode.scrollAware`:
one-finger horizontal drags orbit, one-finger vertical drags keep scrolling
the page, two-finger and trackpad pinches orbit, pan, and zoom.

## FAQ

### What platforms does this package support?

| Platform | Status |
| --- | :-- |
| iOS | 🟢 Validated — 60 fps on device |
| macOS | 🟢 Validated |
| Android | 🟡 Physical device only — see below |
| Web / Windows / Linux | ⚪ Not yet |

Glint follows wherever [Flutter GPU](https://docs.flutter.dev/perf/impeller#availability)
runs. On iOS, Impeller is already Flutter's default renderer. On macOS it's
opt-in (the manifest key above enables it). On Android, physical devices
with Vulkan work well; **emulators do not** — most lack a real Vulkan
driver, so Impeller falls back to its OpenGLES backend, which Flutter GPU
does not support yet, and the app aborts natively rather than failing
gracefully. There is no Dart-level way to detect this today, so: test on a
physical Android device. Web, Windows, and Linux aren't supported because
Flutter GPU isn't available there yet.

### Isn't this a reinvention of `flutter_scene`?

Not the same architecture. [`flutter_scene`](https://github.com/bdero/flutter_scene)
is a general-purpose scene graph with its own renderer integrations. Glint is
Flutter-widget-first: scenes can be declarative Flutter state (`Scene3D`),
widgets anchor to model points with real occlusion, gestures cooperate with
scrollable pages, and `GlintGameView` keeps a normal Flutter HUD above the game.
Glint also owns its glTF, PBR/IBL, animation, picking, diagnostics, and portable
physics contracts so those systems can evolve as one engine. Compare concrete
capabilities and platform needs for your project instead of treating either
package as a drop-in clone of the other.

### Why do I have to touch platform manifests at all?

Flutter GPU ships behind a flag while it's in preview, and Info.plist/
AndroidManifest have no cross-package way to merge settings into a host
app (unlike Android, where a plugin's manifest entries merge
automatically — something worth doing for Glint once it's a proper Flutter
plugin). Until then it's a one-time, two-line setup per app, documented
above.

## Troubleshooting

- **"Flutter GPU requires the Impeller rendering backend"** — the manifest
  keys from step 2 are missing, or you ran without the flags.
- **Native crash on Android:** `render_pass_gles.cc ... Check failed` — see
  the platform FAQ above; run on a physical Vulkan-capable device.
- **"Missing GLB magic header"** — the file isn't a binary glTF (`.glb`).
  If it lives in Git LFS, run `git lfs pull`; a 134-byte "file" is an LFS
  pointer, not a model.
- **Model renders but looks wrong** — Glint reads base-color textures and
  factors, but normal/ORM maps and Draco compression are not supported yet.
- **Blurry textures on imported assets** — embedded textures are decoded at
  a maximum of 1024px per side to protect mobile memory.
- **SoLoud reports that CMake is missing** — install CMake before building the
  optional native audio backend (`brew install cmake` on macOS).
- **A shader graph bundle is missing** — ensure the app has `hook/build.dart`
  and lists its generated `build/shaderbundles/*.shaderbundle` under assets.

## Not yet implemented

Morph targets, normal/ORM maps, Draco compression, a visual graph editor,
GPU-resident compressed textures (pending Flutter GPU APIs), soft bodies,
network transports, and Web/Windows/Linux rendering. Open an issue if one
of these is blocking you — real projects are what decide what comes next.

## License

[MIT](LICENSE). The Duck model is the Khronos glTF sample asset; see
[assets/models/ATTRIBUTION.md](assets/models/ATTRIBUTION.md).

<p align="center">
  <sub><a href="https://glint.kiddobuild.dev">glint.kiddobuild.dev</a> · <a href="https://github.com/kiddo4/glint">GitHub</a> · <a href="https://pub.dev/packages/glint_engine">pub.dev</a></sub>
</p>
