## 0.1.1

* Rewrite the README: pub.dev badges, quick-nav links, and an FAQ covering
  platform support and the `flutter_scene` comparison directly.

## 0.1.0

The first complete Glint release: a pure-Dart 3D engine on Flutter GPU.

* Render binary glTF 2.0 models from assets or network: scene hierarchy,
  node transforms, generated or authored normals, 16/32-bit indices.
* Per-primitive material batches with embedded base-color textures
  (decoded with a 1K cap for mobile memory), factors, metallic, roughness.
* GGX metallic-roughness PBR with directional lighting, HDRI image-based
  lighting (built-in Radiance `.hdr` decoder and CPU prefiltering), and
  distance fog.
* glTF node animation playback: translation/rotation/scale channels,
  LINEAR/STEP sampling, quaternion slerp, automatic looping.
* `Scene3D` declarative API: scenes route to the GPU renderer, materials
  update live through `setState`, hot reload rebuilds shaders.
* Tap picking via CPU raycasting, and `Label3D` — Flutter widgets anchored
  to model surfaces with fade/hide occlusion policies.
* Scroll-aware gesture routing so scenes cooperate with scrollable pages.
* `GlintGameView` game loop: unlimited model instances with per-node
  transforms, free look-at camera, translucent blob-shadow pass, per-frame
  frustum culling, and an allocation-free draw loop (validated at 60 fps
  on iPhone with ~160 draws per frame).
* Live FPS/frame-time/draw/triangle diagnostics and typed, actionable
  errors for every asset failure.
* Four runnable examples: an endless-runner game, a product configurator,
  a minimal viewer, and an anchored-labels demo.

## 0.0.1

* Establish the Glint package and declarative `Scene3D(scene:)` API.
* Add the pure-Dart bootstrap renderer, orbit gestures, and overlay demo.
* Add indexed, depth-tested, textured `flutter_gpu` rendering.
* Add PNG/JPEG asset decoding with actionable texture errors.
