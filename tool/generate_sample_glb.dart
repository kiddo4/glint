import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

void main() {
  const positions = <double>[
    0,
    1.35,
    0,
    0,
    -1.35,
    0,
    -1,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    -1,
  ];
  const uvs = <double>[.5, 0, .5, 1, 0, .5, 1, .5, .5, .5, .5, .5];
  const indices = <int>[
    0,
    4,
    3,
    0,
    2,
    4,
    0,
    5,
    2,
    0,
    3,
    5,
    1,
    3,
    4,
    1,
    4,
    2,
    1,
    2,
    5,
    1,
    5,
    3,
  ];
  final binary = BytesBuilder();
  binary.add(Float32List.fromList(positions).buffer.asUint8List());
  binary.add(Float32List.fromList(uvs).buffer.asUint8List());
  binary.add(Uint16List.fromList(indices).buffer.asUint8List());
  final bin = binary.takeBytes();
  final document = {
    'asset': {'version': '2.0', 'generator': 'Glint'},
    'buffers': [
      {'byteLength': bin.length},
    ],
    'bufferViews': [
      {'buffer': 0, 'byteOffset': 0, 'byteLength': positions.length * 4},
      {
        'buffer': 0,
        'byteOffset': positions.length * 4,
        'byteLength': uvs.length * 4,
      },
      {
        'buffer': 0,
        'byteOffset': (positions.length + uvs.length) * 4,
        'byteLength': indices.length * 2,
      },
    ],
    'accessors': [
      {
        'bufferView': 0,
        'componentType': 5126,
        'count': 6,
        'type': 'VEC3',
        'min': [-1, -1.35, -1],
        'max': [1, 1.35, 1],
      },
      {'bufferView': 1, 'componentType': 5126, 'count': 6, 'type': 'VEC2'},
      {
        'bufferView': 2,
        'componentType': 5123,
        'count': indices.length,
        'type': 'SCALAR',
      },
    ],
    'meshes': [
      {
        'name': 'Glint Prism',
        'primitives': [
          {
            'attributes': {'POSITION': 0, 'TEXCOORD_0': 1},
            'indices': 2,
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
  final json = utf8.encode(jsonEncode(document)).toList();
  while (json.length % 4 != 0) {
    json.add(0x20);
  }
  final binPadded = bin.toList();
  while (binPadded.length % 4 != 0) {
    binPadded.add(0);
  }
  final output = BytesBuilder();
  final header = ByteData(12)
    ..setUint32(0, 0x46546c67, Endian.little)
    ..setUint32(4, 2, Endian.little)
    ..setUint32(8, 12 + 8 + json.length + 8 + binPadded.length, Endian.little);
  output.add(header.buffer.asUint8List());
  _chunk(output, json, 0x4e4f534a);
  _chunk(output, binPadded, 0x004e4942);
  Directory('assets/models').createSync(recursive: true);
  File('assets/models/glint-prism.glb').writeAsBytesSync(output.takeBytes());
}

void _chunk(BytesBuilder output, List<int> bytes, int type) {
  final header = ByteData(8)
    ..setUint32(0, bytes.length, Endian.little)
    ..setUint32(4, type, Endian.little);
  output.add(header.buffer.asUint8List());
  output.add(bytes);
}
