// Desk-layout persistence: entity positions and the amethyst's size survive
// a "restart" (a fresh MockSpatialDataSource reading the same
// shared_preferences store). Example-level stand-in for Milestone 4's real
// canvas_x/canvas_y persistence.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pin_and_paper_canvas_example/mock_spatial_data_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('moved positions and amethyst size are restored by a fresh data source', () async {
    final first = MockSpatialDataSource();
    await first.initialized;

    final card = first.getVisibleEntities(Rect.largest).firstWhere((e) => e.id == 'mock-0');
    final stone = first.getVisibleEntities(Rect.largest).whereType<AmethystEntity>().single;
    final stoneWidthBefore = stone.size.width;

    first.onEntityMoved('mock-0', const Offset(333, 444), 0);
    first.onEntityMoved(stone.id, const Offset(1200, 900), 0);
    // Note: resize is center-anchored, so it legitimately shifts position by
    // half the size delta -- capture the post-operation truth as the
    // expectation rather than hand-computing it.
    first.resizeAmethyst(stone.id, 1.15);
    final expectedStonePosition = stone.position;
    final expectedStoneWidth = stone.size.width;
    // _persist is fire-and-forget; give the microtask queue a beat.
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(card.position, const Offset(333, 444));
    expect(expectedStoneWidth, closeTo(stoneWidthBefore * 1.15, 0.6));

    final second = MockSpatialDataSource();
    await second.initialized;
    final restoredCard = second.getVisibleEntities(Rect.largest).firstWhere((e) => e.id == 'mock-0');
    final restoredStone = second.getVisibleEntities(Rect.largest).whereType<AmethystEntity>().single;

    expect(restoredCard.position, const Offset(333, 444));
    expect(restoredStone.position, expectedStonePosition);
    expect(restoredStone.size.width, closeTo(expectedStoneWidth, 0.001));
  });

  test('with no saved layout, the default grid is used untouched', () async {
    final ds = MockSpatialDataSource();
    await ds.initialized;
    final card = ds.getVisibleEntities(Rect.largest).firstWhere((e) => e.id == 'mock-0');
    expect(card.position, const Offset(20, 20));
  });
}
