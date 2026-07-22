import 'assets/glb.dart';
import 'math.dart';

/// A set of rig nodes affected by an animation layer.
class GlintBoneMask {
  GlintBoneMask(Iterable<int> nodeIndices)
    : nodeIndices = Set.unmodifiable(nodeIndices) {
    if (this.nodeIndices.any((index) => index < 0)) {
      throw ArgumentError.value(nodeIndices, 'nodeIndices', 'must be >= 0');
    }
  }

  /// Builds a mask containing [rootNodeIndex] and all of its descendants.
  factory GlintBoneMask.fromRoot(
    GlintGlbRig rig,
    int rootNodeIndex, {
    bool includeRoot = true,
  }) {
    _checkNodeIndex(rig, rootNodeIndex);
    final result = <int>{};
    void visit(int index) {
      if (!result.add(index)) return;
      for (final child in rig.nodes[index].children) {
        visit(child);
      }
    }

    visit(rootNodeIndex);
    if (!includeRoot) result.remove(rootNodeIndex);
    return GlintBoneMask(result);
  }

  /// Builds a mask from named nodes, optionally including their descendants.
  factory GlintBoneMask.fromNodeNames(
    GlintGlbRig rig,
    Iterable<String> names, {
    bool includeDescendants = true,
  }) {
    final requested = names.toSet();
    final roots = <int>[];
    for (var i = 0; i < rig.nodes.length; i++) {
      if (requested.remove(rig.nodes[i].name)) roots.add(i);
    }
    if (requested.isNotEmpty) {
      throw ArgumentError.value(
        requested,
        'names',
        'contains names not present in the rig',
      );
    }
    final result = <int>{};
    void visit(int index) {
      if (!result.add(index)) return;
      if (includeDescendants) {
        for (final child in rig.nodes[index].children) {
          visit(child);
        }
      }
    }

    for (final root in roots) {
      visit(root);
    }
    return GlintBoneMask(result);
  }

  final Set<int> nodeIndices;

  bool contains(int nodeIndex) => nodeIndices.contains(nodeIndex);
}

/// A named point on an animation clip's timeline.
class GlintAnimationEvent {
  const GlintAnimationEvent({
    required this.animationIndex,
    required this.time,
    required this.name,
    this.data,
  });

  final int animationIndex;
  final double time;
  final String name;
  final Object? data;
}

/// An animation event crossed during one controller update.
class GlintAnimationEventOccurrence {
  const GlintAnimationEventOccurrence({
    required this.event,
    required this.loop,
    this.layer,
  });

  final GlintAnimationEvent event;

  /// The zero-based loop containing this occurrence. This can be negative
  /// when a looping clip is intentionally played backwards past time zero.
  final int loop;

  /// The layer that emitted the event, or null for the base animation.
  final String? layer;
}

/// Root motion extracted during one animation update.
class GlintRootMotionDelta {
  const GlintRootMotionDelta({
    this.translation = Vector3.zero,
    this.rotation = GlintQuaternion.identity,
  });

  static const zero = GlintRootMotionDelta();

  final Vector3 translation;
  final GlintQuaternion rotation;
}

/// Configures motion extraction from one node, commonly the skeleton root.
class GlintRootMotionOptions {
  const GlintRootMotionOptions({
    required this.nodeIndex,
    this.extractTranslation = true,
    this.extractRotation = true,
    this.removeFromPose = true,
  });

  final int nodeIndex;
  final bool extractTranslation;
  final bool extractRotation;

  /// Keeps the rendered skeleton in-place so callers can apply [rootMotion]
  /// to their entity or physics body without applying it twice.
  final bool removeFromPose;
}

/// The result of advancing an animation controller.
class GlintAnimationFrame {
  const GlintAnimationFrame({
    required this.pose,
    this.rootMotion = GlintRootMotionDelta.zero,
    this.events = const [],
  });

  final GlintAnimationPose pose;
  final GlintRootMotionDelta rootMotion;
  final List<GlintAnimationEventOccurrence> events;
}

/// A weighted clip layered over the controller's base animation.
///
/// Override layers blend toward their clip. Additive layers apply the delta
/// from [referenceTime], which is useful for recoil, leaning, and facial
/// animation without replacing locomotion underneath.
class GlintAnimationLayer {
  GlintAnimationLayer({
    required this.name,
    required this.animationIndex,
    this.mask,
    double weight = 1,
    double speed = 1,
    this.loop = true,
    this.additive = false,
    double referenceTime = 0,
    double startTime = 0,
  }) : _weight = _validWeight(weight),
       _speed = _validFinite(speed, 'speed'),
       referenceTime = _validFinite(referenceTime, 'referenceTime'),
       _time = _validFinite(startTime, 'startTime');

  final String name;
  final int animationIndex;
  final GlintBoneMask? mask;
  final bool loop;
  final bool additive;
  final double referenceTime;

  double _weight;
  double _speed;
  double _time;
  Vector3 _rootTranslationOffset = Vector3.zero;
  GlintQuaternion _rootRotationOffset = GlintQuaternion.identity;

  double get weight => _weight;
  set weight(double value) => _weight = _validWeight(value);

  double get speed => _speed;
  set speed(double value) => _speed = _validFinite(value, 'speed');

  double get time => _time;

  void seek(double time) => _time = _validFinite(time, 'time');
}

/// Runtime playback for a [GlintGlbRig].
///
/// It supports interruption-safe crossfades, override and additive layers,
/// bone masks, timeline events, reverse playback, and loop-safe root motion.
/// The resulting [pose] can be passed directly to a game instance.
class GlintAnimationController {
  GlintAnimationController(
    this.rig, {
    int? initialAnimation,
    bool loop = true,
    double speed = 1,
    Iterable<GlintAnimationEvent> events = const [],
    this.rootMotionOptions,
  }) : events = List.unmodifiable(events) {
    if (rootMotionOptions != null) {
      _checkNodeIndex(rig, rootMotionOptions!.nodeIndex);
    }
    for (final event in this.events) {
      _checkAnimationIndex(rig, event.animationIndex);
      final duration = rig.animations[event.animationIndex].duration;
      if (!event.time.isFinite || event.time < 0 || event.time > duration) {
        throw ArgumentError.value(
          event.time,
          'events',
          'event time must be within its clip duration (0..$duration)',
        );
      }
    }
    _pose = rig.bindPose();
    _unwrappedPose = _pose;
    if (initialAnimation != null) {
      play(initialAnimation, loop: loop, speed: speed);
    }
  }

  final GlintGlbRig rig;
  final List<GlintAnimationEvent> events;
  final GlintRootMotionOptions? rootMotionOptions;

  late GlintAnimationPose _pose;
  late GlintAnimationPose _unwrappedPose;
  _GlintAnimationTrack? _current;
  _GlintAnimationTrack? _outgoing;
  GlintAnimationPose? _transitionSource;
  GlintAnimationPose? _transitionSourceUnwrapped;
  double _transitionDuration = 0;
  double _transitionElapsed = 0;
  final List<GlintAnimationLayer> _layers = [];

  GlintAnimationPose get pose => _pose;
  List<GlintAnimationLayer> get layers => List.unmodifiable(_layers);
  int? get currentAnimationIndex => _current?.animationIndex;
  double get time => _current?.time ?? 0;
  bool get isTransitioning => _outgoing != null || _transitionSource != null;

  double get normalizedTime {
    final track = _current;
    if (track == null) return 0;
    final duration = rig.animations[track.animationIndex].duration;
    if (duration <= 0) return 0;
    if (track.loop) return (track.time % duration) / duration;
    return (track.time / duration).clamp(0.0, 1.0).toDouble();
  }

  bool get isComplete {
    final track = _current;
    if (track == null || track.loop) return false;
    final duration = rig.animations[track.animationIndex].duration;
    return track.speed >= 0 ? track.time >= duration : track.time <= 0;
  }

  /// Returns the first clip with [name], throwing when it is absent.
  int animationIndexByName(String name) {
    final index = rig.animations.indexWhere((clip) => clip.name == name);
    if (index < 0) {
      throw ArgumentError.value(name, 'name', 'animation clip was not found');
    }
    return index;
  }

  /// Plays a clip, optionally fading from the currently evaluated pose.
  void play(
    int animationIndex, {
    double fadeDuration = 0,
    bool loop = true,
    double speed = 1,
    double startTime = 0,
    bool restart = true,
  }) {
    _checkAnimationIndex(rig, animationIndex);
    _validDuration(fadeDuration, 'fadeDuration');
    _validFinite(speed, 'speed');
    _validFinite(startTime, 'startTime');
    if (!restart && _current?.animationIndex == animationIndex) return;

    final hadCurrent = _current != null;
    final wasTransitioning = isTransitioning;
    final next = _GlintAnimationTrack(
      animationIndex: animationIndex,
      loop: loop,
      speed: speed,
      time: startTime,
    );

    if (rootMotionOptions != null && hadCurrent) {
      final target = _sampleTrack(next, unwrappedRoot: true);
      final node = rootMotionOptions!.nodeIndex;
      next.rootTranslationOffset =
          _unwrappedPose.nodes[node].translation -
          target.nodes[node].translation;
      next.rootRotationOffset =
          _unwrappedPose.nodes[node].rotation *
          target.nodes[node].rotation.conjugate;
    }

    if (hadCurrent && fadeDuration > 0) {
      if (wasTransitioning) {
        // A transition interrupted by another transition starts from the
        // exact visible pose, avoiding a pop back to either source clip.
        _transitionSource = _pose;
        _transitionSourceUnwrapped = _unwrappedPose;
        _outgoing = null;
      } else {
        _outgoing = _current;
        _transitionSource = null;
        _transitionSourceUnwrapped = null;
      }
      _transitionDuration = fadeDuration;
      _transitionElapsed = 0;
    } else {
      _clearTransition();
    }
    _current = next;
    _evaluatePoses();
  }

  /// Jumps within the current base clip without changing it.
  void seek(double time) {
    final track = _current;
    if (track == null) return;
    track.time = _validFinite(time, 'time');
    _evaluatePoses();
  }

  /// Adds a layer. Layer names are unique within a controller.
  void addLayer(GlintAnimationLayer layer) {
    _checkAnimationIndex(rig, layer.animationIndex);
    if (layer.mask != null &&
        layer.mask!.nodeIndices.any((index) => index >= rig.nodes.length)) {
      throw ArgumentError.value(
        layer.mask!.nodeIndices,
        'layer.mask',
        'contains a node outside this rig',
      );
    }
    if (_layers.any((candidate) => candidate.name == layer.name)) {
      throw ArgumentError.value(layer.name, 'layer.name', 'must be unique');
    }
    if (rootMotionOptions != null) {
      final target = _sampleLayer(layer, unwrappedRoot: true);
      final node = rootMotionOptions!.nodeIndex;
      layer._rootTranslationOffset =
          _unwrappedPose.nodes[node].translation -
          target.nodes[node].translation;
      layer._rootRotationOffset =
          _unwrappedPose.nodes[node].rotation *
          target.nodes[node].rotation.conjugate;
    }
    _layers.add(layer);
    _evaluatePoses();
  }

  bool removeLayer(String name) {
    final before = _layers.length;
    _layers.removeWhere((layer) => layer.name == name);
    if (_layers.length != before) _evaluatePoses();
    return _layers.length != before;
  }

  GlintAnimationLayer? layer(String name) {
    for (final layer in _layers) {
      if (layer.name == name) return layer;
    }
    return null;
  }

  /// Advances every active track and returns its pose, events, and root motion.
  GlintAnimationFrame update(double deltaSeconds) {
    _validDuration(deltaSeconds, 'deltaSeconds');
    final previousUnwrapped = _unwrappedPose;
    final occurrences = <GlintAnimationEventOccurrence>[];

    final current = _current;
    if (current != null) {
      final from = current.time;
      current.time += deltaSeconds * current.speed;
      occurrences.addAll(_eventsCrossed(current, from));
    }
    final outgoing = _outgoing;
    if (outgoing != null) {
      outgoing.time += deltaSeconds * outgoing.speed;
    }
    for (final layer in _layers) {
      final from = layer._time;
      layer._time += deltaSeconds * layer._speed;
      occurrences.addAll(_eventsCrossedLayer(layer, from));
    }
    if (isTransitioning) {
      _transitionElapsed += deltaSeconds;
    }

    _evaluatePoses();
    var rootMotion = GlintRootMotionDelta.zero;
    final root = rootMotionOptions;
    if (root != null) {
      final previous = previousUnwrapped.nodes[root.nodeIndex];
      final currentRoot = _unwrappedPose.nodes[root.nodeIndex];
      rootMotion = GlintRootMotionDelta(
        translation: root.extractTranslation
            ? currentRoot.translation - previous.translation
            : Vector3.zero,
        rotation: root.extractRotation
            ? (currentRoot.rotation * previous.rotation.conjugate).normalized
            : GlintQuaternion.identity,
      );
    }

    if (isTransitioning && _transitionElapsed >= _transitionDuration) {
      _clearTransition();
      _evaluatePoses();
    }
    return GlintAnimationFrame(
      pose: _pose,
      rootMotion: rootMotion,
      events: List.unmodifiable(occurrences),
    );
  }

  void _evaluatePoses() {
    var normal = _current == null
        ? rig.bindPose()
        : _sampleTrack(_current!, unwrappedRoot: false);
    var unwrapped = rootMotionOptions == null
        ? normal
        : _current == null
        ? normal
        : _sampleTrack(_current!, unwrappedRoot: true);

    if (isTransitioning) {
      final t = _transitionDuration <= 0
          ? 1.0
          : (_transitionElapsed / _transitionDuration)
                .clamp(0.0, 1.0)
                .toDouble();
      final source =
          _transitionSource ?? _sampleTrack(_outgoing!, unwrappedRoot: false);
      final sourceUnwrapped = rootMotionOptions == null
          ? source
          : _transitionSourceUnwrapped ??
                _sampleTrack(_outgoing!, unwrappedRoot: true);
      normal = _blendPoses(source, normal, t);
      unwrapped = _blendPoses(sourceUnwrapped, unwrapped, t);
    }

    for (final layer in _layers) {
      if (layer.weight <= 0) continue;
      final layerNormal = _sampleLayer(layer, unwrappedRoot: false);
      final layerUnwrapped = rootMotionOptions == null
          ? layerNormal
          : _sampleLayer(layer, unwrappedRoot: true);
      if (layer.additive) {
        final reference = rig.sampleAnimation(
          animation: layer.animationIndex,
          time: layer.referenceTime,
          loop: false,
        );
        normal = _addPose(
          normal,
          layerNormal,
          reference,
          layer.weight,
          layer.mask,
        );
        unwrapped = _addPose(
          unwrapped,
          layerUnwrapped,
          reference,
          layer.weight,
          layer.mask,
        );
      } else {
        normal = _blendPoses(normal, layerNormal, layer.weight, layer.mask);
        unwrapped = _blendPoses(
          unwrapped,
          layerUnwrapped,
          layer.weight,
          layer.mask,
        );
      }
    }

    _unwrappedPose = unwrapped;
    _pose = _removeExtractedRootMotion(normal);
  }

  GlintAnimationPose _sampleTrack(
    _GlintAnimationTrack track, {
    required bool unwrappedRoot,
  }) {
    final pose = rig.sampleAnimation(
      animation: track.animationIndex,
      time: track.time,
      loop: track.loop,
    );
    return unwrappedRoot
        ? _unwrapRoot(
            pose,
            track.animationIndex,
            track.time,
            track.loop,
            track.rootTranslationOffset,
            track.rootRotationOffset,
          )
        : pose;
  }

  GlintAnimationPose _sampleLayer(
    GlintAnimationLayer layer, {
    required bool unwrappedRoot,
  }) {
    final pose = rig.sampleAnimation(
      animation: layer.animationIndex,
      time: layer.time,
      loop: layer.loop,
    );
    return unwrappedRoot
        ? _unwrapRoot(
            pose,
            layer.animationIndex,
            layer.time,
            layer.loop,
            layer._rootTranslationOffset,
            layer._rootRotationOffset,
          )
        : pose;
  }

  GlintAnimationPose _unwrapRoot(
    GlintAnimationPose pose,
    int animationIndex,
    double time,
    bool loop,
    Vector3 translationOffset,
    GlintQuaternion rotationOffset,
  ) {
    final options = rootMotionOptions;
    if (options == null) return pose;
    final node = options.nodeIndex;
    final clip = rig.animations[animationIndex];
    var translation = pose.nodes[node].translation;
    var rotation = pose.nodes[node].rotation;
    if (loop && clip.duration > 0) {
      final cycles = (time / clip.duration).floor();
      if (cycles != 0) {
        final start = rig
            .sampleAnimation(animation: animationIndex, time: 0, loop: false)
            .nodes[node];
        final end = rig
            .sampleAnimation(
              animation: animationIndex,
              time: clip.duration,
              loop: false,
            )
            .nodes[node];
        translation +=
            (end.translation - start.translation) * cycles.toDouble();
        final cycleRotation =
            (end.rotation * start.rotation.conjugate).normalized;
        rotation =
            (_quaternionPower(cycleRotation, cycles) * rotation).normalized;
      }
    }
    return _replaceNode(
      pose,
      node,
      GlintAnimationNodePose(
        translation: translation + translationOffset,
        rotation: (rotationOffset * rotation).normalized,
        scale: pose.nodes[node].scale,
      ),
    );
  }

  GlintAnimationPose _removeExtractedRootMotion(GlintAnimationPose pose) {
    final options = rootMotionOptions;
    if (options == null || !options.removeFromPose) return pose;
    final node = options.nodeIndex;
    final bind = rig.bindPose().nodes[node];
    final current = pose.nodes[node];
    return _replaceNode(
      pose,
      node,
      GlintAnimationNodePose(
        translation: options.extractTranslation
            ? bind.translation
            : current.translation,
        rotation: options.extractRotation ? bind.rotation : current.rotation,
        scale: current.scale,
      ),
    );
  }

  List<GlintAnimationEventOccurrence> _eventsCrossed(
    _GlintAnimationTrack track,
    double from,
  ) => _collectEvents(
    animationIndex: track.animationIndex,
    from: from,
    to: track.time,
    loop: track.loop,
  );

  List<GlintAnimationEventOccurrence> _eventsCrossedLayer(
    GlintAnimationLayer layer,
    double from,
  ) => _collectEvents(
    animationIndex: layer.animationIndex,
    from: from,
    to: layer.time,
    loop: layer.loop,
    layer: layer.name,
  );

  List<GlintAnimationEventOccurrence> _collectEvents({
    required int animationIndex,
    required double from,
    required double to,
    required bool loop,
    String? layer,
  }) {
    if (from == to) return const [];
    final duration = rig.animations[animationIndex].duration;
    final matching = events.where(
      (event) => event.animationIndex == animationIndex,
    );
    final result = <(double, GlintAnimationEventOccurrence)>[];
    for (final event in matching) {
      if (!loop || duration <= 0) {
        final start = from.clamp(0.0, duration).toDouble();
        final end = to.clamp(0.0, duration).toDouble();
        final crossed = to > from
            ? event.time > start && event.time <= end
            : event.time < start && event.time >= end;
        if (crossed) {
          result.add((
            event.time,
            GlintAnimationEventOccurrence(event: event, loop: 0, layer: layer),
          ));
        }
        continue;
      }
      if (to > from) {
        final firstLoop = ((from - event.time) / duration).floor() + 1;
        final lastLoop = ((to - event.time) / duration).floor();
        for (var cycle = firstLoop; cycle <= lastLoop; cycle++) {
          final absoluteTime = event.time + cycle * duration;
          result.add((
            absoluteTime,
            GlintAnimationEventOccurrence(
              event: event,
              loop: cycle,
              layer: layer,
            ),
          ));
        }
      } else {
        final firstLoop = ((to - event.time) / duration).ceil();
        final lastLoop = ((from - event.time) / duration).ceil() - 1;
        for (var cycle = lastLoop; cycle >= firstLoop; cycle--) {
          final absoluteTime = event.time + cycle * duration;
          result.add((
            absoluteTime,
            GlintAnimationEventOccurrence(
              event: event,
              loop: cycle,
              layer: layer,
            ),
          ));
        }
      }
    }
    result.sort(
      (a, b) => to > from ? a.$1.compareTo(b.$1) : b.$1.compareTo(a.$1),
    );
    return [for (final item in result) item.$2];
  }

  void _clearTransition() {
    _outgoing = null;
    _transitionSource = null;
    _transitionSourceUnwrapped = null;
    _transitionDuration = 0;
    _transitionElapsed = 0;
  }
}

/// One named state in a [GlintAnimationStateMachine].
class GlintAnimationState {
  const GlintAnimationState({
    required this.name,
    required this.animationIndex,
    this.loop = true,
    this.speed = 1,
  });

  final String name;
  final int animationIndex;
  final bool loop;
  final double speed;
}

typedef GlintAnimationTransitionCondition =
    bool Function(GlintAnimationStateMachine machine);

/// A prioritized transition. A null [from] matches every current state.
class GlintAnimationTransition {
  const GlintAnimationTransition({
    this.from,
    required this.to,
    required this.condition,
    this.fadeDuration = .2,
  });

  final String? from;
  final String to;
  final GlintAnimationTransitionCondition condition;
  final double fadeDuration;
}

/// A small parameter-driven state machine around [GlintAnimationController].
///
/// Transitions are evaluated in declaration order, so callers can put hit,
/// death, or other high-priority any-state transitions first.
class GlintAnimationStateMachine {
  GlintAnimationStateMachine({
    required this.controller,
    required Iterable<GlintAnimationState> states,
    required String initialState,
    Iterable<GlintAnimationTransition> transitions = const [],
  }) : _states = {for (final state in states) state.name: state},
       transitions = List.unmodifiable(transitions),
       _currentState = initialState {
    if (_states.length != states.length) {
      throw ArgumentError.value(states, 'states', 'state names must be unique');
    }
    if (!_states.containsKey(initialState)) {
      throw ArgumentError.value(
        initialState,
        'initialState',
        'does not name a state',
      );
    }
    for (final transition in this.transitions) {
      if ((transition.from != null && !_states.containsKey(transition.from)) ||
          !_states.containsKey(transition.to)) {
        throw ArgumentError.value(
          transition,
          'transitions',
          'references an unknown state',
        );
      }
      _validDuration(transition.fadeDuration, 'transition.fadeDuration');
    }
    final initial = _states[initialState]!;
    controller.play(
      initial.animationIndex,
      loop: initial.loop,
      speed: initial.speed,
    );
  }

  final GlintAnimationController controller;
  final Map<String, GlintAnimationState> _states;
  final List<GlintAnimationTransition> transitions;
  final Map<String, double> _numbers = {};
  final Map<String, bool> _booleans = {};
  final Set<String> _triggers = {};
  String _currentState;

  String get currentState => _currentState;

  void setNumber(String name, double value) {
    _numbers[name] = _validFinite(value, 'value');
  }

  double number(String name, [double fallback = 0]) =>
      _numbers[name] ?? fallback;

  void setBool(String name, bool value) => _booleans[name] = value;
  bool boolean(String name, [bool fallback = false]) =>
      _booleans[name] ?? fallback;

  void setTrigger(String name) => _triggers.add(name);
  bool hasTrigger(String name) => _triggers.contains(name);

  void transitionTo(String stateName, {double fadeDuration = .2}) {
    final state = _states[stateName];
    if (state == null) {
      throw ArgumentError.value(
        stateName,
        'stateName',
        'does not name a state',
      );
    }
    _validDuration(fadeDuration, 'fadeDuration');
    _currentState = stateName;
    controller.play(
      state.animationIndex,
      fadeDuration: fadeDuration,
      loop: state.loop,
      speed: state.speed,
    );
  }

  GlintAnimationFrame update(double deltaSeconds) {
    for (final transition in transitions) {
      if (transition.to == _currentState ||
          (transition.from != null && transition.from != _currentState)) {
        continue;
      }
      if (transition.condition(this)) {
        transitionTo(transition.to, fadeDuration: transition.fadeDuration);
        break;
      }
    }
    _triggers.clear();
    return controller.update(deltaSeconds);
  }
}

class _GlintAnimationTrack {
  _GlintAnimationTrack({
    required this.animationIndex,
    required this.loop,
    required this.speed,
    required this.time,
  });

  final int animationIndex;
  final bool loop;
  final double speed;
  double time;
  Vector3 rootTranslationOffset = Vector3.zero;
  GlintQuaternion rootRotationOffset = GlintQuaternion.identity;
}

GlintAnimationPose _blendPoses(
  GlintAnimationPose from,
  GlintAnimationPose to,
  double weight, [
  GlintBoneMask? mask,
]) {
  if (from.nodes.length != to.nodes.length) {
    throw ArgumentError('Cannot blend poses from different rigs.');
  }
  final t = weight.clamp(0.0, 1.0).toDouble();
  final nodes = <GlintAnimationNodePose>[];
  final trsNodes = {...from.trsNodes};
  for (var i = 0; i < from.nodes.length; i++) {
    if (mask != null && !mask.contains(i)) {
      nodes.add(from.nodes[i]);
      continue;
    }
    final a = from.nodes[i];
    final b = to.nodes[i];
    nodes.add(
      GlintAnimationNodePose(
        translation: _lerpVector(a.translation, b.translation, t),
        rotation: GlintQuaternion.slerp(a.rotation, b.rotation, t),
        scale: _lerpVector(a.scale, b.scale, t),
      ),
    );
    if (t >= 1) {
      if (to.trsNodes.contains(i)) {
        trsNodes.add(i);
      } else {
        trsNodes.remove(i);
      }
    } else if (t > 0 && to.trsNodes.contains(i)) {
      trsNodes.add(i);
    }
  }
  return GlintAnimationPose(nodes: nodes, trsNodes: trsNodes);
}

GlintAnimationPose _addPose(
  GlintAnimationPose base,
  GlintAnimationPose layer,
  GlintAnimationPose reference,
  double weight,
  GlintBoneMask? mask,
) {
  if (base.nodes.length != layer.nodes.length ||
      base.nodes.length != reference.nodes.length) {
    throw ArgumentError('Cannot layer poses from different rigs.');
  }
  final t = weight.clamp(0.0, 1.0).toDouble();
  final nodes = <GlintAnimationNodePose>[];
  final trsNodes = {...base.trsNodes};
  for (var i = 0; i < base.nodes.length; i++) {
    if (mask != null && !mask.contains(i)) {
      nodes.add(base.nodes[i]);
      continue;
    }
    final a = base.nodes[i];
    final b = layer.nodes[i];
    final r = reference.nodes[i];
    final rotationDelta = (b.rotation * r.rotation.conjugate).normalized;
    nodes.add(
      GlintAnimationNodePose(
        translation: a.translation + (b.translation - r.translation) * t,
        rotation:
            (GlintQuaternion.slerp(GlintQuaternion.identity, rotationDelta, t) *
                    a.rotation)
                .normalized,
        scale: Vector3(
          a.scale.x * _additiveScale(r.scale.x, b.scale.x, t),
          a.scale.y * _additiveScale(r.scale.y, b.scale.y, t),
          a.scale.z * _additiveScale(r.scale.z, b.scale.z, t),
        ),
      ),
    );
    if (layer.trsNodes.contains(i)) trsNodes.add(i);
  }
  return GlintAnimationPose(nodes: nodes, trsNodes: trsNodes);
}

GlintAnimationPose _replaceNode(
  GlintAnimationPose pose,
  int nodeIndex,
  GlintAnimationNodePose node,
) {
  final nodes = pose.nodes.toList()..[nodeIndex] = node;
  return GlintAnimationPose(
    nodes: nodes,
    trsNodes: {...pose.trsNodes, nodeIndex},
  );
}

Vector3 _lerpVector(Vector3 a, Vector3 b, double t) => Vector3(
  a.x + (b.x - a.x) * t,
  a.y + (b.y - a.y) * t,
  a.z + (b.z - a.z) * t,
);

double _additiveScale(double reference, double value, double weight) =>
    reference == 0 ? 1 : 1 + (value / reference - 1) * weight;

GlintQuaternion _quaternionPower(GlintQuaternion value, int exponent) {
  if (exponent == 0) return GlintQuaternion.identity;
  var factor = exponent < 0 ? value.conjugate.normalized : value.normalized;
  var power = exponent.abs();
  var result = GlintQuaternion.identity;
  while (power > 0) {
    if (power.isOdd) result = (result * factor).normalized;
    factor = (factor * factor).normalized;
    power ~/= 2;
  }
  return result;
}

void _checkAnimationIndex(GlintGlbRig rig, int index) {
  if (index < 0 || index >= rig.animations.length) {
    throw RangeError.index(index, rig.animations, 'animationIndex');
  }
}

void _checkNodeIndex(GlintGlbRig rig, int index) {
  if (index < 0 || index >= rig.nodes.length) {
    throw RangeError.index(index, rig.nodes, 'nodeIndex');
  }
}

double _validFinite(double value, String name) {
  if (!value.isFinite) throw ArgumentError.value(value, name, 'must be finite');
  return value;
}

double _validDuration(double value, String name) {
  if (!value.isFinite || value < 0) {
    throw ArgumentError.value(value, name, 'must be finite and >= 0');
  }
  return value;
}

double _validWeight(double value) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw ArgumentError.value(value, 'weight', 'must be between 0 and 1');
  }
  return value;
}
