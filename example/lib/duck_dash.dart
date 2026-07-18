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

  static const _models = {
    'duck': Model.asset('packages/glint/assets/models/duck.glb'),
    'box': Model.asset('packages/glint/assets/models/box.glb'),
    'coin': Model.asset('packages/glint/assets/models/coin.glb'),
  };

  static const _slate = Material3D(
    color: Color(0xff2c333d),
    metallic: 0,
    roughness: .9,
  );
  static const _rail = Material3D(
    color: Color(0xffffb000),
    metallic: .6,
    roughness: .4,
  );

  GlintGameFrame _buildFrame(double dt) {
    _sim.step(dt);
    // The HUD reads the sim directly; refresh it alongside the 3D frame.
    if (mounted) setState(() {});
    final instances = <GlintGameInstance>[];

    // Scrolling floor segments and rail posts sell the speed.
    final floorScroll = _sim.distance % 12;
    for (var i = 0; i < 10; i++) {
      instances.add(
        GlintGameInstance(
          model: 'box',
          material: _slate,
          transform: Transform3D(
            position: Vector3(0, -.5, floorScroll - 12.0 * i),
            scale: const Vector3(7.4, 1, 12),
          ),
        ),
      );
    }
    final postScroll = _sim.distance % 6;
    for (var i = 0; i < 16; i++) {
      for (final side in const [-3.9, 3.9]) {
        instances.add(
          GlintGameInstance(
            model: 'box',
            material: _rail,
            transform: Transform3D(
              position: Vector3(side, .4, postScroll - 6.0 * i),
              scale: const Vector3(.3, .8, .3),
            ),
          ),
        );
      }
    }

    for (final entity in _sim.entities) {
      switch (entity.kind) {
        case DashKind.crate:
          instances.add(
            GlintGameInstance(
              model: 'box',
              transform: Transform3D(
                position: Vector3(
                  entity.x,
                  DashRules.crateSize / 2,
                  entity.z,
                ),
                scale: const Vector3(
                  DashRules.crateSize,
                  DashRules.crateSize,
                  DashRules.crateSize,
                ),
              ),
            ),
          );
        case DashKind.coin:
          if (entity.collected) continue;
          instances.add(
            GlintGameInstance(
              model: 'coin',
              transform: Transform3D(
                position: Vector3(entity.x, .65, entity.z),
                rotation: Vector3(0, _sim.runTime * 4 + entity.z * .2, 0),
              ),
            ),
          );
      }
    }

    // The duck runs in place; a bob keeps it alive between jumps.
    final bob = _sim.onGround && _sim.state == DashState.running
        ? (math.sin(_sim.runTime * 11).abs()) * .1
        : 0.0;
    instances.add(
      GlintGameInstance(
        model: 'duck',
        transform: Transform3D(
          position: Vector3(_sim.playerX, _sim.playerY + bob, 0),
          rotation: const Vector3(0, math.pi / 2, 0),
        ),
      ),
    );

    return GlintGameFrame(
      camera: GlintGameCamera(
        position: Vector3(_sim.playerX * .5, 3.6, 8.4),
        target: Vector3(_sim.playerX * .7, 1.0, -6),
        fieldOfViewDegrees: 52,
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
              environmentAsset:
                  'packages/glint/assets/environments/studio.hdr',
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
