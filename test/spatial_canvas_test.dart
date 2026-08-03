import 'package:flutter/gestures.dart' show PointerDeviceKind;
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
  SpatialEntityBuilder entityBuilder = _buildTestEntity,
}) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: SpatialCanvas(
        dataSource: dataSource,
        entityBuilder: entityBuilder,
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

/// Returns entity ids in the `SpatialCanvas`'s internal `Stack.children`
/// order -- last is topmost (both painted last, on top, and hit-tested
/// first). This is the ground truth for "which card is visually/hit-test
/// on top" without needing to simulate an actual tap, which would be
/// awkward to do safely mid-gesture (see the layering tests below).
List<String> _stackChildOrder(WidgetTester tester) {
  final stack = tester.widget<Stack>(
    find.descendant(of: find.byType(SpatialCanvas), matching: find.byType(Stack)),
  );
  return stack.children
      .map((child) {
        final key = child.key;
        return key is ValueKey<String> ? key.value : null;
      })
      .whereType<String>()
      .toList();
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

  testWidgets('starting a drag selects the card (glow without needing a tap)', (tester) async {
    final dataSource = _TestDataSource([_TestEntity(id: 'a', position: const Offset(100, 100))]);
    final controller = SpatialCanvasController();
    await _pumpCanvas(tester, dataSource: dataSource, controller: controller);

    await _dragCardInSteps(
      tester,
      start: tester.getCenter(find.byKey(const Key('card-a'))),
      totalScreenDelta: const Offset(80, 40),
    );

    expect(controller.selectedIds, {'a'});
    expect(dataSource.selectionChanges.last, {'a'});
    // Dragging is not tapping: the tap callback must not have fired.
    expect(dataSource.tappedCalls, isEmpty);
  });

  testWidgets('drag lift: card scales up while dragged, settles back on release', (tester) async {
    final dataSource = _TestDataSource([_TestEntity(id: 'a', position: const Offset(100, 100))]);
    await _pumpCanvas(tester, dataSource: dataSource);

    double liftScale() => tester
        .widget<AnimatedScale>(
          find.ancestor(of: find.byKey(const Key('card-a')), matching: find.byType(AnimatedScale)).first,
        )
        .scale;

    expect(liftScale(), 1.0);

    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('card-a'))));
    for (var i = 0; i < 15; i++) {
      await gesture.moveBy(const Offset(6, 4));
      await tester.pump(const Duration(milliseconds: 8));
    }
    // Mid-drag: lifted (docs/drag-feel-research.md Candidate 1).
    expect(liftScale(), 1.03);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(liftScale(), 1.0);
  });

  testWidgets('the actively-dragged card renders on top even with a lower zIndex', (tester) async {
    // 'lo' has the lower zIndex and starts well clear of 'hi' so the drag can
    // originate on it unambiguously; the drag then carries it over 'hi'.
    final dataSource = _TestDataSource([
      _TestEntity(id: 'lo', position: const Offset(50, 50), zIndex: 0),
      _TestEntity(id: 'hi', position: const Offset(300, 50), zIndex: 5),
    ]);
    await _pumpCanvas(tester, dataSource: dataSource);

    // Before any interaction: plain (zIndex, id) order -- 'hi' (zIndex 5) on
    // top of 'lo' (zIndex 0).
    expect(_stackChildOrder(tester), ['lo', 'hi']);

    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('card-lo'))));
    // Drag 'lo' most of the way toward 'hi' -- enough steps that the card
    // drag has definitely won its gesture arena and is in flight.
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 8));
    }

    // Mid-drag (gesture still down): 'lo' must be topmost despite its lower
    // zIndex, because it's the actively-dragged card.
    expect(_stackChildOrder(tester).last, 'lo',
        reason: 'the actively-dragged card must render on top of everything else');

    await gesture.up();
    await tester.pumpAndSettle();

    // After release: no longer dragging, but drag-start selected 'lo'
    // (see 'starting a drag selects the card') and selected cards render
    // above unselected ones -- so 'lo' stays on top until deselected.
    expect(_stackChildOrder(tester), ['hi', 'lo']);

    // Deselect by tapping empty felt: now plain (zIndex, id) order returns.
    await tester.tapAt(const Offset(700, 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(_stackChildOrder(tester), ['lo', 'hi']);
  });

  testWidgets('tap-selecting a card raises it above an overlapping unselected card', (tester) async {
    // 'a' has the higher zIndex (renders on top by default) and fully
    // contains 'b's top-left corner, but 'b' extends further right/down so
    // there's an exposed sliver of 'b' to tap without hitting 'a'.
    final dataSource = _TestDataSource([
      _TestEntity(id: 'a', position: const Offset(100, 100), size: const Size(100, 60), zIndex: 5),
      _TestEntity(id: 'b', position: const Offset(150, 110), size: const Size(200, 150), zIndex: 0),
    ]);
    final controller = SpatialCanvasController();
    await _pumpCanvas(tester, dataSource: dataSource, controller: controller);

    // Before selection: plain (zIndex, id) order -- 'a' (zIndex 5) on top.
    expect(_stackChildOrder(tester), ['b', 'a']);

    // A point inside 'b' (spans x:150-350, y:110-260) but outside 'a' (spans
    // x:100-200, y:100-160).
    const tapPoint = Offset(300, 200);
    await tester.tapAt(tapPoint);
    // Wait out the double-tap timeout (real Timer, not a frame) -- see the
    // 'tapping a card selects it' test above for why pumpAndSettle alone
    // returns too early.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(dataSource.tappedCalls, ['b'], reason: 'tap must land on b, not a');
    expect(controller.selectedIds, {'b'});

    // After selection: 'b' must render on top despite its lower zIndex,
    // because it's now the selected card.
    expect(_stackChildOrder(tester), ['a', 'b'],
        reason: 'the selected card must render above an overlapping unselected one');
  });

  testWidgets('trackpad pan/zoom over a card pans the viewport and never moves the card', (tester) async {
    final dataSource = _TestDataSource([_TestEntity(id: 'a', position: const Offset(300, 300))]);
    final controller = SpatialCanvasController();
    await _pumpCanvas(tester, dataSource: dataSource, controller: controller);

    final cardCenter = tester.getCenter(find.byKey(const Key('card-a')));
    final rectBefore = controller.visibleRect;

    // A two-finger trackpad pan arrives as a single PointerPanZoom* gesture
    // (not discrete down/move pointer events), landing right on top of a
    // card -- exactly the scenario that used to let the card's own pan
    // recognizer claim it and drag the card instead of the desk.
    final trackpadGesture = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await trackpadGesture.panZoomStart(cardCenter);
    await tester.pump();
    for (final pan in const [Offset(-30, -20), Offset(-60, -40), Offset(-90, -60)]) {
      await trackpadGesture.panZoomUpdate(cardCenter, pan: pan);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await trackpadGesture.panZoomEnd();
    await tester.pumpAndSettle();

    expect(dataSource.movedCalls, isEmpty, reason: 'trackpad gestures must never move a card');
    expect(dataSource.movingCalls, isEmpty, reason: 'trackpad gestures must never move a card');
    expect(controller.visibleRect, isNot(equals(rectBefore)),
        reason: 'trackpad gestures must still pan/zoom the viewport');
  });

  testWidgets('trackpad pinch (scale != 1) over empty felt zooms the viewport', (tester) async {
    // Regression coverage added while investigating an owner report of
    // "pinch-to-zoom stopped working on Linux desktop (trackpad)". The
    // above pan test never exercises `scale` (it defaults to 1.0 in
    // `panZoomUpdate`), so it can't catch a zoom-specific break. This test
    // drives `scale` directly to make sure a trackpad pinch reaches
    // `_handleScaleUpdate` and actually changes `currentZoom`.
    final dataSource = _TestDataSource([_TestEntity(id: 'a', position: const Offset(300, 300))]);
    final controller = SpatialCanvasController();
    await _pumpCanvas(tester, dataSource: dataSource, controller: controller);

    const feltPoint = Offset(700, 500); // away from the only card
    final zoomBefore = controller.currentZoom;

    final gesture = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await gesture.panZoomStart(feltPoint);
    await tester.pump();
    for (final scale in const [0.9, 0.8, 0.7]) {
      await gesture.panZoomUpdate(feltPoint, scale: scale);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.panZoomEnd();
    await tester.pumpAndSettle();

    expect(controller.currentZoom, isNot(closeTo(zoomBefore, 0.001)),
        reason: 'a trackpad pinch over the felt must change zoom');
  });

  testWidgets('trackpad pinch (scale != 1) over a card zooms the viewport, never moves the card', (tester) async {
    // Same regression coverage as above, but landing on a card -- the
    // scenario the owner actually hit. The per-card `GestureDetector`
    // excludes `PointerDeviceKind.trackpad` (98240b7), so this pinch should
    // never be seen by the card's own recognizers at all; it should reach
    // the outer canvas `onScale*` exactly as it does over empty felt.
    final dataSource = _TestDataSource([_TestEntity(id: 'a', position: const Offset(300, 300))]);
    final controller = SpatialCanvasController();
    await _pumpCanvas(tester, dataSource: dataSource, controller: controller);

    final cardCenter = tester.getCenter(find.byKey(const Key('card-a')));
    final zoomBefore = controller.currentZoom;

    final gesture = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await gesture.panZoomStart(cardCenter);
    await tester.pump();
    for (final scale in const [0.9, 0.8, 0.7]) {
      await gesture.panZoomUpdate(cardCenter, scale: scale);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.panZoomEnd();
    await tester.pumpAndSettle();

    expect(controller.currentZoom, isNot(closeTo(zoomBefore, 0.001)),
        reason: 'a trackpad pinch over a card must still zoom the viewport');
    expect(dataSource.movedCalls, isEmpty, reason: 'a trackpad pinch must never move a card');
    expect(dataSource.movingCalls, isEmpty, reason: 'a trackpad pinch must never move a card');
  });

  testWidgets(
    'trackpad pinch still zooms when the card content itself has a nested Scrollable',
    (tester) async {
      // pin_and_paper_card_renderer's real TaskCard (used by this package's
      // example app, not by this widget itself) nests a
      // `SingleChildScrollView` inside the card content to keep a tag `Wrap`
      // from overflowing a fixed-height card. `Scrollable` doesn't exclude
      // `PointerDeviceKind.trackpad` from its own drag recognizer, so it's
      // worth confirming that structure -- reproduced locally here rather
      // than adding a dependency on the card renderer -- can't win the
      // gesture arena for a trackpad pinch away from the outer canvas.
      final dataSource = _TestDataSource([_TestEntity(id: 'a', position: const Offset(300, 300))]);
      final controller = SpatialCanvasController();
      await _pumpCanvas(
        tester,
        dataSource: dataSource,
        controller: controller,
        entityBuilder: (entity, isSelected) => Container(
          key: Key('card-${entity.id}'),
          color: Colors.grey,
          child: const Column(
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(children: [SizedBox(width: 40, height: 20)]),
                ),
              ),
            ],
          ),
        ),
      );

      final cardCenter = tester.getCenter(find.byKey(const Key('card-a')));
      final zoomBefore = controller.currentZoom;

      final gesture = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      await gesture.panZoomStart(cardCenter);
      await tester.pump();
      for (final scale in const [0.9, 0.8, 0.7]) {
        await gesture.panZoomUpdate(cardCenter, scale: scale);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.panZoomEnd();
      await tester.pumpAndSettle();

      expect(controller.currentZoom, isNot(closeTo(zoomBefore, 0.001)),
          reason: 'a nested Scrollable in card content must not swallow the trackpad pinch');
    },
  );

  testWidgets('mouse-button drag of a card still works alongside the trackpad exclusion', (tester) async {
    // Guards against a too-broad fix: excluding trackpad from the card's
    // GestureDetector must not accidentally exclude mouse too.
    const original = Offset(100, 100);
    final dataSource = _TestDataSource([_TestEntity(id: 'a', position: original)]);
    await _pumpCanvas(tester, dataSource: dataSource);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('card-a'))),
      kind: PointerDeviceKind.mouse,
    );
    const totalScreenDelta = Offset(120, 80);
    const steps = 20;
    final stepDelta = Offset(totalScreenDelta.dx / steps, totalScreenDelta.dy / steps);
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(stepDelta);
      await tester.pump(const Duration(milliseconds: 8));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(dataSource.movedCalls, hasLength(1));
  });

  testWidgets('background renders below entities and does not intercept taps', (tester) async {
    const backgroundKey = Key('desk-background');
    final dataSource = _TestDataSource([_TestEntity(id: 'a', position: const Offset(50, 50))]);
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: SpatialCanvas(
          dataSource: dataSource,
          entityBuilder: _buildTestEntity,
          canvasSize: const Size(800, 600),
          background: Container(key: backgroundKey, color: Colors.brown),
        ),
      ),
    );

    // The background is the first Stack child (beneath every entity).
    final stack = tester.widget<Stack>(
      find.descendant(of: find.byType(SpatialCanvas), matching: find.byType(Stack)),
    );
    expect(stack.children.first, isA<Positioned>());
    final firstChild = stack.children.first as Positioned;
    expect(firstChild.child, isA<IgnorePointer>());
    expect(find.byKey(backgroundKey), findsOneWidget);

    // Tapping empty felt (away from the card, but still over the
    // background) must still reach onCanvasTapped, not the background.
    await tester.tapAt(const Offset(700, 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(dataSource.canvasTappedCalls, hasLength(1));
    expect(dataSource.canvasTappedCalls.single, const Offset(700, 500));
  });
}
