@DefaultAsset('package:glint_basis/glint_basis_native')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart' show Utf8;

@Native<Int32 Function(Pointer<Uint8>, Size, Pointer<Uint32>)>(
  symbol: 'glint_basis_ktx2_info',
)
external int glintBasisKtx2Info(
  Pointer<Uint8> data,
  int dataSize,
  Pointer<Uint32> output,
);

@Native<Int32 Function(Pointer<Uint8>, Size, Uint32, Pointer<Uint8>, Size)>(
  symbol: 'glint_basis_ktx2_transcode_rgba8',
)
external int glintBasisKtx2TranscodeRgba8(
  Pointer<Uint8> data,
  int dataSize,
  int level,
  Pointer<Uint8> output,
  int outputSize,
);

@Native<Int32 Function(Pointer<Uint8>, Size, Pointer<Uint32>)>(
  symbol: 'glint_basis_file_info',
)
external int glintBasisFileInfo(
  Pointer<Uint8> data,
  int dataSize,
  Pointer<Uint32> output,
);

@Native<Int32 Function(Pointer<Uint8>, Size, Uint32, Pointer<Uint8>, Size)>(
  symbol: 'glint_basis_file_transcode_rgba8',
)
external int glintBasisFileTranscodeRgba8(
  Pointer<Uint8> data,
  int dataSize,
  int level,
  Pointer<Uint8> output,
  int outputSize,
);

@Native<Pointer<Utf8> Function()>(symbol: 'glint_basis_last_error')
external Pointer<Utf8> glintBasisLastError();
