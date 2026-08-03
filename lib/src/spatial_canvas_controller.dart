import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter/widgets.dart' show Offset, Rect;

/// Internal hook-up point between [SpatialCanvasController] and the
/// `SpatialCanvas` widget's state. Not exported from the package barrel —
/// this is an implementation detail shared between `spatial_canvas.dart` and
/// this file, analogous to how `ScrollController`/`ScrollPosition` attach.
///
/// Public (not library-private) only because Dart's `_`-privacy is per-file
/// and these two files need to call each other; treat it as package-private
/// by convention.
abstract class SpatialCanvasControllerDelegate {
  Rect get visibleRect;
  double get currentZoom;
  Set<String> get selectedIds;

  void panTo(Offset canvasPosition, {required bool animate});
  void zoomTo(double scale, {required bool animate});
  void focusOnEntity(String id, {required bool animate});
  void selectEntity(String id);
  void clearSelection();
}

/// Optional controller for programmatic manipulation of a [SpatialCanvas].
///
/// Follows the standard Flutter controller pattern (cf. `ScrollController`):
/// it doesn't hold viewport state itself, it attaches to whichever
/// `SpatialCanvas` widget instance is currently using it and delegates to
/// that widget's state. Before attachment (or after the widget is disposed),
/// getters return sensible defaults and imperative calls are no-ops.
class SpatialCanvasController extends ChangeNotifier {
  SpatialCanvasControllerDelegate? _delegate;

  /// Called by `SpatialCanvasState.initState`/`didUpdateWidget`.
  void attach(SpatialCanvasControllerDelegate delegate) {
    _delegate = delegate;
  }

  /// Called by `SpatialCanvasState.dispose`/`didUpdateWidget`. Guarded by
  /// identity so an out-of-order detach from a stale delegate can't clobber
  /// a newer attach.
  void detach(SpatialCanvasControllerDelegate delegate) {
    if (identical(_delegate, delegate)) {
      _delegate = null;
    }
  }

  /// Called by the attached widget state after it changes pan/zoom/selection
  /// so external listeners of this controller are notified too.
  void notifyCanvasChanged() => notifyListeners();

  /// Pans the viewport so [canvasPosition] is centered.
  void panTo(Offset canvasPosition, {bool animate = true}) {
    _delegate?.panTo(canvasPosition, animate: animate);
  }

  /// Sets the zoom level (1.0 = 100%), clamped to the widget's configured
  /// min/max zoom.
  void zoomTo(double scale, {bool animate = true}) {
    _delegate?.zoomTo(scale, animate: animate);
  }

  /// Pans (and, if needed, zooms out) so the entity with [id] is visible and
  /// centered. No-op if [id] isn't currently known to the data source.
  void focusOnEntity(String id, {bool animate = true}) {
    _delegate?.focusOnEntity(id, animate: animate);
  }

  /// Programmatically selects exactly [id] (replacing any prior selection).
  void selectEntity(String id) {
    _delegate?.selectEntity(id);
  }

  /// Clears the current selection.
  void clearSelection() {
    _delegate?.clearSelection();
  }

  /// Currently visible rectangle, in canvas coordinates. `Rect.zero` before
  /// attachment.
  Rect get visibleRect => _delegate?.visibleRect ?? Rect.zero;

  /// Current zoom level. `1.0` before attachment.
  double get currentZoom => _delegate?.currentZoom ?? 1.0;

  /// Currently selected entity ids. Empty before attachment.
  Set<String> get selectedIds => _delegate?.selectedIds ?? const <String>{};
}
