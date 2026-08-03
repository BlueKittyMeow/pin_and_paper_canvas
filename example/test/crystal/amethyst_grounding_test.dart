// Pixel-level grounding check: renders AmethystChunkPainter offscreen and
// measures the vertical gap between the stone's lowest painted pixel and the
// first shadow pixel beneath it, at several columns. Exists because the
// shadow/stone relationship has now been wrong three times in ways that
// geometry-by-inspection missed (owner reports 2026-08-03) — this measures.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pin_and_paper_canvas_example/crystal/amethyst_chunk.dart';

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
    bool isStone(int x, int y) {
      final i = (y * w + x) * 4;
      final r = bytes.getUint8(i), g = bytes.getUint8(i + 1), b = bytes.getUint8(i + 2), a = bytes.getUint8(i + 3);
      // Saturated purple body: strong alpha, blue-dominant over green.
      return a > 160 && b > 90 && b > g + 25 && r > 60;
    }

    // Sample columns across the stone's central width.
    final results = <String>[];
    var worstGap = 0;
    for (final fx in [0.38, 0.46, 0.54, 0.62]) {
      final x = (w * fx).round();
      var stoneBottom = -1;
      for (var y = h - 1; y >= 0; y--) {
        if (isStone(x, y)) {
          stoneBottom = y;
          break;
        }
      }
      if (stoneBottom < 0) {
        results.add('col $fx: no stone pixels');
        continue;
      }
      // Shadow DENSITY profile below the base: the failure mode isn't a
      // transparent gap but weak shadow at contact with the dark peak
      // offset lower ("lighter area" under the stone, owner screenshot).
      final profile = [
        for (final d in [2, 6, 12, 20, 30, 42])
          stoneBottom + d < h ? alphaAt(x, stoneBottom + d) : 0,
      ];
      // Where does the max density sit?
      var peakOffset = 0, peakAlpha = -1;
      for (var d = 1; d < 60 && stoneBottom + d < h; d++) {
        final a = alphaAt(x, stoneBottom + d);
        if (a > peakAlpha) {
          peakAlpha = a;
          peakOffset = d;
        }
      }
      results.add('col $fx: bottom=$stoneBottom profile(2,6,12,20,30,42)=$profile peak=$peakAlpha@+$peakOffset');
      // "Gap" now means: contact-adjacent shadow (within 6px) must be at
      // least 60% as dense as the peak — otherwise there's a light band.
      final contactAlpha = profile[0] > profile[1] ? profile[0] : profile[1];
      if (peakAlpha > 0 && contactAlpha < peakAlpha * 0.6) {
        worstGap = worstGap < peakOffset ? peakOffset : worstGap;
      }
    }
    debugPrint('GROUNDING: ${results.join(' | ')} worstGap=$worstGap');

    expect(worstGap, lessThanOrEqualTo(3),
        reason: 'shadow must start within 3px of the stone base; got $worstGap. ${results.join(' | ')}');
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

    // The ground zone: the bottom quarter of the canvas, full width.
    var diffs = 0;
    for (var y = (h * 0.80).round(); y < h; y++) {
      for (var x = 0; x < w; x++) {
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
