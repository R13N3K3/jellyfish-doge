import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfish_game/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<JellyfishGame> _start(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'shock': true});
  final prefs = await SharedPreferences.getInstance();
  final game = JellyfishGame(prefs);
  await tester.binding.setSurfaceSize(const Size(450, 800));
  await tester.pumpWidget(MaterialApp(
      home: GameWidget<JellyfishGame>(
    game: game,
    overlayBuilderMap: {
      for (final id in [
        MainMenuOverlay.id,
        HudOverlay.id,
        GameOverOverlay.id,
        ShopOverlay.id,
      ])
        id: (context, g) => const SizedBox.shrink(),
    },
  )));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  game.startGame();
  await tester.pump(const Duration(milliseconds: 50));
  return game;
}

void main() {
  testWidgets('tap fires the shock only when charged and stuns nearby hazards',
      (tester) async {
    final game = await _start(tester);
    final near = AnglerFishComponent(
        fishSize: 50, speed: 100, color: Colors.red, lureColor: Colors.yellow)
      ..position = game.jellyfish!.position + Vector2(0, -100);
    final far = AnglerFishComponent(
        fishSize: 50, speed: 100, color: Colors.red, lureColor: Colors.yellow)
      ..position = Vector2(game.size.x / 2, 20);
    game.add(near);
    game.add(far);
    await tester.pump(const Duration(milliseconds: 50));

    // Not charged: tap does nothing.
    await tester.tapAt(const Offset(200, 300));
    await tester.pump(const Duration(milliseconds: 50));
    expect(near.isStunned, isFalse);

    // Charged: tap stuns the near hazard only.
    game.energy.value = game.chargeCost;
    await tester.tapAt(const Offset(200, 300));
    await tester.pump(const Duration(milliseconds: 50));
    expect(near.isStunned, isTrue);
    expect(far.isStunned, isFalse);
    expect(game.energy.value, 0);

    // Stunned hazards stay put.
    final y = near.position.y;
    await tester.pump(const Duration(milliseconds: 300));
    expect(near.position.y, y);
  });

  testWidgets('dragging does not fire the shock', (tester) async {
    final game = await _start(tester);
    game.energy.value = game.chargeCost;
    final x0 = game.jellyfish!.position.x;
    await tester.dragFrom(const Offset(200, 300), const Offset(80, 0));
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.energy.value, game.chargeCost, reason: 'drag must not shock');
    expect(game.jellyfish!.position.x, isNot(x0));
  });
}
