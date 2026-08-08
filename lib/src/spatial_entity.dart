import 'package:flutter/widgets.dart' show Offset, Size;

/// Anything that can be positioned on the [SpatialCanvas].
///
/// Implemented by the main app (e.g. `TaskSpatialEntity` wrapping a `Task`)
/// or, for the bundled example, by simple mock entities.
///
/// Per INTERFACE_CONTRACTS.md, all geometry is in *canvas* coordinates,
/// unaffected by the viewport's pan/zoom (see viewport_math.dart's doc
/// comment for the coordinate convention).
abstract class SpatialEntity {
  /// Unique identifier, stable across rebuilds.
  String get id;

  /// Position of the entity's top-left corner, in canvas coordinates.
  Offset get position;

  /// Rotation in degrees (0 = upright, positive = clockwise). MVP note: the
  /// canvas widget does not yet offer an interactive rotation gesture
  /// (deferred per the MVP plan) but still respects and round-trips this
  /// value when rendering and when reporting moves.
  double get rotation;

  /// Advisory visual size, in canvas units. Used by the canvas for layout
  /// bounds/hit-testing and (later) culling; the actual rendered widget
  /// returned by the entity builder owns its own visual size.
  Size get size;

  /// Z-order for layering; higher renders on top. Ties break by [id]
  /// (ascending) for a stable, deterministic render order.
  int get zIndex;
}
