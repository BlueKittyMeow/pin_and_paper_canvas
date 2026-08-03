// Painter smoke test: pumps AmethystChunk standalone (no SpatialCanvas
// involved) and asserts it renders without throwing and is backed by a
// CustomPaint, across the parameter combinations most likely to break
// (defaults, selected, edge-of-range knobs, and a non-default rotation).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pin_and_paper_canvas_example/crystal/amethyst_chunk.dart';

void main() {
  Future<void> pumpChunk(WidgetTester tester, Widget chunk) async {
    await tester.pumpWidget(MaterialApp(home: Center(child: chunk)));
    await tester.pump();
  }

  testWidgets('renders with default parameters, no exceptions, backed by a CustomPaint', (tester) async {
    await pumpChunk(tester, const AmethystChunk());

    expect(tester.takeException(), isNull);
    expect(
      find.descendant(of: find.byType(AmethystChunk), matching: find.byType(CustomPaint)),
      findsOneWidget,
    );
  });

  testWidgets('renders when selected, no exceptions', (tester) async {
    await pumpChunk(tester, const AmethystChunk(isSelected: true));

    expect(tester.takeException(), isNull);
    expect(
      find.descendant(of: find.byType(AmethystChunk), matching: find.byType(CustomPaint)),
      findsOneWidget,
    );
  });

  testWidgets('renders across the tunable knobs\' range, no exceptions', (tester) async {
    // inclusions/glassiness at both extremes, a negative light azimuth, and
    // a rotation past a full quarter-turn -- the combination most likely to
    // expose an unclamped HSL value or an empty/degenerate hull.
    await pumpChunk(
      tester,
      const AmethystChunk(
        size: Size(200, 160),
        lightAzimuthDegrees: -45,
        inclusions: 0,
        glassiness: 0,
        rotationY: 2.4,
      ),
    );
    expect(tester.takeException(), isNull);

    await pumpChunk(
      tester,
      const AmethystChunk(
        lightAzimuthDegrees: 60,
        inclusions: 1,
        glassiness: 1,
        rotationY: -1.2,
        isSelected: true,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a zero-size chunk does not throw', (tester) async {
    // Degenerate layout (e.g. mid-animation collapse) -- scale becomes 0,
    // which the painter's pool/gradient math divides by in a couple of
    // places; must clamp rather than throw.
    await pumpChunk(tester, const AmethystChunk(size: Size.zero));
    expect(tester.takeException(), isNull);
  });
}
