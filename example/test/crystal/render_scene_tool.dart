// Diagnostic (not a test): renders the stone over a card-on-kraft scene to a
// PNG so a human (or Claude) can look at the actual composited result.
// Run: flutter test test/crystal/render_scene_tool.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pin_and_paper_canvas/spatial_canvas.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('render scene png', () async {
    const size = Size(980, 760);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // Kraft-ish ground
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF7a5c3e));
    // Cream card occupying the upper-left area, like the owner's screenshots
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(30, 40, 920, 680), const Radius.circular(4)),
      Paint()..color = const Color(0xFFFDF6E3),
    );
    canvas.save();
    canvas.translate(200, 80); // stone straddling the card's lower region
    AmethystChunkPainter.debugGroundOnly = false;
    AmethystChunkPainter(
      rotationY: AmethystChunkMesh.baseAlignedYaw,
      lightAzimuthDegrees: kDeskLightAzimuth,
      inclusions: 0.55,
      glassiness: 0.62,
      isSelected: false,
    ).paint(canvas, const Size(620, 500));
    AmethystChunkPainter.debugLowerSilhouette = null;
    AmethystChunkPainter.debugCastHull = null;
    // Diagnostic overlays: where the painter THINKS its shadow geometry is.
    final silhouette = AmethystChunkPainter.debugLowerSilhouette;
    if (silhouette != null && silhouette.length > 1) {
      final p = Path()..moveTo(silhouette.first.dx, silhouette.first.dy);
      for (final pt in silhouette.skip(1)) {
        p.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF00FF66),
      );
    }
    final cast = AmethystChunkPainter.debugCastHull;
    if (cast != null && cast.length > 2) {
      final p = Path()..moveTo(cast.first.dx, cast.first.dy);
      for (final pt in cast.skip(1)) {
        p.lineTo(pt.dx, pt.dy);
      }
      p.close();
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFFFF3355),
      );
    }
    canvas.restore();
    final image = await recorder.endRecording().toImage(size.width.toInt(), size.height.toInt());
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = File('/tmp/claude-1000/-home-bluekitty-Documents-Git/5b744583-e2bf-49cb-9abd-b2389cfa39a5/scratchpad/stone_scene.png');
    out.writeAsBytesSync(png!.buffer.asUint8List());
    debugPrint('WROTE ${out.path}');
  });
}
