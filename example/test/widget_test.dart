// Smoke test for the example app -- not part of the module's own test suite
// (that lives in the parent package's test/), just enough to catch the
// example failing to build/render at all.

import 'package:flutter_test/flutter_test.dart';

import 'package:pin_and_paper_canvas_example/main.dart';
import 'package:pin_and_paper_canvas_example/mock_spatial_data_source.dart';

void main() {
  testWidgets('example app renders the canvas with the configured mock card count', (tester) async {
    await tester.pumpWidget(const CanvasExampleApp());
    await tester.pump();

    expect(find.textContaining('$kMockCardCount cards'), findsOneWidget);
    expect(find.text('Card 0'), findsOneWidget);
  });
}
