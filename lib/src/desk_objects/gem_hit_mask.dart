import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

import 'dachshund_figurine.dart' show SpriteStop;
import 'gem_figurine.dart';

/// Per-variant, per-stop alpha masks for silhouette hit-testing the gem
/// figurines — same contract and defaults as `DachshundHitMask` (which it
/// mirrors; see that class for the rationale): decoded lazily from each
/// stop's COLOR layer at low resolution, whole-box true until loaded,
/// shadows never grabbable.
class GemHitMask {
  GemHitMask._();

  static const int _dim = 96;
  static const int _alphaThreshold = 24;
  static const int _haloTexels = 1;

  static final Map<String, List<bool>> _masks = {};
  static final Set<String> _loading = {};

  static String _key(GemVariant v, SpriteStop s) => '${v.assetDir}/${s.assetStem}';

  /// Idempotently kicks off async decodes for every variant × stop.
  static void ensureLoading() {
    for (final v in GemVariant.values) {
      for (final s in SpriteStop.values) {
        final key = _key(v, s);
        if (_masks.containsKey(key) || _loading.contains(key)) continue;
        _loading.add(key);
        _load(v, s, key);
      }
    }
  }

  static Future<void> _load(GemVariant v, SpriteStop s, String key) async {
    try {
      final bytes = await rootBundle.load(
        'packages/pin_and_paper_canvas/assets/desk_objects/gems/${v.assetDir}/${s.assetStem}_color.png',
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
      _masks[key] = mask;
    } catch (_) {
      // Missing asset / bare unit test: stay whole-box.
    } finally {
      _loading.remove(key);
    }
  }

  /// Whether normalized position ([u], [v] in 0..1) lands on the stone for
  /// [variant] at [stop]. True while that mask is still loading.
  static bool contains(GemVariant variant, SpriteStop stop, double u, double v) {
    final mask = _masks[_key(variant, stop)];
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

  /// Test hook.
  static void debugReset() {
    _masks.clear();
    _loading.clear();
  }
}
