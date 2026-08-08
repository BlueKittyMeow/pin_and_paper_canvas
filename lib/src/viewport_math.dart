/// Pure functions for the spatial canvas's viewport math.
///
/// Everything here is side-effect free and framework-agnostic beyond using
/// `dart:ui` geometry types (`Offset`, `Size`, `Rect`) and `Matrix4`. Keeping
/// this pure is what makes it exhaustively unit-testable — see
/// `test/viewport_math_test.dart`.
///
/// Coordinate convention (per CANVAS_SPEC.md / fable-review.md §1.4):
/// - "Screen" coordinates are local pixels of the [SpatialCanvas] widget's own
///   render box (i.e. `details.localPosition` from a gesture on the outer
///   `GestureDetector`, *before* the viewport transform is applied).
/// - "Canvas" coordinates are the fixed coordinate space entities live in,
///   unaffected by pan/zoom.
/// - The viewport transform maps canvas -> screen as `screen = canvas * zoom
///   + pan`. `screenToCanvas`/`canvasToScreen` are exact inverses of each
///   other for the same `pan`/`zoom`.
library;

import 'package:flutter/widgets.dart' show Matrix4, Offset, Size;

/// Default allowance (in canvas units) of empty "felt" a bounded canvas may
/// show past its nominal edges before panning clamps further. Matches
/// fable-review.md §2 ("No infinite canvas... allow ~50px of felt margin").
const double kDefaultFeltMargin = 50.0;

/// Builds the `Matrix4` used to paint the canvas: translate by [pan], then
/// scale by [zoom]. Matches fable-review.md §1.2 exactly:
/// `Matrix4.identity()..translate(pan.dx, pan.dy)..scale(zoom)`.
Matrix4 viewportMatrix({required Offset pan, required double zoom}) {
  return Matrix4.identity()
    ..translateByDouble(pan.dx, pan.dy, 0.0, 1.0)
    ..scaleByDouble(zoom, zoom, 1.0, 1.0);
}

/// Converts a point in canvas coordinates to screen coordinates for the given
/// [pan]/[zoom]: `screen = canvasPoint * zoom + pan`.
Offset canvasToScreen(Offset canvasPoint, {required Offset pan, required double zoom}) {
  return Offset(
    canvasPoint.dx * zoom + pan.dx,
    canvasPoint.dy * zoom + pan.dy,
  );
}

/// Converts a point in screen coordinates to canvas coordinates for the given
/// [pan]/[zoom]. Exact inverse of [canvasToScreen].
Offset screenToCanvas(Offset screenPoint, {required Offset pan, required double zoom}) {
  return Offset(
    (screenPoint.dx - pan.dx) / zoom,
    (screenPoint.dy - pan.dy) / zoom,
  );
}

/// The result of a viewport update: a new pan and a new (already-clamped)
/// zoom.
class ViewportTransform {
  const ViewportTransform({required this.pan, required this.zoom});

  final Offset pan;
  final double zoom;

  @override
  bool operator ==(Object other) {
    return other is ViewportTransform && other.pan == pan && other.zoom == zoom;
  }

  @override
  int get hashCode => Object.hash(pan, zoom);

  @override
  String toString() => 'ViewportTransform(pan: $pan, zoom: $zoom)';
}

double _clampDouble(double value, double min, double max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

/// Computes the pan/zoom pair that results from changing zoom to [targetZoom]
/// (clamped to [minZoom]/[maxZoom]) while keeping the canvas point currently
/// under the fixed screen point [focal] anchored under that same screen
/// point.
///
/// This is the classic focal-anchored zoom formula (fable-review.md §1.2):
/// `newPan = focal - (focal - pan) * (newZoom / oldZoom)`.
///
/// This function models a *single* zoom-around-a-fixed-point step. It is
/// deliberately unaware of the focal point having moved since some earlier
/// moment (that's a translation, not a zoom-anchor) — callers doing combined
/// pan+zoom per gesture frame (e.g. [SpatialCanvas]'s `onScaleUpdate` handler)
/// should first translate `pan` by the focal-point delta since the last
/// frame, then call this function with the *current* focal to anchor the
/// zoom change. Composed that way, the two steps together are exactly
/// equivalent to the general combined pan+zoom update; done in one shot here
/// they answer the narrower, directly testable question: "does the canvas
/// point under a fixed focal point stay under it when zoom changes?"
///
/// Does not clamp [pan] to canvas bounds — see [clampPan] for that, applied
/// separately by the caller.
ViewportTransform zoomAtFocal({
  required Offset focal,
  required Offset pan,
  required double zoom,
  required double targetZoom,
  required double minZoom,
  required double maxZoom,
}) {
  assert(zoom > 0, 'zoom must be positive');
  assert(minZoom > 0 && maxZoom >= minZoom, 'minZoom/maxZoom must be positive and ordered');
  final clampedZoom = _clampDouble(targetZoom, minZoom, maxZoom);
  final ratio = clampedZoom / zoom;
  final newPan = Offset(
    focal.dx - (focal.dx - pan.dx) * ratio,
    focal.dy - (focal.dy - pan.dy) * ratio,
  );
  return ViewportTransform(pan: newPan, zoom: clampedZoom);
}

double _clampPanAxis({
  required double pan,
  required double zoom,
  required double canvasExtent,
  required double viewportExtent,
  required double margin,
}) {
  // Visible canvas-space extent at this zoom, converted back to screen-space
  // pan bounds: the screen-space pan such that the visible rect's edges sit
  // at -margin and canvasExtent+margin (in canvas units).
  final minPan = viewportExtent - (canvasExtent + margin) * zoom;
  final maxPan = margin * zoom;
  if (minPan > maxPan) {
    // Viewport (at this zoom) is wider/taller than the canvas plus margin on
    // both sides -- center it instead of clamping to an inverted range.
    return (minPan + maxPan) / 2;
  }
  return _clampDouble(pan, minPan, maxPan);
}

/// Clamps [pan] so that the viewport (of screen size [viewportSize]) stays
/// within [canvasSize]'s bounds at the given [zoom], allowing [margin] canvas
/// units of empty felt to show past each edge. If the viewport is larger than
/// the canvas (plus margins) on an axis, that axis is centered instead of
/// clamped.
///
/// Pure function of its inputs; does not itself know about [zoomAtFocal] --
/// callers apply zoom changes first, then clamp the resulting pan with this
/// function.
Offset clampPan({
  required Offset pan,
  required double zoom,
  required Size canvasSize,
  required Size viewportSize,
  double margin = kDefaultFeltMargin,
}) {
  assert(zoom > 0, 'zoom must be positive');
  return Offset(
    _clampPanAxis(
      pan: pan.dx,
      zoom: zoom,
      canvasExtent: canvasSize.width,
      viewportExtent: viewportSize.width,
      margin: margin,
    ),
    _clampPanAxis(
      pan: pan.dy,
      zoom: zoom,
      canvasExtent: canvasSize.height,
      viewportExtent: viewportSize.height,
      margin: margin,
    ),
  );
}
