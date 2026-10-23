import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Dev flags for screenshots: --dart-define=DEMO=true skips the menu and disables
// damage, --dart-define=START_ELAPSED=60 starts at a later difficulty and
// --dart-define=SCREEN=skins (or skills) opens the shop directly.
const bool _demo = bool.fromEnvironment('DEMO');
const int _startElapsed = int.fromEnvironment('START_ELAPSED');
const String _screen = String.fromEnvironment('SCREEN');

const int maxLives = 3;
const double goldenShieldSeconds = 5;

// Electro shock skill: price of the skill and of each upgrade level.
const int kShockCost = 30;
const List<int> kUpgradeCosts = [15, 30, 60];

enum UpgradeTrack { charge, range, stun }

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Edge-to-Edge (Android 15/16) with transparent system bars.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final prefs = await SharedPreferences.getInstance();
  runApp(JellyfishApp(prefs: prefs));
}

class JellyfishApp extends StatefulWidget {
  const JellyfishApp({super.key, required this.prefs});
  final SharedPreferences prefs;

  @override
  State<JellyfishApp> createState() => _JellyfishAppState();
}

class _JellyfishAppState extends State<JellyfishApp> {
  late final JellyfishGame game = JellyfishGame(widget.prefs);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        backgroundColor: const Color(0xFF020B1F),
        body: GameWidget<JellyfishGame>(
          game: game,
          initialActiveOverlays: const [
            _demo
                ? HudOverlay.id
                : _screen == 'skins' || _screen == 'skills'
                    ? ShopOverlay.id
                    : MainMenuOverlay.id
          ],
          overlayBuilderMap: {
            MainMenuOverlay.id: (context, g) => MainMenuOverlay(game: g),
            ShopOverlay.id: (context, g) =>
                ShopOverlay(game: g, initialTab: _screen == 'skills' ? 1 : 0),
            HudOverlay.id: (context, g) => HudOverlay(game: g),
            GameOverOverlay.id: (context, g) => GameOverOverlay(game: g),
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skins
// ---------------------------------------------------------------------------

class JellyfishSkin {
  const JellyfishSkin({
    required this.name,
    required this.cost,
    required this.bellTop,
    required this.bellBottom,
    required this.glow,
    required this.tentacle,
  });

  final String name;
  final int cost; // in pearls
  final Color bellTop;
  final Color bellBottom;
  final Color glow;
  final Color tentacle;
}

const List<JellyfishSkin> kSkins = [
  JellyfishSkin(
    name: 'Violet',
    cost: 0,
    bellTop: Color(0xFFF3C8FF),
    bellBottom: Color(0xFFB45CE8),
    glow: Color(0xFFC77DFF),
    tentacle: Color(0xFFE0A8FF),
  ),
  JellyfishSkin(
    name: 'Aqua',
    cost: 10,
    bellTop: Color(0xFFC8FFF6),
    bellBottom: Color(0xFF22C6B5),
    glow: Color(0xFF3DF2DD),
    tentacle: Color(0xFF9FFFEF),
  ),
  JellyfishSkin(
    name: 'Coral',
    cost: 25,
    bellTop: Color(0xFFFFD6C9),
    bellBottom: Color(0xFFFF6B6B),
    glow: Color(0xFFFF8A80),
    tentacle: Color(0xFFFFB4A8),
  ),
  JellyfishSkin(
    name: 'Golden',
    cost: 50,
    bellTop: Color(0xFFFFF3B0),
    bellBottom: Color(0xFFFFB300),
    glow: Color(0xFFFFC940),
    tentacle: Color(0xFFFFE48A),
  ),
  JellyfishSkin(
    name: 'Toxic',
    cost: 90,
    bellTop: Color(0xFFD9FFB8),
    bellBottom: Color(0xFF3FD13F),
    glow: Color(0xFF7CFF4D),
    tentacle: Color(0xFFB6FF8C),
  ),
  JellyfishSkin(
    name: 'Ghost',
    cost: 150,
    bellTop: Color(0xFFFFFFFF),
    bellBottom: Color(0xFF9BB4D4),
    glow: Color(0xFFDDE8FF),
    tentacle: Color(0xFFF0F6FF),
  ),
];

// ---------------------------------------------------------------------------
// Game
// ---------------------------------------------------------------------------

class JellyfishGame extends FlameGame
    with HasCollisionDetection, DragCallbacks, TapCallbacks {
  JellyfishGame(this.prefs);

  final SharedPreferences prefs;
  final Random rng = Random();

  // Run state
  final ValueNotifier<int> score = ValueNotifier<int>(0);
  final ValueNotifier<int> lives = ValueNotifier<int>(maxLives);
  final ValueNotifier<int> runPearls = ValueNotifier<int>(0);
  final ValueNotifier<int> depth = ValueNotifier<int>(0);
  int _bonus = 0; // bonus points from pearls

  // Saved state
  late int bestScore = prefs.getInt('best') ?? 0;
  late final ValueNotifier<int> totalPearls =
      ValueNotifier<int>(prefs.getInt('pearls') ?? 0);
  late final ValueNotifier<Set<int>> unlockedSkins = ValueNotifier<Set<int>>({
    0,
    ...(prefs.getStringList('unlocked') ?? const <String>[])
        .map(int.tryParse)
        .whereType<int>()
        .where((i) => i >= 0 && i < kSkins.length),
  });
  late final ValueNotifier<int> selectedSkin = ValueNotifier<int>(
      unlockedSkins.value.contains(prefs.getInt('skin'))
          ? prefs.getInt('skin')!
          : 0);

  JellyfishSkin get currentSkin => kSkins[selectedSkin.value];

  // Electro shock skill: bought in the shop, charged by collecting pearls.
  late final ValueNotifier<bool> shockOwned =
      ValueNotifier<bool>(prefs.getBool('shock') ?? false);
  late final List<ValueNotifier<int>> upgradeLevels = [
    for (final t in UpgradeTrack.values)
      ValueNotifier<int>(
          min(prefs.getInt('upgrade_${t.name}') ?? 0, kUpgradeCosts.length)),
  ];
  final ValueNotifier<int> energy =
      ValueNotifier<int>(0); // pearls toward a charge

  int _level(UpgradeTrack t) => upgradeLevels[t.index].value;
  int get chargeCost => 5 - _level(UpgradeTrack.charge);
  double get shockRadius => (170 + 40.0 * _level(UpgradeTrack.range)) * scale;
  double get stunSeconds => 2.0 + 0.8 * _level(UpgradeTrack.stun);

  JellyfishComponent? jellyfish;
  double elapsed = _startElapsed.toDouble(); // survival time in seconds
  double _fishTimer = 0;
  double _mineTimer = 0;
  double _pearlTimer = 0;
  double _lastFishX = 0;
  double _hitFlash = 0;
  bool isGameOver = false;
  bool newBest = false;
  bool inMenu = !_demo;

  // All sizes, speeds and distances are designed for a screen about 400 dp wide
  // (e.g. Samsung Galaxy A16) and scaled with the actual width of the device.
  static const double _refWidth = 400;
  double get scale => min(max(size.x / _refWidth, 0.8), 1.8);

  // Difficulty increases over time.
  double get fishSpeed => min(140 + elapsed * 3, 380) * scale;
  double get spawnInterval => max(1.3 - elapsed * 0.008, 0.6);

  // Depth in meters: 2 m per second.
  double get depthM => elapsed * 2;
  String get zoneName => depthM < 50
      ? 'Sunlit Zone'
      : depthM < 150
          ? 'Twilight Zone'
          : 'Midnight Zone';

  @override
  Color backgroundColor() => const Color(0xFF020B1F);

  @override
  Future<void> onLoad() async {
    _startMusic();
    add(BubblesComponent());
    final j = JellyfishComponent();
    jellyfish = j;
    add(j);
  }

  // Looping soundtrack. A missing audio backend must never crash the game.
  Future<void> _startMusic() async {
    try {
      await FlameAudio.bgm.initialize();
      await FlameAudio.bgm.play('soundtrack.mp3', volume: 0.6);
    } catch (e) {
      debugPrint('Music unavailable: $e');
    }
  }

  @override
  void onRemove() {
    FlameAudio.bgm.dispose();
    super.onRemove();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    jellyfish?.onScreenResized(size);
  }

  @override
  void render(Canvas canvas) {
    // The deeper, the darker the water.
    final t = min(depthM / 200, 1.0);
    final paint = ui.Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, size.y),
        [
          Color.lerp(const Color(0xFF0A4F7A), const Color(0xFF04122A), t)!,
          Color.lerp(const Color(0xFF062B52), const Color(0xFF030A1A), t)!,
          Color.lerp(const Color(0xFF020B1F), const Color(0xFF010208), t)!,
        ],
        const [0.0, 0.5, 1.0],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, size.x, size.y), paint);
    super.render(canvas);
    if (_hitFlash > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.x, size.y),
        Paint()..color = Colors.red.withValues(alpha: 0.35 * _hitFlash / 0.4),
      );
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_hitFlash > 0) _hitFlash = max(0, _hitFlash - dt);
    if (isGameOver || inMenu) return;

    elapsed += dt;
    score.value = (elapsed * 10).floor() + _bonus;
    depth.value = depthM.floor();

    _fishTimer += dt;
    if (_fishTimer >= spawnInterval) {
      _fishTimer = 0;
      _spawnFish();
    }

    // Sea mines drift down from 10 s on, more often the deeper we get.
    if (elapsed >= 10) {
      _mineTimer += dt;
      if (_mineTimer >= max(3.0, 6.5 - elapsed * 0.03)) {
        _mineTimer = 0;
        _spawnMine();
      }
    }

    _pearlTimer += dt;
    if (_pearlTimer >= 2.4 + rng.nextDouble() * 1.4) {
      _pearlTimer = 0;
      _spawnPearl();
    }
  }

  // --- Spawning ------------------------------------------------------------

  // Dark deep-sea body tones and glowing lure colors.
  static const _fishColors = [
    Color(0xFF5A0F1C), // blood red
    Color(0xFF3F1A70), // deep purple
    Color(0xFF0E5240), // dark green
    Color(0xFF123A82), // dark blue
    Color(0xFF6A3208), // dark orange-brown
  ];
  static const _lureColors = [
    Color(0xFFFFE066),
    Color(0xFF66F0FF),
    Color(0xFFFF6B6B),
  ];
  static const _viperColors = [
    Color(0xFF14323F),
    Color(0xFF2A1238),
    Color(0xFF3A0F14),
  ];
  static const _spikeColors = [
    Color(0xFF8A2B0B),
    Color(0xFF3B5A0F),
    Color(0xFF5B1A66),
  ];

  void _spawnFish() {
    // New fish types show up as the run gets longer.
    final pViper = min(max((elapsed - 20) / 120, 0.0), 0.15);
    final pSpike = min(max((elapsed - 35) / 150, 0.0), 0.1);
    final r = rng.nextDouble();
    final HazardComponent Function() make = r < pViper
        ? _makeViper
        : r < pViper + pSpike
            ? _makeSpikefish
            : _makeAngler;
    final fish = _trySpawn(make) ?? _trySpawn(_makeAngler);
    if (fish == null) {
      // No fair spot right now: try again in a moment.
      _fishTimer = spawnInterval * 0.5;
    } else {
      _lastFishX = fish.position.x;
    }
  }

  void _spawnMine() {
    if (_trySpawn(_makeMine) == null) _mineTimer = 100; // retry next frame
  }

  HazardComponent _makeAngler() {
    final fishSize = (42.0 + rng.nextDouble() * 22) * scale;
    final x = fishSize / 2 + rng.nextDouble() * (size.x - fishSize);
    return AnglerFishComponent(
      fishSize: fishSize,
      speed: fishSpeed * (0.85 + rng.nextDouble() * 0.3),
      color: _fishColors[rng.nextInt(_fishColors.length)],
      lureColor: _lureColors[rng.nextInt(_lureColors.length)],
    )..position = Vector2(x, -fishSize);
  }

  // Fast fish that dive diagonally.
  HazardComponent _makeViper() {
    final fishSize = (40.0 + rng.nextDouble() * 14) * scale;
    final dir = rng.nextBool() ? 1.0 : -1.0;
    final vy = fishSpeed * 1.5;
    final vx = dir * vy * (0.3 + rng.nextDouble() * 0.25);
    final x = dir > 0
        ? size.x * (0.05 + rng.nextDouble() * 0.55)
        : size.x * (0.4 + rng.nextDouble() * 0.55);
    return ViperFishComponent(
      fishSize: fishSize,
      velocity: Vector2(vx, vy),
      color: _viperColors[rng.nextInt(_viperColors.length)],
    )..position = Vector2(x, -fishSize);
  }

  // Big slow fish that sway from side to side.
  HazardComponent _makeSpikefish() {
    final fishSize = (56.0 + rng.nextDouble() * 16) * scale;
    final amp = (35 + rng.nextDouble() * 35) * scale;
    final lo = amp + fishSize / 2;
    final hi = max(lo, size.x - amp - fishSize / 2);
    final x = lo + rng.nextDouble() * (hi - lo);
    return SpikeFishComponent(
      fishSize: fishSize,
      speed: fishSpeed * 0.65,
      baseX: x,
      amplitude: amp,
      frequency: 1.4 + rng.nextDouble() * 1.2,
      phase: rng.nextDouble() * 2 * pi,
      color: _spikeColors[rng.nextInt(_spikeColors.length)],
    )..position = Vector2(x, -fishSize);
  }

  HazardComponent _makeMine() {
    final s = 46.0 * scale;
    return MineComponent(
      mineSize: s,
      speed: min(90 + rng.nextDouble() * 30 + elapsed * 0.5, 170) * scale,
    )..position = Vector2(s / 2 + rng.nextDouble() * (size.x - s), -s);
  }

  // --- Fair spawning -------------------------------------------------------
  //
  // A new hazard is only added if the jellyfish can still get past everything
  // that is on its way: we simulate the next seconds and track the x-ranges the
  // jellyfish can reach, given a realistic maximum steering speed.

  double get _vmax => 320 * scale; // px/s the jellyfish is expected to move
  double get _jellyRadius => 38 * scale; // hitbox + float bob + safety margin
  double get _minGap =>
      30 * scale; // smallest gap that still counts as passable

  // Tries a few random placements and returns the hazard that was added.
  HazardComponent? _trySpawn(HazardComponent Function() make) {
    for (var i = 0; i < 8; i++) {
      final hazard = make();
      if (_isFair(hazard)) {
        add(hazard);
        return hazard;
      }
    }
    return null;
  }

  bool _isFair(HazardComponent candidate) {
    final j = jellyfish;
    if (j == null || size.x < 120) return true;
    final existing = children.whereType<HazardComponent>().toList();
    final lo = 32.0 * scale;
    final hi = size.x - 32 * scale;
    final tolerance = 60 * scale;
    final near =
        (max(lo, j.position.x - tolerance), min(hi, j.position.x + tolerance));

    if (_hasPath([...existing, candidate], near, j)) return true;
    // If there was no way through even before this hazard (the player is
    // already cornered), only require a way through from anywhere.
    if (!_hasPath(existing, near, j)) {
      return _hasPath([...existing, candidate], (lo, hi), j);
    }
    return false;
  }

  bool _hasPath(List<HazardComponent> hazards, (double, double) start,
      JellyfishComponent j) {
    const dt = 0.05;
    const horizon = 9.0;
    final lo = 32.0 * scale;
    final hi = size.x - 32 * scale;
    final jy = j.baseY - 14 * scale; // center of the jellyfish hitbox
    var free = <(double, double)>[start];

    for (var t = dt; t <= horizon; t += dt) {
      // x-ranges the jellyfish center cannot be in at time t.
      final blocked = <(double, double)>[];
      for (final h in hazards) {
        if (t < h.stunLeft) continue; // stunned: harmless for now
        final p = h.positionAt(t);
        final reach = h.collisionRadius + _jellyRadius;
        final dy = p.dy - jy;
        if (dy.abs() >= reach) continue;
        final half = sqrt(reach * reach - dy * dy);
        blocked.add((p.dx - half, p.dx + half));
      }
      free = _advance(free, blocked, _vmax * dt, lo, hi);
      if (free.isEmpty) return false;
    }
    return true;
  }

  // Grows the reachable ranges by [reach], clamps them to the screen and
  // removes everything that is blocked or too narrow to squeeze through.
  List<(double, double)> _advance(List<(double, double)> free,
      List<(double, double)> blocked, double reach, double lo, double hi) {
    final grown = <(double, double)>[
      for (final f in free) (max(lo, f.$1 - reach), min(hi, f.$2 + reach)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    // Merge overlapping ranges.
    final merged = <(double, double)>[];
    for (final f in grown) {
      if (merged.isNotEmpty && f.$1 <= merged.last.$2) {
        merged[merged.length - 1] = (merged.last.$1, max(merged.last.$2, f.$2));
      } else {
        merged.add(f);
      }
    }

    // Cut out the blocked ranges.
    var pieces = merged;
    for (final b in blocked) {
      final next = <(double, double)>[];
      for (final p in pieces) {
        if (b.$2 <= p.$1 || b.$1 >= p.$2) {
          next.add(p);
          continue;
        }
        if (b.$1 - p.$1 > 0) next.add((p.$1, b.$1));
        if (p.$2 - b.$2 > 0) next.add((b.$2, p.$2));
      }
      pieces = next;
    }
    return [
      for (final p in pieces)
        if (p.$2 - p.$1 >= _minGap) p,
    ];
  }

  // Pearls sometimes float right next to the latest fish: risk and reward.
  void _spawnPearl() {
    final margin = 20 * scale;
    var x = margin + rng.nextDouble() * (size.x - 2 * margin);
    if (_lastFishX > 0 && rng.nextDouble() < 0.4) {
      final off =
          (50 + rng.nextDouble() * 40) * scale * (rng.nextBool() ? 1 : -1);
      x = min(max(_lastFishX + off, margin), size.x - margin);
    }
    add(PearlComponent(
      value: rng.nextDouble() < 0.12 ? 3 : 1,
      speed: max(110 * scale, fishSpeed * 0.6),
      scale: scale,
    )..position = Vector2(x, -20 * scale));
  }

  // --- Events --------------------------------------------------------------

  // Dragging: the jellyfish follows the finger horizontally.
  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (isGameOver || inMenu) return;
    jellyfish?.moveBy(event.localDelta.x);
  }

  void hitBy(HazardComponent hazard) {
    final j = jellyfish;
    if (_demo || isGameOver || inMenu || j == null || j.isInvulnerable) return;
    if (hazard.isStunned) return;
    hazard.removeFromParent();
    _hitFlash = 0.4;
    lives.value = lives.value - 1;
    if (lives.value <= 0) {
      gameOver();
    } else {
      j.startInvulnerable(1.6);
    }
  }

  void collectPearl(PearlComponent pearl) {
    if (isGameOver || inMenu) return;
    pearl.removeFromParent();
    runPearls.value += pearl.value;
    totalPearls.value += pearl.value;
    _bonus += 25 * pearl.value;
    prefs.setInt('pearls', totalPearls.value);
    if (shockOwned.value) {
      energy.value = min(chargeCost, energy.value + pearl.value);
    }

    final j = jellyfish;
    if (j == null) return;
    if (pearl.value > 1) {
      // Golden pearl: shield + pearl magnet for a few seconds.
      j.startShield(goldenShieldSeconds);
      add(FloatingText('+${pearl.value} 🦪 Golden Shield!', j.position.clone(),
          color: const Color(0xFFFFD54F), fontSize: 22));
    } else {
      add(FloatingText('+1', j.position.clone()));
    }
  }

  void gameOver() {
    if (isGameOver) return;
    isGameOver = true;
    newBest = score.value > bestScore;
    if (newBest) {
      bestScore = score.value;
      prefs.setInt('best', bestScore);
    }
    pauseEngine();
    overlays.add(GameOverOverlay.id);
  }

  // --- Electro shock -------------------------------------------------------

  // A short tap anywhere fires the shock once the energy bar is full.
  @override
  void onTapUp(TapUpEvent event) {
    if (isGameOver || inMenu || !shockOwned.value) return;
    if (energy.value >= chargeCost) fireShock();
  }

  void fireShock() {
    final j = jellyfish;
    if (j == null) return;
    energy.value = 0;
    final center = j.position.clone();
    final r = shockRadius;
    for (final h in children.whereType<HazardComponent>()) {
      if ((h.position - center).length <= r + h.collisionRadius) {
        h.stun(stunSeconds);
      }
    }
    add(ShockwaveComponent(center: center, radius: r));
  }

  void buyShock() {
    if (shockOwned.value || totalPearls.value < kShockCost) return;
    totalPearls.value -= kShockCost;
    shockOwned.value = true;
    prefs.setInt('pearls', totalPearls.value);
    prefs.setBool('shock', true);
  }

  // Price of the next level, or null when the track is maxed out.
  int? upgradeCost(UpgradeTrack t) {
    final level = upgradeLevels[t.index].value;
    return level >= kUpgradeCosts.length ? null : kUpgradeCosts[level];
  }

  void buyUpgrade(UpgradeTrack t) {
    final cost = upgradeCost(t);
    if (!shockOwned.value || cost == null || totalPearls.value < cost) return;
    totalPearls.value -= cost;
    upgradeLevels[t.index].value += 1;
    prefs.setInt('pearls', totalPearls.value);
    prefs.setInt('upgrade_${t.name}', upgradeLevels[t.index].value);
  }

  // --- Skins ---------------------------------------------------------------

  void selectSkin(int i) {
    if (!unlockedSkins.value.contains(i)) return;
    selectedSkin.value = i;
    prefs.setInt('skin', i);
  }

  void buySkin(int i) {
    final skin = kSkins[i];
    if (unlockedSkins.value.contains(i) || totalPearls.value < skin.cost) {
      return;
    }
    totalPearls.value -= skin.cost;
    unlockedSkins.value = {...unlockedSkins.value, i};
    prefs.setInt('pearls', totalPearls.value);
    prefs.setStringList(
        'unlocked', unlockedSkins.value.map((e) => e.toString()).toList());
    selectSkin(i);
  }

  // --- Flow ----------------------------------------------------------------

  void _resetWorld() {
    children
        .where((c) => c is HazardComponent || c is PearlComponent)
        .toList()
        .forEach((c) => c.removeFromParent());
    elapsed = 0;
    _fishTimer = 0;
    _mineTimer = 0;
    _pearlTimer = 0;
    _lastFishX = 0;
    _hitFlash = 0;
    _bonus = 0;
    score.value = 0;
    depth.value = 0;
    lives.value = maxLives;
    runPearls.value = 0;
    energy.value = 0;
    isGameOver = false;
    newBest = false;
    jellyfish?.reset(size);
  }

  void startGame() {
    _resetWorld();
    inMenu = false;
    overlays.remove(MainMenuOverlay.id);
    overlays.add(HudOverlay.id);
  }

  void restart() {
    _resetWorld();
    overlays.remove(GameOverOverlay.id);
    resumeEngine();
  }

  void toMenu() {
    _resetWorld();
    inMenu = true;
    overlays.remove(GameOverOverlay.id);
    overlays.remove(HudOverlay.id);
    overlays.add(MainMenuOverlay.id);
    resumeEngine();
  }

  void openShop() {
    overlays.remove(MainMenuOverlay.id);
    overlays.add(ShopOverlay.id);
  }

  void closeShop() {
    overlays.remove(ShopOverlay.id);
    overlays.add(MainMenuOverlay.id);
  }
}

// ---------------------------------------------------------------------------
// Jellyfish
// ---------------------------------------------------------------------------

class JellyfishComponent extends PositionComponent
    with CollisionCallbacks, HasGameReference<JellyfishGame> {
  JellyfishComponent() : super(size: _baseSize.clone(), anchor: Anchor.center);

  static final Vector2 _baseSize = Vector2(64, 84);

  // Resting height: high enough to be comfortable for the thumb.
  static const double _restHeight = 0.72;

  CircleHitbox? _hitbox;
  double _scale = 1;

  double _time = 0;
  double _baseY = 0;
  double _invulnerable = 0;

  double _shield = 0;

  bool get isInvulnerable => _invulnerable > 0 || _shield > 0;
  bool get hasShield => _shield > 0;
  double get baseY => _baseY;

  final Paint _bellPaint = Paint();
  final Paint _glowPaint = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
  final Paint _tentaclePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 3;

  @override
  Future<void> onLoad() async {
    // Hitbox covers only the bell and upper tentacles: slightly smaller = fairer.
    final hitbox = CircleHitbox(radius: 24);
    _hitbox = hitbox;
    add(hitbox);
    _applyScale(game.scale);
    reset(game.size);
  }

  // Sizes the jellyfish and its hitbox for the current screen width.
  void _applyScale(double scale) {
    _scale = scale;
    size = _baseSize * scale;
    _hitbox
      ?..radius = 24 * scale
      ..position = Vector2(size.x / 2 - 24 * scale, 4 * scale);
  }

  void reset(Vector2 screen) {
    _applyScale(game.scale);
    _baseY = screen.y * _restHeight;
    _invulnerable = 0;
    _shield = 0;
    position = Vector2(screen.x / 2, _baseY);
  }

  void startInvulnerable(double seconds) => _invulnerable = seconds;

  void startShield(double seconds) => _shield = seconds;

  void onScreenResized(Vector2 screen) {
    _applyScale(game.scale);
    _baseY = screen.y * _restHeight;
    position.x =
        position.x.clamp(size.x / 2, max(size.x / 2, screen.x - size.x / 2));
  }

  void moveBy(double dx) {
    final w = game.size.x;
    position.x = (position.x + dx).clamp(size.x / 2, w - size.x / 2);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    if (_invulnerable > 0) _invulnerable = max(0, _invulnerable - dt);
    if (_shield > 0) _shield = max(0, _shield - dt);
    // Gentle floating.
    position.y = _baseY + sin(_time * 2) * 8 * _scale;
  }

  @override
  void onCollisionStart(
      Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is HazardComponent) {
      game.hitBy(other);
    } else if (other is PearlComponent) {
      game.collectPearl(other);
    }
  }

  @override
  void render(Canvas canvas) {
    // Blink after taking damage.
    if (_invulnerable > 0 && (_invulnerable * 10).floor().isOdd) return;

    final skin = game.currentSkin;

    // Golden shield aura; it flickers during the last second.
    if (_shield > 0 && (_shield > 1 || (_shield * 8).floor().isEven)) {
      final center = Offset(size.x / 2, size.y * 0.45);
      final auraR = size.y * (0.68 + 0.04 * sin(_time * 8));
      canvas.drawCircle(
        center,
        auraR,
        Paint()
          ..color = const Color(0xFFFFC940).withValues(alpha: 0.28)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.drawCircle(
        center,
        auraR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xFFFFE082).withValues(alpha: 0.85),
      );
    }
    final pulse = 0.5 + 0.5 * sin(_time * 4); // 0..1
    final bellW = size.x * (0.92 + 0.12 * pulse);
    final bellH = size.y * 0.5 * (1.06 - 0.12 * pulse);
    final cx = size.x / 2;
    final bell = Rect.fromLTWH(cx - bellW / 2, 0, bellW, bellH * 2);

    // Tentacles
    _tentaclePaint.color = skin.tentacle.withValues(alpha: 0.8);
    for (var i = 0; i < 5; i++) {
      final x = cx - bellW * 0.36 + i * (bellW * 0.72 / 4);
      final path = Path()..moveTo(x, bellH);
      const segs = 6;
      final len = size.y - bellH;
      for (var s = 1; s <= segs; s++) {
        final t = s / segs;
        final wave = sin(_time * 3 + i * 0.9 + t * 4) * 5 * t;
        path.lineTo(x + wave, bellH + len * t);
      }
      canvas.drawPath(path, _tentaclePaint);
    }

    // Glow + bell (upper half ellipse)
    _glowPaint.color = skin.glow.withValues(alpha: 0.4);
    canvas.drawOval(bell.inflate(4), _glowPaint);

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.x, bellH));
    _bellPaint.shader = ui.Gradient.linear(
      Offset(cx, 0),
      Offset(cx, bellH),
      [skin.bellTop, skin.bellBottom],
    );
    canvas.drawOval(bell, _bellPaint);
    canvas.restore();

    // Highlight
    canvas.drawCircle(Offset(cx - bellW * 0.18, bellH * 0.4), 5,
        Paint()..color = Colors.white.withValues(alpha: 0.7));
  }
}

// ---------------------------------------------------------------------------
// Hazards: fish and mines
// ---------------------------------------------------------------------------

abstract class HazardComponent extends PositionComponent
    with HasGameReference<JellyfishGame> {
  HazardComponent({required Vector2 size, Vector2? velocity})
      : velocity = velocity ?? Vector2.zero(),
        super(size: size, anchor: Anchor.center);

  Vector2 velocity;
  double time = 0;

  final Paint fill = Paint();
  final Paint stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Paint glow = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

  void move(double dt) => position.addScaled(velocity, dt);

  // Radius that covers the hitbox, and where the center will be in [t] seconds.
  double get collisionRadius;

  // Where the center will be in [t] seconds, taking a running stun into account.
  Offset positionAt(double t) => predict(max(0, t - stunLeft));

  Offset predict(double t) =>
      Offset(position.x + velocity.x * t, position.y + velocity.y * t);

  // Electro shock: a stunned hazard freezes and is harmless.
  double stunLeft = 0;
  bool get isStunned => stunLeft > 0;
  void stun(double seconds) => stunLeft = max(stunLeft, seconds);

  CircleHitbox circleHitbox(double radius, Offset center) => CircleHitbox(
        radius: radius,
        position: Vector2(center.dx - radius, center.dy - radius),
        collisionType: CollisionType.passive,
      );

  @override
  void update(double dt) {
    super.update(dt);
    if (stunLeft > 0) {
      stunLeft = max(0, stunLeft - dt);
      return;
    }
    time += dt;
    move(dt);
    final s = game.size;
    if (position.y - size.y > s.y ||
        position.x < -size.x * 2 ||
        position.x > s.x + size.x * 2) {
      removeFromParent();
    }
  }

  @override
  void renderTree(Canvas canvas) {
    super.renderTree(canvas);
    if (stunLeft > 0) _renderStun(canvas);
  }

  // Crackling electric ring around a stunned hazard (parent coordinates).
  void _renderStun(Canvas canvas) {
    final c = Offset(position.x, position.y);
    final r = collisionRadius + 8;
    final fade = min(1.0, stunLeft / 0.5);
    stroke
      ..color = const Color(0xFF7DF9FF).withValues(alpha: 0.9 * fade)
      ..strokeWidth = 2.5;
    canvas.drawCircle(c, r, stroke);
    final rng = game.rng;
    for (var i = 0; i < 3; i++) {
      final a = rng.nextDouble() * 2 * pi;
      final path = Path()
        ..moveTo(c.dx + cos(a) * r * 0.4, c.dy + sin(a) * r * 0.4);
      for (var k = 1; k <= 3; k++) {
        final d = r * (0.4 + 0.35 * k);
        final j = (rng.nextDouble() - 0.5) * 0.5;
        path.lineTo(c.dx + cos(a + j) * d, c.dy + sin(a + j) * d);
      }
      canvas.drawPath(path, stroke..strokeWidth = 1.8);
    }
  }
}

// Angler fish: swims straight down, dark body, glowing lure, fangs.
class AnglerFishComponent extends HazardComponent {
  AnglerFishComponent({
    required double fishSize,
    required double speed,
    required this.color,
    required this.lureColor,
  }) : super(
          size: Vector2(fishSize * 0.8, fishSize),
          velocity: Vector2(0, speed),
        );

  final Color color;
  final Color lureColor;

  @override
  double get collisionRadius => size.x * 0.38;

  @override
  Future<void> onLoad() async {
    // Hitbox covers the body only, not the lure.
    add(circleHitbox(size.x * 0.38, Offset(size.x / 2, size.y * 0.5)));
  }

  @override
  void render(Canvas canvas) {
    // The fish swims downward: head and mouth at the bottom.
    final w = size.x;
    final h = size.y;
    final cx = w / 2;
    final rim = Color.lerp(color, Colors.white, 0.45)!;

    // Lure: stalk rising from the middle of the forehead, hooking forward over
    // the head, with a glowing bulb at the tip.
    final lureEnd = Offset(cx + w * 0.1 + sin(time * 3) * w * 0.04, h * 0.0);
    final stalk = Path()
      ..moveTo(cx, h * 0.3)
      ..quadraticBezierTo(cx - w * 0.12, -h * 0.28, lureEnd.dx, lureEnd.dy);
    stroke
      ..color = rim
      ..strokeWidth = max(1.5, w * 0.03);
    canvas.drawPath(stalk, stroke);
    final pulse = 0.7 + 0.3 * sin(time * 5);
    glow.color = lureColor.withValues(alpha: 0.55 * pulse);
    canvas.drawCircle(lureEnd, w * 0.2, glow);
    fill.color = lureColor;
    canvas.drawCircle(lureEnd, w * 0.07, fill);

    fill.color = color;

    // Spiky side fins
    for (final side in [-1.0, 1.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(cx + side * w * 0.4, h * 0.3)
          ..lineTo(cx + side * w * 0.62, h * 0.4)
          ..lineTo(cx + side * w * 0.42, h * 0.48)
          ..lineTo(cx + side * w * 0.6, h * 0.58)
          ..lineTo(cx + side * w * 0.38, h * 0.62)
          ..close(),
        fill,
      );
    }

    // Body with a faint rim light so it stays visible against the dark water.
    final body = Rect.fromLTWH(w * 0.04, h * 0.18, w * 0.92, h * 0.74);
    canvas.drawOval(body, fill);
    stroke
      ..color = rim.withValues(alpha: 0.7)
      ..strokeWidth = 1.5;
    canvas.drawOval(body, stroke);

    // Glowing angry eyes with slit pupils and slanted brows.
    final eyeY = h * 0.5;
    for (final side in [-1.0, 1.0]) {
      final ex = cx + side * w * 0.22;
      glow.color = const Color(0xAAFF2A2A);
      canvas.drawCircle(Offset(ex, eyeY), w * 0.12, glow);
      fill.color = const Color(0xFFFFD21F);
      canvas.drawCircle(Offset(ex, eyeY), w * 0.095, fill);
      fill.color = Colors.black;
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(ex, eyeY), width: w * 0.03, height: w * 0.14),
        fill,
      );
      stroke
        ..color = Colors.black
        ..strokeWidth = max(2, w * 0.045);
      // Angry brow: the inner end is low, the outer end is high.
      canvas.drawLine(
        Offset(ex - side * w * 0.13, eyeY - w * 0.04),
        Offset(ex + side * w * 0.13, eyeY - w * 0.18),
        stroke,
      );
    }

    // Wide mouth with interlocking fangs.
    final mouth = Rect.fromLTWH(w * 0.12, h * 0.64, w * 0.76, h * 0.26);
    fill.color = const Color(0xFF12020A);
    canvas.drawOval(mouth, fill);
    fill.color = const Color(0xFFF2F2E6);
    const fangs = 5;
    for (var i = 0; i < fangs; i++) {
      final t = (i + 0.5) / fangs;
      final fx = mouth.left + mouth.width * (0.08 + 0.84 * t);
      final edge =
          sqrt(max(0, 1 - pow(2 * (fx - mouth.center.dx) / mouth.width, 2))) *
              mouth.height /
              2;
      final fl = h * (i.isEven ? 0.12 : 0.085);
      // Upper fangs point down into the mouth, lower fangs point up.
      canvas.drawPath(
        Path()
          ..moveTo(fx - w * 0.04, mouth.center.dy - edge)
          ..lineTo(fx + w * 0.04, mouth.center.dy - edge)
          ..lineTo(fx, mouth.center.dy - edge + fl)
          ..close(),
        fill,
      );
      canvas.drawPath(
        Path()
          ..moveTo(fx - w * 0.04, mouth.center.dy + edge)
          ..lineTo(fx + w * 0.04, mouth.center.dy + edge)
          ..lineTo(fx, mouth.center.dy + edge - fl)
          ..close(),
        fill,
      );
    }
  }
}

// Viperfish: slim and fast, dives diagonally and points its head along the way.
class ViperFishComponent extends HazardComponent {
  ViperFishComponent({
    required double fishSize,
    required Vector2 velocity,
    required this.color,
  }) : super(
          size: Vector2(fishSize * 0.6, fishSize * 1.15),
          velocity: velocity,
        ) {
    // The fish art faces down (+y); rotate it toward the swim direction.
    angle = atan2(-velocity.x, velocity.y);
  }

  final Color color;

  @override
  double get collisionRadius => size.x * 0.42 + size.y * 0.08;

  @override
  Future<void> onLoad() async {
    add(circleHitbox(size.x * 0.42, Offset(size.x / 2, size.y * 0.58)));
  }

  @override
  void render(Canvas canvas) {
    final w = size.x;
    final h = size.y;
    final cx = w / 2;
    final rim = Color.lerp(color, Colors.white, 0.5)!;

    // Speed streaks behind the fish.
    stroke
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 2;
    for (final dx in [-0.25, 0.0, 0.25]) {
      canvas.drawLine(
        Offset(cx + dx * w, h * 0.05),
        Offset(cx + dx * w, -h * (0.35 + 0.1 * sin(time * 20 + dx * 9))),
        stroke,
      );
    }

    // Dorsal spikes at the tail end.
    fill.color = color;
    for (final side in [-1.0, 1.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(cx + side * w * 0.2, h * 0.25)
          ..lineTo(cx + side * w * 0.75, h * 0.02)
          ..lineTo(cx + side * w * 0.3, h * 0.42)
          ..close(),
        fill,
      );
    }

    // Slim pointed body.
    final body = Path()
      ..moveTo(cx, 0)
      ..cubicTo(w * 1.1, h * 0.25, w * 1.0, h * 0.7, cx, h)
      ..cubicTo(0, h * 0.7, -w * 0.1, h * 0.25, cx, 0)
      ..close();
    canvas.drawPath(body, fill);
    stroke
      ..color = rim.withValues(alpha: 0.75)
      ..strokeWidth = 1.5;
    canvas.drawPath(body, stroke);

    // Red glowing eyes with angry brows.
    final eyeY = h * 0.5;
    for (final side in [-1.0, 1.0]) {
      final ex = cx + side * w * 0.2;
      glow.color = const Color(0xCCFF1A1A);
      canvas.drawCircle(Offset(ex, eyeY), w * 0.16, glow);
      fill.color = const Color(0xFFFF3B2F);
      canvas.drawCircle(Offset(ex, eyeY), w * 0.1, fill);
      fill.color = Colors.black;
      canvas.drawCircle(Offset(ex, eyeY), w * 0.04, fill);
      stroke
        ..color = Colors.black
        ..strokeWidth = max(2, w * 0.07);
      canvas.drawLine(
        Offset(ex - side * w * 0.12, eyeY - w * 0.06),
        Offset(ex + side * w * 0.14, eyeY - w * 0.2),
        stroke,
      );
    }

    // Gaping jaw with long fangs at the front.
    fill.color = const Color(0xFF12020A);
    canvas.drawPath(
      Path()
        ..moveTo(cx - w * 0.3, h * 0.74)
        ..lineTo(cx + w * 0.3, h * 0.74)
        ..lineTo(cx, h * 0.99)
        ..close(),
      fill,
    );
    fill.color = const Color(0xFFF2F2E6);
    for (final side in [-1.0, 1.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(cx + side * w * 0.3, h * 0.74)
          ..lineTo(cx + side * w * 0.14, h * 0.74)
          ..lineTo(cx + side * w * 0.2, h * 0.93)
          ..close(),
        fill,
      );
    }
  }
}

// Spikefish: big and slow, sways from side to side, covered in spikes.
class SpikeFishComponent extends HazardComponent {
  SpikeFishComponent({
    required double fishSize,
    required double speed,
    required this.baseX,
    required this.amplitude,
    required this.frequency,
    required this.phase,
    required this.color,
  }) : super(
          size: Vector2.all(fishSize),
          velocity: Vector2(0, speed),
        );

  final double baseX;
  final double amplitude;
  final double frequency;
  final double phase;
  final Color color;

  @override
  double get collisionRadius => size.x * 0.42;

  @override
  Future<void> onLoad() async {
    add(circleHitbox(size.x * 0.42, Offset(size.x / 2, size.y / 2)));
  }

  @override
  Offset predict(double t) => Offset(
        baseX + sin((time + t) * frequency + phase) * amplitude,
        position.y + velocity.y * t,
      );

  @override
  void move(double dt) {
    position.y += velocity.y * dt;
    position.x = baseX + sin(time * frequency + phase) * amplitude;
  }

  @override
  void render(Canvas canvas) {
    final s = size.x;
    final c = Offset(s / 2, s / 2);
    final rim = Color.lerp(color, Colors.white, 0.45)!;

    // Spikes slowly rotating around the body.
    const spikes = 14;
    fill.color = Color.lerp(color, Colors.white, 0.25)!;
    for (var i = 0; i < spikes; i++) {
      final a = time * 0.6 + i * 2 * pi / spikes;
      final base1 = c + Offset(cos(a - 0.12), sin(a - 0.12)) * (s * 0.3);
      final base2 = c + Offset(cos(a + 0.12), sin(a + 0.12)) * (s * 0.3);
      final tip = c + Offset(cos(a), sin(a)) * (s * 0.5);
      canvas.drawPath(
        Path()
          ..moveTo(base1.dx, base1.dy)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(base2.dx, base2.dy)
          ..close(),
        fill,
      );
    }

    // Round body
    fill.color = color;
    canvas.drawCircle(c, s * 0.34, fill);
    stroke
      ..color = rim.withValues(alpha: 0.75)
      ..strokeWidth = 1.5;
    canvas.drawCircle(c, s * 0.34, stroke);

    // Angry eyes
    for (final side in [-1.0, 1.0]) {
      final ex = c.dx + side * s * 0.14;
      final ey = c.dy - s * 0.05;
      glow.color = const Color(0xAAFF2A2A);
      canvas.drawCircle(Offset(ex, ey), s * 0.1, glow);
      fill.color = const Color(0xFFFFD21F);
      canvas.drawCircle(Offset(ex, ey), s * 0.075, fill);
      fill.color = Colors.black;
      canvas.drawCircle(Offset(ex, ey), s * 0.03, fill);
      stroke
        ..color = Colors.black
        ..strokeWidth = max(2, s * 0.04);
      canvas.drawLine(
        Offset(ex - side * s * 0.09, ey - s * 0.03),
        Offset(ex + side * s * 0.1, ey - s * 0.13),
        stroke,
      );
    }

    // Grumpy mouth with two fangs
    stroke
      ..color = Colors.black
      ..strokeWidth = max(2, s * 0.04);
    canvas.drawArc(
      Rect.fromCenter(
          center: Offset(c.dx, c.dy + s * 0.2),
          width: s * 0.3,
          height: s * 0.16),
      pi,
      pi,
      false,
      stroke,
    );
    fill.color = const Color(0xFFF2F2E6);
    for (final side in [-1.0, 1.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(c.dx + side * s * 0.1, c.dy + s * 0.2)
          ..lineTo(c.dx + side * s * 0.04, c.dy + s * 0.2)
          ..lineTo(c.dx + side * s * 0.07, c.dy + s * 0.29)
          ..close(),
        fill,
      );
    }
  }
}

// Sea mine: drifts down slowly, spiky, blinking red light.
class MineComponent extends HazardComponent {
  MineComponent({required double mineSize, required double speed})
      : super(size: Vector2.all(mineSize), velocity: Vector2(0, speed));

  @override
  double get collisionRadius => size.x * 0.42;

  @override
  Future<void> onLoad() async {
    add(circleHitbox(size.x * 0.42, Offset(size.x / 2, size.y / 2)));
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isStunned) angle += dt * 0.6;
  }

  @override
  void render(Canvas canvas) {
    final s = size.x;
    final c = Offset(s / 2, s / 2);

    stroke
      ..color = const Color(0xFF6B7683)
      ..strokeWidth = max(3, s * 0.1);
    const spikes = 8;
    for (var i = 0; i < spikes; i++) {
      final a = i * 2 * pi / spikes;
      canvas.drawLine(
        c + Offset(cos(a), sin(a)) * (s * 0.3),
        c + Offset(cos(a), sin(a)) * (s * 0.5),
        stroke,
      );
    }

    fill.shader = ui.Gradient.radial(
      c - Offset(s * 0.1, s * 0.1),
      s * 0.4,
      const [Color(0xFF5A6572), Color(0xFF1B2128)],
    );
    canvas.drawCircle(c, s * 0.33, fill);
    fill.shader = null;
    stroke
      ..color = const Color(0xFF8A96A3)
      ..strokeWidth = 1.5;
    canvas.drawCircle(c, s * 0.33, stroke);

    // Blinking warning light
    final blink = 0.5 + 0.5 * sin(time * 6);
    glow.color = const Color(0xFFFF2A2A).withValues(alpha: 0.8 * blink);
    canvas.drawCircle(c, s * 0.2, glow);
    fill.color =
        Color.lerp(const Color(0xFF661111), const Color(0xFFFF4040), blink)!;
    canvas.drawCircle(c, s * 0.08, fill);
  }
}

// ---------------------------------------------------------------------------
// Electro shock wave
// ---------------------------------------------------------------------------

class ShockwaveComponent extends PositionComponent {
  ShockwaveComponent({required Vector2 center, required this.radius})
      : super(position: center) {
    priority = 90;
  }

  final double radius;
  double _age = 0;
  static const _life = 0.5;
  final Paint _paint = Paint()..style = PaintingStyle.stroke;

  @override
  void update(double dt) {
    super.update(dt);
    _age += dt;
    if (_age >= _life) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final t = _age / _life;
    final r = radius * (1 - pow(1 - t, 2));
    final fade = 1 - t;

    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()..color = const Color(0xFF7DF9FF).withValues(alpha: 0.14 * fade),
    );
    _paint
      ..color = const Color(0xFFB9FBFF).withValues(alpha: 0.95 * fade)
      ..strokeWidth = 2 + 6 * fade;
    canvas.drawCircle(Offset.zero, r, _paint);

    // Jagged bolts radiating outwards.
    _paint
      ..color = const Color(0xFFFFFFFF).withValues(alpha: fade)
      ..strokeWidth = 2;
    final rnd = Random(7);
    for (var i = 0; i < 9; i++) {
      final a = i * 2 * pi / 9 + rnd.nextDouble() * 0.3;
      final path = Path()..moveTo(cos(a) * r * 0.3, sin(a) * r * 0.3);
      for (var k = 1; k <= 4; k++) {
        final d = r * (0.3 + 0.7 * k / 4);
        final j = (rnd.nextDouble() - 0.5) * 0.25;
        path.lineTo(cos(a + j) * d, sin(a + j) * d);
      }
      canvas.drawPath(path, _paint);
    }
  }
}

// ---------------------------------------------------------------------------
// Pearls
// ---------------------------------------------------------------------------

class PearlComponent extends PositionComponent
    with HasGameReference<JellyfishGame> {
  PearlComponent(
      {required this.value, required this.speed, required double scale})
      : super(
            size: Vector2.all((value > 1 ? 26 : 22) * scale),
            anchor: Anchor.center);

  final int value; // 1 = white pearl, 3 = golden pearl
  final double speed;
  double _time = 0;

  final Paint _paint = Paint();
  final Paint _glow = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);

  @override
  Future<void> onLoad() async {
    final r = size.x * 0.55;
    add(CircleHitbox(
      radius: r,
      position: Vector2(size.x / 2 - r, size.y / 2 - r),
      collisionType: CollisionType.passive,
    ));
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    // The golden shield pulls pearls toward the jellyfish.
    final j = game.jellyfish;
    if (j != null && j.hasShield && !game.isGameOver) {
      final to = j.position - position;
      if (to.length < 260 * game.scale) {
        position.addScaled(to.normalized(), 520 * game.scale * dt);
        return;
      }
    }
    position.y += speed * dt;
    if (position.y - size.y > game.size.y) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final golden = value > 1;
    final c = Offset(size.x / 2, size.y / 2);
    final r = size.x / 2 * (0.95 + 0.05 * sin(_time * 6));

    _glow.color = (golden ? const Color(0xFFFFC940) : const Color(0xFFBFE9FF))
        .withValues(alpha: 0.7);
    canvas.drawCircle(c, r * 1.5, _glow);

    // Rotating sparkles mark the golden pearl as special.
    if (golden) {
      final sparkle = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2
        ..color = const Color(0xFFFFF3B0).withValues(alpha: 0.9);
      for (var i = 0; i < 4; i++) {
        final a = _time * 2 + i * pi / 2;
        canvas.drawLine(
          c + Offset(cos(a), sin(a)) * (r * 1.25),
          c + Offset(cos(a), sin(a)) * (r * 1.9),
          sparkle,
        );
      }
    }

    _paint.shader = ui.Gradient.radial(
      c - Offset(r * 0.3, r * 0.3),
      r * 1.3,
      golden
          ? const [Color(0xFFFFFBE0), Color(0xFFFFC107), Color(0xFFB77900)]
          : const [Color(0xFFFFFFFF), Color(0xFFDDEBFF), Color(0xFF9FB6D6)],
      const [0.0, 0.6, 1.0],
    );
    canvas.drawCircle(c, r, _paint);
    _paint.shader = null;
    canvas.drawCircle(c - Offset(r * 0.35, r * 0.35), r * 0.2,
        Paint()..color = Colors.white.withValues(alpha: 0.9));
  }
}

// ---------------------------------------------------------------------------
// Floating feedback text
// ---------------------------------------------------------------------------

class FloatingText extends TextComponent {
  FloatingText(
    String text,
    Vector2 position, {
    this.color = Colors.white,
    this.fontSize = 18,
  }) : super(text: text, position: position, anchor: Anchor.center) {
    priority = 100;
  }

  final Color color;
  final double fontSize;
  double _age = 0;
  static const _life = 1.2;

  @override
  void update(double dt) {
    super.update(dt);
    _age += dt;
    if (_age >= _life) {
      removeFromParent();
      return;
    }
    position.y -= 50 * dt;
    textRenderer = TextPaint(
      style: TextStyle(
        color: color.withValues(alpha: 1 - _age / _life),
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        shadows: const [Shadow(blurRadius: 4)],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Decoration: rising bubbles
// ---------------------------------------------------------------------------

class BubblesComponent extends Component with HasGameReference<JellyfishGame> {
  final List<_Bubble> _bubbles = [];
  final Paint _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;

  @override
  void onMount() {
    super.onMount();
    for (var i = 0; i < 18; i++) {
      _bubbles.add(_randomBubble(initial: true));
    }
  }

  _Bubble _randomBubble({bool initial = false}) {
    final r = game.rng;
    final s = game.size;
    return _Bubble(
      x: r.nextDouble() * max(s.x, 1),
      y: initial ? r.nextDouble() * max(s.y, 1) : s.y + 10,
      radius: 2 + r.nextDouble() * 6,
      speed: 15 + r.nextDouble() * 35,
    );
  }

  @override
  void update(double dt) {
    for (var i = 0; i < _bubbles.length; i++) {
      final b = _bubbles[i];
      b.y -= b.speed * dt;
      if (b.y < -10) _bubbles[i] = _randomBubble();
    }
  }

  @override
  void render(Canvas canvas) {
    _paint.color = Colors.white.withValues(alpha: 0.25);
    for (final b in _bubbles) {
      canvas.drawCircle(Offset(b.x, b.y), b.radius, _paint);
    }
  }
}

class _Bubble {
  _Bubble(
      {required this.x,
      required this.y,
      required this.radius,
      required this.speed});
  double x, y, radius, speed;
}

// ---------------------------------------------------------------------------
// Overlays (Flutter widgets)
// ---------------------------------------------------------------------------

class _Pill extends StatelessWidget {
  const _Pill({required this.child, this.vertical = 6});
  final Widget child;
  final double vertical;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: vertical),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(24),
      ),
      child: child,
    );
  }
}

class _EnergyBar extends StatelessWidget {
  const _EnergyBar({required this.game});
  final JellyfishGame game;

  @override
  Widget build(BuildContext context) {
    final cost = game.chargeCost;
    final energy = min(game.energy.value, cost);
    final full = energy >= cost;
    return _Pill(
      vertical: 4,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            full ? '⚡ Tap to shock!' : '⚡',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: full ? Colors.amberAccent : Colors.white,
            ),
          ),
          if (!full) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 90,
              height: 8,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: energy / cost,
                  color: Colors.cyanAccent,
                  backgroundColor: Colors.white24,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class HudOverlay extends StatelessWidget {
  const HudOverlay({super.key, required this.game});
  static const String id = 'hud';
  final JellyfishGame game;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: IgnorePointer(
            child: ListenableBuilder(
              listenable: Listenable.merge([
                game.score,
                game.lives,
                game.runPearls,
                game.depth,
                game.energy,
                game.shockOwned,
                ...game.upgradeLevels,
              ]),
              builder: (context, _) {
                final lives = game.lives.value.clamp(0, maxLives);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Pill(
                      vertical: 8,
                      child: Text(
                        '🪼 ${game.score.value}',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _Pill(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < maxLives; i++)
                            Icon(
                              i < lives
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              size: 22,
                              color:
                                  i < lives ? Colors.redAccent : Colors.white38,
                            ),
                          const SizedBox(width: 14),
                          Text('🦪 ${game.runPearls.value}',
                              style: const TextStyle(
                                  fontSize: 18, color: Colors.white)),
                          const SizedBox(width: 14),
                          Text('⬇ ${game.depth.value} m',
                              style: const TextStyle(
                                  fontSize: 18, color: Colors.white)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(game.zoneName,
                        style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                            shadows: [Shadow(blurRadius: 4)])),
                    if (game.shockOwned.value) ...[
                      const SizedBox(height: 6),
                      _EnergyBar(game: game),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class MainMenuOverlay extends StatelessWidget {
  const MainMenuOverlay({super.key, required this.game});
  static const String id = 'mainMenu';
  final JellyfishGame game;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.35),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🪼', style: TextStyle(fontSize: 72)),
              const SizedBox(height: 8),
              const Text('Jellyfish Dodge',
                  style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 8),
              const Text(
                  'Drag the jellyfish, dodge the fish\nand collect pearls!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.white70)),
              const SizedBox(height: 16),
              if (game.bestScore > 0)
                Text('Best: ${game.bestScore}',
                    style: const TextStyle(fontSize: 20, color: Colors.white)),
              ValueListenableBuilder<int>(
                valueListenable: game.totalPearls,
                builder: (context, pearls, _) => Text('🦪 $pearls',
                    style: const TextStyle(fontSize: 20, color: Colors.white)),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: game.startGame,
                icon: const Icon(Icons.play_arrow),
                label: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text('Play', style: TextStyle(fontSize: 20)),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: game.openShop,
                icon: const Icon(Icons.storefront_outlined),
                label: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text('Shop', style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ShopOverlay extends StatefulWidget {
  const ShopOverlay({super.key, required this.game, this.initialTab = 0});
  static const String id = 'shop';
  final JellyfishGame game;
  final int initialTab; // 0 = skins, 1 = skills

  @override
  State<ShopOverlay> createState() => _ShopOverlayState();
}

class _ShopOverlayState extends State<ShopOverlay> {
  late int _tab = widget.initialTab;
  JellyfishGame get game => widget.game;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black.withValues(alpha: 0.85),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            const Text('Shop',
                style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            ValueListenableBuilder<int>(
              valueListenable: game.totalPearls,
              builder: (context, pearls, _) => Text('🦪 $pearls',
                  style: const TextStyle(fontSize: 20, color: Colors.white)),
            ),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                    value: 0,
                    label: Text('Skins'),
                    icon: Icon(Icons.palette_outlined)),
                ButtonSegment(
                    value: 1, label: Text('Skills'), icon: Icon(Icons.bolt)),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    game.totalPearls,
                    game.unlockedSkins,
                    game.selectedSkin,
                    game.shockOwned,
                    ...game.upgradeLevels,
                  ]),
                  builder: (context, _) => _tab == 0 ? _skins() : _skills(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: FilledButton.icon(
                onPressed: game.closeShop,
                icon: const Icon(Icons.arrow_back),
                label: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text('Back', style: TextStyle(fontSize: 18)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Skins tab -------------------------------------------------------------

  Widget _skins() => Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 12,
        children: [for (var i = 0; i < kSkins.length; i++) _skinCard(i)],
      );

  Widget _skinCard(int i) {
    final skin = kSkins[i];
    final unlocked = game.unlockedSkins.value.contains(i);
    final selected = game.selectedSkin.value == i;
    final canBuy = game.totalPearls.value >= skin.cost;

    final Widget action;
    if (selected) {
      action = const Text('Selected',
          style: TextStyle(color: Colors.lightGreenAccent, fontSize: 15));
    } else if (unlocked) {
      action = FilledButton(
          onPressed: () => game.selectSkin(i), child: const Text('Select'));
    } else {
      action = FilledButton(
        onPressed: canBuy ? () => game.buySkin(i) : null,
        child: Text('🦪 ${skin.cost}'),
      );
    }

    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? Colors.lightGreenAccent : Colors.white24,
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Opacity(
            opacity: unlocked ? 1 : 0.45,
            child: SizedBox(
              width: 64,
              height: 80,
              child: CustomPaint(painter: _SkinPreviewPainter(skin)),
            ),
          ),
          const SizedBox(height: 8),
          Text(skin.name,
              style: const TextStyle(fontSize: 16, color: Colors.white)),
          const SizedBox(height: 8),
          SizedBox(height: 40, child: Center(child: action)),
        ],
      ),
    );
  }

  // --- Skills tab ------------------------------------------------------------

  Widget _skills() {
    final owned = game.shockOwned.value;
    final canBuy = game.totalPearls.value >= kShockCost;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          children: [
            _panel(
              highlight: owned,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('⚡', style: TextStyle(fontSize: 40)),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Electro Shock',
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
                            SizedBox(height: 4),
                            Text(
                              'Collect pearls to charge the bar, then tap the '
                              'screen to stun every enemy around you.',
                              style: TextStyle(
                                  fontSize: 14, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: owned
                        ? const Text('Unlocked',
                            style: TextStyle(
                                color: Colors.lightGreenAccent, fontSize: 15))
                        : FilledButton(
                            onPressed: canBuy ? game.buyShock : null,
                            child: Text('Unlock  🦪 $kShockCost'),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (final t in UpgradeTrack.values) ...[
              _upgradeRow(t, owned),
              const SizedBox(height: 10),
            ],
            if (!owned)
              const Text('Unlock the shock to buy upgrades.',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _panel({required Widget child, bool highlight = false}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: highlight ? Colors.lightGreenAccent : Colors.white24,
            width: highlight ? 2 : 1,
          ),
        ),
        child: child,
      );

  Widget _upgradeRow(UpgradeTrack t, bool owned) {
    final level = game.upgradeLevels[t.index].value;
    final cost = game.upgradeCost(t);
    final canBuy = owned && cost != null && game.totalPearls.value >= cost;

    // (title, current value -> next value)
    String change(String Function(int) f) =>
        cost == null ? f(level) : '${f(level)}  →  ${f(level + 1)}';
    final (String title, String detail) = switch (t) {
      UpgradeTrack.charge => (
          'Faster charge',
          change((l) => '${5 - l} pearls'),
        ),
      UpgradeTrack.range => (
          'Wider shockwave',
          change((l) => '${170 + 40 * l} px'),
        ),
      UpgradeTrack.stun => (
          'Longer stun',
          change((l) => '${(2 + 0.8 * l).toStringAsFixed(1)} s'),
        ),
    };

    return Opacity(
      opacity: owned ? 1 : 0.45,
      child: _panel(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style:
                          const TextStyle(fontSize: 16, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(detail,
                      style:
                          const TextStyle(fontSize: 13, color: Colors.white70)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (var i = 0; i < kUpgradeCosts.length; i++)
                        Container(
                          width: 14,
                          height: 6,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color:
                                i < level ? Colors.cyanAccent : Colors.white24,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (cost == null)
              const Text('MAX',
                  style: TextStyle(
                      color: Colors.cyanAccent, fontWeight: FontWeight.bold))
            else
              FilledButton(
                onPressed: canBuy ? () => game.buyUpgrade(t) : null,
                child: Text('🦪 $cost'),
              ),
          ],
        ),
      ),
    );
  }
}

class _SkinPreviewPainter extends CustomPainter {
  _SkinPreviewPainter(this.skin);
  final JellyfishSkin skin;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final bellH = size.height * 0.5;
    final bell =
        Rect.fromLTWH(cx - size.width * 0.45, 0, size.width * 0.9, bellH * 2);

    final tentacle = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3
      ..color = skin.tentacle.withValues(alpha: 0.85);
    for (var i = 0; i < 5; i++) {
      final x = cx - size.width * 0.33 + i * (size.width * 0.66 / 4);
      final wave = (i.isEven ? 1 : -1) * 4.0;
      canvas.drawPath(
        Path()
          ..moveTo(x, bellH)
          ..quadraticBezierTo(
              x + wave, (bellH + size.height) / 2, x, size.height),
        tentacle,
      );
    }

    canvas.drawOval(
      bell.inflate(3),
      Paint()
        ..color = skin.glow.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, bellH));
    canvas.drawOval(
      bell,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(cx, 0),
          Offset(cx, bellH),
          [skin.bellTop, skin.bellBottom],
        ),
    );
    canvas.restore();
    canvas.drawCircle(Offset(cx - size.width * 0.17, bellH * 0.4), 4,
        Paint()..color = Colors.white.withValues(alpha: 0.7));
  }

  @override
  bool shouldRepaint(_SkinPreviewPainter old) => old.skin != skin;
}

class GameOverOverlay extends StatelessWidget {
  const GameOverOverlay({super.key, required this.game});
  static const String id = 'gameOver';
  final JellyfishGame game;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.65),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Game Over',
                  style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 16),
              Text('Score: ${game.score.value}',
                  style: const TextStyle(fontSize: 28, color: Colors.white)),
              const SizedBox(height: 4),
              if (game.newBest)
                const Text('New best!',
                    style: TextStyle(fontSize: 20, color: Colors.amberAccent))
              else
                Text('Best: ${game.bestScore}',
                    style:
                        const TextStyle(fontSize: 18, color: Colors.white70)),
              const SizedBox(height: 4),
              Text('Depth: ${game.depth.value} m   🦪 +${game.runPearls.value}',
                  style: const TextStyle(fontSize: 18, color: Colors.white70)),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: game.restart,
                icon: const Icon(Icons.replay),
                label: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text('Play Again', style: TextStyle(fontSize: 20)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: game.toMenu,
                child: const Text('Main Menu', style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
