import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glint_basis/glint_basis.dart';
import 'package:glint_engine/glint_engine.dart';

void main() {
  test('transcodes an official Basis KTX2 fixture to RGBA8', () async {
    final encoded = await File('test/kodim23.ktx2').readAsBytes();
    final container = GlintKtx2Container.parse(encoded);
    expect(container.isBasisUniversal, isTrue);

    final pixels = await const GlintBasisTranscoder().transcodeKtx2(
      container,
      debugLabel: 'kodim23.ktx2',
    );

    expect(pixels.width, container.width);
    expect(pixels.height, container.height);
    expect(pixels.bytes.lengthInBytes, pixels.width * pixels.height * 4);
    expect(
      pixels.bytes.buffer.asUint8List().any((channel) => channel != 0),
      isTrue,
    );
  });
}
