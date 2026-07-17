# Glint

Glint is the 3D engine for Flutter: a pure-Dart runtime for putting beautiful,
interactive glTF product experiences directly in Flutter's widget tree.

```dart
Stack(children: [
  Scene3D(scene: ProductShowroom()),
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
- Orbit and zoom gestures
- Native Flutter composition and hot-reload-safe scene code
- A temporary canvas renderer used to validate the public API
- `GlintGpuFirstLight`, an offscreen GPU triangle using a compiled Impeller
  shader bundle and Flutter texture composition

This renderer is not the v1 architecture. Milestone 1 replaces it with
`flutter_gpu`; Glint does not build a separate Metal/Vulkan abstraction.

## Run the prototype

```sh
cd example
flutter run -d macos --enable-flutter-gpu
```

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
