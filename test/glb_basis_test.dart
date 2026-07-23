import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glint_engine/glint_engine.dart';

void main() {
  test('KHR_texture_basisu source wins over its raster fallback', () {
    final basisBytes = Uint8List.fromList(const [
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
    final mesh = GlintGlbMesh.parse(
      ByteData.sublistView(_basisGlb(basisBytes)),
      debugLabel: 'basis-extension.glb',
    );

    expect(mesh.baseColorImageBytes, basisBytes);
  });
}

Uint8List _basisGlb(Uint8List basisBytes) {
  const positionsLength = 9 * 4;
  const indicesOffset = positionsLength;
  const indicesLength = 3 * 2;
  const fallbackOffset = 44;
  const fallbackLength = 4;
  const basisOffset = 48;
  final binaryLength = basisOffset + basisBytes.length;
  final binary = Uint8List((binaryLength + 3) & ~3);
  final binaryData = ByteData.sublistView(binary);
  const positions = <double>[0, 0, 0, 1, 0, 0, 0, 1, 0];
  for (var index = 0; index < positions.length; index++) {
    binaryData.setFloat32(index * 4, positions[index], Endian.little);
  }
  for (var index = 0; index < 3; index++) {
    binaryData.setUint16(indicesOffset + index * 2, index, Endian.little);
  }
  binary.setAll(fallbackOffset, const [1, 2, 3, 4]);
  binary.setAll(basisOffset, basisBytes);

  final document = <String, Object?>{
    'asset': {'version': '2.0'},
    'buffers': [
      {'byteLength': binaryLength},
    ],
    'bufferViews': [
      {'buffer': 0, 'byteOffset': 0, 'byteLength': positionsLength},
      {'buffer': 0, 'byteOffset': indicesOffset, 'byteLength': indicesLength},
      {'buffer': 0, 'byteOffset': fallbackOffset, 'byteLength': fallbackLength},
      {'buffer': 0, 'byteOffset': basisOffset, 'byteLength': basisBytes.length},
    ],
    'accessors': [
      {
        'bufferView': 0,
        'componentType': 5126,
        'count': 3,
        'type': 'VEC3',
        'min': [0, 0, 0],
        'max': [1, 1, 0],
      },
      {'bufferView': 1, 'componentType': 5123, 'count': 3, 'type': 'SCALAR'},
    ],
    'images': [
      {'bufferView': 2, 'mimeType': 'image/png'},
      {'bufferView': 3, 'mimeType': 'image/ktx2'},
    ],
    'textures': [
      {
        'source': 0,
        'extensions': {
          'KHR_texture_basisu': {'source': 1},
        },
      },
    ],
    'materials': [
      {
        'pbrMetallicRoughness': {
          'baseColorTexture': {'index': 0},
        },
      },
    ],
    'meshes': [
      {
        'primitives': [
          {
            'attributes': {'POSITION': 0},
            'indices': 1,
            'material': 0,
          },
        ],
      },
    ],
    'nodes': [
      {'mesh': 0},
    ],
    'scenes': [
      {
        'nodes': [0],
      },
    ],
    'scene': 0,
  };
  final json = Uint8List.fromList(utf8.encode(jsonEncode(document)));
  final paddedJson = Uint8List((json.length + 3) & ~3);
  paddedJson.fillRange(0, paddedJson.length, 0x20);
  paddedJson.setAll(0, json);
  final totalLength = 12 + 8 + paddedJson.length + 8 + binary.length;
  final glb = Uint8List(totalLength);
  final data = ByteData.sublistView(glb);
  data.setUint32(0, 0x46546c67, Endian.little);
  data.setUint32(4, 2, Endian.little);
  data.setUint32(8, totalLength, Endian.little);
  data.setUint32(12, paddedJson.length, Endian.little);
  data.setUint32(16, 0x4e4f534a, Endian.little);
  glb.setAll(20, paddedJson);
  final binaryHeader = 20 + paddedJson.length;
  data.setUint32(binaryHeader, binary.length, Endian.little);
  data.setUint32(binaryHeader + 4, 0x004e4942, Endian.little);
  glb.setAll(binaryHeader + 8, binary);
  return glb;
}
