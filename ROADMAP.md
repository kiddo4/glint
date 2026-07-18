# Glint execution roadmap

The roadmap follows the new PRD's brutal cut. v0.1 is a product-experience
engine, not a general game engine.

## Milestone 0 — Direction and API bootstrap (complete)

- Establish the `glint` package identity
- Prove `Scene3D(scene: ProductShowroom())` inside a Flutter `Stack`
- Validate scene hierarchy, orbit gestures, hot reload, and overlay composition
- Preserve renderer replacement behind the scene API

## Milestone 1 — First Light (complete)

- [x] Pin Flutter 3.44.1 stable with Impeller and opt-in `flutter_gpu`
- [x] Compile a multi-backend Impeller shader bundle
- [x] Render a triangle offscreen and composite its texture in Flutter
- [x] Indexed cube with model-view-projection and a depth attachment
- [x] Texture coordinates, sampler, and procedural GPU image upload
- [x] Decode PNG/JPEG assets into upload-ready RGBA pixels
- [x] Wire a packaged PNG through decoding, upload, and the showcase sampler
- [x] Expose reusable `Model.asset` and bounded `Model.network` sources
- [x] Parse GLB headers, JSON/BIN chunks, buffer views, and mesh accessors
- [x] Render GLB positions, UVs, and 16/32-bit indices instead of cube geometry
- [x] Resolve base-color material factors and embedded GLB image buffer views
- [x] Render the official Khronos Duck GLB with its own embedded texture
- [x] Parse or generate normals for lit meshes
- [x] Perspective camera with automatic rotation, orbit, pan, and zoom
- [x] GGX metallic-roughness shader with directional and ambient light
- [x] Actionable typed image, GLB, HTTP, size, and timeout errors

The v0.1 loader intentionally renders the first triangle primitive. Multi-node,
multi-primitive scene aggregation is part of Milestone 2's scene graph work.

Deliverable: a spinning, well-lit real glTF model inside the showcase app.

## Milestone 2 — Scene Engine (6–8 weeks)

- [x] Traverse active glTF scene roots and child-node hierarchies
- [x] Compose node matrix or translation/rotation/scale world transforms
- [x] Transform mesh positions and normals and expose world-space bounds
- [x] Aggregate triangle primitives across active mesh-node instances
- [x] View-frustum culling
- [x] Ray construction, mesh intersection, and tap picking
- [x] HDRI image-based environment lighting
- [x] Runtime base-color, metallic, and roughness updates
- [x] Debug overlay for FPS, draw calls, and triangle count

Deliverable: tap product parts and change their materials live.

## Milestone 3 — The Moat (4–6 weeks)

- [x] Harden the `Scene3D` public API and hot-reload lifecycle
- [x] Implement `Label3D` with node-to-screen projection and occlusion policy
- [x] Resolve Flutter-scroll versus scene-orbit gesture routing
- [x] Build the flagship configurator with Flutter controls and anchored labels

Deliverable: the public launch demo and video.

## Milestone 4 — v0.1 release (3–4 weeks)

- Three runnable examples: viewer, configurator, anchored labels
- API reference, copy-paste guides, compatibility table, and troubleshooting
- Device performance validation on macOS, iOS, and mid-range Android
- Package hygiene and pub.dev release readiness

## Explicitly outside v0.1

Skeletal animation, point/spot lights, shadows, physics, particles, audio, KTX,
custom shader graphs, non-orbit cameras, editor tooling, Rust/FFI, Windows,
Linux, Web, and XR.
