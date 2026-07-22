import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glint_box3d/glint_box3d.dart';
import 'package:glint_engine/glint_engine.dart';

const _bodies = int.fromEnvironment('GLINT_STRESS_BODIES', defaultValue: 512);
const _vehicles = int.fromEnvironment('GLINT_STRESS_VEHICLES', defaultValue: 2);
const _steps = int.fromEnvironment('GLINT_STRESS_STEPS', defaultValue: 1200);
const _queries = int.fromEnvironment('GLINT_STRESS_QUERIES', defaultValue: 4);
const _minimumRealtime = String.fromEnvironment(
  'GLINT_STRESS_MINIMUM_REALTIME',
  defaultValue: '0',
);

void main() {
  setUpAll(GlintBox3dWorld.ensureInitialized);

  test(
    'mixed rigid-body, query, contact, and vehicle workload',
    () async {
      final world = GlintBox3dWorld(fixedTimeStep: 1 / 120, solverSubSteps: 4);
      try {
        final result = await GlintPhysicsStressRunner(
          world: world,
          config: GlintPhysicsStressConfig(
            bodyCount: _bodies,
            vehicleCount: _vehicles,
            steps: _steps,
            queriesPerStep: _queries,
            minimumRealTimeFactor: double.parse(_minimumRealtime),
          ),
        ).run();
        stdout.writeln(
          const JsonEncoder.withIndent('  ').convert(result.toJson()),
        );
        expect(result.passed, isTrue, reason: '$result');
      } finally {
        world.dispose();
      }
    },
    timeout: Timeout.none,
  );
}
