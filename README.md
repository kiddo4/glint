# Glint

**3D belongs in the widget tree.**

Glint is a pure-Dart 3D engine for Flutter, built directly on Flutter GPU
(Impeller). It renders real glTF/GLB models — textures, multi-material
meshes, PBR lighting, HDRI reflections, animations — as ordinary widgets:
no platform views, no WebViews, no native code. Overlay Flutter UI on your
scene, restyle materials with `setState`, pin widgets to points on a model,
and even run a game loop.

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

## What's inside

| Capability | Detail |
| --- | --- |
| glTF 2.0 loading | Binary `.glb` from assets or network; scene hierarchy, node transforms, 16/32-bit indices, normals (parsed or generated) |
| Materials | Per-primitive material batches: base-color textures + factors, metallic, roughness; embedded PNG/JPEG textures (auto-capped at 1K for mobile memory) |
| Lighting | GGX metallic-roughness PBR, directional key light, HDRI image-based lighting (`.hdr` decoder + irradiance/specular prefiltering built in), distance fog |
| Animation | glTF node animation clips: translation/rotation/scale channels, LINEAR and STEP sampling, quaternion slerp, looping |
| Interaction | Orbit/pan/zoom gestures, scroll-aware mode for scrollable pages, tap picking via CPU raycasting (Möller–Trumbore) |
| Widgets in 3D | `Label3D`: project any widget onto a model anchor with fade/hide occlusion policies |
| Game loop | `GlintGameView`: ticker-driven frames, unlimited model instances with per-node transforms, free look-at camera, translucent blob shadows, frustum culling |
| Diagnostics | Live FPS / frame time / draw call / triangle overlay; typed, actionable errors for every asset failure |

Verified at 60 fps with ~160 draw calls and ~90k triangles per frame on
an iPhone, and on macOS desktop.

## Getting started

### 1. Enable Flutter GPU (one-time, per app)

Glint renders through Flutter GPU, which ships behind a flag. Bake it into
your app so no run flags are ever needed:

**iOS and macOS** — add to `ios/Runner/Info.plist` and
`macos/Runner/Info.plist`:

```xml
<key>FLTEnableFlutterGPU</key>
<true/>
<!-- macOS only, Impeller is already default on iOS: -->
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

### 2. Render a model

```dart
import 'package:glint_engine/glint_engine.dart';

GlintGpuFirstLight(
  model: Model.asset('assets/product.glb'),           // or Model.network(url)
  environmentAsset: 'assets/studio.hdr',              // optional HDRI
  fallback: const Text('Flutter GPU unavailable'),    // shown when disabled
)
```

### 3. Or describe a scene declaratively

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

### 4. Build a game

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

## Examples

`example/` is a launcher with four demos, each a compact reference:

- **Duck Dash** — endless runner: imported multi-material models, animation
  playback, fog, blob shadows, swipe input, Flutter HUD.
- **Product configurator** — a scrollable product page with scroll-aware
  orbiting, live material swatches, tap-to-restyle, anchored labels.
- **Model viewer** — the minimal one-widget integration.
- **Anchored labels** — `Label3D` occlusion policies in isolation.

```sh
cd example && flutter run   # manifests already carry the GPU flags
```

## Gesture routing in scrollable pages

Inside a `ListView`, pass `gestureMode: GlintGestureMode.scrollAware`:
one-finger horizontal drags orbit, one-finger vertical drags keep scrolling
the page, two-finger and trackpad pinches orbit, pan, and zoom.

## Compatibility

| Platform | Status |
| --- | --- |
| iOS | Validated (60 fps on device) |
| macOS | Validated |
| Android (physical device) | Requires Vulkan (any modern device); flag baked into the example |
| Android emulator | Not supported: emulators fall back to Impeller's OpenGLES backend, which Flutter GPU does not support yet — the raster thread aborts natively. Test on a physical device. |
| Web / Windows / Linux | Not supported in v0.1 (Flutter GPU availability) |

Requires Flutter 3.44+ with Impeller.

## Troubleshooting

- **"Flutter GPU requires the Impeller rendering backend"** — the manifest
  keys from step 1 are missing, or you ran without the flags.
- **Native crash on Android:** `render_pass_gles.cc ... Check failed` — the
  device (almost always an emulator) has no Vulkan, so Impeller fell back to
  its OpenGLES backend, which Flutter GPU does not support yet. There is no
  Dart-level API to detect or catch this today; run on a physical
  Vulkan-capable Android device.
- **"Missing GLB magic header"** — the file isn't a binary glTF (`.glb`).
  If it lives in Git LFS, run `git lfs pull`; a 134-byte "file" is an LFS
  pointer, not a model.
- **Model renders but looks wrong** — Glint v0.1 reads base-color textures
  and factors; normal/ORM maps, Draco compression, and skeletal skinning
  are not supported yet.
- **Blurry textures on imported assets** — embedded textures are decoded at
  a maximum of 1024px per side to protect mobile memory.

## Outside v0.1

Skeletal skinning, morph targets, point/spot lights, shadow mapping, KTX,
custom shaders, physics, audio, Web/Windows/Linux. The roadmap lives in
[ROADMAP.md](ROADMAP.md).

## License

See [LICENSE](LICENSE). The Duck model is the Khronos glTF sample asset;
see [assets/models/ATTRIBUTION.md](assets/models/ATTRIBUTION.md).
