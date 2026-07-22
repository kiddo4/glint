# Contributing to Glint

Thanks for considering a contribution. Glint is early — expect the API and
internals to keep moving — but issues, discussion, and PRs are welcome.

## Workflow

`main` is protected: all changes land through a pull request, not a direct
push. Fork or branch, open a PR, and describe what changed and why.

1. Fork/branch from `main`.
2. Make your change.
3. Run the checks below.
4. Open a PR against `main`.

## Requirements

- Flutter `>=3.44.1`, Dart SDK `^3.12.1` (see `pubspec.yaml`).
- Flutter GPU enabled to actually see the renderer run — see the README's
  "Enable Flutter GPU" section for the per-platform manifest flags, or pass
  `--enable-impeller --enable-flutter-gpu` to `flutter run` for a quick trial.

## Running checks

From the repo root:

```sh
flutter analyze
flutter test
```

From `example/`:

```sh
flutter analyze
flutter test
```

Both should be clean before opening a PR.

Physics/backend changes also run the native package suite and its repeatable
stress workload:

```sh
cd packages/glint_box3d
flutter test
flutter test benchmark/physics_stress_test.dart --reporter expanded
```

## Editing shaders

`shaders/unlit.vert` and `shaders/unlit.frag` are GLSL source. The engine
loads a **pre-compiled** binary bundle at `shaders/glint.shaderbundle` —
editing the `.vert`/`.frag` files alone does nothing until you recompile it.

There's no `flutter build` step for this (Flutter's own `flutter: shaders:`
pubspec key is for `dart:ui` `FragmentProgram`, a different mechanism —
`flutter_gpu`'s shader bundles are compiled offline with `impellerc`).
Rebuild after any shader edit with:

```sh
<path-to-flutter-sdk>/bin/cache/artifacts/engine/darwin-x64/impellerc \
  --shader-bundle='{"UnlitVertex": {"type": "vertex", "file": "shaders/unlit.vert"}, "UnlitFragment": {"type": "fragment", "file": "shaders/unlit.frag"}}' \
  --sl=shaders/glint.shaderbundle
```

Run this from the repo root (the manifest's file paths are relative to
`impellerc`'s working directory). Swap `darwin-x64` for your platform's
engine artifact directory if you're not on macOS. This single invocation
compiles all backends (Metal, GLES, Vulkan) into one bundle — no
per-platform flags needed. Commit the resulting binary alongside your
source changes.

## Verifying renderer changes

`flutter test` runs headless and can't exercise the GPU path — the existing
suite already expects and handles `Flutter GPU requires the Impeller
rendering backend` failures there. For anything touching `lib/src/gpu/` or
the shaders, run one of the `example/` apps on a real device or simulator
(`flutter run -d <device> --enable-impeller --enable-flutter-gpu`) and
visually confirm the change before opening a PR.

## Style

- `flutter_lints` via `analysis_options.yaml`; keep `flutter analyze` clean.
- Minimal comments — only where the *why* isn't obvious from the code
  itself (a workaround, a non-obvious constraint), not restating what a
  line does.
- No half-finished features behind flags left in a broken state; if
  something doesn't work, it shouldn't be reachable from the public API.

## Reporting issues

Open a GitHub issue. Real use cases are what shape the roadmap (see
`ROADMAP.md`) — if something you need is missing, say what you're building.
