import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:glint_showcase/duck_dash_sim.dart';

void main() {
  DuckDashSim startedSim() {
    final sim = DuckDashSim(random: math.Random(7))..start();
    return sim;
  }

  test('starting resets the run and spawning fills the corridor', () {
    final sim = startedSim();
    expect(sim.state, DashState.running);
    sim.step(1 / 60);
    expect(sim.entities, isNotEmpty);
    expect(sim.distance, greaterThan(0));
    // Everything spawns ahead of the player.
    for (final entity in sim.entities) {
      expect(entity.z, lessThan(0));
    }
  });

  test('steering clamps to the three lanes', () {
    final sim = startedSim();
    sim.steer(-1);
    sim.steer(-1);
    expect(sim.playerLane, -1);
    sim.steer(1);
    sim.steer(1);
    sim.steer(1);
    expect(sim.playerLane, 1);
  });

  test('speed ramps toward the cap and score follows distance and coins', () {
    final sim = startedSim();
    for (var i = 0; i < 600; i++) {
      sim.entities.clear(); // No obstacles: pure survival.
      sim.step(1 / 60);
    }
    expect(sim.speed, greaterThan(DashRules.startSpeed));
    expect(sim.speed, lessThanOrEqualTo(DashRules.maxSpeed));
    expect(sim.score, sim.distance.floor());
  });

  test('an unavoided crate in the player lane ends the run', () {
    final sim = startedSim();
    sim.entities
      ..clear()
      ..add(DashEntity(DashKind.crate, 0, -3));
    for (var i = 0; i < 60 && sim.state == DashState.running; i++) {
      sim.step(1 / 60);
    }
    expect(sim.state, DashState.gameOver);
    expect(sim.best, sim.score);
  });

  test('a crate in another lane is harmless', () {
    final sim = startedSim();
    sim.steer(-1);
    for (var i = 0; i < 30; i++) {
      sim.step(1 / 60); // Let the duck settle into the left lane.
      sim.entities.clear();
    }
    sim.entities.add(DashEntity(DashKind.crate, 1, -3));
    for (var i = 0; i < 60; i++) {
      sim.step(1 / 60);
    }
    expect(sim.state, DashState.running);
  });

  test('jumping clears a crate', () {
    final sim = startedSim();
    sim.entities
      ..clear()
      ..add(DashEntity(DashKind.crate, 0, -4));
    sim.jump();
    for (var i = 0; i < 40; i++) {
      sim.step(1 / 60);
      sim.entities.removeWhere((e) => false); // Keep only our crate scenario.
      sim.entities.removeWhere(
        (e) => e.z < -4.5, // Drop newly spawned patterns, keep the test crate.
      );
    }
    expect(sim.state, DashState.running);
  });

  test('running through a coin collects it exactly once', () {
    final sim = startedSim();
    sim.entities
      ..clear()
      ..add(DashEntity(DashKind.coin, 0, -3));
    for (var i = 0; i < 60; i++) {
      sim.step(1 / 60);
      sim.entities.removeWhere((e) => e.z < -4.5);
    }
    expect(sim.coins, 1);
    expect(sim.score, sim.distance.floor() + DashRules.coinValue);
  });
}
