/// A snapshot of renderer throughput for the debug overlay.
class GlintRenderStats {
  const GlintRenderStats({
    required this.framesPerSecond,
    required this.frameTimeMilliseconds,
    required this.drawCalls,
    required this.triangleCount,
  });

  /// Completed renders over the trailing second.
  final int framesPerSecond;

  /// Wall time of the latest render, encode through GPU completion.
  final double frameTimeMilliseconds;

  /// Draw calls submitted in the latest render; 0 when the model was culled.
  final int drawCalls;

  /// Triangles submitted in the latest render; 0 when the model was culled.
  final int triangleCount;

  @override
  String toString() =>
      '$framesPerSecond fps • '
      '${frameTimeMilliseconds.toStringAsFixed(1)} ms • '
      '$drawCalls draw${drawCalls == 1 ? '' : 's'} • '
      '$triangleCount tris';
}
