import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Writes assets/environments/studio.hdr: a synthetic photo-studio
/// equirectangular Radiance image with a graded backdrop and bright softbox
/// panels whose radiance exceeds 1.0, so speculars read as real highlights.
void main() {
  const width = 256;
  const height = 128;
  final rgb = Float32List(width * height * 3);

  for (var y = 0; y < height; y++) {
    final v = (y + .5) / height;
    for (var x = 0; x < width; x++) {
      final u = (x + .5) / width;
      // Neutral studio sweep: bright zenith cove falling to a dark floor.
      final sweep = math.pow(1 - v, 1.6).toDouble();
      var r = .04 + .5 * sweep;
      var g = .045 + .52 * sweep;
      var b = .055 + .58 * sweep;

      // Key softbox: large warm panel high on the left.
      r += 5.5 * _panel(u, v, .21, .30, .10, .085);
      g += 5.1 * _panel(u, v, .21, .30, .10, .085);
      b += 4.4 * _panel(u, v, .21, .30, .10, .085);

      // Fill softbox: dimmer cool panel high on the right.
      r += 1.6 * _panel(u, v, .74, .33, .085, .07);
      g += 1.8 * _panel(u, v, .74, .33, .085, .07);
      b += 2.2 * _panel(u, v, .74, .33, .085, .07);

      // Rim strip behind the subject for edge separation.
      r += 2.4 * _panel(u, v, .5, .22, .16, .03);
      g += 2.4 * _panel(u, v, .5, .22, .16, .03);
      b += 2.4 * _panel(u, v, .5, .22, .16, .03);

      final base = (y * width + x) * 3;
      rgb[base] = r;
      rgb[base + 1] = g;
      rgb[base + 2] = b;
    }
  }

  final bytes = BytesBuilder()
    ..add('#?RADIANCE\n'.codeUnits)
    ..add('FORMAT=32-bit_rle_rgbe\n'.codeUnits)
    ..add('\n'.codeUnits)
    ..add('-Y $height +X $width\n'.codeUnits);
  for (var i = 0; i < width * height; i++) {
    bytes.add(_rgbe(rgb[i * 3], rgb[i * 3 + 1], rgb[i * 3 + 2]));
  }
  File('assets/environments/studio.hdr')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes.takeBytes());
  stdout.writeln('Wrote assets/environments/studio.hdr');
}

/// Soft-edged rectangular emitter coverage with horizontal wrap.
double _panel(double u, double v, double cu, double cv, double hw, double hh) {
  var du = (u - cu).abs();
  du = math.min(du, 1 - du);
  final dv = (v - cv).abs();
  final falloffU = (1 - du / hw).clamp(0.0, 1.0);
  final falloffV = (1 - dv / hh).clamp(0.0, 1.0);
  return math.pow(falloffU * falloffV, 1.5).toDouble();
}

List<int> _rgbe(double r, double g, double b) {
  final peak = math.max(r, math.max(g, b));
  if (peak < 1e-9) return const [0, 0, 0, 0];
  final exponent = (math.log(peak) / math.ln2).floor() + 1;
  final scale = math.pow(2.0, -exponent).toDouble() * 256;
  return [
    (r * scale).clamp(0, 255).floor(),
    (g * scale).clamp(0, 255).floor(),
    (b * scale).clamp(0, 255).floor(),
    exponent + 128,
  ];
}
