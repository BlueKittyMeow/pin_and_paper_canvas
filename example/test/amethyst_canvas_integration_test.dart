// Integration coverage: the amethyst chunk desk object rendered by the real
// example app (CanvasExampleApp -- the full SpatialCanvas + MockSpatialData
// Source wiring, not a bespoke test harness), alongside the 24 mock cards,
// and draggable through the same gesture pipeline the cards use.

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pin_and_paper_card_renderer/card_renderer.dart';

import 'package:pin_and_paper_canvas_example/crystal/amethyst_chunk.dart';
import 'package:pin_and_paper_canvas_example/main.dart';
import 'package:pin_and_paper_canvas_example/mock_spatial_data_source.dart';

/// Drags from [start] to [start] + [totalScreenDelta] over many small
/// incremental pointer moves, with a pump between each, then releases.
///
/// Copied (not imported -- the parent `pin_and_paper_canvas` package's own
/// test/spatial_canvas_test.dart isn't reachable from this example package)
/// from that suite's `_dragCardInSteps`: the per-entity `GestureDetector`
/// and the outer canvas's viewport `GestureDetector` compete in the same
/// gesture arena, and some initial pointer movement is consumed by
/// arbitration before `onPanUpdate` starts firing -- spreading the total
/// delta over many small steps keeps that one-time loss a small, bounded
/// fraction, so assertions below use a generous tolerance rather than an
/// exact match.
Future<void> _dragInSteps(
  WidgetTester tester, {
  required Offset start,
  required Offset totalScreenDelta,
  int steps = 40,
}) async {
  final gesture = await tester.startGesture(start);
  final stepDelta = Offset(totalScreenDelta.dx / steps, totalScreenDelta.dy / steps);
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(stepDelta);
    await tester.pump(const Duration(milliseconds: 8));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

/// Pumps the real example app with a viewport tall enough to actually show
/// the amethyst chunk on screen. The chunk sits below the mock card grid
/// (`mock_spatial_data_source.dart`'s `_generateAmethystEntity`, roughly
/// canvas y 520-640) -- comfortably on-screen in the real app's window, but
/// `flutter_test`'s default 800x600 surface minus the Scaffold's AppBar
/// leaves too little body height to reach it, so widget-space taps/drags
/// miss it entirely. A larger explicit viewport (same technique the parent
/// package's spatial_canvas_test.dart uses) fixes that without having to
/// shrink the chunk's real desk position to fit a test default.
Future<void> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const CanvasExampleApp());
  await tester.pump();
}

void main() {
  testWidgets('the amethyst chunk renders on the canvas alongside all 24 mock cards', (tester) async {
    await _pumpApp(tester);

    // All 24 cards are present (none flipped, so all show
    // kTaskCardSurfaceKey), plus exactly one amethyst chunk -- a
    // non-card entity that doesn't carry that key at all.
    expect(find.byKey(kTaskCardSurfaceKey), findsNWidgets(kMockCardCount));
    expect(find.byType(AmethystChunk), findsOneWidget);
  });

  testWidgets('dragging the amethyst chunk moves it (onEntityMoved fires for its id)', (tester) async {
    await _pumpApp(tester);

    final chunkFinder = find.byType(AmethystChunk);
    expect(chunkFinder, findsOneWidget);
    final before = tester.getTopLeft(chunkFinder);

    const totalScreenDelta = Offset(120, 60);
    await _dragInSteps(tester, start: tester.getCenter(chunkFinder), totalScreenDelta: totalScreenDelta);

    // MockSpatialDataSource.onEntityMoved looks the dragged entity up by id
    // and mutates *that* entity's position before calling notifyListeners --
    // the chunk's own rendered position moving (while it remains the one and
    // only AmethystChunk on screen) is exactly the observable effect of that
    // id-keyed callback having fired for 'amethyst-1', without needing a
    // spy hook into the data source. Generous tolerance for the same gesture
    // -arena arbitration loss _dragInSteps's doc comment describes.
    final after = tester.getTopLeft(find.byType(AmethystChunk));
    final moved = after - before;
    expect(moved.dx, closeTo(totalScreenDelta.dx, 40));
    expect(moved.dy, closeTo(totalScreenDelta.dy, 40));

    // The 24 cards are undisturbed -- this drag only ever touched the chunk.
    expect(find.byKey(kTaskCardSurfaceKey), findsNWidgets(kMockCardCount));
  });

  testWidgets('the amethyst chunk is selectable via the same tap gesture cards use', (tester) async {
    await _pumpApp(tester);

    final chunkFinder = find.byType(AmethystChunk);
    await tester.tap(chunkFinder);
    // Wait out Flutter's double-tap timeout the same way the parent card
    // tests do (a real Timer, not an animation frame -- pumpAndSettle alone
    // can return before it fires).
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    final chunk = tester.widget<AmethystChunk>(chunkFinder);
    expect(chunk.isSelected, isTrue);
  });

  testWidgets(
    'a two-finger trackpad gesture over the chunk pans the viewport, never moves it in canvas space',
    (tester) async {
      // Mirrors the parent suite's equivalent card coverage: the per-entity
      // GestureDetector (which AmethystChunk sits behind, same as
      // FlippableTaskCard) must exclude PointerDeviceKind.trackpad so a
      // two-finger trackpad pan over the stone pans the desk instead of
      // dragging the stone. A viewport pan *does* move the chunk's on-screen
      // position (panning moves everything on screen together) -- what must
      // stay fixed is the chunk's position *relative to* an untouched card:
      // if the chunk itself had been dragged in canvas space instead of the
      // whole viewport panning, that relative offset would shift.
      await _pumpApp(tester);

      final chunkFinder = find.byType(AmethystChunk);
      final cardFinder = find.byKey(kTaskCardSurfaceKey).first;
      final chunkBefore = tester.getTopLeft(chunkFinder);
      final cardBefore = tester.getTopLeft(cardFinder);
      final chunkCenter = tester.getCenter(chunkFinder);

      final trackpadGesture = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      await trackpadGesture.panZoomStart(chunkCenter);
      await tester.pump();
      for (final pan in const [Offset(-20, -10), Offset(-40, -20)]) {
        await trackpadGesture.panZoomUpdate(chunkCenter, pan: pan);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await trackpadGesture.panZoomEnd();
      await tester.pumpAndSettle();

      final chunkAfter = tester.getTopLeft(find.byType(AmethystChunk));
      final cardAfter = tester.getTopLeft(cardFinder);

      // The viewport visibly panned...
      expect(chunkAfter, isNot(chunkBefore));
      // ...but the chunk was never dragged itself: its offset relative to
      // the (also never-dragged) card is unchanged.
      final relativeBefore = chunkBefore - cardBefore;
      final relativeAfter = chunkAfter - cardAfter;
      expect(relativeAfter.dx, closeTo(relativeBefore.dx, 0.5));
      expect(relativeAfter.dy, closeTo(relativeBefore.dy, 0.5));
    },
  );

  testWidgets('selecting the amethyst shows resize chips that grow/shrink it from center', (tester) async {
    await _pumpApp(tester);

    final chunkFinder = find.byType(AmethystChunk);
    // No chips while unselected.
    expect(find.byTooltip('Bigger'), findsNothing);

    // Select with a plain tap. The module registers onDoubleTap on every
    // entity, so the single tap only commits after the double-tap timeout
    // (same pump technique as the parent suite's tap tests).
    await tester.tap(chunkFinder);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Bigger'), findsOneWidget);
    expect(find.byTooltip('Smaller'), findsOneWidget);

    final sizeBefore = tester.getSize(chunkFinder);
    final centerBefore = tester.getCenter(chunkFinder);

    await tester.tap(find.byTooltip('Bigger'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    final sizeAfter = tester.getSize(find.byType(AmethystChunk));
    final centerAfter = tester.getCenter(find.byType(AmethystChunk));
    expect(sizeAfter.width, closeTo(sizeBefore.width * 1.15, 0.6));
    // Grows from center: the stone shouldn't slide toward its top-left.
    expect(centerAfter.dx, closeTo(centerBefore.dx, 1.0));
    expect(centerAfter.dy, closeTo(centerBefore.dy, 1.0));

    await tester.tap(find.byTooltip('Smaller'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AmethystChunk)).width, closeTo(sizeBefore.width, 0.6));

    // Shrinking below the clamp floor stops at 90 wide.
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byTooltip('Smaller'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
    }
    expect(tester.getSize(find.byType(AmethystChunk)).width, greaterThanOrEqualTo(90.0));
  });
}
