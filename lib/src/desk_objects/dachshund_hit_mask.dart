import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

import 'dachshund_figurine.dart';

/// Per-stop alpha masks for silhouette hit-testing the dachshund sprite —
/// the hit-test half of `SpatialCanvas.entityHitTest` for the figurine.
///
/// The widened sprite frame is mostly transparent shadow margin (the dog is
/// only the central ~40%), so box hit-testing steals taps from cards under
/// his nose (owner report 2026-08-04). Each stop's COLOR layer (never the
/// shadows — a shadow isn't grabbable) is decoded once at a small mask
/// resolution and sampled by normalized position.
///
/// Loading is lazy and async; until a stop's mask has landed, [contains]
/// answers true (the old whole-box behavior) so the figurine is never
/// momentarily untappable.
class DachshundHitMask {
  DachshundHitMask._();

  /// Mask resolution per side. 96 keeps all seven masks under ~65KB total
  /// while a mask texel still maps to ~4 logical px at the default display
  /// size — finer than a fingertip.
  static const int _dim = 96;

  /// Alpha above this (0–255) counts as dog. Low on purpose: antialiased
  /// coat edges should be grabbable.
  static const int _alphaThreshold = 24;

  /// How far (in mask texels) around the sample point to look — a
  /// forgiving halo so taps just off the silhouette still count. One texel
  /// ≈ 4 logical px at default size.
  static const int _haloTexels = 1;

  static final Map<DachshundStop, List<bool>> _masks = {};
  static final Set<DachshundStop> _loading = {};

  /// Kicks off (idempotently) the async decode of every stop's mask.
  /// Call once from the host screen's initState.
  static void ensureLoading() {
    for (final stop in DachshundStop.values) {
      if (_masks.containsKey(stop) || _loading.contains(stop)) continue;
      _loading.add(stop);
      _load(stop);
    }
  }

  static Future<void> _load(DachshundStop stop) async {
    try {
      final bytes = await rootBundle.load(
        'packages/pin_and_paper_canvas/assets/desk_objects/dachshund/${stop.assetStem}_color.png',
      );
      final codec = await ui.instantiateImageCodec(
        bytes.buffer.asUint8List(),
        targetWidth: _dim,
        targetHeight: _dim,
      );
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      frame.image.dispose();
      if (data == null) return;
      final mask = List<bool>.filled(_dim * _dim, false);
      for (var i = 0; i < _dim * _dim; i++) {
        mask[i] = data.getUint8(i * 4 + 3) > _alphaThreshold;
      }
      _masks[stop] = mask;
    } catch (_) {
      // Asset missing or decode failed (e.g. bare unit tests): leave the
      // mask absent — [contains] keeps answering true, whole-box behavior.
    } finally {
      _loading.remove(stop);
    }
  }

  /// Whether the normalized position ([u], [v] in `0..1` across the sprite
  /// frame) lands on the dog for [stop]. True while the mask is still
  /// loading (see class doc).
  static bool contains(DachshundStop stop, double u, double v) {
    final mask = _masks[stop];
    if (mask == null) {
      ensureLoading();
      return true;
    }
    final x = (u * _dim).floor().clamp(0, _dim - 1);
    final y = (v * _dim).floor().clamp(0, _dim - 1);
    for (var dy = -_haloTexels; dy <= _haloTexels; dy++) {
      for (var dx = -_haloTexels; dx <= _haloTexels; dx++) {
        final sx = x + dx, sy = y + dy;
        if (sx < 0 || sx >= _dim || sy < 0 || sy >= _dim) continue;
        if (mask[sy * _dim + sx]) return true;
      }
    }
    return false;
  }

  /// Test hook: forget every decoded mask.
  static void debugReset() {
    _masks.clear();
    _loading.clear();
  }
}
