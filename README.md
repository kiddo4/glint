# Glint

Glint is the 3D engine for Flutter: a pure-Dart runtime for putting beautiful,
interactive glTF product experiences directly in Flutter's widget tree.

```dart
Stack(children: [
  GlintGpuFirstLight(
    model: Model.asset('assets/product.glb'),
  ),
  const ProductCard(), // ordinary Flutter UI, zero bridging
])
```

The v1 promise is deliberately narrow: load a glTF/GLB product model, render it
well through `flutter_gpu`, orbit and pick it, attach Flutter UI to its nodes,
and keep hot reload intact.

## Current bootstrap

The repository currently contains an executable API prototype and the first
verified `flutter_gpu` render pass:

- `Scene3D(scene: ...)`, `Scene`, `Node3D`, and transform hierarchy
- Perspective `OrbitCamera`, directional and ambient lighting contracts
- Automatic rotation, drag orbit, pinch zoom, and two-finger pan
- Native Flutter composition and hot-reload-safe scene code
- A temporary canvas renderer used to validate the public API
- `GlintGpuFirstLight`, an indexed GLB model using a compiled Impeller
  shader bundle and Flutter texture composition
- Packaged PNG/JPEG decoding and RGBA texture upload into a sampled GPU material
- GLB geometry, normals, embedded base-color images, and material factors
- GGX metallic-roughness lighting with directional and ambient illumination
- `Model.asset` and bounded, timeout-aware `Model.network` sources

The GPU path is the Milestone 1 architecture. The canvas renderer remains only
as a compatibility fallback; Glint does not build a separate Metal/Vulkan
abstraction.

## Run the prototype

```sh
cd example
flutter run -d macos --enable-impeller --enable-flutter-gpu
```

The example now launches **Aether Tilt**, a portrait gravity-puzzle game built
with a Glint procedural 3D scene and ordinary Flutter HUD. See
[docs/AETHER_TILT.md](docs/AETHER_TILT.md) for the game direction and first
playable scope.

## v1 scope

- `flutter_gpu` rendering on macOS, iOS, and Android
- glTF 2.0 / GLB meshes, materials, textures, and node hierarchy
- PBR metallic-roughness materials and alpha blending
- Directional and HDRI environment lighting
- Orbit, pan, zoom, and ray-cast picking
- `Scene3D`, standard Flutter overlays, and node-anchored `Label3D`
- FPS, draw-call, triangle-count diagnostics and clear asset errors

Skeletal animation, extra light/camera types, shadows, physics, particles,
audio, KTX, Rust/FFI, shader graphs, and visual tooling are deferred until the
runtime earns adoption.

See [ROADMAP.md](ROADMAP.md) for the execution plan.
