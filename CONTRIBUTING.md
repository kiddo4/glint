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
- CMake when building the optional `glint_soloud` backend (`brew install cmake`
  on macOS).

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

Texture/audio backend changes run their packages independently:

```sh
cd packages/glint_basis && flutter analyze && flutter test
cd ../glint_soloud && flutter analyze
```

## Release order

The repository-local `pubspec_overrides.yaml` files keep optional packages on
the current engine while developing. Their published manifests use hosted
constraints, so consumers never receive a path dependency.

Publish and verify releases in dependency order:

1. Update the website and task-oriented documentation.
2. Dry-run and publish `glint_engine` from the repository root.
3. Stage each optional package outside the parent repository ignore rules,
   then dry-run and publish `glint_box3d`, `glint_basis`, and `glint_soloud`.
4. Create a clean external Flutter project and resolve only hosted packages.

```sh
stage_dir="$(tool/stage_pub_package.sh packages/glint_box3d)"
dart pub publish --dry-run --directory="$stage_dir"
```

Repeat the staging command for each optional package. The stage intentionally
excludes local overrides, build output, tests, and lockfiles; after
`glint_engine` is live, validation therefore exercises the same hosted
dependency graph users receive.

## Editing shaders

`shaders/unlit.vert` and `shaders/unlit.frag` are GLSL source. The engine
loads a **pre-compiled** binary bundle at `shaders/glint.shaderbundle` —
editing the `.vert`/`.frag` files alone does nothing until you recompile it.

There's no `flutter build` step for this (Flutter's own `flutter: shaders:`
pubspec key is for `dart:ui` `FragmentProgram`, a different mechanism —
`flutter_gpu`'s shader bundles are compiled offline with `impellerc`).
`shaders/glint.shaderbundle.json` is the canonical entry-point manifest. Rebuild
after any engine shader edit by passing its compact JSON contents to
`impellerc`:

```sh
bundle_json="$(jq -c . shaders/glint.shaderbundle.json)"
<path-to-flutter-sdk>/bin/cache/artifacts/engine/<platform-arch>/impellerc \
  --shader-bundle="$bundle_json" \
  --sl=shaders/glint.shaderbundle
```

Run this from the repo root (the manifest's file paths are relative to
`impellerc`'s working directory). Swap `darwin-x64` for your platform's
engine artifact directory if you're not on macOS. This single invocation
compiles all backends (Metal, GLES, Vulkan) into one bundle — no
per-platform flags needed. Commit the resulting binary alongside your
source changes.

Application shader graphs use their own `hook/build.dart` and
`buildGlintShaderGraphBundle`; they are generated automatically during an app
build and should also be validated with the graph CLI described in the README.

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
