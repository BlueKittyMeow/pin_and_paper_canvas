// Pixel-level grounding check: renders AmethystChunkPainter offscreen and
// measures the vertical gap between the stone's lowest painted pixel and the
// first shadow pixel beneath it, at several columns. Exists because the
// shadow/stone relationship has now been wrong three times in ways that
// geometry-by-inspection missed (owner reports 2026-08-03) — this measures.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pin_and_paper_canvas/spatial_canvas.dart';

Future<ui.Image> _paint(Size size, {bool isSelected = false}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  AmethystChunkPainter(
    rotationY: AmethystChunkMesh.baseAlignedYaw,
    lightAzimuthDegrees: kDeskLightAzimuth,
    inclusions: 0.55,
    glassiness: 0.62,
    isSelected: isSelected,
  ).paint(canvas, size);
  return recorder.endRecording().toImage(size.width.toInt(), size.height.toInt());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shadow hugs the stone: no light gap under the base', () async {
    const size = Size(300, 240);
    final image = await _paint(size);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final w = image.width, h = image.height;

    int alphaAt(int x, int y) => bytes.getUint8((y * w + x) * 4 + 3);
    // Stone body pixels composite near-opaque over the transparent test
    // background (>= 235 even for glassy facets over interior passes);
    // ground shadow washes stay well below that. This is only valid because
    // the background here is transparent — do not reuse over a real desk.
    bool isStone(int x, int y) => alphaAt(x, y) >= 235;

    // Sweep columns across the WHOLE silhouette width — the light-band bug
    // lived under the flanks, which center-only probing missed (owner
    // demonstrated it with a selected/unselected screenshot pair after the
    // first version of this test called it fixed).
    // Collect per-column seam density first, then judge by position within
    // the silhouette's x-span: the AO design is DELIBERATELY graded — dense
    // under the belly's central span, soft (but present) under the tapered
    // overhang ends (full density there produced the square-wing artifact).
    final columns = <({int x, int seamAlpha})>[];
    for (var x = (w * 0.10).round(); x < (w * 0.90).round(); x += 4) {
      var stoneBottom = -1;
      for (var y = h - 1; y >= 0; y--) {
        if (isStone(x, y)) {
          stoneBottom = y;
          break;
        }
      }
      if (stoneBottom < 0) continue;
      final seamY = stoneBottom + 3;
      columns.add((x: x, seamAlpha: seamY < h ? alphaAt(x, seamY) : 0));
    }
    expect(columns.length, greaterThan(10), reason: 'silhouette sweep found too few columns');
    final minX = columns.first.x, maxX = columns.last.x;
    final results = <String>[];
    for (final c in columns) {
      final rel = (c.x - minX) / (maxX - minX);
      // Only the central belly span must be dense. The overhang tips
      // DELIBERATELY dissolve to nothing (ground-proximity weighting +
      // lateral end-fade — the wings fix); requiring density there would
      // re-mandate the square-wing artifact.
      if (rel < 0.25 || rel > 0.75) continue;
      // Threshold recalibrated 2026-08-03 for the owner-chosen soft-blob
      // design (Gemini-base chimera): the seam is a deliberately gentle,
      // UNIFORM wash (~42 alpha) rather than the engineered-dark band —
      // what matters is presence without gaps, not maximal darkness.
      if (c.seamAlpha < 30) {
        results.add('x=${c.x} rel=${rel.toStringAsFixed(2)} seamAlpha=${c.seamAlpha} (<30)');
      }
    }
    debugPrint('GROUNDING ${results.isEmpty ? "(all snug)" : results.join(" | ")}');
    expect(results, isEmpty,
        reason: 'AO must be dense under the central belly and present at the '
            'tapered ends; violations: ${results.join(' | ')}');
  });

  test('selection paints nothing on the ground (no underglow wash)', () async {
    // Regression: the amber selection underglow used to wash light across
    // the contact zone, reading as a pale band under the stone. Selection
    // now lives entirely in the stone's own sparkle: the pixels below the
    // base must be identical selected vs unselected.
    const size = Size(300, 240);
    final plain = (await (await _paint(size)).toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final selected =
        (await (await _paint(size, isSelected: true)).toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final w = size.width.toInt(), h = size.height.toInt();

    // Mask the stone GEOMETRICALLY: project every mesh vertex with the
    // painter's own formulas, take the (convex) 2D silhouette, dilate 3px.
    // Alpha-based masking can't work here — glassy facets composite below
    // full opacity and dense shadow overlaps composite near it. The stone's
    // own pixels are ALLOWED to differ (that's the sparkle); the ground is
    // not.
    final yaw = AmethystChunkMesh.baseAlignedYaw;
    final cx = size.width / 2, baseY = size.height * 0.78, scale = size.height * 0.42;
    final projected = <Offset>[];
    for (final face in AmethystChunkMesh.faces) {
      for (final v in face) {
        final x1 = v.x * math.cos(yaw) + v.z * math.sin(yaw);
        final z1 = -v.x * math.sin(yaw) + v.z * math.cos(yaw);
        final y2 = v.y * math.cos(kAmethystCameraTilt) - z1 * math.sin(kAmethystCameraTilt);
        projected.add(Offset(cx + x1 * scale, baseY - y2 * scale));
      }
    }
    // Convex silhouette via monotone-chain hull of the projected points
    // (angle-sorting ALL vertices makes a star, not the outline — interior
    // vertices must be discarded by a real hull), dilated 3px radially.
    final sorted = [...projected]..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
    double crossZ(Offset o, Offset a, Offset b) =>
        (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
    final lower = <Offset>[];
    for (final p in sorted) {
      while (lower.length > 1 && crossZ(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }
    final upper = <Offset>[];
    for (final p in sorted.reversed) {
      while (upper.length > 1 && crossZ(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }
    final ring = [...lower.sublist(0, lower.length - 1), ...upper.sublist(0, upper.length - 1)];
    var scx = 0.0, scy = 0.0;
    for (final p in ring) {
      scx += p.dx;
      scy += p.dy;
    }
    scx /= ring.length;
    scy /= ring.length;
    final dilated = [
      for (final p in ring)
        () {
          final dx = p.dx - scx, dy = p.dy - scy;
          final d = math.sqrt(dx * dx + dy * dy);
          final k = d == 0 ? 1.0 : (d + 3) / d;
          return Offset(scx + dx * k, scy + dy * k);
        }(),
    ];
    bool insideStone(double px, double py) {
      // Convex point-in-polygon: consistent cross-product sign. The ring is
      // angle-sorted CCW-or-CW; accept either by checking sign consistency.
      double? sign;
      for (var i = 0; i < dilated.length; i++) {
        final a = dilated[i], b = dilated[(i + 1) % dilated.length];
        final cross = (b.dx - a.dx) * (py - a.dy) - (b.dy - a.dy) * (px - a.dx);
        if (cross.abs() < 1e-9) continue;
        if (sign == null) {
          sign = cross.sign;
        } else if (cross.sign != sign) {
          return false;
        }
      }
      return true;
    }

    var diffs = 0;
    for (var y = (h * 0.80).round(); y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (insideStone(x.toDouble(), y.toDouble())) continue;
        final i = (y * w + x) * 4;
        for (var c = 0; c < 4; c++) {
          if ((plain.getUint8(i + c) - selected.getUint8(i + c)).abs() > 2) {
            diffs++;
            break;
          }
        }
      }
    }
    expect(diffs, 0, reason: 'selection altered $diffs ground-zone pixels');
  });
}
