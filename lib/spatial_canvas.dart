/// Spatial canvas positioning for Pin & Paper — pan, zoom, drag, rotate.
///
/// See `SpatialCanvas`, `SpatialCanvasController`, `SpatialEntity`,
/// `SpatialDataSource`, and the pure viewport math helpers
/// (`screenToCanvas`, `canvasToScreen`, `zoomAtFocal`, `clampPan`,
/// `viewportMatrix`).
library pin_and_paper_canvas;

export 'src/desk_objects/amethyst_chunk.dart';
export 'src/desk_objects/dachshund_figurine.dart';
export 'src/desk_objects/dachshund_hit_mask.dart';
export 'src/desk_objects/gem_figurine.dart';
export 'src/desk_objects/gem_hit_mask.dart';
export 'src/spatial_canvas.dart';
export 'src/spatial_canvas_controller.dart' show SpatialCanvasController;
export 'src/spatial_data_source.dart';
export 'src/spatial_entity.dart';
export 'src/viewport_math.dart';
