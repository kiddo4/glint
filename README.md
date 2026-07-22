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
| Animation | glTF node and skeletal animation: vertex skinning, LINEAR/STEP/CUBICSPLINE sampling, quaternion slerp, looping or one-shot playback |
| Physics | Backend-neutral fixed stepping plus an optional Box3D backend: angular rigid bodies, CCD, sleeping, compound/convex/mesh/heightfield colliders, joints, events, ray/overlap/shape queries, filtering, and interpolated render transforms |
| Vehicle dynamics | Optional raycast vehicle layer with self-excluding wheel rays, spring/damper suspension, load-sensitive tire grip, anti-roll, automatic gears, brakes/handbrake, aero, boost, surface grip hooks, and telemetry |
| Interaction | Orbit/pan/zoom gestures, scroll-aware mode for scrollable pages, tap picking via CPU raycasting (Möller–Trumbore) |
| Widgets in 3D | `Label3D`: project any widget onto a model anchor with fade/hide occlusion policies |
| Game loop | `GlintGameView`: ticker-driven frames, unlimited model instances with per-node transforms, free look-at camera, translucent blob shadows, frustum culling |
| Diagnostics | Live FPS / frame time / draw call / triangle overlay; typed, actionable errors for every asset failure |

> **Status:** v0.1, feature-complete for the first release and validated at
> 60 fps with ~160 draw calls per frame on a physical iPhone and on macOS
> desktop. Like [Flutter GPU](https://github.com/flutter/flutter/blob/main/docs/engine/impeller/Flutter-GPU.md)
> itself, Glint is early — expect rough edges, and see [Outside v0.1](#outside-v01)
> for what isn't here yet.

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

### 6. Add physics

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

## Examples

`example/` is a launcher with six demos, each a compact reference:

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

Not the same bet. [`flutter_scene`](https://github.com/bdero/flutter_scene)
is a general-purpose scene graph; Glint is a product-experience engine
built widget-first: scenes are declarative Flutter state (`Scene3D`,
restyled with `setState`), Flutter widgets anchor to points on a model with
real occlusion, gestures cooperate with scrollable pages, and it drives a
real-time game loop with a Flutter HUD over it. Owning the whole
pipeline — glTF parser, PBR + IBL shaders, picking, animation — is
deliberate: every millisecond of the frame is understood, not inherited.

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

## Outside v0.1

Morph targets, normal/ORM maps, Draco compression, KTX, custom shaders,
audio, Web/Windows/Linux rendering. Open an issue if one
of these is blocking you — real projects are what decide what comes next.

## License

[MIT](LICENSE). The Duck model is the Khronos glTF sample asset; see
[assets/models/ATTRIBUTION.md](assets/models/ATTRIBUTION.md).

<p align="center">
  <sub><a href="https://glint.kiddobuild.dev">glint.kiddobuild.dev</a> · <a href="https://github.com/kiddo4/glint">GitHub</a> · <a href="https://pub.dev/packages/glint_engine">pub.dev</a></sub>
</p>
