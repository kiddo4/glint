import 'dart:math' as math;

/// Duck Dash gameplay constants, shared by the sim and the renderer so
/// hitboxes always match what's drawn.
abstract final class DashRules {
  static const laneWidth = 2.2;
  static const startSpeed = 14.0;
  static const maxSpeed = 34.0;
  static const speedRamp = .35;
  static const jumpVelocity = 9.5;
  static const gravity = 26.0;
  static const crateSize = 1.15;
  static const coinValue = 25;
  static const spawnHorizon = -90.0;
  static const despawnZ = 6.0;
}

enum DashState { ready, running, gameOver }

enum DashKind { crate, coin }

/// One obstacle or pickup scrolling toward the player.
class DashEntity {
  DashEntity(this.kind, this.lane, this.z);

  final DashKind kind;

  /// -1, 0, or 1.
  final int lane;
  double z;
  bool collected = false;

  double get x => lane * DashRules.laneWidth;
}

/// The whole game, deterministic and renderer-free: lanes, jumping,
/// spawning, collisions, and scoring advance only through [step].
class DuckDashSim {
  DuckDashSim({math.Random? random}) : _random = random ?? math.Random();

  final math.Random _random;

  var state = DashState.ready;
  var distance = 0.0;
  var speed = DashRules.startSpeed;
  var coins = 0;
  var best = 0;
  var runTime = 0.0;

  /// Player pose. x eases toward the target lane; y > 0 while airborne.
  var playerLane = 0;
  var playerX = 0.0;
  var playerY = 0.0;
  var _verticalVelocity = 0.0;

  final entities = <DashEntity>[];
  var _nextSpawnZ = -30.0;

  int get score => distance.floor() + coins * DashRules.coinValue;

  bool get onGround => playerY <= 0;

  void start() {
    state = DashState.running;
    distance = 0;
    speed = DashRules.startSpeed;
    coins = 0;
    runTime = 0;
    playerLane = 0;
    playerX = 0;
    playerY = 0;
    _verticalVelocity = 0;
    entities.clear();
    _nextSpawnZ = -30;
  }

  void steer(int direction) {
    if (state != DashState.running) return;
    playerLane = (playerLane + direction.sign).clamp(-1, 1);
  }

  void jump() {
    if (state != DashState.running || !onGround) return;
    _verticalVelocity = DashRules.jumpVelocity;
    playerY = .001;
  }

  void step(double dt) {
    if (state != DashState.running || dt <= 0) return;
    runTime += dt;
    speed = math.min(DashRules.maxSpeed, speed + DashRules.speedRamp * dt);
    distance += speed * dt;

    // Ease into the target lane fast enough to dodge at top speed.
    final targetX = playerLane * DashRules.laneWidth;
    final ease = 1 - math.exp(-14 * dt);
    playerX += (targetX - playerX) * ease;

    if (!onGround || _verticalVelocity > 0) {
      playerY += _verticalVelocity * dt;
      _verticalVelocity -= DashRules.gravity * dt;
      if (playerY <= 0) {
        playerY = 0;
        _verticalVelocity = 0;
      }
    }

    for (final entity in entities) {
      entity.z += speed * dt;
    }
    entities.removeWhere((entity) => entity.z > DashRules.despawnZ);
    while (_nextSpawnZ > DashRules.spawnHorizon) {
      _spawnPattern(_nextSpawnZ);
      _nextSpawnZ -= 10 + _random.nextDouble() * 6;
    }
    _nextSpawnZ += speed * dt;

    _collide();
  }

  void _spawnPattern(double z) {
    switch (_random.nextInt(4)) {
      case 0:
        // Single crate.
        entities.add(DashEntity(DashKind.crate, _random.nextInt(3) - 1, z));
      case 1:
        // Two crates leaving exactly one safe lane.
        final open = _random.nextInt(3) - 1;
        for (var lane = -1; lane <= 1; lane++) {
          if (lane != open) entities.add(DashEntity(DashKind.crate, lane, z));
        }
      case 2:
        // A run of coins down one lane.
        final lane = _random.nextInt(3) - 1;
        for (var i = 0; i < 5; i++) {
          entities.add(DashEntity(DashKind.coin, lane, z - i * 2.4));
        }
      case 3:
        // A crate with reward coins in a neighbouring lane.
        final crateLane = _random.nextInt(3) - 1;
        final coinLane = crateLane == 1 ? 0 : crateLane + 1;
        entities.add(DashEntity(DashKind.crate, crateLane, z));
        for (var i = 0; i < 3; i++) {
          entities.add(DashEntity(DashKind.coin, coinLane, z - i * 2.4));
        }
    }
  }

  void _collide() {
    for (final entity in entities) {
      final dx = (entity.x - playerX).abs();
      final dz = entity.z.abs();
      switch (entity.kind) {
        case DashKind.crate:
          // Jumping clears a crate; the top sits at crateSize world units.
          if (dx < 1.2 && dz < 1.15 && playerY < DashRules.crateSize - .15) {
            state = DashState.gameOver;
            if (score > best) best = score;
            return;
          }
        case DashKind.coin:
          if (!entity.collected && dx < 1.0 && dz < 1.0 && playerY < 1.5) {
            entity.collected = true;
            coins++;
          }
      }
    }
  }
}
