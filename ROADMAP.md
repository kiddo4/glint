# Glint execution roadmap

Glint began as a focused product-experience renderer. The current direction is
a general Flutter-first 3D engine whose public systems remain composable: the
renderer, animation runtime, physics contract, native backend, and higher-level
gameplay helpers can be used independently.

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

- [x] Runnable examples: viewer, configurator, anchored labels, Duck Dash
- [x] README with quick start, copy-paste guides, compatibility table, and
      troubleshooting; dartdoc comments across the public API
- [x] Device performance validation on macOS and iPhone (60 fps);
      mid-range Android still pending
- [x] Package hygiene: version 0.1.0, changelog, license, attribution
- [x] Publish the initial `glint_engine` releases to pub.dev

## Flagship game — Duck Dash (endless runner)

A Subway-Surfers-style lane runner starring the Glint duck, built to prove
the engine drives real games: many moving objects, a chase camera, and a
Flutter-widget HUD over a smooth 3D world.

- [x] GlintGameView: multi-instance rendering with per-node transforms
- [x] Free look-at chase camera independent of orbit gestures
- [x] Ticker-driven game loop with delta-time updates
- [x] Procedural and imported multi-material props, fog, blob shadows
- [x] Three-lane runner: swipe steering, obstacles, coins, ramping speed
- [x] Score HUD, game-over and restart flow, iPhone 60 fps validation
- [x] glTF node-animation playback with an allocation-free draw loop

## Milestone 5 — General engine foundation (current)

- [x] Vertex-level skeletal skinning with validated joints/weights
- [x] LINEAR, STEP, and CUBICSPLINE sampling
- [x] Crossfades, additive/override layers, bone masks, events, state machines,
      one-shots, reverse playback, and loop-safe root motion
- [x] Directional shadows plus point and spot lights
- [x] Backend-neutral angular rigid-body API with general collider families,
      joints, filtering, triggers, events, queries, CCD, sleep, and interpolation
- [x] Optional native Box3D backend
- [x] Backend-neutral raycast vehicle with suspension, material-aware tires,
      dynamic-surface reactions, anti-roll, gears, braking, aero, and boost
- [x] Rollback snapshots, fixed-tick replay tapes, deterministic state digests,
      and a repeatable mixed-load stress harness
- [x] Deterministic pooled particles with GPU billboards, curves, sprite
      sheets, local/world simulation, physics collision, and events
- [x] Backend-neutral spatial audio plus optional SoLoud/miniaudio backend
- [x] KTX2 parsing, `KHR_texture_basisu`, mip selection, and optional native
      Basis Universal transcoding
- [x] Typed custom shader graphs with offline Impeller compilation and runtime
      static/skinned PBR materials
- [x] Sweep-and-slide character controller and reusable ragdoll construction
      helpers with partial animation/physics blending
- [x] Stable active-contact/trigger tracking, fixed-tick stay events, and
      per-step backend/callback profiling
- [ ] Expanded constraint/backend stress coverage
- [ ] Physical iOS and Android profiling at release-scale workloads

## Milestone 6 — Documentation and public release

- [ ] Break the public API into comprehensive, task-oriented website guides
- [ ] Document rendering, assets, animation, physics, vehicles, replay,
      diagnostics, platform setup, optimization, and troubleshooting separately
- [ ] Add current device captures, including the skeletal-character reel
- [ ] Reconcile README, API dartdoc, examples, roadmap, and website claims
- [ ] Publish compatible `glint_engine` and native physics-backend versions
- [ ] Validate a clean external project using only published dependencies

## Flagship follow-up — standalone arcade racer

After Milestone 6, build the Asphalt-style racing vertical slice in its own
repository/project. It must depend on the published packages rather than path
dependencies, making it both a game and an honest integration test.

## Deferred, not ruled out

Visual editor tooling, GPU-resident compressed texture upload (pending Flutter
GPU support), Windows/Linux/Web support, XR, soft bodies, and networking
transports.
