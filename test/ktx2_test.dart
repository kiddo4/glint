import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glint_engine/glint_engine.dart';

void main() {
  test(
    'memory texture sources retain application-managed encoded bytes',
    () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final source = GlintTextureSource.memory('generated.ktx2', bytes);

      expect(await source.read(), same(bytes));
      expect(source.debugLabel, 'generated.ktx2');
    },
  );

  test('parses and decodes an uncompressed sRGB KTX2 texture', () {
    final encoded = _rgbaKtx2();
    final container = GlintKtx2Container.parse(encoded);
    final pixels = container.decodeUncompressed();

    expect(container.width, 2);
    expect(container.height, 2);
    expect(container.isSrgb, isTrue);
    expect(pixels.colorSpace, GlintTextureColorSpace.srgb);
    expect(pixels.bytes.buffer.asUint8List(), encoded.sublist(104));
  });

  test('rejects a level whose range escapes the KTX2 file', () {
    final encoded = _rgbaKtx2();
    ByteData.sublistView(encoded).setUint64(80, 10000, Endian.little);
    expect(
      () => GlintKtx2Container.parse(encoded),
      throwsA(isA<GlintTextureException>()),
    );
  });
}

Uint8List _rgbaKtx2() {
  final bytes = Uint8List(104 + 16);
  bytes.setAll(0, const [
    0xab,
    0x4b,
    0x54,
    0x58,
    0x20,
    0x32,
    0x30,
    0xbb,
    0x0d,
    0x0a,
    0x1a,
    0x0a,
  ]);
  final data = ByteData.sublistView(bytes);
  data.setUint32(12, 43, Endian.little); // R8G8B8A8_SRGB
  data.setUint32(16, 1, Endian.little);
  data.setUint32(20, 2, Endian.little);
  data.setUint32(24, 2, Endian.little);
  data.setUint32(36, 1, Endian.little);
  data.setUint32(40, 1, Endian.little);
  data.setUint64(80, 104, Endian.little);
  data.setUint64(88, 16, Endian.little);
  data.setUint64(96, 16, Endian.little);
  bytes.setAll(104, const [
    255,
    0,
    0,
    255,
    0,
    255,
    0,
    255,
    0,
    0,
    255,
    255,
    255,
    255,
    255,
    255,
  ]);
  return bytes;
}
