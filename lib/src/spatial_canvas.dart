import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';

import 'spatial_canvas_controller.dart';
import 'spatial_data_source.dart';
import 'spatial_entity.dart';
import 'viewport_math.dart';

/// Builds the visual for one entity. [isSelected] reflects the canvas's
/// current selection state for [entity].
typedef SpatialEntityBuilder = Widget Function(SpatialEntity entity, bool isSelected);

/// A bounded, pannable, zoomable surface of draggable [SpatialEntity]
/// widgets — Pin & Paper's "flatlay desk".
///
/// ## Rendering
/// `ClipRect` -> `Transform(viewportMatrix)` (pan+zoom applied once) ->
/// canvas-sized `Stack` -> optionally [background] first (`Positioned.fill`
/// + `IgnorePointer`, so it paints but never hit-tests), then per entity,
/// sorted by visual layer tier (dragged > selected > plain), with `zIndex`
/// (id tie-break) within a tier: `Positioned` -> `Transform.rotate` ->
/// `RepaintBoundary` -> a per-card `GestureDetector` -> `entityBuilder`.
/// Deliberately `Stack` + `Positioned`, not `CustomPaint`, and a hand-rolled
/// viewport, not `InteractiveViewer` — see fable-review.md §1.1/§1.2 for why.
///
/// ## Gesture arbitration (decided once, per fable-review.md §1.3)
/// - The outer `GestureDetector` uses a single `onScale*` recognizer for the
///   viewport (pan + pinch-zoom combined) plus `onTapUp` for canvas-tap.
/// - Each card has its own child `GestureDetector` (`onPanStart/Update/End`
///   for drag, `onTap`/`onDoubleTap` for selection). When a touch lands on a
///   card, the child detector wins the arena over the outer one by default
///   — "touch card = drag card, touch felt = pan desk" falls out for free.
/// - Two fingers always control the viewport, even if one of them started on
///   a card. This canvas does *not* rely solely on the outer `onScaleUpdate`
///   reporting `pointerCount >= 2` for this, because when finger 1 started on
///   a card, the outer Scale recognizer never got that pointer at all (it
///   lost the arena), so its own `pointerCount` can't be trusted to reflect
///   "how many fingers are down, total". Instead a raw [Listener] wrapping
///   everything tracks the *true* total pointer count independent of arena
///   outcomes, and: (a) a second pointer arriving mid-drag cancels the
///   in-flight card drag outright (no `onEntityMoved` for that drag), and
///   (b) a card drag refuses to start at all (`onPanStart` no-ops) if a
///   second pointer is already down. Either way, the viewport ends up
///   owning any 2+-finger gesture.
/// - Card drag delta ends up in canvas units without any explicit division
///   by zoom in the handler. fable-review.md §1.3/§1.4 says the drag delta
///   "must be divided by zoom (screen px -> canvas units)", which is the
///   right *intent*, but not literally the right code here: the per-card
///   `GestureDetector` lives inside `Transform(viewportMatrix)`, and Flutter
///   documents `DragUpdateDetails.delta` as being in "the coordinate space of
///   the event receiver" -- i.e. it already comes back pre-divided by the
///   ancestor transform's scale. Explicitly dividing by zoom again would
///   double-divide (invisible at zoom 1.0, silently halves every drag at
///   zoom 2.0 -- see `_handlePanUpdate`'s doc comment and
///   test/spatial_canvas_test.dart's zoom-2.0 drag test, which is what
///   caught this).
/// - Rotation gestures, z-order-on-tap, selection glow, snapping
///   (`rotationSnapDegrees`/`positionSnapSize` are accepted in the
///   constructor for API-shape compatibility with later milestones but are
///   not yet wired to any gesture), multi-select and inertia are all
///   explicitly deferred past this MVP milestone (fable-review.md §1.6/§2).
/// - The per-card `GestureDetector`'s `supportedDevices` deliberately omits
///   `PointerDeviceKind.trackpad` (touch/mouse/stylus/invertedStylus stay
///   supported, so mouse-button card drags are unaffected). A two-finger
///   trackpad pan/pinch arrives as a single `PointerPanZoom*` gesture, not
///   discrete down events; without this exclusion, hovering that gesture
///   over a card let the card's own pan recognizer claim it and drag the
///   card instead of the desk. The outer `GestureDetector`'s `onScale*`
///   recognizer is left with its default (unrestricted) `supportedDevices`
///   so it keeps handling trackpad pan/zoom for the viewport.
///
/// ## Write policy
/// During a drag, only local widget state changes (a preview offset); the
/// entity itself is not mutated. [SpatialDataSource.onEntityMoved] fires
/// exactly once, in `onPanEnd`, with the final clamped canvas position.
/// [SpatialDataSource.onEntityMoving] is fired on every drag frame purely as
/// an optional live-update hook for consumers that want it.
///
/// ## Coordinates
/// Entities live in canvas coordinates, unaffected by pan/zoom. Gesture
/// handlers convert screen -> canvas at the boundary (see
/// `viewport_math.dart`); no other code in this widget sees screen
/// coordinates.
///
/// ## Culling
/// None for the MVP (fable-review.md §1.7): [SpatialDataSource
/// .getVisibleEntities] is always called with the full canvas rect.
class SpatialCanvas extends StatefulWidget {
  const SpatialCanvas({
    super.key,
    required this.dataSource,
    required this.entityBuilder,
    required this.canvasSize,
    this.controller,
    this.minZoom = 0.5,
    this.maxZoom = 2.0,
    this.rotationSnapDegrees,
    this.positionSnapSize,
    this.background,
  }) : assert(minZoom > 0, 'minZoom must be positive'),
       assert(maxZoom >= minZoom, 'maxZoom must be >= minZoom');

  /// Provides entity data and receives interaction callbacks.
  final SpatialDataSource dataSource;

  /// Builds the visual for each entity.
  final SpatialEntityBuilder entityBuilder;

  /// Canvas bounds; entities can't be dragged outside, and the viewport
  /// can't pan past them (beyond a small felt margin — see
  /// `viewport_math.dart`'s `clampPan`).
  final Size canvasSize;

  /// Optional controller for programmatic control (pan/zoom/selection).
  final SpatialCanvasController? controller;

  /// Minimum zoom (default 50%).
  final double minZoom;

  /// Maximum zoom (default 200%).
  final double maxZoom;

  /// Optional rotation snap increment in degrees. Accepted for API-shape
  /// parity with CANVAS_SPEC.md; not yet wired to a gesture in this MVP
  /// milestone (rotation gestures are deferred).
  final double? rotationSnapDegrees;

  /// Optional position snap grid size, in canvas units. Accepted for
  /// API-shape parity with CANVAS_SPEC.md; not yet applied to drags in this
  /// MVP milestone (snapping is deferred).
  final double? positionSnapSize;

  /// Optional visual backdrop for the desk, painted at exactly [canvasSize]
  /// -- i.e. it delineates where the usable canvas ends, which otherwise
  /// isn't visible once zoomed/panned past the edge into the felt margin
  /// (see `viewport_math.dart`'s `kDefaultFeltMargin`). Rendered as the
  /// first `Stack` child, beneath every entity, and wrapped in
  /// `IgnorePointer` so it never intercepts hit-testing -- taps still fall
  /// through to the outer `GestureDetector`'s felt-tap handling exactly as
  /// when [background] is null. Purely decorative; carries no state and
  /// receives no callbacks.
  final Widget? background;

  @override
  State<SpatialCanvas> createState() => _SpatialCanvasState();
}

class _SpatialCanvasState extends State<SpatialCanvas>
    with SingleTickerProviderStateMixin
    implements SpatialCanvasControllerDelegate {
  Offset _pan = Offset.zero;
  double _zoom = 1.0;
  Set<String> _selectedIds = const <String>{};

  String? _draggingEntityId;
  Offset? _dragPreviewPosition;

  int _pointerCount = 0;
  Size _viewportSize = Size.zero;

  Offset? _gestureLastFocal;
  double? _gestureLastScale;

  AnimationController? _animController;

  late SpatialCanvasController _controller;
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    widget.dataSource.addListener(_handleDataSourceChanged);
    _attachController();
  }

  void _attachController() {
    _controller = widget.controller ?? SpatialCanvasController();
    _ownsController = widget.controller == null;
    _controller.attach(this);
  }

  @override
  void didUpdateWidget(SpatialCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataSource != widget.dataSource) {
      oldWidget.dataSource.removeListener(_handleDataSourceChanged);
      widget.dataSource.addListener(_handleDataSourceChanged);
    }
    if (oldWidget.controller != widget.controller) {
      _controller.detach(this);
      if (_ownsController) {
        _controller.dispose();
      }
      _attachController();
    }
  }

  @override
  void dispose() {
    widget.dataSource.removeListener(_handleDataSourceChanged);
    _controller.detach(this);
    if (_ownsController) {
      _controller.dispose();
    }
    _animController?.dispose();
    super.dispose();
  }

  void _handleDataSourceChanged() {
    if (mounted) setState(() {});
  }

  /// Entities in data-order: `(zIndex, id)` ascending, ties broken by [id].
  /// This is the order [SpatialEntity.zIndex] alone describes, and is what
  /// [focusOnEntity] uses to look a card up -- lookup order doesn't matter
  /// for that, so it doesn't need the visual-layering tiers below.
  List<SpatialEntity> _sortedEntities() {
    final rect = Rect.fromLTWH(0, 0, widget.canvasSize.width, widget.canvasSize.height);
    final entities = widget.dataSource.getVisibleEntities(rect).toList();
    entities.sort((a, b) {
      final byZ = a.zIndex.compareTo(b.zIndex);
      return byZ != 0 ? byZ : a.id.compareTo(b.id);
    });
    return entities;
  }

  /// Visual layer tier for [entity], highest paints last (on top). Widget
  /// state (drag-in-progress, selection) always wins over data-side
  /// [SpatialEntity.zIndex] here so the card you're touching is never buried
  /// mid-gesture -- persisting a z-order bump from that is the data source's
  /// business (see `MockSpatialDataSource.onEntityMoved`'s "tap-to-front-on-
  /// move" comment), not this widget's.
  int _layerTier(SpatialEntity entity) {
    if (entity.id == _draggingEntityId) return 2;
    if (_selectedIds.contains(entity.id)) return 1;
    return 0;
  }

  /// Entities in render/hit-test order for the `Stack`: tiered by
  /// [_layerTier] (dragged > selected > plain) so the actively-dragged card
  /// is always topmost and selected cards sit above unselected ones, then
  /// within a tier by [_sortedEntities]'s `(zIndex, id)` order. Only [build]
  /// should use this -- it's about *how* things paint/hit-test this frame,
  /// not the entities' own data order.
  List<SpatialEntity> _visuallySortedEntities() {
    final entities = _sortedEntities();
    entities.sort((a, b) {
      final byTier = _layerTier(a).compareTo(_layerTier(b));
      if (byTier != 0) return byTier;
      final byZ = a.zIndex.compareTo(b.zIndex);
      return byZ != 0 ? byZ : a.id.compareTo(b.id);
    });
    return entities;
  }

  @override
  Widget build(BuildContext context) {
    final entities = _visuallySortedEntities();
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = constraints.biggest;
        return Listener(
          onPointerDown: _handleGlobalPointerDown,
          onPointerUp: _handleGlobalPointerUp,
          onPointerCancel: _handleGlobalPointerUp,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _handleScaleStart,
            onScaleUpdate: _handleScaleUpdate,
            onScaleEnd: _handleScaleEnd,
            onTapUp: _handleCanvasTapUp,
            child: ClipRect(
              // OverflowBox hands the canvas child unbounded constraints so the
              // SizedBox really lays out at canvasSize. Without it, incoming
              // viewport constraints clamp the SizedBox/Stack to window size —
              // Clip.none still paints the escapee cards, but RenderBox hit
              // tests reject any point outside the laid-out bounds, making
              // every card beyond the window's dimensions (in canvas coords)
              // visible yet untappable when zoomed out or panned.
              // alignment must stay topLeft: the canvas origin has to coincide
              // with the viewport origin for viewportMatrix to hold.
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: 0,
                minHeight: 0,
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                child: Transform(
                  transform: viewportMatrix(pan: _pan, zoom: _zoom),
                  child: SizedBox(
                    width: widget.canvasSize.width,
                    height: widget.canvasSize.height,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (widget.background != null)
                          Positioned.fill(
                            child: IgnorePointer(child: widget.background),
                          ),
                        for (final entity in entities) _buildEntity(entity),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEntity(SpatialEntity entity) {
    final isDraggingThis = _draggingEntityId == entity.id;
    final position = isDraggingThis ? (_dragPreviewPosition ?? entity.position) : entity.position;
    final isSelected = _selectedIds.contains(entity.id);

    return Positioned(
      key: ValueKey(entity.id),
      left: position.dx,
      top: position.dy,
      width: entity.size.width,
      height: entity.size.height,
      child: Transform.rotate(
        // SpatialEntity.rotation is in degrees per INTERFACE_CONTRACTS.md;
        // Transform.rotate wants radians.
        angle: entity.rotation * (math.pi / 180.0),
        child: RepaintBoundary(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Deliberately excludes PointerDeviceKind.trackpad (see this
            // class's doc comment, "Gesture arbitration"): a two-finger
            // trackpad pan/pinch must always fall through to the outer
            // canvas GestureDetector's onScale* viewport handling, never be
            // claimed by this card's own pan/tap recognizers.
            supportedDevices: const {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.stylus,
              PointerDeviceKind.invertedStylus,
            },
            onTap: () => _handleEntityTap(entity),
            onDoubleTap: () => widget.dataSource.onEntityDoubleTapped(entity.id),
            onPanStart: (_) => _handlePanStart(entity),
            onPanUpdate: (details) => _handlePanUpdate(entity, details),
            onPanEnd: (_) => _handlePanEnd(entity),
            child: widget.entityBuilder(entity, isSelected),
          ),
        ),
      ),
    );
  }

  // --- Global pointer tracking (arena-independent) ---------------------

  void _handleGlobalPointerDown(PointerDownEvent event) {
    _pointerCount++;
    if (_pointerCount >= 2 && _draggingEntityId != null) {
      // Two fingers down anywhere cancels an in-flight card drag; the
      // viewport wins. Snap the card back to its authoritative position by
      // clearing the preview.
      setState(() {
        _draggingEntityId = null;
        _dragPreviewPosition = null;
      });
    }
  }

  void _handleGlobalPointerUp(PointerEvent event) {
    if (_pointerCount > 0) {
      _pointerCount--;
    }
  }

  // --- Viewport gestures -------------------------------------------------

  void _handleScaleStart(ScaleStartDetails details) {
    _animController?.stop();
    _gestureLastFocal = details.localFocalPoint;
    _gestureLastScale = 1.0;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    final lastFocal = _gestureLastFocal;
    final lastScale = _gestureLastScale;
    if (lastFocal == null || lastScale == null || lastScale == 0) {
      _gestureLastFocal = details.localFocalPoint;
      _gestureLastScale = details.scale;
      return;
    }

    final focal = details.localFocalPoint;
    final incrementalRatio = details.scale / lastScale;
    final targetZoom = _zoom * incrementalRatio;

    // Step 1: translate pan by the focal-point delta since the last frame
    // (this is what makes single-finger panning, and the drifting midpoint
    // of a two-finger pinch, track the finger(s)).
    final translatedPan = _pan + (focal - lastFocal);

    // Step 2: anchor any zoom change at the *current* focal on top of that
    // translation. See viewport_math.dart's zoomAtFocal doc comment for why
    // composing these two steps this way yields the correct combined
    // pan+zoom update.
    final result = zoomAtFocal(
      focal: focal,
      pan: translatedPan,
      zoom: _zoom,
      targetZoom: targetZoom,
      minZoom: widget.minZoom,
      maxZoom: widget.maxZoom,
    );

    setState(() {
      _zoom = result.zoom;
      _pan = clampPan(
        pan: result.pan,
        zoom: result.zoom,
        canvasSize: widget.canvasSize,
        viewportSize: _viewportSize,
      );
    });
    _controller.notifyCanvasChanged();

    _gestureLastFocal = focal;
    _gestureLastScale = details.scale;
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _gestureLastFocal = null;
    _gestureLastScale = null;
  }

  void _handleCanvasTapUp(TapUpDetails details) {
    final canvasPos = screenToCanvas(details.localPosition, pan: _pan, zoom: _zoom);
    if (_selectedIds.isNotEmpty) {
      setState(() {
        _selectedIds = const <String>{};
      });
      widget.dataSource.onSelectionChanged(_selectedIds);
      _controller.notifyCanvasChanged();
    }
    widget.dataSource.onCanvasTapped(canvasPos);
  }

  // --- Card gestures -------------------------------------------------------

  void _handleEntityTap(SpatialEntity entity) {
    final newSelection = <String>{entity.id};
    setState(() {
      _selectedIds = newSelection;
    });
    widget.dataSource.onEntityTapped(entity.id);
    widget.dataSource.onSelectionChanged(_selectedIds);
    _controller.notifyCanvasChanged();
  }

  void _handlePanStart(SpatialEntity entity) {
    if (_pointerCount >= 2) {
      // A second pointer is already down elsewhere; the viewport owns this
      // gesture, don't start a card drag at all.
      return;
    }
    // Grabbing a card is choosing it: dragging selects, same as a tap
    // (owner feedback 2026-08-03 — the selection glow never appeared on
    // drag-only interactions). onEntityTapped is NOT fired here; taps and
    // drags stay distinct events for the data source.
    final selectionChanged = !_selectedIds.contains(entity.id) || _selectedIds.length != 1;
    setState(() {
      _draggingEntityId = entity.id;
      _dragPreviewPosition = entity.position;
      _selectedIds = <String>{entity.id};
    });
    if (selectionChanged) {
      widget.dataSource.onSelectionChanged(_selectedIds);
      _controller.notifyCanvasChanged();
    }
  }

  void _handlePanUpdate(SpatialEntity entity, DragUpdateDetails details) {
    if (_draggingEntityId != entity.id) {
      // Never started (2+ pointers already down) or cancelled mid-drag.
      return;
    }
    final current = _dragPreviewPosition ?? entity.position;
    // NOTE ON A DEVIATION FROM fable-review.md sec 1.3's literal text
    // ("drag delta must be divided by zoom"): that's the right *intent*
    // (screen px -> canvas units) but not the right implementation for this
    // widget's structure. This card's GestureDetector lives *inside*
    // Transform(viewportMatrix), and Flutter's DragUpdateDetails.delta is
    // documented as "the amount the pointer has moved in the coordinate
    // space of the event receiver" -- i.e. it is already expressed in this
    // widget's *local* (post-scale) coordinate space, not raw global screen
    // pixels. Dividing it by _zoom again double-divides, which is invisible
    // at zoom 1.0 (dividing by 1 is a no-op) but silently halves every drag
    // at zoom 2.0 -- caught by test/spatial_canvas_test.dart's zoom-2.0 drag
    // test. So: use the delta as-is here.
    //
    // Caveat for whoever adds rotation gestures (deferred past this
    // milestone): this GestureDetector also sits inside Transform.rotate
    // (currently a no-op since rotation is always 0 in the MVP). Once
    // entities can have nonzero rotation, this same "delta is already
    // locally transformed" fact means `details.delta` would also come back
    // rotated, which is *not* what you want for a canvas-space drag delta --
    // you'd need to either hoist this GestureDetector outside the per-entity
    // Transform.rotate, or counter-rotate the delta by `-entity.rotation`
    // before using it.
    final proposed = current + details.delta;
    final maxX = math.max(0.0, widget.canvasSize.width - entity.size.width);
    final maxY = math.max(0.0, widget.canvasSize.height - entity.size.height);
    final clamped = Offset(
      _clampD(proposed.dx, 0.0, maxX),
      _clampD(proposed.dy, 0.0, maxY),
    );
    setState(() {
      _dragPreviewPosition = clamped;
    });
    widget.dataSource.onEntityMoving(entity.id, clamped, entity.rotation);
  }

  void _handlePanEnd(SpatialEntity entity) {
    if (_draggingEntityId != entity.id) {
      // Was cancelled mid-drag by a 2nd pointer (or never started); nothing
      // to commit.
      return;
    }
    final finalPosition = _dragPreviewPosition ?? entity.position;
    setState(() {
      _draggingEntityId = null;
      _dragPreviewPosition = null;
    });
    widget.dataSource.onEntityMoved(entity.id, finalPosition, entity.rotation);
  }

  static double _clampD(double value, double lo, double hi) {
    if (value < lo) return lo;
    if (value > hi) return hi;
    return value;
  }

  // --- SpatialCanvasControllerDelegate ------------------------------------

  @override
  Rect get visibleRect {
    final topLeft = screenToCanvas(Offset.zero, pan: _pan, zoom: _zoom);
    final width = _viewportSize.width / _zoom;
    final height = _viewportSize.height / _zoom;
    return Rect.fromLTWH(topLeft.dx, topLeft.dy, width, height);
  }

  @override
  double get currentZoom => _zoom;

  @override
  Set<String> get selectedIds => _selectedIds;

  @override
  void panTo(Offset canvasPosition, {required bool animate}) {
    final screenCenter = Offset(_viewportSize.width / 2, _viewportSize.height / 2);
    final targetPan = screenCenter - canvasPosition * _zoom;
    final clamped = clampPan(
      pan: targetPan,
      zoom: _zoom,
      canvasSize: widget.canvasSize,
      viewportSize: _viewportSize,
    );
    _animateTo(pan: clamped, zoom: _zoom, animate: animate);
  }

  @override
  void zoomTo(double scale, {required bool animate}) {
    final focal = Offset(_viewportSize.width / 2, _viewportSize.height / 2);
    final result = zoomAtFocal(
      focal: focal,
      pan: _pan,
      zoom: _zoom,
      targetZoom: scale,
      minZoom: widget.minZoom,
      maxZoom: widget.maxZoom,
    );
    final clampedPan = clampPan(
      pan: result.pan,
      zoom: result.zoom,
      canvasSize: widget.canvasSize,
      viewportSize: _viewportSize,
    );
    _animateTo(pan: clampedPan, zoom: result.zoom, animate: animate);
  }

  @override
  void focusOnEntity(String id, {required bool animate}) {
    SpatialEntity? found;
    for (final entity in _sortedEntities()) {
      if (entity.id == id) {
        found = entity;
        break;
      }
    }
    if (found == null) return;
    final center = found.position + Offset(found.size.width / 2, found.size.height / 2);
    panTo(center, animate: animate);
  }

  @override
  void selectEntity(String id) {
    final newSelection = <String>{id};
    setState(() {
      _selectedIds = newSelection;
    });
    widget.dataSource.onSelectionChanged(_selectedIds);
    _controller.notifyCanvasChanged();
  }

  @override
  void clearSelection() {
    if (_selectedIds.isEmpty) return;
    setState(() {
      _selectedIds = const <String>{};
    });
    widget.dataSource.onSelectionChanged(_selectedIds);
    _controller.notifyCanvasChanged();
  }

  void _animateTo({required Offset pan, required double zoom, required bool animate}) {
    _animController?.dispose();
    _animController = null;

    if (!animate) {
      setState(() {
        _pan = pan;
        _zoom = zoom;
      });
      _controller.notifyCanvasChanged();
      return;
    }

    final panTween = Tween<Offset>(begin: _pan, end: pan);
    final zoomTween = Tween<double>(begin: _zoom, end: zoom);
    final animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    final curved = CurvedAnimation(parent: animController, curve: Curves.easeOutCubic);
    _animController = animController;
    curved.addListener(() {
      if (!mounted) return;
      setState(() {
        _pan = panTween.evaluate(curved);
        _zoom = zoomTween.evaluate(curved);
      });
    });
    animController.forward().whenComplete(() {
      _controller.notifyCanvasChanged();
    });
  }
}
