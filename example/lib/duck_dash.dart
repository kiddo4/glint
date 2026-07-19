import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:glint/glint.dart';

import 'duck_dash_sim.dart';

/// Duck Dash: a three-lane endless runner rendered by [GlintGameView] with
/// the HUD, menus, and input as plain Flutter widgets on top.
class DuckDashApp extends StatelessWidget {
  const DuckDashApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffffb000),
        brightness: Brightness.dark,
      ),
    ),
    home: const DuckDashScreen(),
  );
}

class DuckDashScreen extends StatefulWidget {
  const DuckDashScreen({super.key});

  @override
  State<DuckDashScreen> createState() => _DuckDashScreenState();
}

class _DuckDashScreenState extends State<DuckDashScreen> {
  final _sim = DuckDashSim();
  var _squash = 0.0;
  var _wasAirborne = false;

  static const _models = {
    'duck': Model.asset('packages/glint/assets/models/duck.glb'),
    'box': Model.asset('packages/glint/assets/models/box.glb'),
    'disc': Model.asset('packages/glint/assets/models/disc.glb'),
    'barrier': Model.asset('packages/glint/assets/models/traffic_barrier.glb'),
    'goldcoin': Model.asset(
      'packages/glint/assets/models/cc0_gold_coin_blank.glb',
    ),
    'scenery': Model.asset(
      'packages/glint/assets/models/low_poly_rocks_and_trees.glb',
    ),
    'cargo': Model.asset('packages/glint/assets/models/box_animated.glb'),
  };

  // The dawn palette: haze shared by fog and sky so the horizon is seamless.
  static const _haze = Color(0xffdfb28a);
  static const _asphalt = Material3D(
    color: Color(0xff37322d),
    metallic: 0,
    roughness: .95,
  );
  static const _grass = Material3D(
    color: Color(0xff5d7c4d),
    metallic: 0,
    roughness: 1,
  );
  static const _marking = Material3D(
    color: Color(0xffe9e3d4),
    metallic: 0,
    roughness: .8,
  );

  Material3D _shadow(double strength) => Material3D(
    color: const Color(0xff000000),
    opacity: strength.clamp(0, .42),
    metallic: 0,
    roughness: 1,
  );

  GlintGameFrame _buildFrame(double dt) {
    final wasAirborne = !_sim.onGround;
    _sim.step(dt);
    if (_wasAirborne && _sim.onGround) _squash = .18;
    _wasAirborne = wasAirborne;
    _squash = math.max(0, _squash - dt);
    // The HUD reads the sim directly; refresh it alongside the 3D frame.
    if (mounted) setState(() {});

    final instances = <GlintGameInstance>[];

    // Track, shoulders, and dashed lane markings scroll under the duck.
    final floorScroll = _sim.distance % 12;
    for (var i = 0; i < 10; i++) {
      final z = floorScroll - 12.0 * i;
      instances.add(
        GlintGameInstance(
          model: 'box',
          material: _asphalt,
          transform: Transform3D(
            position: Vector3(0, -.5, z),
            scale: const Vector3(7.4, 1, 12),
          ),
        ),
      );
      for (final side in const [-11.2, 11.2]) {
        instances.add(
          GlintGameInstance(
            model: 'box',
            material: _grass,
            transform: Transform3D(
              position: Vector3(side, -.55, z),
              scale: const Vector3(15, 1, 12),
            ),
          ),
        );
      }
    }
    final markScroll = _sim.distance % 4;
    for (var i = 0; i < 25; i++) {
      for (final x in const [-1.1, 1.1]) {
        instances.add(
          GlintGameInstance(
            model: 'box',
            material: _marking,
            transform: Transform3D(
              position: Vector3(x, .015, markScroll - 4.0 * i),
              scale: const Vector3(.14, .03, 2),
            ),
          ),
        );
      }
    }
    // Real imported scenery: the rocks-and-trees diorama repeats down both
    // sides, mirrored per slot so the repetition doesn't read as a pattern.
    final sceneryScroll = _sim.distance % 16;
    final firstSlot = (_sim.distance / 16).floor();
    for (var i = 0; i < 7; i++) {
      final slot = firstSlot + i;
      final hash = (slot * 2654435761) & 0x7fffffff;
      final side = (slot.isEven ? -1 : 1).toDouble();
      final mirror = hash & 1 == 0;
      final z = sceneryScroll - 16.0 * i;
      instances.add(
        GlintGameInstance(
          model: 'scenery',
          transform: Transform3D(
            position: Vector3(side * (14.5 + (hash >> 4 & 0xf) / 4), .2, z),
            rotation: Vector3(0, mirror ? math.pi : 0, 0),
            scale: const Vector3(.12, .12, .12),
          ),
        ),
      );
    }

    // Animated cargo crates (Khronos BoxAnimated) flip their lids trackside,
    // driven by the game clock through the engine's animation sampler.
    final cargoScroll = _sim.distance % 48;
    for (var i = 0; i < 3; i++) {
      instances.add(
        GlintGameInstance(
          model: 'cargo',
          animationTime: _sim.runTime,
          transform: Transform3D(
            position: Vector3(5.3, 0, cargoScroll - 48.0 * i - 10),
            rotation: const Vector3(0, -math.pi / 2, 0),
            scale: const Vector3(.8, .8, .8),
          ),
        ),
      );
    }

    for (final entity in _sim.entities) {
      switch (entity.kind) {
        case DashKind.crate:
          instances
            ..add(
              GlintGameInstance(
                model: 'disc',
                material: _shadow(.34),
                translucent: true,
                transform: Transform3D(
                  position: Vector3(entity.x, .02, entity.z),
                  scale: const Vector3(2.1, 1, 2.1),
                ),
              ),
            )
            ..add(
              GlintGameInstance(
                // Real traffic barrier, authored at 9cm: scale 22x lands it
                // at ~1.9 wide and ~1.1 tall, matching the jumpable hitbox.
                model: 'barrier',
                transform: Transform3D(
                  position: Vector3(entity.x, 0, entity.z),
                  scale: const Vector3(22, 22, 22),
                ),
              ),
            );
        case DashKind.coin:
          if (entity.collected) continue;
          final bob = math.sin(_sim.runTime * 5 + entity.z * .7) * .1;
          instances.add(
            GlintGameInstance(
              // Real minted coin, authored at 4cm: scale 24x gives a chunky
              // collectible with its gold texture doing the shine.
              model: 'goldcoin',
              transform: Transform3D(
                position: Vector3(entity.x, .7 + bob, entity.z),
                rotation: Vector3(0, _sim.runTime * 4 + entity.z * .2, 0),
                scale: const Vector3(24, 24, 24),
              ),
            ),
          );
      }
    }

    // The duck: bob while grounded, lean into lane changes, squash on
    // landing, and a blob shadow that thins as it jumps.
    final running = _sim.state == DashState.running;
    final bob = _sim.onGround && running
        ? (math.sin(_sim.runTime * 11).abs()) * .1
        : 0.0;
    final lean =
        (_sim.playerX - _sim.playerLane * DashRules.laneWidth) * .12;
    final squash = _squash / .18;
    instances
      ..add(
        GlintGameInstance(
          model: 'disc',
          material: _shadow(.4 - _sim.playerY * .12),
          translucent: true,
          transform: Transform3D(
            position: Vector3(_sim.playerX, .02, 0),
            scale: Vector3(
              2.4 - _sim.playerY * .35,
              1,
              2.4 - _sim.playerY * .35,
            ),
          ),
        ),
      )
      ..add(
        GlintGameInstance(
          model: 'duck',
          transform: Transform3D(
            position: Vector3(_sim.playerX, _sim.playerY + bob, 0),
            rotation: Vector3(0, math.pi / 2, lean),
            scale: Vector3(
              1 + squash * .18,
              1 - squash * .3,
              1 + squash * .18,
            ),
          ),
        ),
      );

    // Speed reads through the lens: the FOV widens as the run ramps up.
    final rush =
        (_sim.speed - DashRules.startSpeed) /
        (DashRules.maxSpeed - DashRules.startSpeed);
    return GlintGameFrame(
      camera: GlintGameCamera(
        position: Vector3(_sim.playerX * .5, 3.6, 8.4),
        target: Vector3(_sim.playerX * .7, 1.0, -6),
        fieldOfViewDegrees: 50 + rush * 12,
        far: 140,
      ),
      instances: instances,
    );
  }

  void _handleTap() {
    if (_sim.state != DashState.running) {
      setState(_sim.start);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity.abs() > 80) _sim.steer(velocity > 0 ? 1 : -1);
        },
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) < -120) _sim.jump();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            GlintGameView(
              models: _models,
              onFrame: _buildFrame,
              showStats: true,
              environmentAsset: 'packages/glint/assets/environments/dawn.hdr',
              backgroundColor: _haze,
              fogColor: _haze,
              fogDistance: 95,
              lightDirection: const Vector3(-.35, -1, -.7),
              lightIntensity: 2.4,
              fallback: const Center(
                child: Text(
                  'Flutter GPU renderer unavailable.\n'
                  'Launch with --enable-impeller --enable-flutter-gpu.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _Hud(sim: _sim),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Score readouts plus the ready / game-over overlays. Rebuilt every frame
/// by the game view's setState, so it can read the sim directly.
class _Hud extends StatelessWidget {
  const _Hud({required this.sim});

  final DuckDashSim sim;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.displaySmall?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: 2,
      shadows: const [Shadow(blurRadius: 16, color: Colors.black54)],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                '${sim.score}',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  shadows: const [
                    Shadow(blurRadius: 12, color: Colors.black87),
                  ],
                ),
              ),
            ),
            _Pill(text: '● ${sim.coins}', color: const Color(0xffffb000)),
          ],
        ),
        const Spacer(),
        if (sim.state == DashState.ready) ...[
          Text('DUCK\nDASH', style: titleStyle),
          const SizedBox(height: 12),
          const _Pill(text: 'TAP TO RUN'),
          const SizedBox(height: 8),
          const _Pill(text: 'SWIPE ◀ ▶ STEER   •   SWIPE ▲ JUMP'),
          const SizedBox(height: 24),
        ],
        if (sim.state == DashState.gameOver) ...[
          Text('DUCK\nDOWN', style: titleStyle),
          const SizedBox(height: 12),
          _Pill(text: 'SCORE ${sim.score}   •   BEST ${sim.best}'),
          const SizedBox(height: 8),
          const _Pill(text: 'TAP TO RUN AGAIN'),
          const SizedBox(height: 24),
        ],
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .4),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: Colors.white12),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          letterSpacing: 1.1,
          color: color ?? Colors.white,
        ),
      ),
    ),
  );
}
