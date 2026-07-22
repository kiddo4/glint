import 'dart:math' as math;

import 'math.dart';
import 'physics.dart';

class GlintVehicleWheel {
  const GlintVehicleWheel({
    required this.name,
    required this.mount,
    required this.axle,
    this.radius = .34,
    this.suspensionLength = .32,
    this.springStiffness = 35000,
    this.damping = 4200,
    this.powered = false,
    this.steered = false,
    this.handbrake = false,
    this.grip = 1,
  });

  final String name;
  final Vector3 mount;
  final int axle;
  final double radius;
  final double suspensionLength;
  final double springStiffness;
  final double damping;
  final bool powered;
  final bool steered;
  final bool handbrake;
  final double grip;
}

class GlintVehicleConfig {
  const GlintVehicleConfig({
    required this.wheels,
    this.localForward = const Vector3(0, 0, -1),
    this.localUp = const Vector3(0, 1, 0),
    this.maxSteerAngle = .55,
    this.steerResponse = 8,
    this.engineForce = 11500,
    this.serviceBrakeForce = 18000,
    this.handbrakeForce = 23000,
    this.rollingResistance = 90,
    this.lateralStiffness = 14500,
    this.longitudinalStiffness = 9000,
    this.tireFriction = 1.25,
    this.handbrakeGrip = .42,
    this.antiRollStiffness = 9000,
    this.aerodynamicDrag = .42,
    this.downforce = 3.2,
    this.boostForce = 6500,
    this.finalDrive = 3.7,
    this.gearRatios = const [3.1, 2.15, 1.55, 1.18, .94, .78],
    this.shiftUpRpm = 6800,
    this.shiftDownRpm = 2800,
    this.idleRpm = 900,
    this.redlineRpm = 7200,
  });

  final List<GlintVehicleWheel> wheels;
  final Vector3 localForward;
  final Vector3 localUp;
  final double maxSteerAngle;
  final double steerResponse;
  final double engineForce;
  final double serviceBrakeForce;
  final double handbrakeForce;
  final double rollingResistance;
  final double lateralStiffness;
  final double longitudinalStiffness;
  final double tireFriction;
  final double handbrakeGrip;
  final double antiRollStiffness;
  final double aerodynamicDrag;
  final double downforce;
  final double boostForce;
  final double finalDrive;
  final List<double> gearRatios;
  final double shiftUpRpm;
  final double shiftDownRpm;
  final double idleRpm;
  final double redlineRpm;
}

class GlintVehicleWheelState {
  GlintVehicleWheelState(this.wheel);

  final GlintVehicleWheel wheel;
  bool grounded = false;
  double compression = 0;
  double suspensionForce = 0;
  double longitudinalSlip = 0;
  double lateralSlip = 0;
  double spinAngle = 0;
  Vector3 center = Vector3.zero;
  Vector3 contactPoint = Vector3.zero;
  Vector3 contactNormal = const Vector3(0, 1, 0);
  GlintQuaternion orientation = GlintQuaternion.identity;
}

/// A high-level arcade vehicle built entirely on [GlintPhysicsWorld].
///
/// It is deliberately outside the rigid-body contract: general physics stays
/// useful for any game, while racers get suspension, tire forces, anti-roll,
/// gears, aero, boost, surface grip, and per-wheel telemetry.
class GlintRaycastVehicle {
  GlintRaycastVehicle({
    required this.world,
    required this.chassis,
    required this.config,
    this.surfaceGrip,
  }) : wheelStates = [
         for (final wheel in config.wheels) GlintVehicleWheelState(wheel),
       ] {
    if (config.wheels.isEmpty) {
      throw ArgumentError.value(
        config.wheels,
        'config.wheels',
        'cannot be empty',
      );
    }
    world.addFixedStepCallback(_fixedUpdate);
  }

  final GlintPhysicsWorld world;
  final GlintRigidBody chassis;
  final GlintVehicleConfig config;
  final double Function(GlintPhysicsRayHit hit)? surfaceGrip;
  final List<GlintVehicleWheelState> wheelStates;

  double throttle = 0;
  double brake = 0;
  double steer = 0;
  double handbrake = 0;
  bool boost = false;

  double forwardSpeed = 0;
  double engineRpm = 0;
  int gear = 1;
  double _steerAngle = 0;
  bool _disposed = false;

  bool get isGrounded => wheelStates.any((wheel) => wheel.grounded);
  double get speedKilometersPerHour => chassis.linearVelocity.length * 3.6;

  void _fixedUpdate(double dt) {
    final rotation = chassis.orientation;
    final up = rotation.rotate(config.localUp).normalized;
    final forward = rotation.rotate(config.localForward).normalized;
    final velocity = chassis.linearVelocity;
    forwardSpeed = velocity.dot(forward);

    final targetSteer = steer.clamp(-1.0, 1.0) * config.maxSteerAngle;
    _steerAngle +=
        (targetSteer - _steerAngle) *
        (1 - math.exp(-config.steerResponse * dt));
    _updateTransmission();

    final poweredCount = math.max(
      1,
      config.wheels.where((w) => w.powered).length,
    );
    final axleStates = <int, List<GlintVehicleWheelState>>{};
    for (final state in wheelStates) {
      final wheel = state.wheel;
      final mount = chassis.position + rotation.rotate(wheel.mount);
      final ray = GlintRay(mount, -up);
      final hit = world.raycast(
        ray,
        maxDistance: wheel.suspensionLength + wheel.radius,
        filter: GlintQueryFilter(excludedBodies: {chassis}),
      );
      state.orientation = rotation;
      axleStates.putIfAbsent(wheel.axle, () => []).add(state);
      if (hit == null) {
        state
          ..grounded = false
          ..compression = 0
          ..suspensionForce = 0
          ..longitudinalSlip = 0
          ..lateralSlip = 0
          ..center = mount - up * wheel.suspensionLength;
        continue;
      }

      final suspensionLength = (hit.distance - wheel.radius).clamp(
        0.0,
        wheel.suspensionLength,
      );
      final compression = wheel.suspensionLength - suspensionLength;
      final pointVelocity = chassis.velocityAtWorldPoint(hit.position);
      var normalForce =
          wheel.springStiffness * compression -
          wheel.damping * pointVelocity.dot(up);
      normalForce = math.max(0, normalForce);

      state
        ..grounded = true
        ..compression = compression
        ..suspensionForce = normalForce
        ..contactPoint = hit.position
        ..contactNormal = hit.normal
        ..center = mount - up * suspensionLength;

      final suspensionDirection = (up + hit.normal).normalized;
      chassis.applyForce(
        suspensionDirection * normalForce,
        atWorldPoint: hit.position,
      );

      var tireForward = forward;
      if (wheel.steered && _steerAngle != 0) {
        tireForward = GlintQuaternion.axisAngle(
          up,
          _steerAngle,
        ).rotate(tireForward);
      }
      tireForward =
          (tireForward - hit.normal * tireForward.dot(hit.normal)).normalized;
      final tireRight = tireForward.cross(hit.normal).normalized;
      state.orientation = GlintQuaternion.axisAngle(up, _steerAngle) * rotation;

      final longitudinalVelocity = pointVelocity.dot(tireForward);
      final lateralVelocity = pointVelocity.dot(tireRight);
      state
        ..longitudinalSlip = longitudinalVelocity
        ..lateralSlip = lateralVelocity;

      var longitudinalForce = -longitudinalVelocity * config.rollingResistance;
      if (wheel.powered) {
        final speedFraction = (engineRpm / config.redlineRpm).clamp(0.0, 1.0);
        final torqueBand = .55 + .45 * math.sin(speedFraction * math.pi);
        longitudinalForce +=
            throttle.clamp(-1.0, 1.0) *
            config.engineForce *
            torqueBand /
            poweredCount;
      }
      longitudinalForce -=
          longitudinalVelocity.sign *
          brake.clamp(0.0, 1.0) *
          config.serviceBrakeForce;
      if (wheel.handbrake) {
        longitudinalForce -=
            longitudinalVelocity.sign *
            handbrake.clamp(0.0, 1.0) *
            config.handbrakeForce;
      }
      longitudinalForce -=
          longitudinalVelocity * config.longitudinalStiffness * .02;
      var lateralForce = -lateralVelocity * config.lateralStiffness;

      final roadGrip = surfaceGrip?.call(hit) ?? 1;
      final handbrakeScale = wheel.handbrake
          ? 1 - handbrake.clamp(0.0, 1.0) * (1 - config.handbrakeGrip)
          : 1.0;
      final forceLimit =
          normalForce *
          config.tireFriction *
          wheel.grip *
          roadGrip *
          handbrakeScale;
      final combined = math.sqrt(
        longitudinalForce * longitudinalForce + lateralForce * lateralForce,
      );
      if (combined > forceLimit && combined > 0) {
        final scale = forceLimit / combined;
        longitudinalForce *= scale;
        lateralForce *= scale;
      }
      chassis.applyForce(
        tireForward * longitudinalForce + tireRight * lateralForce,
        atWorldPoint: hit.position,
      );
      state.spinAngle += longitudinalVelocity / wheel.radius * dt;
    }

    for (final axle in axleStates.values) {
      if (axle.length != 2 || !axle[0].grounded || !axle[1].grounded) continue;
      final antiRoll =
          (axle[0].compression - axle[1].compression) *
          config.antiRollStiffness;
      chassis.applyForce(-up * antiRoll, atWorldPoint: axle[0].contactPoint);
      chassis.applyForce(up * antiRoll, atWorldPoint: axle[1].contactPoint);
    }

    final speed = velocity.length;
    if (speed > 0) {
      chassis.applyForce(
        velocity.normalized * (-config.aerodynamicDrag * speed * speed),
      );
    }
    if (isGrounded) {
      chassis.applyForce(
        -up * (config.downforce * forwardSpeed.abs() * forwardSpeed.abs()),
      );
      if (boost && throttle > 0) {
        chassis.applyForce(
          forward * (config.boostForce * throttle.clamp(0.0, 1.0)),
        );
      }
    }
  }

  void _updateTransmission() {
    if (config.gearRatios.isEmpty) {
      gear = 1;
      engineRpm = config.idleRpm;
      return;
    }
    final powered = config.wheels.firstWhere(
      (wheel) => wheel.powered,
      orElse: () => config.wheels.first,
    );
    final ratio = config.gearRatios[gear - 1] * config.finalDrive;
    engineRpm = math.max(
      config.idleRpm,
      forwardSpeed.abs() / powered.radius * ratio * 60 / (2 * math.pi),
    );
    if (engineRpm > config.shiftUpRpm && gear < config.gearRatios.length) {
      gear++;
    } else if (engineRpm < config.shiftDownRpm && gear > 1) {
      gear--;
    }
    engineRpm = engineRpm.clamp(config.idleRpm, config.redlineRpm);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    world.removeFixedStepCallback(_fixedUpdate);
  }
}
