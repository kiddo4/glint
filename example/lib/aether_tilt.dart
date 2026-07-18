import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:glint/glint.dart';

enum TiltDirection {
  up(0, -1, Icons.keyboard_arrow_up_rounded),
  right(1, 0, Icons.keyboard_arrow_right_rounded),
  down(0, 1, Icons.keyboard_arrow_down_rounded),
  left(-1, 0, Icons.keyboard_arrow_left_rounded);

  const TiltDirection(this.dx, this.dy, this.icon);
  final int dx;
  final int dy;
  final IconData icon;
}

@immutable
class GridCell {
  const GridCell(this.x, this.y);
  final int x;
  final int y;

  GridCell step(TiltDirection direction) =>
      GridCell(x + direction.dx, y + direction.dy);

  @override
  bool operator ==(Object other) =>
      other is GridCell && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);
}

class AetherLevel {
  AetherLevel({
    required this.name,
    required this.width,
    required this.height,
    required this.start,
    required this.exit,
    required this.floor,
    required this.walls,
    required this.shards,
  });

  final String name;
  final int width;
  final int height;
  final GridCell start;
  final GridCell exit;
  final Set<GridCell> floor;
  final Set<GridCell> walls;
  final Set<GridCell> shards;

  static final first = AetherLevel(
    name: 'The First Signal',
    width: 7,
    height: 7,
    start: GridCell(1, 5),
    exit: GridCell(5, 1),
    floor: {
      GridCell(1, 1),
      GridCell(2, 1),
      GridCell(3, 1),
      GridCell(4, 1),
      GridCell(5, 1),
      GridCell(1, 2),
      GridCell(2, 2),
      GridCell(3, 2),
      GridCell(4, 2),
      GridCell(5, 2),
      GridCell(1, 3),
      GridCell(2, 3),
      GridCell(3, 3),
      GridCell(4, 3),
      GridCell(5, 3),
      GridCell(1, 4),
      GridCell(2, 4),
      GridCell(3, 4),
      GridCell(4, 4),
      GridCell(5, 4),
      GridCell(1, 5),
      GridCell(2, 5),
      GridCell(3, 5),
      GridCell(4, 5),
      GridCell(5, 5),
    },
    walls: {GridCell(3, 2), GridCell(2, 3), GridCell(4, 4)},
    shards: {GridCell(1, 1), GridCell(5, 3), GridCell(3, 5)},
  );
}

class AetherGame extends ChangeNotifier {
  AetherGame({AetherLevel? level}) : this._(level ?? AetherLevel.first);

  AetherGame._(this.level) : _core = level.start, _shards = {...level.shards};

  final AetherLevel level;
  GridCell _core;
  Set<GridCell> _shards;
  int _moves = 0;
  bool _won = false;

  GridCell get core => _core;
  Set<GridCell> get remainingShards => Set.unmodifiable(_shards);
  int get collectedShards => level.shards.length - _shards.length;
  int get moves => _moves;
  bool get won => _won;

  List<GridCell> tilt(TiltDirection direction) {
    if (_won) return const [];
    final path = <GridCell>[];
    var next = _core.step(direction);
    while (level.floor.contains(next) && !level.walls.contains(next)) {
      _core = next;
      path.add(next);
      _shards.remove(next);
      next = _core.step(direction);
    }
    if (path.isNotEmpty) {
      _moves++;
      _won = _core == level.exit && _shards.isEmpty;
      notifyListeners();
    }
    return path;
  }

  void reset() {
    _core = level.start;
    _shards = {...level.shards};
    _moves = 0;
    _won = false;
    notifyListeners();
  }
}

class AetherTiltApp extends StatelessWidget {
  const AetherTiltApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Aether Tilt',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xff03080e),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff20e6ef),
        brightness: Brightness.dark,
      ),
    ),
    home: const AetherTiltPage(),
  );
}

class AetherTiltPage extends StatefulWidget {
  const AetherTiltPage({super.key, this.game});
  final AetherGame? game;

  @override
  State<AetherTiltPage> createState() => _AetherTiltPageState();
}

class _AetherTiltPageState extends State<AetherTiltPage>
    with SingleTickerProviderStateMixin {
  late final AetherGame _game;
  late final AnimationController _motion;
  GridCell? _from;
  GridCell? _to;

  @override
  void initState() {
    super.initState();
    _game = widget.game ?? AetherGame();
    _game.addListener(_onGameChanged);
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    )..addListener(() => setState(() {}));
  }

  void _onGameChanged() {
    if (mounted) setState(() {});
  }

  void _tilt(TiltDirection direction) {
    if (_motion.isAnimating) return;
    final start = _game.core;
    final path = _game.tilt(direction);
    if (path.isEmpty) return;
    _from = start;
    _to = path.last;
    _motion.forward(from: 0).whenComplete(() {
      if (mounted && _game.won) _showVictory();
    });
  }

  void _showVictory() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xff0a141d),
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, color: Color(0xfff3bd62), size: 42),
            const SizedBox(height: 12),
            Text(
              'RELIC AWAKENED',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text('${_game.moves} gravity shifts  •  All shards recovered'),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _game.reset();
              },
              icon: const Icon(Icons.replay_rounded),
              label: const Text('Play again'),
            ),
          ],
        ),
      ),
    );
  }

  Offset get _corePosition {
    final from = _from ?? _game.core;
    final to = _to ?? _game.core;
    final t = Curves.easeInOutCubic.transform(_motion.value);
    return Offset(from.x + (to.x - from.x) * t, from.y + (to.y - from.y) * t);
  }

  @override
  void dispose() {
    _game.removeListener(_onGameChanged);
    if (widget.game == null) _game.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(.25, -.35),
                radius: 1.15,
                colors: [
                  Color(0xff123044),
                  Color(0xff071019),
                  Color(0xff020509),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(child: CustomPaint(painter: const _StarPainter())),
        Positioned(
          left: 0,
          right: 0,
          top: 118,
          bottom: 176,
          child: RepaintBoundary(
            child: Scene3D(
              scene: _AetherScene(
                level: _game.level,
                core: _corePosition,
                remainingShards: _game.remainingShards,
                portalOpen: _game.remainingShards.isEmpty,
              ),
              backgroundColor: Colors.transparent,
              enableGestures: true,
              autoRotate: false,
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
            child: Column(
              children: [
                _TopBar(game: _game),
                const Spacer(),
                _GravityPad(onTilt: _tilt),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.game});
  final AetherGame game;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          const _GlassButton(icon: Icons.pause_rounded),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'AETHER TILT',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      letterSpacing: 4,
                      fontWeight: FontWeight.w300,
                      color: const Color(0xfff3d195),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'LEVEL 01  •  ${game.level.name.toUpperCase()}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.5,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _GlassButton(icon: Icons.refresh_rounded, onPressed: game.reset),
        ],
      ),
      const SizedBox(height: 18),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _StatPill(
            icon: Icons.diamond_outlined,
            value: '${game.collectedShards}/${game.level.shards.length}',
            label: 'SHARDS',
          ),
          const SizedBox(width: 12),
          _StatPill(
            icon: Icons.rotate_90_degrees_ccw_rounded,
            value: '${game.moves}',
            label: 'MOVES',
          ),
        ],
      ),
    ],
  );
}

class _GravityPad extends StatelessWidget {
  const _GravityPad({required this.onTilt});
  final ValueChanged<TiltDirection> onTilt;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    decoration: BoxDecoration(
      color: const Color(0xcc07121b),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: const Color(0x55f3bd62)),
      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 30)],
    ),
    child: Row(
      children: [
        Text(
          'SHIFT\nGRAVITY',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            letterSpacing: 1.5,
            height: 1.5,
            color: Colors.white54,
          ),
        ),
        const Spacer(),
        for (final direction in TiltDirection.values)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: IconButton.filledTonal(
              key: ValueKey('tilt-${direction.name}'),
              onPressed: () => onTilt(direction),
              icon: Icon(direction.icon),
              color: const Color(0xff7af7ff),
            ),
          ),
      ],
    ),
  );
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.icon, this.onPressed});
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed ?? () {},
    icon: Icon(icon),
    style: IconButton.styleFrom(
      backgroundColor: Colors.white.withValues(alpha: .06),
      side: const BorderSide(color: Colors.white12),
    ),
  );
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .28),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: const Color(0x44f3bd62)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 17, color: const Color(0xff57edf5)),
        const SizedBox(width: 7),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            letterSpacing: 1.2,
            color: Colors.white54,
          ),
        ),
      ],
    ),
  );
}

class _AetherScene extends Scene {
  const _AetherScene({
    required this.level,
    required this.core,
    required this.remainingShards,
    required this.portalOpen,
  });
  final AetherLevel level;
  final Offset core;
  final Set<GridCell> remainingShards;
  final bool portalOpen;

  static final _cube = Mesh3D.cube();
  static final _sphere = Mesh3D.sphere(segments: 14, rings: 8);

  Vector3 _position(num x, num y, [double z = 0]) => Vector3(
    (x - (level.width - 1) / 2) * 1.08,
    ((level.height - 1) / 2 - y) * 1.08,
    z,
  );

  @override
  Camera3D get camera =>
      const PerspectiveCamera(position: Vector3(0, 0, 11), fieldOfView: 42);

  @override
  List<Light3D> get lights => const [
    AmbientLight(intensity: .36),
    DirectionalLight(direction: Vector3(-.7, -1, -1), intensity: .95),
  ];

  @override
  List<Node3D> get children => [
    Node3D(
      name: 'diorama-root',
      transform: const Transform3D(rotation: Vector3(-.08, .12, -.04)),
      children: [
        for (final cell in level.floor)
          Node3D(
            name: 'tile-${cell.x}-${cell.y}',
            mesh: _cube,
            transform: Transform3D(
              position: _position(cell.x, cell.y),
              scale: const Vector3(.5, .5, .14),
            ),
            material: Material3D(
              color: (cell.x + cell.y).isEven
                  ? const Color(0xff17252d)
                  : const Color(0xff101b22),
              metallic: .5,
              roughness: .55,
            ),
          ),
        for (final cell in level.walls)
          Node3D(
            name: 'wall-${cell.x}-${cell.y}',
            mesh: _cube,
            transform: Transform3D(
              position: _position(cell.x, cell.y, .42),
              scale: const Vector3(.5, .5, .55),
            ),
            material: const Material3D(
              color: Color(0xff705427),
              metallic: .85,
              roughness: .32,
            ),
          ),
        Node3D(
          name: 'portal',
          mesh: _sphere,
          transform: Transform3D(
            position: _position(level.exit.x, level.exit.y, .34),
            scale: const Vector3(.38, .38, .18),
          ),
          material: Material3D(
            color: portalOpen
                ? const Color(0xfff3bd62)
                : const Color(0xff493f35),
            metallic: .7,
            roughness: .2,
          ),
        ),
        for (final shard in remainingShards)
          Node3D(
            name: 'shard-${shard.x}-${shard.y}',
            mesh: _cube,
            transform: Transform3D(
              position: _position(shard.x, shard.y, .38),
              rotation: const Vector3(0, 0, math.pi / 4),
              scale: const Vector3(.18, .18, .32),
            ),
            material: const Material3D(
              color: Color(0xff36e9f2),
              metallic: .25,
              roughness: .12,
            ),
          ),
        Node3D(
          name: 'aether-core',
          mesh: _sphere,
          transform: Transform3D(
            position: _position(core.dx, core.dy, .56),
            scale: const Vector3(.34, .34, .34),
          ),
          material: const Material3D(
            color: Color(0xff8ffbff),
            metallic: .1,
            roughness: .08,
          ),
        ),
      ],
    ),
  ];
}

class _StarPainter extends CustomPainter {
  const _StarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(41);
    final paint = Paint();
    for (var i = 0; i < 90; i++) {
      final alpha = .12 + random.nextDouble() * .5;
      paint.color = Colors.white.withValues(alpha: alpha);
      final point = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      canvas.drawCircle(point, .35 + random.nextDouble() * 1.1, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
