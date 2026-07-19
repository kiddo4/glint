import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Writes assets/environments/dawn.hdr: a golden-hour equirectangular sky —
/// warm haze at the horizon, muted blue zenith, a low sun with a wide glow,
/// and a dark warm ground bounce. HDR radiance in the sun sells speculars.
void main() {
  const width = 256;
  const height = 128;
  final rgb = Float32List(width * height * 3);

  for (var y = 0; y < height; y++) {
    final v = (y + .5) / height;
    for (var x = 0; x < width; x++) {
      final u = (x + .5) / width;
      double r, g, b;
      if (v < .5) {
        // Sky: zenith blue blending into horizon peach.
        final t = math.pow(v / .5, 1.4).toDouble();
        r = .16 + (1.05 - .16) * t;
        g = .28 + (.72 - .28) * t;
        b = .55 + (.52 - .55) * t;
      } else {
        // Ground: warm dark bounce fading darker underfoot.
        final t = (v - .5) / .5;
        r = .30 - .20 * t;
        g = .22 - .15 * t;
        b = .16 - .11 * t;
      }
      // Low sun behind the camera's right shoulder with a broad glow.
      final du = ((u - .22).abs()).clamp(0.0, 1.0);
      final wrappedDu = math.min(du, 1 - du);
      final sunDistance = math.sqrt(
        wrappedDu * wrappedDu * 4 + (v - .47) * (v - .47),
      );
      final glow = math.exp(-sunDistance * 14);
      r += 26 * math.exp(-sunDistance * 55) + 2.6 * glow;
      g += 20 * math.exp(-sunDistance * 55) + 1.8 * glow;
      b += 12 * math.exp(-sunDistance * 55) + 1.0 * glow;

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
  File('assets/environments/dawn.hdr')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes.takeBytes());
  stdout.writeln('Wrote assets/environments/dawn.hdr');
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
