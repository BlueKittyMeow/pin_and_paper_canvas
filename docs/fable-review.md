# Fable — Canvas Module Pre-Build Review

**Date:** 2026-07-09
**State:** Repo is empty (`.gitkeep`). This is a pre-implementation review of `CANVAS_SPEC.md` + `INTERFACE_CONTRACTS.md` (dev harness repo) with concrete technical decisions, so the implementer doesn't have to make them mid-build. The spec itself is good — follow it; this doc pins down the parts it leaves open and flags the traps.

---

## 1. Decisions (make these the plan of record)

### 1.1 Rendering: `Stack` + per-entity `Transform`, not `CustomPaint`
Cards are full widgets (text, chips, later drawings) — they must be widgets, not painted. Structure:

```
SpatialCanvas
└── ClipRect
    └── Transform(matrix: viewportMatrix)        // pan+zoom applied ONCE here
        └── Stack (size = canvas bounds)
            └── for each entity (sorted by zIndex):
                Positioned(left: e.position.dx, top: e.position.dy)
                  └── Transform.rotate(angle: e.rotation)
                      └── RepaintBoundary          // ← non-negotiable
                          └── entityBuilder(e, isSelected)
```

`RepaintBoundary` per card means a drag repaints one layer, not the desk. Without it, 30 textured cards will jank on every gesture frame.

### 1.2 Viewport: own `Matrix4` + one `GestureDetector.onScale*` — not `InteractiveViewer`
`InteractiveViewer` fights you on exactly the things this module is for: per-child drag gestures compete with its pan recognizer, it offers no rotation, and its bounds model doesn't match "bounded desk". A hand-rolled viewport is ~120 lines:

```dart
// State: Offset _pan; double _zoom (clamp 0.5–2.0 per spec)
Matrix4 get viewportMatrix =>
    Matrix4.identity()..translate(_pan.dx, _pan.dy)..scale(_zoom);

Offset screenToCanvas(Offset p) =>
    MatrixUtils.transformPoint(Matrix4.inverted(viewportMatrix), p);
```

`onScaleUpdate` handles pan (focal point delta) and pinch (`details.scale`) in one recognizer — never register separate Pan and Scale detectors on the same widget (arena conflict; Scale supersedes Pan, use Scale alone with `pointerCount == 1` acting as pan).

**Zoom must anchor at the pinch focal point**, not the origin — the standard formula:
`_pan = focal - (focal - _pan) * (newZoom / oldZoom)`. Getting this wrong is the most common canvas bug; test it first.

### 1.3 Gesture arbitration: canvas vs card
- Card drag: `GestureDetector(onPanStart/Update/End)` (or Scale) on the card widget itself. Child detectors win the arena over the parent canvas detector by default when the touch lands on a card — this gives "touch card = drag card, touch felt = pan desk" for free.
- Two-finger anything (pan/pinch/twist) always operates on the **viewport**, even if one finger started on a card: when the canvas ScaleUpdate reports `pointerCount >= 2`, cancel any in-flight card drag.
- Rotation (Phase 4.3): two-finger twist **on a selected card** uses `ScaleUpdate.rotation` delta. Simplest arbitration that feels right: two fingers on empty felt → viewport; two fingers when the gesture *started* on a card → rotate/scale that card. Decide once, write it in the widget doc comment.
- Drag delta must be divided by `_zoom` (screen px → canvas units).

### 1.4 Coordinates: everything stored in canvas units
Entity `position`/`size` are in canvas coordinates, unaffected by zoom. Only gesture handlers convert (screen→canvas at the boundary, once). No other code may see screen coordinates. This single rule prevents the whole class of "drifts while zoomed" bugs.

### 1.5 Write policy: local during drag, commit on release
During drag, mutate widget-local state only (or an in-memory entity copy). Call `dataSource.onEntityMoved(...)` exactly once in `onPanEnd`. This is a hard contract requirement — per-frame callbacks would flood the main app's DB and sync log (see integration review §5.2).

### 1.6 Z-order
`int zIndex`; tap-to-front = `maxZ + 1`. Render order = sort by zIndex (stable sort; tie-break by id). Don't renormalize during a session; the datasource may compact values on load if they exceed ~10⁶ (they won't).

### 1.7 Culling: skip it for MVP
With `RepaintBoundary` per card, offscreen cards cost layout only. Add rect-intersection culling (`entity.rect.overlaps(visibleRect)`) only if the harness "simulate 100 tasks" test drops below 60fps. Building culling first is premature.

---

## 2. Garden paths — explicitly do NOT

- **No game/physics engine** (Flame, forge2d) for a draggable desk. Plain widgets handle this scale easily; an engine buys nothing and costs the entire widget ecosystem (text, ink, a11y).
- **No infinite canvas.** The spec says bounded desk; infinite canvas triples viewport math and breaks the "physical desk" metaphor. Clamp: `_pan` such that visibleRect stays within bounds (allow ~50px of felt margin).
- **No custom `RenderObject`/`MultiChildLayoutDelegate`.** `Stack` + `Positioned` is enough until proven otherwise by a profile, not a feeling.
- **No canvas-level `CustomPaint` re-implementation of cards** "for performance". The performance plan is RepaintBoundary + (later) rasterized drawings — see card_renderer and sketchpad review docs.
- **No gesture velocity physics/inertia on cards** in MVP. Inertial *viewport* panning (fling) is a nice Phase 4.3 add via `onScaleEnd` velocity — cards themselves should stop where the finger stops, like real paper.

---

## 3. Public API deltas vs the contract

Implement `SpatialCanvas`, `SpatialCanvasController`, `SpatialEntity`, `SpatialDataSource` as written in `INTERFACE_CONTRACTS.md`, with the amendments from the integration review §5:

1. Datasource is a `ChangeNotifier` (canvas listens and calls `getVisibleEntities` again on notify).
2. `onEntityMoved` fires on gesture end only; optional `onEntityMoving` for live consumers.
3. `SpatialEntity.size` is advisory (hit-testing/culling); actual rendered size belongs to the entity builder.
4. Controller additions worth including now (cheap, needed later): `Rect get visibleRect`, `void panTo(Offset, {bool animate})`, `double get zoom`.

## 4. Test plan (the module is very unit-testable — use that)

- Pure math tests: `screenToCanvas`/`canvasToScreen` round-trip at several zooms; focal-point zoom invariant ("the canvas point under the pinch focal stays under it"); bounds clamping.
- Widget tests with `WidgetTester.gesture`: drag moves entity by delta/zoom; tap selects; tap felt deselects; two-finger updates viewport not entity.
- Harness checks: 100 mock entities at 60fps (DevTools timeline), drag latency.

## 5. Build order

Viewport math + tests → static entity rendering → card drag → tap/selection → wire to harness mock (spec 4.1 checkpoint) → rotation + z-order + fling (4.3).
