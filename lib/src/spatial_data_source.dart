import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter/widgets.dart' show Offset, Rect;

import 'spatial_entity.dart';

/// Provides entity data to a [SpatialCanvas] and receives callbacks for user
/// interaction. Implemented by the main app (or, for the bundled example, by
/// `MockSpatialDataSource`).
///
/// This is a [ChangeNotifier] per the MVP plan: the canvas listens and calls
/// [getVisibleEntities] again whenever the data source calls
/// `notifyListeners()` (e.g. after an external edit to the underlying task
/// list), without waiting for a gesture.
///
/// [getVisibleEntities] and [onEntityMoved] are the only two members every
/// implementation must supply. The rest have no-op default bodies so minimal
/// data sources (like the mock used by tests/example) don't need to
/// implement callbacks they don't care about.
///
/// Naming note: INTERFACE_CONTRACTS.md names the double-tap callback
/// `onEntityDoubleTapped`; the MVP plan's file-layout comment abbreviates it
/// to `onDoubleTapped`. This implementation uses the full
/// `onEntityDoubleTapped` name for consistency with the other `onEntity*`
/// members and because INTERFACE_CONTRACTS.md is the more precise source for
/// exact naming where the plan is shorthand.
abstract class SpatialDataSource extends ChangeNotifier {
  /// Returns all entities that should render for the given [viewport] (in
  /// canvas coordinates).
  ///
  /// MVP note: the canvas does not cull for the MVP milestone (fable-review
  /// §1.7) — it always passes the full canvas rect — so implementations may
  /// ignore [viewport] and return everything. Filtering to the viewport is
  /// still supported for when culling is added and for larger real data
  /// sets, so implementations should still honor it when it's cheap to do so.
  List<SpatialEntity> getVisibleEntities(Rect viewport);

  /// Called exactly once, on gesture end, when the user finishes dragging an
  /// entity. [position] is the entity's new top-left in canvas coordinates,
  /// already clamped to canvas bounds. [rotation] is passed through
  /// unchanged in the MVP (no rotation gesture yet).
  ///
  /// This is a hard contract requirement (fable-review §1.5): the canvas
  /// must not call this per-frame during a drag, only once on release, to
  /// avoid flooding a database/sync log.
  void onEntityMoved(String id, Offset position, double rotation);

  /// Optional live-update hook, called on every drag frame (not just on
  /// release) while an entity is being dragged. Most data sources should
  /// leave this as a no-op and rely on [onEntityMoved]; it exists for
  /// consumers that want to mirror in-progress drags elsewhere (e.g. a
  /// minimap) without persisting anything.
  void onEntityMoving(String id, Offset position, double rotation) {}

  /// Called when the user taps an entity (single-select).
  void onEntityTapped(String id) {}

  /// Called when the user double-taps an entity.
  void onEntityDoubleTapped(String id) {}

  /// Called when the user taps empty canvas ("felt"), in canvas coordinates.
  /// The canvas clears its own selection state before calling this.
  void onCanvasTapped(Offset position) {}

  /// Called whenever the canvas's selection set changes, with the full
  /// current set of selected ids.
  void onSelectionChanged(Set<String> selectedIds) {}
}
