import 'package:flutter_test/flutter_test.dart';
import 'package:glint_engine/glint_engine.dart';

void main() {
  testWidgets('BoxAnimated parses into a rig with clips and local meshes', (
    tester,
  ) async {
    final rig = await tester.runAsync(
      () =>
          GlintGlbRig.fromAsset('packages/glint_engine/assets/models/box_animated.glb'),
    );
    expect(rig!.nodes, hasLength(4));
    expect(rig.meshes, hasLength(2));
    expect(rig.animations, hasLength(1));
    final clip = rig.animations.single;
    expect(clip.channels, hasLength(2));
    expect(clip.duration, greaterThan(1));
    expect(
      clip.channels.map((channel) => channel.path),
      containsAll([
        GlintGlbAnimationPath.rotation,
        GlintGlbAnimationPath.translation,
      ]),
    );
  });

  testWidgets('sampling the clip moves animated nodes over time', (
    tester,
  ) async {
    final rig = await tester.runAsync(
      () =>
          GlintGlbRig.fromAsset('packages/glint_engine/assets/models/box_animated.glb'),
    );
    final rest = rig!.nodeWorldTransforms(animation: 0, time: 0);
    final later = rig.nodeWorldTransforms(
      animation: 0,
      time: rig.animations.single.duration / 2,
    );
    final rotated = rig.animations.single.channels
        .firstWhere(
          (channel) => channel.path == GlintGlbAnimationPath.rotation,
        )
        .nodeIndex;
    var moved = 0.0;
    for (var i = 0; i < 16; i++) {
      moved += (rest[rotated][i] - later[rotated][i]).abs();
    }
    expect(moved, greaterThan(.01));
    // The bind pose (-1) matches sampling with no valid clip.
    final bind = rig.nodeWorldTransforms(animation: -1);
    expect(bind, hasLength(rig.nodes.length));
    // Looping: a full duration later matches time zero.
    final wrapped = rig.nodeWorldTransforms(
      animation: 0,
      time: rig.animations.single.duration,
    );
    for (var i = 0; i < 16; i++) {
      expect(wrapped[rotated][i], closeTo(rest[rotated][i], 1e-4));
    }
  });

  testWidgets('animation probing distinguishes animated from static GLBs', (
    tester,
  ) async {
    final animated = await tester.runAsync(
      () => const Model.asset(
        'packages/glint_engine/assets/models/box_animated.glb',
      ).read(),
    );
    final static_ = await tester.runAsync(
      () => const Model.asset('packages/glint_engine/assets/models/duck.glb').read(),
    );
    expect(GlintGlbRig.probeAnimations(animated!), isTrue);
    expect(GlintGlbRig.probeAnimations(static_!), isFalse);
  });
}
