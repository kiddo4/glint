import 'package:flutter_test/flutter_test.dart';
import 'package:glint_engine/glint_engine.dart';

void main() {
  group('GlintAnimationController', () {
    test('crossfades clips without changing the rig hierarchy', () {
      final rig = _testRig();
      final controller = GlintAnimationController(rig, initialAnimation: 0);

      controller.play(1, fadeDuration: 1, loop: false);
      final halfway = controller.update(.5);

      // The outgoing idle root is 0, the incoming run root is 5, and the
      // transition itself is halfway complete.
      expect(halfway.pose.nodes[0].translation.x, closeTo(2.5, 1e-9));
      expect(rig.nodeWorldTransformsFromPose(halfway.pose), hasLength(3));

      final completed = controller.update(.5);
      expect(completed.pose.nodes[0].translation.x, closeTo(10, 1e-9));
      expect(controller.isTransitioning, isFalse);
      expect(controller.isComplete, isTrue);
    });

    test('an interrupted crossfade begins at the currently visible pose', () {
      final controller = GlintAnimationController(
        _testRig(),
        initialAnimation: 0,
      );
      controller.play(1, fadeDuration: 1, loop: false);
      final beforeInterruption = controller
          .update(.5)
          .pose
          .nodes[0]
          .translation;

      controller.play(0, fadeDuration: 1, loop: false);
      final afterInterruption = controller.pose.nodes[0].translation;

      expect(afterInterruption.x, closeTo(beforeInterruption.x, 1e-9));
    });

    test('bone masks keep animation layers local to one subtree', () {
      final rig = _testRig();
      final controller = GlintAnimationController(rig, initialAnimation: 0);
      controller.addLayer(
        GlintAnimationLayer(
          name: 'upper body',
          animationIndex: 2,
          weight: .5,
          mask: GlintBoneMask.fromRoot(rig, 1),
        ),
      );

      final frame = controller.update(.5);

      expect(frame.pose.nodes[1].translation.y, closeTo(1, 1e-9));
      expect(frame.pose.nodes[2].translation, Vector3.zero);
    });

    test('additive layers apply a delta from their reference frame', () {
      final rig = _testRig();
      final controller = GlintAnimationController(rig, initialAnimation: 0);
      controller.addLayer(
        GlintAnimationLayer(
          name: 'recoil',
          animationIndex: 2,
          additive: true,
          weight: .5,
          mask: GlintBoneMask([1]),
        ),
      );

      final frame = controller.update(.5);

      expect(frame.pose.nodes[1].translation.y, closeTo(1, 1e-9));
      expect(frame.pose.nodes[0].translation, Vector3.zero);
    });

    test('events are emitted in timeline order across multiple loops', () {
      final controller = GlintAnimationController(
        _testRig(),
        initialAnimation: 1,
        events: const [
          GlintAnimationEvent(animationIndex: 1, time: .25, name: 'left foot'),
          GlintAnimationEvent(animationIndex: 1, time: .75, name: 'right foot'),
        ],
      );

      final occurrences = controller.update(2.1).events;

      expect(occurrences.map((occurrence) => occurrence.event.name), [
        'left foot',
        'right foot',
        'left foot',
        'right foot',
      ]);
      expect(occurrences.map((occurrence) => occurrence.loop), [0, 0, 1, 1]);
    });

    test('root motion stays continuous through a looping clip boundary', () {
      final controller = GlintAnimationController(
        _testRig(),
        initialAnimation: 1,
        rootMotionOptions: const GlintRootMotionOptions(nodeIndex: 0),
      );

      final first = controller.update(.75);
      final acrossBoundary = controller.update(.5);

      expect(first.rootMotion.translation.x, closeTo(7.5, 1e-9));
      expect(acrossBoundary.rootMotion.translation.x, closeTo(5, 1e-9));
      expect(first.pose.nodes[0].translation, Vector3.zero);
      expect(acrossBoundary.pose.nodes[0].translation, Vector3.zero);
    });
  });

  test('state machine drives crossfades from gameplay parameters', () {
    final controller = GlintAnimationController(_testRig());
    final machine = GlintAnimationStateMachine(
      controller: controller,
      states: const [
        GlintAnimationState(name: 'idle', animationIndex: 0),
        GlintAnimationState(name: 'run', animationIndex: 1),
      ],
      initialState: 'idle',
      transitions: [
        GlintAnimationTransition(
          from: 'idle',
          to: 'run',
          condition: (state) => state.number('speed') > .5,
        ),
        GlintAnimationTransition(
          from: 'run',
          to: 'idle',
          condition: (state) => state.number('speed') <= .5,
        ),
      ],
    );

    machine.setNumber('speed', 1);
    machine.update(.1);
    expect(machine.currentState, 'run');
    expect(controller.currentAnimationIndex, 1);

    machine.setNumber('speed', 0);
    machine.update(.1);
    expect(machine.currentState, 'idle');
    expect(controller.currentAnimationIndex, 0);
  });

  test('named masks reject nodes absent from the rig', () {
    expect(
      () => GlintBoneMask.fromNodeNames(_testRig(), ['missing']),
      throwsArgumentError,
    );
  });
}

GlintGlbRig _testRig() => const GlintGlbRig(
  nodes: [
    GlintGlbNode(name: 'root', children: [1, 2]),
    GlintGlbNode(name: 'upper'),
    GlintGlbNode(name: 'prop'),
  ],
  rootNodes: [0],
  meshes: [],
  animations: [
    GlintGlbAnimation(
      name: 'idle',
      duration: 1,
      channels: [
        GlintGlbAnimationChannel(
          nodeIndex: 0,
          path: GlintGlbAnimationPath.translation,
          inputTimes: [0, 1],
          output: [0, 0, 0, 0, 0, 0],
        ),
      ],
    ),
    GlintGlbAnimation(
      name: 'run',
      duration: 1,
      channels: [
        GlintGlbAnimationChannel(
          nodeIndex: 0,
          path: GlintGlbAnimationPath.translation,
          inputTimes: [0, 1],
          output: [0, 0, 0, 10, 0, 0],
        ),
      ],
    ),
    GlintGlbAnimation(
      name: 'wave',
      duration: 1,
      channels: [
        GlintGlbAnimationChannel(
          nodeIndex: 1,
          path: GlintGlbAnimationPath.translation,
          inputTimes: [0, 1],
          output: [0, 0, 0, 0, 4, 0],
        ),
      ],
    ),
  ],
);
