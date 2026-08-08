import 'package:flutter/widgets.dart';

import 'dachshund_figurine.dart' show SpriteStop, kDachshundShadowOpacity;

/// The five modeled minerals of the habit_v1 bundle (owner-approved
/// 2026-08-05), each grown in its real mineralogical habit — these are
/// SEPARATE MESHES, not colorways: never cross-fade or swap one variant's
/// frame for another's (bundle manifest `geometry_policy`).
enum GemVariant {
  amethyst('amethyst', 'Amethyst'),
  citrine('citrine', 'Citrine'),
  roseQuartz('rose_quartz', 'Rose Quartz'),
  fluorite('fluorite', 'Fluorite'),
  snowflakeObsidian('snowflake_obsidian', 'Obsidian');

  const GemVariant(this.assetDir, this.label);

  /// Asset subdirectory under `assets/desk_objects/gems/`.
  final String assetDir;

  /// Drawer-tile display name.
  final String label;
}

/// A modeled gem/mineral desk object from the habit_v1 sprite bundle:
/// druzy amethyst spray, twin-sceptre citrine, massive rose quartz chunk,
/// cubic fluorite cluster, or conchoidal snowflake obsidian. Replaces the
/// painted `AmethystChunk` stones in the drawer (the painter itself is
/// retained — earmarked for an easter-egg return someday).
///
/// Identical composition contract to [DachshundFigurine]: three stacked
/// same-frame layers per rotation stop — contact + cast shadows at
/// [kDachshundShadowOpacity], neutral-lit color on top; 960px color
/// masters for crispness under canvas zoom, 320px shadow tiers. Frame
/// padding 1.25 (the stone occupies most of the frame — much less margin
/// than the dachshund's 1.75).
class GemFigurine extends StatelessWidget {
  const GemFigurine({
    super.key,
    required this.variant,
    required this.size,
    this.stop = SpriteStop.threeQLeft,
    this.isSelected = false,
  });

  final GemVariant variant;

  /// Display box (square, like the sprite frames). Manifest true desk
  /// scale is a 160-logical-px box (0.16 m frame, `ppm_multiplier: 2`);
  /// defaults ship larger per the sparks-joy doctrine.
  final Size size;

  final SpriteStop stop;

  final bool isSelected;

  static const ColorFilter _selectedBrighten = ColorFilter.matrix(<double>[
    1.12, 0, 0, 0, 0, //
    0, 1.12, 0, 0, 0, //
    0, 0, 1.12, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  Widget _layer(String layer, {double opacity = 1.0}) {
    final image = Image.asset(
      'assets/desk_objects/gems/${variant.assetDir}/${stop.assetStem}_$layer.png',
      package: 'pin_and_paper_canvas',
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    );
    return opacity == 1.0 ? image : Opacity(opacity: opacity, child: image);
  }

  @override
  Widget build(BuildContext context) {
    Widget color = _layer('color');
    if (isSelected) {
      color = ColorFiltered(colorFilter: _selectedBrighten, child: color);
    }
    return SizedBox.fromSize(
      size: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _layer('cast', opacity: kDachshundShadowOpacity),
          _layer('contact', opacity: kDachshundShadowOpacity),
          color,
        ],
      ),
    );
  }
}
