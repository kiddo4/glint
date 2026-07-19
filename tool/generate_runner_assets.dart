import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Writes the Duck Dash prop models: a unit box (crates, floor, rails via
/// per-instance scaling) and a segmented coin, both with normals and PBR
/// material factors and no texture.
void main() {
  _writeGlb(
    'assets/models/box.glb',
    _box(),
    baseColor: [.58, .4, .2, 1],
    metallic: 0,
    roughness: .8,
  );
  _writeGlb(
    'assets/models/coin.glb',
    _coin(radius: .5, thickness: .16, segments: 20),
    baseColor: [1, .78, .18, 1],
    metallic: 1,
    roughness: .25,
  );
  _writeGlb(
    'assets/models/cone.glb',
    _cone(radius: .5, height: 1, segments: 10),
    baseColor: [.19, .38, .22, 1],
    metallic: 0,
    roughness: .9,
  );
  _writeGlb(
    'assets/models/disc.glb',
    _disc(radius: .5, segments: 18),
    baseColor: [0, 0, 0, .38],
    metallic: 0,
    roughness: 1,
  );
  stdout.writeln('Wrote box.glb, coin.glb, cone.glb, and disc.glb');
}

/// An upright cone: base circle on y=0, apex at [height]. Used for trees.
_Geometry _cone({
  required double radius,
  required double height,
  required int segments,
}) {
  final g = _Geometry();
  for (var i = 0; i < segments; i++) {
    final a0 = i * 2 * math.pi / segments;
    final a1 = (i + 1) * 2 * math.pi / segments;
    final x0 = math.cos(a0) * radius, z0 = math.sin(a0) * radius;
    final x1 = math.cos(a1) * radius, z1 = math.sin(a1) * radius;
    final mid = (a0 + a1) / 2;
    // Slanted side triangle; CCW seen from outside (+z faces the viewer at
    // mid-angle 90°, where x decreases with angle).
    final side = g.positions.length ~/ 3;
    g.positions.addAll([0, height, 0, x1, 0, z1, x0, 0, z0]);
    final slant = radius / height;
    for (var v = 0; v < 3; v++) {
      g.normals.addAll([math.cos(mid), slant, math.sin(mid)]);
      g.uvs.addAll([0, 0]);
    }
    g.indices.addAll([side, side + 1, side + 2]);
    // Base triangle facing down.
    final base = g.positions.length ~/ 3;
    g.positions.addAll([0, 0, 0, x0, 0, z0, x1, 0, z1]);
    g.normals.addAll([0, -1, 0, 0, -1, 0, 0, -1, 0]);
    g.uvs.addAll([0, 0, 0, 0, 0, 0]);
    g.indices.addAll([base, base + 1, base + 2]);
  }
  return g;
}

/// A flat circle on the ground plane facing +y. Used for blob shadows.
_Geometry _disc({required double radius, required int segments}) {
  final g = _Geometry();
  for (var i = 0; i < segments; i++) {
    final a0 = i * 2 * math.pi / segments;
    final a1 = (i + 1) * 2 * math.pi / segments;
    final start = g.positions.length ~/ 3;
    // CCW seen from above (+y): angle sweep runs x→z clockwise in screen
    // terms, so wind center, a1, a0.
    g.positions.addAll([
      0, 0, 0,
      math.cos(a1) * radius, 0, math.sin(a1) * radius,
      math.cos(a0) * radius, 0, math.sin(a0) * radius,
    ]);
    g.normals.addAll([0, 1, 0, 0, 1, 0, 0, 1, 0]);
    g.uvs.addAll([0, 0, 0, 0, 0, 0]);
    g.indices.addAll([start, start + 1, start + 2]);
  }
  return g;
}

class _Geometry {
  final positions = <double>[];
  final normals = <double>[];
  final uvs = <double>[];
  final indices = <int>[];

  void quad(List<List<double>> corners, List<double> normal) {
    final base = positions.length ~/ 3;
    for (final corner in corners) {
      positions.addAll(corner);
      normals.addAll(normal);
      uvs.addAll([0, 0]);
    }
    indices.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
  }
}

/// A unit cube centered on the origin with outward faces.
_Geometry _box() {
  final g = _Geometry();
  const h = .5;
  g.quad(
    [
      [-h, -h, h],
      [h, -h, h],
      [h, h, h],
      [-h, h, h],
    ],
    [0, 0, 1],
  );
  g.quad(
    [
      [h, -h, -h],
      [-h, -h, -h],
      [-h, h, -h],
      [h, h, -h],
    ],
    [0, 0, -1],
  );
  g.quad(
    [
      [h, -h, h],
      [h, -h, -h],
      [h, h, -h],
      [h, h, h],
    ],
    [1, 0, 0],
  );
  g.quad(
    [
      [-h, -h, -h],
      [-h, -h, h],
      [-h, h, h],
      [-h, h, -h],
    ],
    [-1, 0, 0],
  );
  g.quad(
    [
      [-h, h, h],
      [h, h, h],
      [h, h, -h],
      [-h, h, -h],
    ],
    [0, 1, 0],
  );
  g.quad(
    [
      [-h, -h, -h],
      [h, -h, -h],
      [h, -h, h],
      [-h, -h, h],
    ],
    [0, -1, 0],
  );
  return g;
}

/// An upright coin: a short cylinder along z, faces at ±thickness/2.
_Geometry _coin({
  required double radius,
  required double thickness,
  required int segments,
}) {
  final g = _Geometry();
  final half = thickness / 2;
  for (var i = 0; i < segments; i++) {
    final a0 = i * 2 * math.pi / segments;
    final a1 = (i + 1) * 2 * math.pi / segments;
    final x0 = math.cos(a0) * radius, y0 = math.sin(a0) * radius;
    final x1 = math.cos(a1) * radius, y1 = math.sin(a1) * radius;
    // Front cap triangle (+z), wound counter-clockwise seen from +z.
    final front = g.positions.length ~/ 3;
    g.positions.addAll([0, 0, half, x0, y0, half, x1, y1, half]);
    g.normals.addAll([0, 0, 1, 0, 0, 1, 0, 0, 1]);
    g.uvs.addAll([0, 0, 0, 0, 0, 0]);
    g.indices.addAll([front, front + 1, front + 2]);
    // Back cap triangle (-z).
    final back = g.positions.length ~/ 3;
    g.positions.addAll([0, 0, -half, x1, y1, -half, x0, y0, -half]);
    g.normals.addAll([0, 0, -1, 0, 0, -1, 0, 0, -1]);
    g.uvs.addAll([0, 0, 0, 0, 0, 0]);
    g.indices.addAll([back, back + 1, back + 2]);
    // Rim quad with radial normals.
    g.quad(
      [
        [x0, y0, -half],
        [x1, y1, -half],
        [x1, y1, half],
        [x0, y0, half],
      ],
      [math.cos((a0 + a1) / 2), math.sin((a0 + a1) / 2), 0],
    );
  }
  return g;
}

void _writeGlb(
  String path,
  _Geometry geometry, {
  required List<double> baseColor,
  required double metallic,
  required double roughness,
}) {
  final binary = BytesBuilder();
  binary.add(Float32List.fromList(geometry.positions).buffer.asUint8List());
  final uvOffset = binary.length;
  binary.add(Float32List.fromList(geometry.uvs).buffer.asUint8List());
  final normalOffset = binary.length;
  binary.add(Float32List.fromList(geometry.normals).buffer.asUint8List());
  final indexOffset = binary.length;
  binary.add(Uint16List.fromList(geometry.indices).buffer.asUint8List());
  var bin = binary.takeBytes();
  if (bin.length % 4 != 0) {
    bin = Uint8List.fromList([...bin, ...List.filled(4 - bin.length % 4, 0)]);
  }

  final vertexCount = geometry.positions.length ~/ 3;
  final minimum = List<double>.filled(3, double.infinity);
  final maximum = List<double>.filled(3, double.negativeInfinity);
  for (var i = 0; i < geometry.positions.length; i += 3) {
    for (var axis = 0; axis < 3; axis++) {
      final value = geometry.positions[i + axis];
      if (value < minimum[axis]) minimum[axis] = value;
      if (value > maximum[axis]) maximum[axis] = value;
    }
  }

  final document = {
    'asset': {'version': '2.0', 'generator': 'Glint runner assets'},
    'scene': 0,
    'scenes': [
      {
        'nodes': [0],
      },
    ],
    'nodes': [
      {'mesh': 0},
    ],
    'meshes': [
      {
        'primitives': [
          {
            'attributes': {'POSITION': 0, 'TEXCOORD_0': 1, 'NORMAL': 2},
            'indices': 3,
            'material': 0,
          },
        ],
      },
    ],
    'materials': [
      {
        'pbrMetallicRoughness': {
          'baseColorFactor': baseColor,
          'metallicFactor': metallic,
          'roughnessFactor': roughness,
        },
      },
    ],
    'buffers': [
      {'byteLength': bin.length},
    ],
    'bufferViews': [
      {
        'buffer': 0,
        'byteOffset': 0,
        'byteLength': geometry.positions.length * 4,
      },
      {
        'buffer': 0,
        'byteOffset': uvOffset,
        'byteLength': geometry.uvs.length * 4,
      },
      {
        'buffer': 0,
        'byteOffset': normalOffset,
        'byteLength': geometry.normals.length * 4,
      },
      {
        'buffer': 0,
        'byteOffset': indexOffset,
        'byteLength': geometry.indices.length * 2,
      },
    ],
    'accessors': [
      {
        'bufferView': 0,
        'componentType': 5126,
        'count': vertexCount,
        'type': 'VEC3',
        'min': minimum,
        'max': maximum,
      },
      {
        'bufferView': 1,
        'componentType': 5126,
        'count': vertexCount,
        'type': 'VEC2',
      },
      {
        'bufferView': 2,
        'componentType': 5126,
        'count': vertexCount,
        'type': 'VEC3',
      },
      {
        'bufferView': 3,
        'componentType': 5123,
        'count': geometry.indices.length,
        'type': 'SCALAR',
      },
    ],
  };

  var json = utf8.encode(jsonEncode(document));
  if (json.length % 4 != 0) {
    json = Uint8List.fromList([
      ...json,
      ...List.filled(4 - json.length % 4, 0x20),
    ]);
  }
  final total = 12 + 8 + json.length + 8 + bin.length;
  final output = BytesBuilder()
    ..add(_uint32(0x46546c67))
    ..add(_uint32(2))
    ..add(_uint32(total))
    ..add(_uint32(json.length))
    ..add(_uint32(0x4e4f534a))
    ..add(json)
    ..add(_uint32(bin.length))
    ..add(_uint32(0x004e4942))
    ..add(bin);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(output.takeBytes());
}

Uint8List _uint32(int value) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);
