import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pin_and_paper_canvas/src/viewport_math.dart';

void main() {
  group('screenToCanvas / canvasToScreen round-trip', () {
    for (final zoom in [0.5, 1.0, 2.0]) {
      for (final pan in [Offset.zero, const Offset(37.5, -18.25), const Offset(-200, 400)]) {
        test('zoom=$zoom pan=$pan: canvas -> screen -> canvas', () {
          const canvasPoint = Offset(123.0, 456.0);
          final screen = canvasToScreen(canvasPoint, pan: pan, zoom: zoom);
          final back = screenToCanvas(screen, pan: pan, zoom: zoom);
          expect(back.dx, closeTo(canvasPoint.dx, 1e-9));
          expect(back.dy, closeTo(canvasPoint.dy, 1e-9));
        });

        test('zoom=$zoom pan=$pan: screen -> canvas -> screen', () {
          const screenPoint = Offset(300.0, 150.0);
          final canvas = screenToCanvas(screenPoint, pan: pan, zoom: zoom);
          final back = canvasToScreen(canvas, pan: pan, zoom: zoom);
          expect(back.dx, closeTo(screenPoint.dx, 1e-9));
          expect(back.dy, closeTo(screenPoint.dy, 1e-9));
        });
      }
    }

    test('canvasToScreen matches viewportMatrix transform', () {
      const pan = Offset(10, -5);
      const zoom = 1.75;
      const canvasPoint = Offset(64, 32);
      final matrix = viewportMatrix(pan: pan, zoom: zoom);
      final viaMatrix = MatrixUtils.transformPoint(matrix, canvasPoint);
      final viaFunction = canvasToScreen(canvasPoint, pan: pan, zoom: zoom);
      expect(viaMatrix.dx, closeTo(viaFunction.dx, 1e-9));
      expect(viaMatrix.dy, closeTo(viaFunction.dy, 1e-9));
    });

    test('screenToCanvas matches inverse viewportMatrix transform', () {
      const pan = Offset(10, -5);
      const zoom = 1.75;
      const screenPoint = Offset(200, 90);
      final matrix = viewportMatrix(pan: pan, zoom: zoom);
      final viaMatrix = MatrixUtils.transformPoint(Matrix4.inverted(matrix), screenPoint);
      final viaFunction = screenToCanvas(screenPoint, pan: pan, zoom: zoom);
      expect(viaMatrix.dx, closeTo(viaFunction.dx, 1e-9));
      expect(viaMatrix.dy, closeTo(viaFunction.dy, 1e-9));
    });
  });

  group('zoomAtFocal', () {
    test('focal-zoom invariant: canvas point under focal stays under it', () {
      const focal = Offset(150, 200);
      const pan = Offset(20, -10);
      const zoom = 1.0;

      final canvasPointBefore = screenToCanvas(focal, pan: pan, zoom: zoom);

      final result = zoomAtFocal(
        focal: focal,
        pan: pan,
        zoom: zoom,
        targetZoom: 1.8,
        minZoom: 0.5,
        maxZoom: 2.0,
      );

      final canvasPointAfter = screenToCanvas(focal, pan: result.pan, zoom: result.zoom);
      expect(canvasPointAfter.dx, closeTo(canvasPointBefore.dx, 1e-9));
      expect(canvasPointAfter.dy, closeTo(canvasPointBefore.dy, 1e-9));
    });

    test('focal-zoom invariant holds when zooming out too', () {
      const focal = Offset(80, 60);
      const pan = Offset(-40, 15);
      const zoom = 1.6;

      final canvasPointBefore = screenToCanvas(focal, pan: pan, zoom: zoom);

      final result = zoomAtFocal(
        focal: focal,
        pan: pan,
        zoom: zoom,
        targetZoom: 0.7,
        minZoom: 0.5,
        maxZoom: 2.0,
      );

      final canvasPointAfter = screenToCanvas(focal, pan: result.pan, zoom: result.zoom);
      expect(canvasPointAfter.dx, closeTo(canvasPointBefore.dx, 1e-9));
      expect(canvasPointAfter.dy, closeTo(canvasPointBefore.dy, 1e-9));
    });

    test('clamps target zoom above maxZoom', () {
      final result = zoomAtFocal(
        focal: const Offset(0, 0),
        pan: Offset.zero,
        zoom: 1.0,
        targetZoom: 5.0,
        minZoom: 0.5,
        maxZoom: 2.0,
      );
      expect(result.zoom, 2.0);
    });

    test('clamps target zoom below minZoom', () {
      final result = zoomAtFocal(
        focal: const Offset(0, 0),
        pan: Offset.zero,
        zoom: 1.0,
        targetZoom: 0.01,
        minZoom: 0.5,
        maxZoom: 2.0,
      );
      expect(result.zoom, 0.5);
    });

    test('invariant still holds when the requested zoom gets clamped', () {
      const focal = Offset(400, 300);
      const pan = Offset(5, 5);
      const zoom = 1.0;
      final canvasPointBefore = screenToCanvas(focal, pan: pan, zoom: zoom);

      final result = zoomAtFocal(
        focal: focal,
        pan: pan,
        zoom: zoom,
        targetZoom: 999.0, // will clamp to maxZoom
        minZoom: 0.5,
        maxZoom: 2.0,
      );
      expect(result.zoom, 2.0);

      final canvasPointAfter = screenToCanvas(focal, pan: result.pan, zoom: result.zoom);
      expect(canvasPointAfter.dx, closeTo(canvasPointBefore.dx, 1e-9));
      expect(canvasPointAfter.dy, closeTo(canvasPointBefore.dy, 1e-9));
    });

    test('no-op when targetZoom equals current zoom (pure focal point, no pan)', () {
      const focal = Offset(10, 10);
      const pan = Offset(3, 4);
      final result = zoomAtFocal(
        focal: focal,
        pan: pan,
        zoom: 1.0,
        targetZoom: 1.0,
        minZoom: 0.5,
        maxZoom: 2.0,
      );
      expect(result.zoom, 1.0);
      expect(result.pan.dx, closeTo(pan.dx, 1e-9));
      expect(result.pan.dy, closeTo(pan.dy, 1e-9));
    });
  });

  group('clampPan', () {
    const canvasSize = Size(1000, 800);
    const viewportSize = Size(400, 300);

    test('pan within bounds is left untouched', () {
      const pan = Offset(-100, -50);
      final result = clampPan(pan: pan, zoom: 1.0, canvasSize: canvasSize, viewportSize: viewportSize);
      expect(result, pan);
    });

    test('clamps an excessively negative pan (viewport pushed past bottom-right edge)', () {
      const pan = Offset(-5000, -5000);
      final result = clampPan(pan: pan, zoom: 1.0, canvasSize: canvasSize, viewportSize: viewportSize, margin: 50);
      // minPanX = viewportWidth - (canvasWidth + margin) * zoom = 400 - 1050 = -650
      expect(result.dx, closeTo(-650, 1e-9));
      expect(result.dy, closeTo(300 - (800 + 50), 1e-9));
    });

    test('clamps an excessively positive pan (viewport pushed past top-left edge)', () {
      const pan = Offset(5000, 5000);
      final result = clampPan(pan: pan, zoom: 1.0, canvasSize: canvasSize, viewportSize: viewportSize, margin: 50);
      // maxPanX = margin * zoom = 50
      expect(result.dx, closeTo(50, 1e-9));
      expect(result.dy, closeTo(50, 1e-9));
    });

    test('centers the axis when the viewport is larger than canvas + margins', () {
      const bigViewport = Size(3000, 3000);
      const pan = Offset(123, -456);
      final result = clampPan(pan: pan, zoom: 1.0, canvasSize: canvasSize, viewportSize: bigViewport, margin: 50);
      // minPanX = 3000 - 1050 = 1950, maxPanX = 50 -> minPanX > maxPanX -> center = 1000
      expect(result.dx, closeTo((1950 + 50) / 2, 1e-9));
      // minPanY = 3000 - 850 = 2150, maxPanY = 50 -> center = 1100
      expect(result.dy, closeTo((2150 + 50) / 2, 1e-9));
    });

    test('bounds scale with zoom', () {
      const pan = Offset(-5000, -5000);
      final result = clampPan(pan: pan, zoom: 2.0, canvasSize: canvasSize, viewportSize: viewportSize, margin: 50);
      // minPanX = viewportWidth - (canvasWidth + margin) * zoom = 400 - (1050*2) = -1700
      expect(result.dx, closeTo(400 - 1050 * 2, 1e-9));
      expect(result.dy, closeTo(300 - 850 * 2, 1e-9));
    });

    test('pan clamping holds at min zoom and max zoom', () {
      for (final zoom in [0.5, 2.0]) {
        final farOut = clampPan(pan: const Offset(-9999, -9999), zoom: zoom, canvasSize: canvasSize, viewportSize: viewportSize);
        final farIn = clampPan(pan: const Offset(9999, 9999), zoom: zoom, canvasSize: canvasSize, viewportSize: viewportSize);
        // The visible rect (in canvas coords) after clamping should overlap
        // the canvas bounds allowing only the felt margin on each side.
        final visibleAfterFarOut = screenToCanvas(Offset.zero, pan: farOut, zoom: zoom) &
            Size(viewportSize.width / zoom, viewportSize.height / zoom);
        expect(visibleAfterFarOut.right, greaterThanOrEqualTo(0));
        expect(visibleAfterFarOut.left, lessThanOrEqualTo(canvasSize.width));

        final visibleAfterFarIn = screenToCanvas(Offset.zero, pan: farIn, zoom: zoom) &
            Size(viewportSize.width / zoom, viewportSize.height / zoom);
        expect(visibleAfterFarIn.left, lessThanOrEqualTo(canvasSize.width));
        expect(visibleAfterFarIn.right, greaterThanOrEqualTo(0));
      }
    });

    test('default margin constant matches kDefaultFeltMargin when unspecified', () {
      const pan = Offset(-5000, -5000);
      final explicit = clampPan(
        pan: pan,
        zoom: 1.0,
        canvasSize: canvasSize,
        viewportSize: viewportSize,
        margin: kDefaultFeltMargin,
      );
      final implicit = clampPan(pan: pan, zoom: 1.0, canvasSize: canvasSize, viewportSize: viewportSize);
      expect(implicit, explicit);
    });
  });
}
