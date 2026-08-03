import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pin_and_paper_canvas/spatial_canvas.dart';

class _TestEntity implements SpatialEntity {
  _TestEntity({
    required this.id,
    required this.position,
    // ignore: unused_element_parameter
    this.rotation = 0,
    this.size = const Size(100, 60),
    // ignore: unused_element_parameter
    this.zIndex = 0,
  });

  @override
  final String id;

  @override
  Offset position;

  @override
  double rotation;

  @override
  final Size size;

  @override
  final int zIndex;
}

class _MovedCall {
  const _MovedCall(this.id, this.position, this.rotation);
  final String id;
  final Offset position;
  final double rotation;
}

class _TestDataSource extends SpatialDataSource {
  _TestDataSource(this._entities);

  final List<_TestEntity> _entities;

  final List<_MovedCall> movedCalls = [];
  final List<_MovedCall> movingCalls = [];
  final List<String> tappedCalls = [];
  final List<String> doubleTappedCalls = [];
  final List<Offset> canvasTappedCalls = [];
  final List<Set<String>> selectionChanges = [];

  @override
  List<SpatialEntity> getVisibleEntities(Rect viewport) => _entities;

  @override
  void onEntityMoved(String id, Offset position, double rotation) {
    movedCalls.add(_MovedCall(id, position, rotation));
    final entity = _entities.firstWhere((e) => e.id == id);
    entity.position = position;
    entity.rotation = rotation;
  }

  @override
  void onEntityMoving(String id, Offset position, double rotation) {
    movingCalls.add(_MovedCall(id, position, rotation));
  }

  @override
  void onEntityTapped(String id) => tappedCalls.add(id);

  @override
  void onEntityDoubleTapped(String id) => doubleTappedCalls.add(id);

  @override
  void onCanvasTapped(Offset position) => canvasTappedCalls.add(position);

  @override
  void onSelectionChanged(Set<String> selectedIds) => selectionChanges.add(Set.of(selectedIds));

  /// Test helper: simulate an external edit elsewhere (e.g. a task list
  /// refresh) notifying listeners, distinct from an in-gesture callback.
  void simulateExternalChange() => notifyListeners();
}

Widget _buildTestEntity(SpatialEntity entity, bool isSelected) {
  return Container(
    key: Key('card-${entity.id}'),
    color: isSelected ? Colors.blue : Colors.grey,
  );
}

Future<void> _pumpCanvas(
  WidgetTester tester, {
  required SpatialDataSource dataSource,
  SpatialCanvasController? controller,
  Size canvasSize = const Size(2000, 1500),
}) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: SpatialCanvas(
        dataSource: dataSource,
        entityBuilder: _buildTestEntity,
        canvasSize: canvasSize,
        controller: controller,
      ),
    ),
  );
}

/// Drags from [start] to [start] + [totalScreenDelta] over many small
/// incremental pointer moves (with a pump between each), then releases.
///
/// Why many small steps rather than one `tester.drag()` call: the card's own
/// `onPan*` `GestureDetector` and the outer canvas's `onScale*`
/// `GestureDetector` compete in the same Flutter gesture arena for the first
/// pointer, and while that arena is being resolved some amount of initial
/// pointer movement is consumed by arbitration and never reaches
/// `onPanUpdate` at all -- this is precisely fable-review.md's "Risk to
/// watch" (nested-detector gesture arenas are the flakiest thing to widget-
/// test here). The exact amount "lost" to arbitration is a Flutter
/// gesture-recognizer implementation detail, not part of this package's
/// contract, and isn't worth hard-coding an exact expectation around.
/// Spreading a large total delta over many steps keeps that one-time loss a
/// small, bounded fraction of the total, so callers can assert the result
/// with a generous (rather than sub-pixel) tolerance and still clearly
/// distinguish real bugs (e.g. forgetting to divide by zoom, which is a 2x
/// error) from arena noise.
Future<void> _dragCardInSteps(
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

void main() {
  testWidgets('renders entities at their canvas position when pan=0, zoom=1', (tester) async {
    final dataSource = _TestDataSource([
      _TestEntity(id: 'a', position: const Offset(50, 50)),
      _TestEntity(id: 'b', position: const Offset(300, 200)),
    ]);
    await _pumpCanvas(tester, dataSource: dataSource);

    expect(tester.getTopLeft(find.byKey(const Key('card-a'))), const Offset(50, 50));
    expect(tester.getTopLeft(find.byKey(const Key('card-b'))), const Offset(300, 200));
  });

  testWidgets('dragging a card fires onEntityMoved exactly once, at zoom 1.0', (tester) async {
    const original = Offset(100, 100);
    final dataSource = _TestDataSource([_TestEntity(id: 'a', position: original)]);
    await _pumpCanvas(tester, dataSource: dataSource);

    final cardFinder = find.byKey(const Key('card-a'));
    const totalScreenDelta = Offset(240, 160);
    await _dragCardInSteps(tester, start: tester.getCenter(cardFinder), totalScreenDelta: totalScreenDelta);

    expect(dataSource.movedCalls, hasLength(1));
    final moved = dataSource.movedCalls.single;
    expect(moved.id, 'a');

    // At zoom 1.0, canvas delta == screen delta. Generous tolerance absorbs
    // one-time gesture-arena arbitration loss (see _dragCardInSteps) without
    // masking a real bug -- e.g. dividing by the wrong zoom would be off by
    // a large, easily distinguished margin at other zoom levels (see the
    // zoom 2.0 test below).
    final expected = original + totalScreenDelta;
    expect(moved.position.dx, closeTo(expected.dx, 40));
    expect(moved.position.dy, closeTo(expected.dy, 40));

    // Live hook should have fired at least once during the drag too.
    expect(dataSource.movingCalls, isNotEmpty);
  });

  testWidgets('dragging a card at zoom 2.0 divides the screen delta by zoom', (tester) async {
    // Positioned close to the viewport's center-of-zoom (zoomTo anchors at
    // the viewport center) so the card stays fully on-screen -- and
    // draggable -- after zooming to 2.0 in an 800x600 test viewport.
    const original = Offset(350, 250);
    final dataSource = _TestDataSource([_TestEntity(id: 'a', position: original)]);
    final controller = SpatialCanvasController();
    await _pumpCanvas(tester, dataSource: dataSource, controller: controller);

    controller.zoomTo(2.0, animate: false);
    await tester.pump();
    expect(controller.currentZoom, 2.0);

    final cardFinder = find.byKey(const Key('card-a'));
    const totalScreenDelta = Offset(240, 160);
    await _dragCardInSteps(tester, start: tester.getCenter(cardFinder), totalScreenDelta: totalScreenDelta);

    expect(dataSource.movedCalls, hasLength(1));
    final moved = dataSource.movedCalls.single;

    // At zoom 2.0, a screen delta of (240, 160) must correspond to a canvas
    // delta of (120, 80) -- exactly the delta-must-be-divided-by-zoom
    // requirement fable-review.md sec 1.3 calls out. A tolerance of 40
    // canvas units comfortably absorbs gesture-arena arbitration loss (see
    // _dragCardInSteps) while remaining far tighter than the ~120-canvas-unit
    // gap a forgotten zoom division would produce (that bug would report a
    // canvas delta of ~240,160 instead of ~120,80).
    final expected = original + Offset(totalScreenDelta.dx / 2.0, totalScreenDelta.dy / 2.0);
    expect(moved.position.dx, closeTo(expected.dx, 40));
    expect(moved.position.dy, closeTo(expected.dy, 40));
  });

  testWidgets('dragging past the top-left edge clamps to (0, 0)', (tester) async {
    final dataSource = _TestDataSource([
      _TestEntity(id: 'a', position: const Offset(10, 10), size: const Size(80, 60)),
    ]);
    await _pumpCanvas(tester, dataSource: dataSource, canvasSize: const Size(300, 200));

    final start = tester.getCenter(find.byKey(const Key('card-a')));
    final gesture = await tester.startGesture(start);
    // Many small steps, well past the canvas bounds in total -- any
    // arena-arbitration loss (see _dragCardAndMeasure's doc comment) is
    // negligible next to this much overshoot, so clamping is unambiguous.
    for (var i = 0; i < 30; i++) {
      await gesture.moveBy(const Offset(-20, -20));
      await tester.pump(const Duration(milliseconds: 8));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(dataSource.movedCalls, hasLength(1));
    expect(dataSource.movedCalls.single.position, Offset.zero);
  });

  testWidgets('dragging past the bottom-right edge clamps to canvasSize - entitySize', (tester) async {
    final dataSource = _TestDataSource([
      _TestEntity(id: 'a', position: const Offset(10, 10), size: const Size(80, 60)),
    ]);
    await _pumpCanvas(tester, dataSource: dataSource, canvasSize: const Size(300, 200));

    final start = tester.getCenter(find.byKey(const Key('card-a')));
    final gesture = await tester.startGesture(start);
    for (var i = 0; i < 30; i++) {
      await gesture.moveBy(const Offset(20, 20));
      await tester.pump(const Duration(milliseconds: 8));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(dataSource.movedCalls, hasLength(1));
    expect(dataSource.movedCalls.single.position, const Offset(300 - 80, 200 - 60));
  });

  testWidgets('tapping a card selects it and fires onEntityTapped/onSelectionChanged', (tester) async {
    final dataSource = _TestDataSource([_TestEntity(id: 'a', position: const Offset(50, 50))]);
    final controller = SpatialCanvasController();
    await _pumpCanvas(tester, dataSource: dataSource, controller: controller);

    await tester.tap(find.byKey(const Key('card-a')));
    // The card also has onDoubleTap registered, so Flutter's tap recognizer
    // must wait out the double-tap timeout before committing to a single
    // tap. That wait is a real Timer, not a scheduled animation frame, so
    // pumpAndSettle's "no more frames" check can return before it fires --
    // an explicit pump duration past kDoubleTapTimeout is required.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(controller.selectedIds, {'a'});
    expect(dataSource.tappedCalls, ['a']);
    expect(dataSource.selectionChanges.last, {'a'});
  });

  testWidgets('tapping empty felt deselects and fires onCanvasTapped with canvas coords', (tester) async {
    final dataSource = _TestDataSource([_TestEntity(id: 'a', position: const Offset(50, 50))]);
    final controller = SpatialCanvasController();
    await _pumpCanvas(tester, dataSource: dataSource, controller: controller, canvasSize: const Size(800, 600));

    await tester.tap(find.byKey(const Key('card-a')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(controller.selectedIds, {'a'});

    // Somewhere far from the card, well within the 800x600 test viewport.
    // (Empty-felt taps don't have a double-tap recognizer in the way, but
    // pump the same explicit duration for consistency/safety.)
    await tester.tapAt(const Offset(700, 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(controller.selectedIds, isEmpty);
    expect(dataSource.canvasTappedCalls, hasLength(1));
    expect(dataSource.canvasTappedCalls.single, const Offset(700, 500));
    expect(dataSource.selectionChanges.last, isEmpty);
  });

  testWidgets('two-finger gesture pans the viewport and moves no entity', (tester) async {
    final dataSource = _TestDataSource([_TestEntity(id: 'a', position: const Offset(50, 50))]);
    final controller = SpatialCanvasController();
    await _pumpCanvas(tester, dataSource: dataSource, controller: controller);

    final rectBefore = controller.visibleRect;

    // Both pointers land on empty felt, well away from the card.
    final gesture1 = await tester.startGesture(const Offset(600, 100));
    final gesture2 = await tester.startGesture(const Offset(700, 100));
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 5; i++) {
      await gesture1.moveBy(const Offset(-10, -5));
      await gesture2.moveBy(const Offset(-10, -5));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture1.up();
    await gesture2.up();
    await tester.pumpAndSettle();

    expect(dataSource.movedCalls, isEmpty);
    expect(controller.visibleRect, isNot(equals(rectBefore)));
  });

  testWidgets('a second pointer cancels an in-flight card drag (viewport wins)', (tester) async {
    final dataSource = _TestDataSource([_TestEntity(id: 'a', position: const Offset(300, 300))]);
    await _pumpCanvas(tester, dataSource: dataSource);

    final cardCenter = tester.getCenter(find.byKey(const Key('card-a')));
    final cardGesture = await tester.startGesture(cardCenter);
    // Enough cumulative movement that the card drag has definitely won its
    // gesture arena and is actively in-flight before the 2nd pointer lands.
    for (var i = 0; i < 10; i++) {
      await cardGesture.moveBy(const Offset(5, 5));
      await tester.pump(const Duration(milliseconds: 8));
    }

    // A second finger comes down elsewhere on empty felt mid-drag.
    final secondGesture = await tester.startGesture(const Offset(700, 500));
    await tester.pump(const Duration(milliseconds: 16));

    await cardGesture.up();
    await secondGesture.up();
    await tester.pumpAndSettle();

    // The drag was cancelled by the 2nd pointer -- onEntityMoved must not
    // fire for it.
    expect(dataSource.movedCalls, isEmpty);
  });

  testWidgets('external dataSource.notifyListeners triggers a rebuild reflecting new positions', (tester) async {
    final entity = _TestEntity(id: 'a', position: const Offset(20, 20));
    final dataSource = _TestDataSource([entity]);
    await _pumpCanvas(tester, dataSource: dataSource);

    expect(tester.getTopLeft(find.byKey(const Key('card-a'))), const Offset(20, 20));

    entity.position = const Offset(220, 180);
    dataSource.simulateExternalChange();
    await tester.pump();

    expect(tester.getTopLeft(find.byKey(const Key('card-a'))), const Offset(220, 180));
  });

  testWidgets('cards beyond the viewport dimensions (in canvas coords) are tappable when zoomed out', (tester) async {
    // Regression: incoming viewport constraints used to clamp the canvas
    // SizedBox/Stack to window size, so cards whose canvas position exceeded
    // the window's own dimensions painted (Clip.none) but failed hit tests --
    // visible yet untappable/undraggable once zoomed out or panned. Found
    // live in the example app: with a ~1280px window every card past canvas
    // x=1280 fell through to onCanvasTapped.
    final farEntity = _TestEntity(id: 'far', position: const Offset(1200, 900));
    final dataSource = _TestDataSource([farEntity]);
    final controller = SpatialCanvasController();
    await _pumpCanvas(tester, dataSource: dataSource, controller: controller);

    controller.zoomTo(0.5, animate: false);
    await tester.pumpAndSettle();
    expect(controller.currentZoom, 0.5);

    // Derive the card's on-screen center from the controller's own view of
    // the viewport, so the test stays correct however zoomTo pans/clamps.
    final zoom = controller.currentZoom;
    final pan = -controller.visibleRect.topLeft * zoom;
    final entityCenter = farEntity.position + const Offset(50, 30); // size 100x60
    final screenPoint = canvasToScreen(entityCenter, pan: pan, zoom: zoom);

    await tester.tapAt(screenPoint);
    // Wait out the double-tap timeout (real Timer, not a frame) -- see the
    // 'tapping a card selects it' test above for why pumpAndSettle alone
    // returns too early.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(dataSource.tappedCalls, ['far'],
        reason: 'tap must reach the card, not fall through to the felt');
    expect(dataSource.canvasTappedCalls, isEmpty);

    // And it must be draggable, not just tappable.
    await _dragCardInSteps(tester,
        start: screenPoint, totalScreenDelta: const Offset(-60, -40));
    expect(dataSource.movedCalls, isNotEmpty,
        reason: 'drag must engage the card\'s pan recognizer');
  });
}
