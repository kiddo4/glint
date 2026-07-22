import 'package:flutter_test/flutter_test.dart';
import 'package:glint_engine/glint_engine.dart';

void main() {
  testWidgets('Fox skin deforms finitely and preserves its bind pose', (
    tester,
  ) async {
    final rig = await tester.runAsync(
      () =>
          GlintGlbRig.fromAsset('packages/glint_engine/assets/models/fox.glb'),
    );
    final fox = rig!;
    expect(fox.nodes, hasLength(26));
    expect(fox.skins.single.jointNodeIndices, hasLength(24));
    expect(fox.animations.map((clip) => clip.name), ['Survey', 'Walk', 'Run']);

    final skinIndex = fox.nodes[1].skinIndex!;
    final bindJoints = fox.jointMatrices(skinIndex, 1, animation: -1);
    const identity = [
      1.0, 0.0, 0.0, 0.0, //
      0.0, 1.0, 0.0, 0.0, //
      0.0, 0.0, 1.0, 0.0, //
      0.0, 0.0, 0.0, 1.0, //
    ];
    for (final joint in bindJoints) {
      var maxDiff = 0.0;
      for (var i = 0; i < 16; i++) {
        final difference = (joint[i] - identity[i]).abs();
        if (difference > maxDiff) maxDiff = difference;
      }
      expect(maxDiff, lessThan(1e-4));
    }

    final walk = fox.animations[1];
    final animatedJoints = fox.jointMatrices(
      skinIndex,
      1,
      animation: 1,
      time: walk.duration / 2,
      loop: false,
    );
    final mesh = fox.meshes.single;
    var totalMovement = 0.0;
    for (var vertex = 0; vertex < mesh.vertexCount; vertex++) {
      final x = mesh.positions[vertex * 3];
      final y = mesh.positions[vertex * 3 + 1];
      final z = mesh.positions[vertex * 3 + 2];
      var skinnedX = 0.0, skinnedY = 0.0, skinnedZ = 0.0;
      for (var influence = 0; influence < 4; influence++) {
        final weight = mesh.weights[vertex * 4 + influence];
        if (weight == 0) continue;
        final jointIndex = mesh.joints[vertex * 4 + influence].toInt();
        final matrix = animatedJoints[jointIndex];
        skinnedX +=
            weight *
            (matrix[0] * x + matrix[4] * y + matrix[8] * z + matrix[12]);
        skinnedY +=
            weight *
            (matrix[1] * x + matrix[5] * y + matrix[9] * z + matrix[13]);
        skinnedZ +=
            weight *
            (matrix[2] * x + matrix[6] * y + matrix[10] * z + matrix[14]);
      }
      expect(
        skinnedX.isFinite && skinnedY.isFinite && skinnedZ.isFinite,
        isTrue,
      );
      expect(skinnedX.abs(), lessThan(1000));
      expect(skinnedY.abs(), lessThan(1000));
      expect(skinnedZ.abs(), lessThan(1000));
      totalMovement +=
          (skinnedX - x).abs() + (skinnedY - y).abs() + (skinnedZ - z).abs();
    }
    expect(totalMovement, greaterThan(1));
  });
}
