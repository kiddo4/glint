import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glint_engine/glint_engine.dart';

void main() {
  testWidgets('DEBUG: Fox skin/joint sanity', (tester) async {
    final rig = await tester.runAsync(
      () => GlintGlbRig.fromAsset(
        'packages/glint_engine/assets/models/fox.glb',
      ),
    );
    debugPrint('nodes: ${rig!.nodes.length}');
    debugPrint('skins: ${rig.skins.length}');
    debugPrint('node[1] name/skinIndex: ${rig.nodes[1].name} ${rig.nodes[1].skinIndex}');
    debugPrint('skin[0] joint count: ${rig.skins[0].jointNodeIndices.length}');
    debugPrint('skin[0] joints: ${rig.skins[0].jointNodeIndices}');
    debugPrint('mesh isSkinned: ${rig.meshes[0].isSkinned}, vertexCount: ${rig.meshes[0].vertexCount}');
    debugPrint('joints.length: ${rig.meshes[0].joints.length}, weights.length: ${rig.meshes[0].weights.length}');

    // Sample first few vertices' joint indices/weights.
    for (var v = 0; v < 5; v++) {
      final j = rig.meshes[0].joints.skip(v * 4).take(4).toList();
      final w = rig.meshes[0].weights.skip(v * 4).take(4).toList();
      debugPrint('vertex $v joints=$j weights=$w sum=${w.fold(0.0, (a, b) => a + b)}');
    }

    final skinIndex = rig.nodes[1].skinIndex!;
    final joints = rig.jointMatrices(skinIndex, 1, animation: -1);
    debugPrint('joint matrix count: ${joints.length}');
    const identity = [
      1.0, 0.0, 0.0, 0.0, //
      0.0, 1.0, 0.0, 0.0, //
      0.0, 0.0, 1.0, 0.0, //
      0.0, 0.0, 0.0, 1.0, //
    ];
    for (var j = 0; j < joints.length; j++) {
      var maxDiff = 0.0;
      for (var i = 0; i < 16; i++) {
        maxDiff = (joints[j][i] - identity[i]).abs() > maxDiff
            ? (joints[j][i] - identity[i]).abs()
            : maxDiff;
      }
      debugPrint('joint $j (node ${rig.skins[skinIndex].jointNodeIndices[j]}) maxDiffFromIdentity=$maxDiff');
    }
  });
}
