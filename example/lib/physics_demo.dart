import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glint_box3d/glint_box3d.dart';
import 'package:glint_engine/glint_engine.dart';

class PhysicsDemoPage extends StatefulWidget {
  const PhysicsDemoPage({super.key});

  @override
  State<PhysicsDemoPage> createState() => _PhysicsDemoPageState();
}

class _PhysicsDemoPageState extends State<PhysicsDemoPage> {
  static const _models = {
    'box': Model.asset('packages/glint_engine/assets/models/box.glb'),
  };
  static const _track = Material3D(color: Color(0xff252a32), roughness: .92);
  static const _car = Material3D(
    color: Color(0xffff7a18),
    metallic: .55,
    roughness: .28,
  );
  static const _tire = Material3D(color: Color(0xff15171b), roughness: .8);
  static const _barrier = Material3D(color: Color(0xffe8edf2), roughness: .6);

  late GlintBox3dWorld _world;
  late GlintRigidBody _chassis;
  late GlintRaycastVehicle _vehicle;
  final List<GlintRigidBody> _props = [];
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    if (_ready) {
      _vehicle.dispose();
      _world.dispose();
    }
    _world = GlintBox3dWorld(fixedTimeStep: 1 / 120, maxSubSteps: 8);

    final track = _world.createBody(
      const GlintRigidBodyConfig(type: GlintBodyType.static),
    );
    track.addCollider(
      const GlintBoxCollider(Vector3(10, .25, 42)),
      localPosition: const Vector3(0, -.25, -12),
      material: const GlintPhysicsMaterial(friction: 1.1),
    );
    for (final x in const [-10.4, 10.4]) {
      track.addCollider(
        const GlintBoxCollider(Vector3(.35, .7, 42)),
        localPosition: Vector3(x, .7, -12),
        material: const GlintPhysicsMaterial(friction: .7),
      );
    }

    _chassis = _world.createBody(
      const GlintRigidBodyConfig(
        position: Vector3(0, 1.1, 7),
        linearDamping: .03,
        angularDamping: .16,
        ccdEnabled: true,
      ),
    );
    _chassis.addCollider(
      const GlintCompoundCollider([
        GlintCompoundChild(collider: GlintBoxCollider(Vector3(.9, .28, 1.75))),
        GlintCompoundChild(
          collider: GlintBoxCollider(Vector3(.68, .25, .78)),
          position: Vector3(0, .38, .12),
        ),
      ]),
      localPosition: const Vector3(0, .18, 0),
      material: const GlintPhysicsMaterial(
        density: 430,
        friction: .45,
        restitution: .03,
      ),
    );
    _vehicle = GlintRaycastVehicle(
      world: _world,
      chassis: _chassis,
      config: const GlintVehicleConfig(
        wheels: [
          GlintVehicleWheel(
            name: 'front-left',
            mount: Vector3(-.83, .12, -1.27),
            axle: 0,
            powered: true,
            steered: true,
          ),
          GlintVehicleWheel(
            name: 'front-right',
            mount: Vector3(.83, .12, -1.27),
            axle: 0,
            powered: true,
            steered: true,
          ),
          GlintVehicleWheel(
            name: 'rear-left',
            mount: Vector3(-.83, .12, 1.2),
            axle: 1,
            powered: true,
            handbrake: true,
          ),
          GlintVehicleWheel(
            name: 'rear-right',
            mount: Vector3(.83, .12, 1.2),
            axle: 1,
            powered: true,
            handbrake: true,
          ),
        ],
      ),
    );

    _props.clear();
    for (var i = 0; i < 8; i++) {
      final prop = _world.createBody(
        GlintRigidBodyConfig(
          position: Vector3(i.isEven ? -6.8 : 6.8, .65, -4.0 - i * 5.0),
          angularDamping: .08,
        ),
      );
      prop.addCollider(
        const GlintBoxCollider(Vector3(.55, .65, .55)),
        material: const GlintPhysicsMaterial(
          density: 45,
          friction: .7,
          restitution: .15,
        ),
      );
      _props.add(prop);
    }
    _ready = true;
  }

  bool _pressed(LogicalKeyboardKey key) =>
      HardwareKeyboard.instance.isLogicalKeyPressed(key);

  GlintGameFrame _frame(double dt) {
    _vehicle
      ..throttle =
          _pressed(LogicalKeyboardKey.arrowUp) ||
              _pressed(LogicalKeyboardKey.keyW)
          ? 1
          : _pressed(LogicalKeyboardKey.arrowDown) ||
                _pressed(LogicalKeyboardKey.keyS)
          ? -.65
          : 0
      ..brake = _pressed(LogicalKeyboardKey.shiftLeft) ? 1 : 0
      ..steer =
          _pressed(LogicalKeyboardKey.arrowLeft) ||
              _pressed(LogicalKeyboardKey.keyA)
          ? -1
          : _pressed(LogicalKeyboardKey.arrowRight) ||
                _pressed(LogicalKeyboardKey.keyD)
          ? 1
          : 0
      ..handbrake = _pressed(LogicalKeyboardKey.space) ? 1 : 0
      ..boost = _pressed(LogicalKeyboardKey.keyN);
    _world.step(dt);

    final position = _chassis.interpolatedPosition;
    final forward = _chassis.interpolatedOrientation.rotate(
      const Vector3(0, 0, -1),
    );
    return GlintGameFrame(
      camera: GlintGameCamera(
        position: position - forward * 8 + const Vector3(0, 4.2, 0),
        target: position + forward * 4 + const Vector3(0, .6, 0),
        fieldOfViewDegrees: 58,
        far: 180,
      ),
      instances: [
        const GlintGameInstance(
          model: 'box',
          transform: Transform3D(
            position: Vector3(0, -.25, -12),
            scale: Vector3(20, .5, 84),
          ),
          material: _track,
        ),
        for (final x in const [-10.4, 10.4])
          GlintGameInstance(
            model: 'box',
            transform: Transform3D(
              position: Vector3(x, .7, -12),
              scale: const Vector3(.7, 1.4, 84),
            ),
            material: _barrier,
          ),
        GlintGameInstance(
          model: 'box',
          transform: _chassis.toTransform(scale: const Vector3(1.8, .65, 3.5)),
          material: _car,
        ),
        for (final wheel in _vehicle.wheelStates)
          GlintGameInstance(
            model: 'box',
            transform: Transform3D(
              position: wheel.center,
              orientation: wheel.orientation,
              scale: const Vector3(.5, .5, .24),
            ),
            material: _tire,
          ),
        for (final prop in _props)
          GlintGameInstance(
            model: 'box',
            transform: prop.toTransform(scale: const Vector3(1.1, 1.3, 1.1)),
            material: _barrier,
          ),
      ],
    );
  }

  @override
  void dispose() {
    _vehicle.dispose();
    _world.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        GlintGameView(
          models: _models,
          onFrame: _frame,
          environmentAsset:
              'packages/glint_engine/assets/environments/studio.hdr',
          showStats: true,
          fallback: const Center(
            child: Text(
              'Flutter GPU requires Impeller.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton.filledTonal(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 12),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Text(
                      'WASD / arrows · Shift brake · Space drift · N nitro',
                    ),
                  ),
                ),
                const Spacer(),
                IconButton.filledTonal(
                  tooltip: 'Reset car and props',
                  onPressed: () => setState(_reset),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
