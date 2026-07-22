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

  testWidgets('skin probing finds a rig independently of geometry parsing', (
    tester,
  ) async {
    final bytes = await tester.runAsync(
      () => const Model.asset(
        'packages/glint_engine/assets/models/simple_skin.glb',
      ).read(),
    );
    expect(GlintGlbRig.probeSkins(bytes!), isTrue);
  });

  test('CUBICSPLINE channels use Hermite tangents', () {
    const rig = GlintGlbRig(
      nodes: [GlintGlbNode()],
      rootNodes: [0],
      meshes: [],
      animations: [
        GlintGlbAnimation(
          name: 'ease',
          duration: 1,
          channels: [
            GlintGlbAnimationChannel(
              nodeIndex: 0,
              path: GlintGlbAnimationPath.translation,
              inputTimes: [0, 1],
              // Each key is in-tangent, value, out-tangent.
              output: [0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0],
              interpolation: GlintGlbInterpolation.cubicSpline,
            ),
          ],
        ),
      ],
    );
    final halfway = rig.nodeWorldTransforms(time: .5, loop: false);
    expect(halfway.single[12], closeTo(.75, 1e-9));
    final held = rig.nodeWorldTransforms(time: 2, loop: false);
    expect(held.single[12], closeTo(1, 1e-9));
    final looped = rig.nodeWorldTransforms(time: 1);
    expect(looped.single[12], closeTo(0, 1e-9));
  });
}
