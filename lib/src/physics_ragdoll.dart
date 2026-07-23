import 'package:vector_math/vector_math.dart' as vm;

import 'assets/glb.dart';
import 'math.dart';
import 'physics.dart';

/// One physics body attached to a node in a skeletal rig.
class GlintRagdollPart {
  const GlintRagdollPart({
    required this.id,
    required this.collider,
    this.nodeIndex,
    this.nodeName,
    this.bodyOffset = const Transform3D(),
    this.colliderPosition = Vector3.zero,
    this.colliderOrientation = GlintQuaternion.identity,
    this.material = const GlintPhysicsMaterial(),
    this.linearDamping = .05,
    this.angularDamping = .1,
    this.ccdEnabled = false,
    this.collisionLayer = 1,
    this.collisionMask = 0x7fffffff,
    this.userData,
  });

  final String id;
  final int? nodeIndex;
  final String? nodeName;
  final GlintCollider collider;

  /// Transform from the skeleton node to the rigid body. This lets a capsule
  /// sit at a bone's midpoint while still driving the original joint node.
  final Transform3D bodyOffset;
  final Vector3 colliderPosition;
  final GlintQuaternion colliderOrientation;
  final GlintPhysicsMaterial material;
  final double linearDamping;
  final double angularDamping;
  final bool ccdEnabled;
  final int collisionLayer;
  final int collisionMask;
  final Object? userData;
}

enum GlintRagdollJointType { fixed, revolute, spherical }

/// A joint between two named [GlintRagdollPart] definitions.
class GlintRagdollConstraint {
  const GlintRagdollConstraint({
    required this.parentPart,
    required this.childPart,
    this.type = GlintRagdollJointType.spherical,
    this.frameA = const GlintJointFrame(),
    this.frameB = const GlintJointFrame(),
    this.collideConnected = false,
    this.lowerLimit,
    this.upperLimit,
    this.coneAngle,
    this.lowerTwist,
    this.upperTwist,
    this.linearFrequency = 0,
    this.angularFrequency = 0,
    this.dampingRatio = 0,
    this.maxMotorTorque,
  });

  final String parentPart;
  final String childPart;
  final GlintRagdollJointType type;
  final GlintJointFrame frameA;
  final GlintJointFrame frameB;
  final bool collideConnected;
  final double? lowerLimit;
  final double? upperLimit;
  final double? coneAngle;
  final double? lowerTwist;
  final double? upperTwist;
  final double linearFrequency;
  final double angularFrequency;
  final double dampingRatio;
  final double? maxMotorTorque;
}

/// A reusable, model-specific mapping from skeleton nodes to physics bodies.
class GlintRagdollDefinition {
  const GlintRagdollDefinition({
    required this.parts,
    this.constraints = const [],
  });

  final List<GlintRagdollPart> parts;
  final List<GlintRagdollConstraint> constraints;
}

/// Runtime bridge between a [GlintGlbRig] animation pose and an articulated
/// set of backend-neutral physics bodies.
///
/// The ragdoll may be kinematically driven from animation, switched to full
/// simulation, then blended back into any animation-controller pose. The
/// definition is intentionally authored outside the engine so humanoids,
/// animals, robots, and procedural rigs can all choose their own bodies and
/// limits.
class GlintRagdoll implements GlintPhysicsSnapshotParticipant {
  factory GlintRagdoll.create({
    required GlintPhysicsWorld world,
    required GlintGlbRig rig,
    required GlintRagdollDefinition definition,
    GlintAnimationPose? pose,
    Transform3D modelTransform = const Transform3D(),
    bool simulated = true,
    double blendWeight = 1,
  }) {
    if (definition.parts.isEmpty) {
      throw ArgumentError.value(definition, 'definition', 'has no parts');
    }
    if (!blendWeight.isFinite || blendWeight < 0 || blendWeight > 1) {
      throw ArgumentError.value(blendWeight, 'blendWeight', 'must be 0..1');
    }
    final resolved = <String, _ResolvedRagdollPart>{};
    final occupiedNodes = <int>{};
    for (final part in definition.parts) {
      if (part.id.isEmpty || resolved.containsKey(part.id)) {
        throw ArgumentError.value(
          part.id,
          'definition',
          'part ids must be unique',
        );
      }
      final hasIndex = part.nodeIndex != null;
      final hasName = part.nodeName != null;
      if (hasIndex == hasName) {
        throw ArgumentError.value(
          part.id,
          'definition',
          'each part must specify exactly one nodeIndex or nodeName',
        );
      }
      final nodeIndex =
          part.nodeIndex ??
          rig.nodes.indexWhere((node) => node.name == part.nodeName);
      if (nodeIndex < 0 || nodeIndex >= rig.nodes.length) {
        throw ArgumentError.value(
          part.nodeName ?? part.nodeIndex,
          'definition',
          'does not identify a rig node',
        );
      }
      if (!occupiedNodes.add(nodeIndex)) {
        throw ArgumentError.value(
          nodeIndex,
          'definition',
          'only one body may drive a rig node',
        );
      }
      resolved[part.id] = _ResolvedRagdollPart(part, nodeIndex);
    }
    for (final constraint in definition.constraints) {
      if (!resolved.containsKey(constraint.parentPart) ||
          !resolved.containsKey(constraint.childPart) ||
          constraint.parentPart == constraint.childPart) {
        throw ArgumentError.value(
          constraint,
          'definition',
          'constraints must reference two different declared parts',
        );
      }
    }

    final ragdoll = GlintRagdoll._(
      world: world,
      rig: rig,
      definition: definition,
      resolved: resolved,
      simulated: simulated,
      blendWeight: blendWeight,
    );
    ragdoll._build(pose ?? rig.bindPose(), modelTransform);
    return ragdoll;
  }

  GlintRagdoll._({
    required this.world,
    required this.rig,
    required this.definition,
    required this._resolved,
    required this._simulated,
    required this._blendWeight,
  });

  final GlintPhysicsWorld world;
  final GlintGlbRig rig;
  final GlintRagdollDefinition definition;
  final Map<String, _ResolvedRagdollPart> _resolved;
  final Map<String, GlintRigidBody> _bodies = {};
  final List<GlintColliderHandle> _colliders = [];
  final List<GlintJoint> _joints = [];
  late final List<int> _parents = _nodeParents(rig);
  bool _simulated;
  double _blendWeight;
  bool _disposed = false;

  Map<String, GlintRigidBody> get bodies => Map.unmodifiable(_bodies);
  bool get isSimulated => _simulated;

  double get blendWeight => _blendWeight;
  set blendWeight(double value) {
    if (!value.isFinite || value < 0 || value > 1) {
      throw ArgumentError.value(value, 'blendWeight', 'must be 0..1');
    }
    _blendWeight = value;
  }

  GlintRigidBody body(String partId) {
    final result = _bodies[partId];
    if (result == null) {
      throw ArgumentError.value(partId, 'partId', 'was not found');
    }
    return result;
  }

  void _build(GlintAnimationPose pose, Transform3D modelTransform) {
    final nodeWorlds = rig.nodeWorldTransformsFromPose(pose);
    final model = _transformMatrix(modelTransform);
    for (final entry in _resolved.entries) {
      final part = entry.value.definition;
      final node = vm.Matrix4.fromList(nodeWorlds[entry.value.nodeIndex]);
      final offset = _transformMatrix(part.bodyOffset);
      final bodyWorld = model * node * offset as vm.Matrix4;
      final transform = _decompose(bodyWorld);
      final body = world.createBody(
        GlintRigidBodyConfig(
          type: _simulated ? GlintBodyType.dynamic : GlintBodyType.kinematic,
          position: transform.position,
          orientation: transform.orientation!,
          linearDamping: part.linearDamping,
          angularDamping: part.angularDamping,
          gravityScale: _simulated ? 1 : 0,
          ccdEnabled: part.ccdEnabled,
          sleepEnabled: _simulated,
          userData: part.userData ?? part.id,
        ),
      );
      _bodies[entry.key] = body;
      _colliders.add(
        body.addCollider(
          part.collider,
          material: part.material,
          localPosition: part.colliderPosition,
          localOrientation: part.colliderOrientation,
          collisionLayer: part.collisionLayer,
          collisionMask: part.collisionMask,
          userData: part.userData ?? part.id,
        ),
      );
    }

    for (final constraint in definition.constraints) {
      final parent = body(constraint.parentPart);
      final child = body(constraint.childPart);
      final config = switch (constraint.type) {
        GlintRagdollJointType.fixed => GlintFixedJointConfig(
          bodyA: parent,
          bodyB: child,
          frameA: constraint.frameA,
          frameB: constraint.frameB,
          collideConnected: constraint.collideConnected,
          linearFrequency: constraint.linearFrequency,
          angularFrequency: constraint.angularFrequency,
          linearDampingRatio: constraint.dampingRatio,
          angularDampingRatio: constraint.dampingRatio,
        ),
        GlintRagdollJointType.revolute => GlintRevoluteJointConfig(
          bodyA: parent,
          bodyB: child,
          frameA: constraint.frameA,
          frameB: constraint.frameB,
          collideConnected: constraint.collideConnected,
          lowerLimit: constraint.lowerLimit,
          upperLimit: constraint.upperLimit,
          maxMotorTorque: constraint.maxMotorTorque,
        ),
        GlintRagdollJointType.spherical => GlintSphericalJointConfig(
          bodyA: parent,
          bodyB: child,
          frameA: constraint.frameA,
          frameB: constraint.frameB,
          collideConnected: constraint.collideConnected,
          coneAngle: constraint.coneAngle,
          lowerTwist: constraint.lowerTwist,
          upperTwist: constraint.upperTwist,
          maxMotorTorque: constraint.maxMotorTorque,
        ),
      };
      _joints.add(world.createJoint(config));
    }
    world.addSnapshotParticipant(this);
  }

  /// Switches between dynamic simulation and animation-driven kinematics.
  /// Call [driveFromAnimation] every fixed tick while kinematic.
  void setSimulated(
    bool value, {
    Vector3 linearVelocity = Vector3.zero,
    Vector3 angularVelocity = Vector3.zero,
  }) {
    if (_simulated == value) return;
    _simulated = value;
    for (final body in _bodies.values) {
      body
        ..type = value ? GlintBodyType.dynamic : GlintBodyType.kinematic
        ..setGravityScale(value ? 1 : 0)
        ..linearVelocity = value ? linearVelocity : Vector3.zero
        ..angularVelocity = value ? angularVelocity : Vector3.zero
        ..wakeUp();
    }
  }

  /// Teleports kinematic parts to [pose]. This is also useful immediately
  /// before enabling simulation so the ragdoll starts from the visible frame.
  void driveFromAnimation(
    GlintAnimationPose pose, {
    Transform3D modelTransform = const Transform3D(),
  }) {
    _checkPose(pose);
    final worlds = rig.nodeWorldTransformsFromPose(pose);
    final model = _transformMatrix(modelTransform);
    for (final entry in _resolved.entries) {
      final part = entry.value.definition;
      final node = vm.Matrix4.fromList(worlds[entry.value.nodeIndex]);
      final bodyWorld =
          model * node * _transformMatrix(part.bodyOffset) as vm.Matrix4;
      final transform = _decompose(bodyWorld);
      body(entry.key)
        ..setTransform(transform.position, transform.orientation!)
        ..linearVelocity = Vector3.zero
        ..angularVelocity = Vector3.zero;
    }
  }

  /// Returns an animation pose whose mapped nodes are driven by physics.
  /// Unmapped nodes retain their local animation, so facial animation,
  /// accessories, and partially simulated rigs continue to work.
  GlintAnimationPose poseFromPhysics(
    GlintAnimationPose animationPose, {
    Transform3D modelTransform = const Transform3D(),
    double? weight,
  }) {
    _checkPose(animationPose);
    final mix = weight ?? _blendWeight;
    if (!mix.isFinite || mix < 0 || mix > 1) {
      throw ArgumentError.value(mix, 'weight', 'must be 0..1');
    }
    if (mix == 0) return animationPose;

    final sourceWorldValues = rig.nodeWorldTransformsFromPose(animationPose);
    final sourceWorlds = [
      for (final matrix in sourceWorldValues) vm.Matrix4.fromList(matrix),
    ];
    final sourceLocals = <vm.Matrix4>[];
    for (var index = 0; index < rig.nodes.length; index++) {
      final parent = _parents[index];
      if (parent < 0) {
        sourceLocals.add(sourceWorlds[index].clone());
      } else {
        final inverseParent = sourceWorlds[parent].clone();
        if (inverseParent.invert() == 0) {
          throw StateError('Rig parent transform $parent is not invertible.');
        }
        sourceLocals.add(inverseParent * sourceWorlds[index] as vm.Matrix4);
      }
    }

    final modelInverse = _transformMatrix(modelTransform);
    if (modelInverse.invert() == 0) {
      throw ArgumentError.value(
        modelTransform,
        'modelTransform',
        'must be invertible',
      );
    }
    final partByNode = <int, MapEntry<String, _ResolvedRagdollPart>>{
      for (final entry in _resolved.entries) entry.value.nodeIndex: entry,
    };
    final targetWorlds = List<vm.Matrix4?>.filled(rig.nodes.length, null);
    vm.Matrix4 resolveWorld(int index) {
      final cached = targetWorlds[index];
      if (cached != null) return cached;
      final part = partByNode[index];
      if (part != null) {
        final bodyWorld = _bodyMatrix(body(part.key));
        final offsetInverse = _transformMatrix(
          part.value.definition.bodyOffset,
        );
        if (offsetInverse.invert() == 0) {
          throw StateError(
            'Ragdoll part ${part.key} has a singular bodyOffset.',
          );
        }
        return targetWorlds[index] =
            modelInverse * bodyWorld * offsetInverse as vm.Matrix4;
      }
      final parent = _parents[index];
      return targetWorlds[index] = parent < 0
          ? sourceLocals[index].clone()
          : resolveWorld(parent) * sourceLocals[index] as vm.Matrix4;
    }

    final output = animationPose.nodes.toList();
    final trsNodes = {...animationPose.trsNodes};
    for (final entry in partByNode.entries) {
      final index = entry.key;
      final parent = _parents[index];
      var local = resolveWorld(index).clone();
      if (parent >= 0) {
        final inverseParent = resolveWorld(parent).clone();
        if (inverseParent.invert() == 0) {
          throw StateError('Resolved rig parent $parent is not invertible.');
        }
        local = inverseParent * local as vm.Matrix4;
      }
      final target = _decompose(local);
      final source = animationPose.nodes[index];
      output[index] = GlintAnimationNodePose(
        translation: _lerp(source.translation, target.position, mix),
        rotation: GlintQuaternion.slerp(
          source.rotation,
          target.orientation!,
          mix,
        ),
        // Rigid bodies carry no scale. Preserve the authored bone scale.
        scale: source.scale,
      );
      trsNodes.add(index);
    }
    return GlintAnimationPose(nodes: output, trsNodes: trsNodes);
  }

  void applyImpulse(String partId, Vector3 impulse, {Vector3? atWorldPoint}) =>
      body(partId).applyImpulse(impulse, atWorldPoint: atWorldPoint);

  void _checkPose(GlintAnimationPose pose) {
    if (pose.nodes.length != rig.nodes.length) {
      throw ArgumentError.value(
        pose.nodes.length,
        'pose',
        'must contain ${rig.nodes.length} nodes',
      );
    }
  }

  @override
  Object capturePhysicsState() => (_simulated, _blendWeight);

  @override
  void restorePhysicsState(Object state) {
    if (state is! (bool, double)) {
      throw ArgumentError.value(state, 'state', 'is not a ragdoll snapshot');
    }
    _simulated = state.$1;
    _blendWeight = state.$2;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    world.removeSnapshotParticipant(this);
    for (final joint in _joints.reversed) {
      joint.destroy();
    }
    for (final collider in _colliders.reversed) {
      collider.destroy();
    }
    for (final body in _bodies.values.toList().reversed) {
      body.destroy();
    }
    _joints.clear();
    _colliders.clear();
    _bodies.clear();
  }
}

class _ResolvedRagdollPart {
  const _ResolvedRagdollPart(this.definition, this.nodeIndex);
  final GlintRagdollPart definition;
  final int nodeIndex;
}

List<int> _nodeParents(GlintGlbRig rig) {
  final parents = List.filled(rig.nodes.length, -1);
  for (var parent = 0; parent < rig.nodes.length; parent++) {
    for (final child in rig.nodes[parent].children) {
      if (child < 0 || child >= parents.length) {
        throw StateError('Rig node $parent has an invalid child $child.');
      }
      if (parents[child] >= 0) {
        throw StateError('Rig node $child has more than one parent.');
      }
      parents[child] = parent;
    }
  }
  return parents;
}

vm.Matrix4 _transformMatrix(Transform3D value) {
  final orientation = value.orientation;
  if (orientation != null) {
    return vm.Matrix4.compose(
      vm.Vector3(value.position.x, value.position.y, value.position.z),
      vm.Quaternion(orientation.x, orientation.y, orientation.z, orientation.w),
      vm.Vector3(value.scale.x, value.scale.y, value.scale.z),
    );
  }
  return vm.Matrix4.identity()
    ..translateByDouble(value.position.x, value.position.y, value.position.z, 1)
    ..rotateZ(value.rotation.z)
    ..rotateY(value.rotation.y)
    ..rotateX(value.rotation.x)
    ..scaleByDouble(value.scale.x, value.scale.y, value.scale.z, 1);
}

vm.Matrix4 _bodyMatrix(GlintRigidBody body) => vm.Matrix4.compose(
  vm.Vector3(body.position.x, body.position.y, body.position.z),
  vm.Quaternion(
    body.orientation.x,
    body.orientation.y,
    body.orientation.z,
    body.orientation.w,
  ),
  vm.Vector3.all(1),
);

Transform3D _decompose(vm.Matrix4 matrix) {
  final translation = vm.Vector3.zero();
  final rotation = vm.Quaternion.identity();
  final scale = vm.Vector3.zero();
  matrix.decompose(translation, rotation, scale);
  return Transform3D(
    position: Vector3(translation.x, translation.y, translation.z),
    orientation: GlintQuaternion(
      rotation.x,
      rotation.y,
      rotation.z,
      rotation.w,
    ).normalized,
    scale: Vector3(scale.x, scale.y, scale.z),
  );
}

Vector3 _lerp(Vector3 a, Vector3 b, double t) => a + (b - a) * t;
