# glint_basis

The official Basis Universal reference transcoder backend for Glint Engine.
It accepts Basis-compressed KTX2 and standalone `.basis` textures and decodes
the selected mip on a background isolate.

```dart
final decoder = GlintTextureDecoder(
  basisTranscoder: const GlintBasisTranscoder(),
);

final pixels = await GlintTexturePixels.fromAsset(
  'assets/bodywork.ktx2',
  decoder: decoder,
  maximumDimension: 2048,
);
```

Pass the same decoder to `GlintGameView.textureDecoder` to cover particle
textures, graph textures, and embedded GLB materials. Glint resolves
`KHR_texture_basisu.source` ahead of an optional PNG/JPEG fallback.

Flutter GPU does not currently expose ASTC/ETC/BC texture formats or mip-level
uploads, so this release transcodes to RGBA8 before upload. The public backend
boundary preserves the compressed asset pipeline and can select a native GPU
format when Flutter GPU exposes those capabilities.

The package vendors only the upstream transcoder and Zstandard decoder, builds
them through Dart native assets, and runs each decode in a background isolate.
See `THIRD_PARTY_NOTICES.md` for licensing.
