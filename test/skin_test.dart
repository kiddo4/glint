import 'package:flutter_test/flutter_test.dart';
import 'package:glint_engine/glint_engine.dart';

void main() {
  testWidgets('SimpleSkin parses a skin, joints, and per-vertex weights', (
    tester,
  ) async {
    final rig = await tester.runAsync(
      () => GlintGlbRig.fromAsset(
        'packages/glint_engine/assets/models/simple_skin.glb',
      ),
    );
    expect(rig!.nodes, hasLength(3));
    expect(rig.skins, hasLength(1));
    expect(rig.meshes, hasLength(1));

    // Node 0 is the skinned mesh node; its skin references joints 1 and 2
    // (node indices, not direct array positions into JOINTS_0's values).
    expect(rig.nodes[0].skinIndex, 0);
    expect(rig.skins[0].jointNodeIndices, [1, 2]);
    expect(rig.skins[0].inverseBindMatrices, hasLength(2));
    for (final matrix in rig.skins[0].inverseBindMatrices) {
      expect(matrix, hasLength(16));
    }

    final mesh = rig.meshes[0];
    expect(mesh.isSkinned, isTrue);
    expect(mesh.vertexCount, 10);
    expect(mesh.joints, hasLength(10 * 4));
    expect(mesh.weights, hasLength(10 * 4));
    // Each vertex's 4 weights sum to ~1, the standard glTF skinning
    // invariant — a sanity check that WEIGHTS_0 was read from the right
    // accessor/offset, not garbage.
    for (var vertex = 0; vertex < mesh.vertexCount; vertex++) {
      final sum = mesh.weights
          .skip(vertex * 4)
          .take(4)
          .fold(0.0, (total, w) => total + w);
      expect(sum, closeTo(1, 1e-5));
    }
  });

  testWidgets('joint matrices are identity at the authored bind pose', (
    tester,
  ) async {
    final rig = await tester.runAsync(
      () => GlintGlbRig.fromAsset(
        'packages/glint_engine/assets/models/simple_skin.glb',
      ),
    );
    // animation: -1 is the bind pose (no channels applied) — SimpleSkin's
    // only animated node (2) already defaults to its bind-pose TRS, so this
    // matches what the asset's inverseBindMatrices were authored against.
    // jointMatrix = meshWorldInverse * jointWorld * inverseBindMatrix
    // collapses to identity exactly there: the defining property of an
    // inverse bind matrix. A non-identity result means the joint-node
    // indexing, the mesh-node inverse, or the accessor reads are wrong.
    final joints = rig!.jointMatrices(0, 0, animation: -1);
    expect(joints, hasLength(2));
    const identity = [
      1.0, 0.0, 0.0, 0.0, //
      0.0, 1.0, 0.0, 0.0, //
      0.0, 0.0, 1.0, 0.0, //
      0.0, 0.0, 0.0, 1.0, //
    ];
    for (final matrix in joints) {
      for (var i = 0; i < 16; i++) {
        expect(matrix[i], closeTo(identity[i], 1e-4));
      }
    }
  });

  testWidgets('animating the clip moves the second joint matrix away from '
      'identity', (tester) async {
    final rig = await tester.runAsync(
      () => GlintGlbRig.fromAsset(
        'packages/glint_engine/assets/models/simple_skin.glb',
      ),
    );
    // t=1.0 sits on an authored keyframe with a 90-degree rotation (z=0.707,
    // w=0.707) — duration/2 was tried first and landed in a flat plateau
    // where the clip happens to pass back through identity, which isn't a
    // useful "is this animating" check.
    final joints = rig!.jointMatrices(0, 0, animation: 0, time: 1);
    // Joint 0 (node 1) is never animated; joint 1 (node 2) is the rotating
    // node, so only the second joint matrix should move.
    final first = joints[0];
    const identity = [
      1.0, 0.0, 0.0, 0.0, //
      0.0, 1.0, 0.0, 0.0, //
      0.0, 0.0, 1.0, 0.0, //
      0.0, 0.0, 0.0, 1.0, //
    ];
    for (var i = 0; i < 16; i++) {
      expect(first[i], closeTo(identity[i], 1e-4));
    }
    final second = joints[1];
    var moved = 0.0;
    for (var i = 0; i < 16; i++) {
      moved += (second[i] - identity[i]).abs();
    }
    expect(moved, greaterThan(.01));
  });
}
