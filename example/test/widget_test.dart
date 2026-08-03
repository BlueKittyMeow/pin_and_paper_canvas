// Smoke test for the example app -- not part of the module's own test suite
// (that lives in the parent package's test/), just enough to catch the
// example failing to build/render at all.

import 'package:flutter_test/flutter_test.dart';
import 'package:pin_and_paper_card_renderer/card_renderer.dart';

import 'package:pin_and_paper_canvas_example/main.dart';
import 'package:pin_and_paper_canvas_example/mock_spatial_data_source.dart';

/// Simulates a double-tap on [finder] -- two `tap`s inside Flutter's
/// double-tap timeout (300ms), separated by more than its minimum inter-tap
/// gap, so the gesture arena resolves to `onDoubleTap` rather than two
/// separate `onTap`s. Mirrors the wait/pump pattern the parent package's own
/// `spatial_canvas_test.dart` uses around double-tap timing.
Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(finder);
}

void main() {
  testWidgets('example app renders the canvas with the configured mock card count', (tester) async {
    await tester.pumpWidget(const CanvasExampleApp());
    await tester.pump();

    expect(find.textContaining('$kMockCardCount cards'), findsOneWidget);
    // Milestone 2 preview: mock entities render as real TaskCards with
    // believable titles (cycled, so the first title appears more than once).
    expect(find.text('Water the plants'), findsWidgets);
  });

  testWidgets('double-tapping a card flips it to show the back face', (tester) async {
    await tester.pumpWidget(const CanvasExampleApp());
    await tester.pump();

    expect(find.byKey(kTaskCardBackSurfaceKey), findsNothing);

    // mock-0 (zIndex 0, lowest id) sorts first, so this is that card's front
    // surface -- same entity mock_spatial_data_source.dart's mock-0 seeds
    // with a note (index 0 % 4 == 0), used by the next test.
    final cardFront = find.byKey(kTaskCardSurfaceKey).first;
    await _doubleTap(tester, cardFront);
    await tester.pumpAndSettle();

    expect(find.byKey(kTaskCardBackSurfaceKey), findsOneWidget);
    // The other 23 cards are untouched and still show their fronts.
    expect(find.byKey(kTaskCardSurfaceKey), findsNWidgets(kMockCardCount - 1));
  });

  testWidgets('toggling a back field off via the menu hides it on an already-flipped card', (tester) async {
    await tester.pumpWidget(const CanvasExampleApp());
    await tester.pump();

    final cardFront = find.byKey(kTaskCardSurfaceKey).first;
    await _doubleTap(tester, cardFront);
    await tester.pumpAndSettle();

    // mock-0's seeded note (mock_spatial_data_source.dart's `_mockNotes[0]`)
    // -- literal here the same way this file already hardcodes 'Water the
    // plants' above, rather than exporting the private mock list.
    const mock0Note =
        'Check the soil moisture before watering -- the ferns are still recovering from the heat wave.';
    expect(find.text(mock0Note), findsOneWidget);

    await tester.tap(find.byTooltip('Card back fields'));
    await tester.pumpAndSettle();
    // warnIfMissed: false -- CheckedPopupMenuItem's checkmark icon shifts
    // the item's actual hit box slightly from its Text child's own render
    // box; the tap still lands on (and fires) the menu item itself, which
    // the assertions below confirm.
    await tester.tap(find.text('Notes'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text(mock0Note), findsNothing);
    // The card is still flipped -- only the field visibility changed.
    expect(find.byKey(kTaskCardBackSurfaceKey), findsOneWidget);
  });
}
