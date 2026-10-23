import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfish_game/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<JellyfishGame> _pump(WidgetTester tester, Size logical) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final game = JellyfishGame(prefs);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = logical;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: GameWidget<JellyfishGame>(
      game: game,
      overlayBuilderMap: {
        for (final id in [MainMenuOverlay.id, HudOverlay.id])
          id: (context, g) => const SizedBox.shrink(),
      },
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  return game;
}

void main() {
  // name, logical size in dp
  final devices = {
    'Galaxy A16 (411x891)': const Size(411, 891),
    'small phone (360x780)': const Size(360, 780),
    'tablet (800x1280)': const Size(800, 1280),
  };

  for (final e in devices.entries) {
    testWidgets('${e.key}: jellyfish sits high and everything scales',
        (tester) async {
      final game = await _pump(tester, e.value);
      final j = game.jellyfish!;
      // ignore: avoid_print
      print('${e.key}: game ${game.size.x.round()}x${game.size.y.round()} '
          'scale ${game.scale.toStringAsFixed(2)} '
          'jelly ${j.size.x.round()}x${j.size.y.round()} '
          'y=${(j.baseY / game.size.y * 100).round()}% from top');

      expect(game.size.x, e.value.width);
      expect(j.baseY / game.size.y, closeTo(0.72, 0.001));
      expect(j.size.x, closeTo(64 * game.scale, 0.01));
      expect(j.size.y, closeTo(84 * game.scale, 0.01));
    });
  }
}
